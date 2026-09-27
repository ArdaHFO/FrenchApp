"""Local, resumable editorial ledger. Never writes the content database.

No semantic inference, network access, publication, or application progress I/O.
"""
import argparse
from collections import Counter, defaultdict
from contextlib import closing, contextmanager
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import random
import sqlite3
import sys

from editorial_pilot import validate_review

ALGORITHM = 'word-review-v1'
SCOPE = ['target_meaning_alignment', 'example_and_translation_alignment',
         'visible_usage_information']
WORD_FIELDS = ('lemma_fr', 'pos', 'article', 'gender', 'plural_fr', 'ipa',
               'meaning_tr', 'meaning_en', 'meaning_en_2', 'note_tr', 'literal_tr',
               'register', 'is_idiom')
EXAMPLE_FIELDS = tuple(['sentence_' + lang for lang in ('fr', 'en', 'tr')]
                      + ['sentence_' + lang + '_id' for lang in ('fr', 'en', 'tr')]
                      + ['author_' + lang for lang in ('fr', 'en', 'tr')]
                      + ['tr_direct', 'max_level'])
RESULT_STATUSES = {'proposed_keep', 'proposal', 'blocked_source', 'blocked_structure'}
HISTORY_FILES = ['FA-010A-sample.json', 'FA-010A-review.json', 'FA-010A-notes.md',
                 'FA-011A-sample.json', 'FA-011A-review.json', 'FA-011A-notes.md',
                 'FA-011A-decisions.json', 'FA-011A-review-evidence.json']


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    def invalid_constant(value):
        raise ValueError('Invalid JSON numeric constant: '+value)
    return json.loads(Path(path).read_text(encoding='utf-8'), parse_constant=invalid_constant)


def different_file(output, inputs):
    """Reject normalized, symlink and existing hardlink collisions before writes."""
    out = Path(output).resolve()
    for value in inputs:
        source = Path(value).resolve()
        if out == source or (out.exists() and source.exists() and out.samefile(source)):
            raise ValueError(f'Output overlaps protected input: {output}')


def immutable_file(path, data, inputs=()):
    path = Path(path)
    different_file(path, inputs)
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f'Refusing to overwrite existing file: {path}')
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(data)


def semantic_record(word, examples):
    """Physical row IDs/order, frequency, review flags and DB metadata are excluded.

    Language source IDs/authors ARE included: changing attribution changes the
    material reviewed. Duplicate ordinal=0 rows remain duplicates in this list.
    """
    values = [{key: row.get(key) for key in EXAMPLE_FIELDS} for row in examples]
    return {'algorithm': ALGORITHM, 'scope': SCOPE,
            'word': {key: word.get(key) for key in WORD_FIELDS},
            'ordinal_zero_examples': sorted(values, key=canonical)}


def fingerprint(word, examples):
    return digest(canonical(semantic_record(word, examples)).encode('utf-8'))


def sample_fingerprint(record):
    example = record['displayed_example']
    return fingerprint(record['current'], [] if example is None else [example])


def adapt_legacy(sample, review):
    """FA-010A-v1 adapter; derives text differences, NEVER source visits/approval."""
    adapted = copy.deepcopy(review)
    for row in adapted['records']:
        original = row.get('current_example') or {}
        proposed = row.get('proposed_fields', {}).get('example', {})
        row['language_attribution_plan'] = {}
        for lang in ('fr', 'en', 'tr'):
            field = 'sentence_' + lang
            changed = proposed.get(field, original.get(field)) != original.get(field)
            row['language_attribution_plan'][lang] = {
                'text_changed': changed, 'retain_original_id_author': not changed,
                'action': 'new_local_on_application' if changed else 'preserve_existing',
                'derivation': 'adapter-derived: FA-010A-v1 actual text comparison'}
        # An absent source claim remains unverified. Existing reported visits are
        # preserved as claims by the originating reviewer, never our own visits.
        row.setdefault('french_source_status', 'not_externally_verified')
        row.setdefault('sources', [])
        row.setdefault('human_review_performed', False)
    validate_review(sample, adapted)
    return adapted


def inspect_content(path):
    path = Path(path).resolve(strict=True)
    before = digest(path.read_bytes())
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        words = [dict(r) for r in db.execute('SELECT * FROM words ORDER BY id COLLATE BINARY')]
        examples = defaultdict(list)
        for row in db.execute('SELECT * FROM examples WHERE ordinal=0 ORDER BY word_id,id'):
            examples[row['word_id']].append(dict(row))
        orphan = [dict(r) for r in db.execute('''SELECT e.word_id,COUNT(*) AS row_count
            FROM examples e LEFT JOIN words w ON w.id=e.word_id
            WHERE w.id IS NULL GROUP BY e.word_id ORDER BY e.word_id''')]
    assert len({w['id'] for w in words}) == len(words), 'Duplicate word IDs'
    duplicates = Counter(w.get('meaning_tr') for w in words if w.get('meaning_tr'))
    inventory = []
    for word in words:
        rows = examples[word['id']]
        findings = []
        def finding(rule, field, severity):
            findings.append(dict(rule=rule, field=field, severity=severity))
        if not (word.get('meaning_tr') or '').strip():
            finding('empty_meaning_tr', 'words.meaning_tr', 'structural_error')
        if not (word.get('meaning_en') or '').strip():
            finding('empty_meaning_en', 'words.meaning_en', 'review_hint')
        if len(rows) != 1:
            finding('ordinal_zero_missing' if not rows else 'ordinal_zero_multiple',
                    'examples.ordinal', 'structural_error')
        for ex in rows:
            for lang in ('fr', 'en', 'tr'):
                if not (ex.get('sentence_' + lang) or '').strip():
                    finding('missing_sentence_' + lang, 'examples.sentence_' + lang, 'review_hint')
                sid = ex.get('sentence_' + lang + '_id')
                if sid and sid > 0 and not ex.get('author_' + lang):
                    finding('external_source_without_author', 'examples.author_' + lang, 'review_hint')
        if duplicates[word.get('meaning_tr')] > 1:
            finding('same_meaning_text_not_necessarily_error', 'words.meaning_tr', 'review_hint')
        eligible = word.get('is_function') is not None and word['is_function'] != 1 and word.get('needs_review') is not None and word['needs_review'] != 1
        inventory.append(dict(id=word['id'], current=word, displayed_examples=rows,
                              fingerprint=fingerprint(word, rows), eligible=eligible,
                              findings=findings))
    after = digest(path.read_bytes())
    if after != before:
        raise ValueError('Content changed during read-only scan; rerun sync')
    return inventory, {'path': str(path), 'sha256': before, 'bytes': path.stat().st_size,
                       'orphan_example_word_ids': orphan}


class ReviewQueue:
    """One local ledger; short BEGIN IMMEDIATE transactions serialize acceptance."""
    def __init__(self, work, content=None):
        self.work = Path(work).resolve()
        self.header_path = self.work / 'workspace.json'
        self.path = self.work / 'registry.sqlite'
        if content is not None:
            content = Path(content).resolve(strict=True)
            different_file(self.path, [content])
            different_file(self.header_path, [content])
        if not self.header_path.exists():
            if content is None:
                raise ValueError('Workspace missing; run init --db first')
            if self.work.exists() and any(self.work.iterdir()):
                raise ValueError('New workspace must be empty')
            immutable_file(self.header_path, (canonical({'schema': 1, 'content_path': str(content)})+'\n').encode(), [content])
        header = read_json(self.header_path)
        if header.get('schema') != 1:
            raise ValueError('Unsupported review workspace schema')
        self.content_path = Path(header['content_path']).resolve(strict=True)
        if content and content != self.content_path:
            raise ValueError('This workspace is bound to a different content path')
        # Existing copies are immutable protected input, even on reopened workspaces.
        self.protected = [self.content_path, self.header_path] + list((self.work/'sources').glob('*'))
        different_file(self.path, self.protected)
        self.db = sqlite3.connect(self.path, timeout=15, isolation_level=None)
        self.db.row_factory = sqlite3.Row
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS inventory(word_id TEXT PRIMARY KEY,fingerprint TEXT NOT NULL,
                level TEXT,rank INTEGER,eligible INTEGER NOT NULL,data TEXT NOT NULL,findings TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS sources(sha256 TEXT PRIMARY KEY,path TEXT NOT NULL,names TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS events(event_key TEXT PRIMARY KEY,word_id TEXT NOT NULL,
                kind TEXT NOT NULL,fingerprint TEXT NOT NULL,payload TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS states(word_id TEXT PRIMARY KEY,fingerprint TEXT NOT NULL,
                status TEXT NOT NULL,review_event TEXT,decision_event TEXT,application_event TEXT);
            CREATE TABLE IF NOT EXISTS jobs(id INTEGER PRIMARY KEY AUTOINCREMENT,
                owner TEXT NOT NULL,status TEXT NOT NULL,created TEXT NOT NULL);
            CREATE UNIQUE INDEX IF NOT EXISTS one_open_job ON jobs(status) WHERE status='open';
            CREATE TABLE IF NOT EXISTS items(job_id INTEGER NOT NULL REFERENCES jobs(id),word_id TEXT NOT NULL,
                position INTEGER NOT NULL,fingerprint TEXT NOT NULL,snapshot TEXT NOT NULL,
                result_hash TEXT,result TEXT,resolution TEXT,
                PRIMARY KEY(job_id,word_id),UNIQUE(job_id,position));
            CREATE TABLE IF NOT EXISTS conflicts(id INTEGER PRIMARY KEY AUTOINCREMENT,
                job_id INTEGER,word_id TEXT,reason TEXT NOT NULL,details TEXT NOT NULL);
        ''')

    def close(self):
        self.db.close()

    @contextmanager
    def transaction(self):
        self.db.execute('BEGIN IMMEDIATE')
        try:
            yield
        except BaseException:
            self.db.execute('ROLLBACK')
            raise
        else:
            self.db.execute('COMMIT')

    def sync(self):
        inventory, info = inspect_content(self.content_path)
        with self.transaction():
            self.db.execute('DELETE FROM inventory')
            self.db.executemany('INSERT INTO inventory VALUES(?,?,?,?,?,?,?)', [
                (r['id'],r['fingerprint'],r['current'].get('level'),r['current'].get('freq_rank'),
                 int(r['eligible']),canonical(r),canonical(r['findings'])) for r in inventory])
            self.db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('content_snapshot',canonical(info)))
        return self.report()

    def event(self, word_id, kind, fp, payload):
        key = digest(canonical([word_id,kind,fp,payload]).encode())
        self.db.execute('INSERT OR IGNORE INTO events VALUES(?,?,?,?,?)',
                        (key,word_id,kind,fp,canonical(payload)))
        return key

    def source_copy(self, path):
        path = Path(path).resolve(strict=True)
        different_file(path, [self.path, self.header_path])
        data = path.read_bytes()
        sha = digest(data)
        destination = self.work/'sources'/(sha + path.suffix)
        # Refuse ALL known input collisions, not merely textual path equality.
        immutable_file(destination,data,[path,self.content_path,self.path,self.header_path])
        if destination not in self.protected:
            self.protected.append(destination)
        prior = self.db.execute('SELECT names FROM sources WHERE sha256=?',(sha,)).fetchone()
        names = sorted(set(json.loads(prior['names']) if prior else []) | {path.name})
        self.db.execute('INSERT OR REPLACE INTO sources VALUES(?,?,?)',
                        (sha,str(destination),canonical(names)))
        return {'sha256':sha,'path':str(destination),'original_name':path.name}

    def set_state(self, word_id, fp, status, review_event, decision_event=None, application_event=None):
        self.db.execute('INSERT OR REPLACE INTO states VALUES(?,?,?,?,?,?)',
            (word_id,fp,status,review_event,decision_event,application_event))

    def require_synced(self):
        info=self.meta_value('content_snapshot')
        if info is None or digest(self.content_path.read_bytes()) != info['sha256']:
            raise ValueError('Content bytes changed or inventory absent; run sync before accepting work')

    def import_history(self, package, manifest_path, manifest_sha256):
        self.require_synced()
        package = Path(package).resolve(strict=True)
        sums = read_json(package/'SHA256SUMS.json')
        required = {'inputs/'+name for name in HISTORY_FILES}
        if not required <= set(sums):
            raise ValueError('Missing history source hashes')
        for name, spec in sums.items():
            p = (package/name).resolve(strict=True)
            if not p.is_relative_to(package):
                raise ValueError('Source path escapes package')
            b = p.read_bytes()
            if digest(b) != spec['sha256'] or len(b) != spec['bytes']:
                raise ValueError('Source hash/size mismatch: '+name)
        manifest_path = Path(manifest_path).resolve(strict=True)
        if digest(manifest_path.read_bytes()) != manifest_sha256:
            raise ValueError('Approved application manifest hash mismatch')
        documents = {name:read_json(package/'inputs'/name) for name in HISTORY_FILES if name.endswith('.json')}
        old,new = documents['FA-010A-sample.json'],documents['FA-011A-sample.json']
        old_review = adapt_legacy(old,documents['FA-010A-review.json'])
        new_review = documents['FA-011A-review.json']
        validate_review(new,new_review)
        decisions = documents['FA-011A-decisions.json']
        manifest = read_json(manifest_path)
        if manifest['review_sha256'] != sums['inputs/FA-010A-review.json']['sha256']:
            raise ValueError('Application manifest refers to another review')
        if manifest['initial_db_sha256'] != old['input_db']['sha256']:
            raise ValueError('Application manifest initial snapshot mismatch')
        for key,name in [('input_review_sha256','FA-011A-review.json'),('input_sample_sha256','FA-011A-sample.json')]:
            if decisions[key] != sums['inputs/'+name]['sha256']:
                raise ValueError('Decision source hash mismatch')
        if decisions['input_content_sha256'] != new['input_db']['sha256']:
            raise ValueError('Decision content snapshot mismatch')
        if new_review.get('sample_sha256') != sums['inputs/FA-011A-sample.json']['sha256']:
            raise ValueError('Review sample hash mismatch')
        if new_review['input_db']['sha256'] != new['input_db']['sha256'] or old_review['input_db']['sha256'] != old['input_db']['sha256']:
            raise ValueError('Review/source snapshot mismatch')
        def unique(rows):
            result = {r['id']:r for r in rows}
            if len(result) != len(rows): raise ValueError('Duplicate history ID')
            return result
        old_records,new_records = unique(old['records']),unique(new['records'])
        if set(old_records) & set(new_records): raise ValueError('History samples overlap')
        apps = unique(manifest['entries'])
        kept = manifest['unchanged_pilot_ids']
        if len(kept) != len(set(kept)) or set(apps)&set(kept) or set(apps)|set(kept)!=set(old_records):
            raise ValueError('Manifest does not partition original pilot')
        choices = unique(decisions['entries'])
        if set(choices) != set(new_records): raise ValueError('Decision IDs differ from sample')
        inventory = {r['word_id']:r for r in self.db.execute('SELECT * FROM inventory')}
        if not (set(old_records)|set(new_records)) <= set(inventory):
            raise ValueError('History contains missing content IDs; sync or resolve first')
        for word_id, app in apps.items():
            base = old_records[word_id]
            if app['initial_words'] != base['current'] or app['initial_example'] != base['displayed_example']:
                raise ValueError('Application before-values mismatch: '+word_id)
            if app['lemma_fr'] != base['current']['lemma_fr'] or app['pos'] != base['current']['pos']:
                raise ValueError('Application identity mismatch')
        for word_id, choice in choices.items():
            if choice['lemma_fr'] != new_records[word_id]['current']['lemma_fr'] or choice['human_expert_review'] is not False:
                raise ValueError('Unsupported decision identity/expert claim')
            if choice['status'] not in {'retained_current','approved_pending_application','blocked_structure'}:
                raise ValueError('Invalid imported decision status')
            if choice['status']=='retained_current' and choice.get('approved_fields'):
                raise ValueError('Retention decision contains changes')
        # All validation above precedes ledger mutation. Retrying identical input
        # is a no-op, including after sync makes current text stale.
        key = digest(canonical([sums,manifest_sha256]).encode())
        with self.transaction():
            prior = self.db.execute('SELECT value FROM meta WHERE key=?',('import:'+key,)).fetchone()
            if prior: return {'already_imported':True,'import_key':key,'records':json.loads(prior['value'])}
            source_refs = {name:self.source_copy(package/name) for name in sums}
            source_refs['application_manifest'] = self.source_copy(manifest_path)
            self.source_copy(package/'SHA256SUMS.json')
            for base, review, origin in [(old,old_review,'FA-010A'),(new,new_review,'FA-011A')]:
                for sample,row in zip(base['records'],review['records']):
                    wid=row['id']; fp=sample_fingerprint(sample)
                    payload={'adapter':'FA-010A-v1' if origin=='FA-010A' else 'FA-011A-v1',
                        'review':row,'scope':SCOPE,'source_content_sha256':base['input_db']['sha256'],
                        'review_source':source_refs['inputs/'+origin+'-review.json'],
                        'sample_source':source_refs['inputs/'+origin+'-sample.json'],
                        'reported_source_visits':row.get('sources',[]),
                        'source_visits_by_importer':False,'human_expert_review':False,
                        'independent_review_evidence':source_refs['inputs/FA-011A-review-evidence.json'] if origin=='FA-011A' else None}
                    rev=self.event(wid,'review',fp,payload)
                    app_event=None
                    if origin=='FA-010A':
                        status='retained_current' if wid in kept else 'approved_pending_application'
                        decision={'source':source_refs['application_manifest'],'status':status,
                                  'approval_type':'user-accepted model-assisted editorial package; not expert review'}
                        dec=self.event(wid,'decision',fp,decision)
                        if wid in apps:
                            app=apps[wid]; final=copy.deepcopy(sample['current']);final.update(app['final_words'])
                            after=fingerprint(final,[app['final_example']])
                            if inventory[wid]['fingerprint']==after:
                                app_event=self.event(wid,'application',after,dict(
                                    before_fingerprint=fp,after_fingerprint=after,
                                    manifest=source_refs['application_manifest'],
                                    evidence='Approved final semantic fields match current read-only DB; historical runtime not replayed',
                                    source_content_sha256=json.loads(self.db.execute("SELECT value FROM meta WHERE key='content_snapshot'").fetchone()[0])['sha256']))
                                fp=after;status='applied'
                    else:
                        choice=choices[wid];status=choice['status']
                        dec=self.event(wid,'decision',fp,dict(decision=choice,
                            source=source_refs['inputs/FA-011A-decisions.json']))
                    self.set_state(wid,fp,status,rev,dec,app_event)
            count=len(old_records)+len(new_records)
            self.db.execute('INSERT INTO meta VALUES(?,?)',('import:'+key,canonical(count)))
        return {'already_imported':False,'import_key':key,'records':count}

    def status_rows(self):
        return list(self.db.execute('''SELECT i.*,s.status AS saved_status,
            s.fingerprint AS reviewed_fingerprint,s.review_event,s.decision_event,s.application_event
            FROM inventory i LEFT JOIN states s ON s.word_id=i.word_id'''))

    @staticmethod
    def effective_status(row):
        if row['saved_status'] is None: return 'unreviewed'
        if row['reviewed_fingerprint'] != row['fingerprint']: return 'stale'
        return row['saved_status']

    def report(self):
        rows=self.status_rows(); statuses=Counter(self.effective_status(r) for r in rows)
        levels=Counter(r['level'] or 'unknown' for r in rows)
        structural=Counter(f['rule'] for r in rows for f in json.loads(r['findings']))
        snapshot=self.db.execute("SELECT value FROM meta WHERE key='content_snapshot'").fetchone()
        history=self.db.execute("SELECT COUNT(DISTINCT word_id) FROM events WHERE kind='review'").fetchone()[0]
        snapshot_info=json.loads(snapshot[0]) if snapshot else None
        return {'fingerprint_algorithm':ALGORITHM,'scope':SCOPE,'content_snapshot':snapshot_info,
            'content_matches_last_sync':bool(snapshot_info and digest(self.content_path.read_bytes())==snapshot_info['sha256']),
            'total_words':len(rows),'by_level':dict(sorted(levels.items())),
            'normal_eligible':sum(r['eligible'] for r in rows),'not_normal_eligible':sum(not r['eligible'] for r in rows),
            'priority_A1_A2':sum(r['eligible'] and r['level'] in ('A1','A2') for r in rows),
            'priority_A1_A2_unreviewed':sum(r['eligible'] and r['level'] in ('A1','A2') and self.effective_status(r)=='unreviewed' for r in rows),
            'structural_checked':len(rows),'structural_unchecked':0,'structural_rule_counts':dict(structural),
            'semantic_history_distinct_words':history,'without_semantic_history':sum(r['review_event'] is None for r in rows),
            'statuses':dict(sorted(statuses.items())),
            'by_level_and_status':{level:dict(Counter(self.effective_status(r) for r in rows if (r['level'] or 'unknown')==level)) for level in sorted(levels)},
            'approval_pending':statuses['proposal']+statuses['proposed_keep'],
            'application_pending':statuses['approved_pending_application'],
            'human_expert_approval_inferred':False,'language_certification':False,
            'open_jobs':[dict(r) for r in self.db.execute("SELECT * FROM jobs WHERE status='open'")],
            'sources':[dict(r) for r in self.db.execute('SELECT * FROM sources ORDER BY sha256')],
            'last_completion':self.meta_value('last_completion'),
            'other_tables_semantically_reviewed':False}

    def meta_value(self,key):
        row=self.db.execute('SELECT value FROM meta WHERE key=?',(key,)).fetchone()
        return json.loads(row[0]) if row else None

    def short_report(self):
        report=self.report()
        jobs=[]
        for job in report['open_jobs']:
            counts=self.db.execute('''SELECT COUNT(*) AS total,
                SUM(result_hash IS NOT NULL) AS completed,
                SUM(result_hash IS NULL AND resolution IS NULL) AS remaining
                FROM items WHERE job_id=?''',(job['id'],)).fetchone()
            jobs.append(dict(job_id=job['id'],owner=job['owner'],**dict(counts)))
        return {**{key:report[key] for key in ('total_words','normal_eligible',
            'priority_A1_A2','priority_A1_A2_unreviewed','semantic_history_distinct_words',
            'statuses','approval_pending','application_pending','content_matches_last_sync',
            'last_completion')},'open_jobs':jobs,
            'requires_decision':[{'id':x['id'],'status':x['status']} for x in self.exceptions()['open_decisions_and_mismatches']],
            'note':'Structural scan, worker source claims, editorial approval and publication are separate.'}

    def exceptions(self):
        items=[]
        for r in self.status_rows():
            status=self.effective_status(r)
            if status in ('stale','blocked_structure','blocked_source'):
                event=self.db.execute('SELECT payload FROM events WHERE event_key=?',(r['decision_event'] or r['review_event'],)).fetchone()
                items.append(dict(id=r['word_id'],status=status,current_fingerprint=r['fingerprint'],
                                  reviewed_fingerprint=r['reviewed_fingerprint'],context=json.loads(event[0]) if event else None))
            if status=='approved_pending_application' and r['decision_event']:
                d=json.loads(self.db.execute('SELECT payload FROM events WHERE event_key=?',(r['decision_event'],)).fetchone()[0])
                fields=d.get('decision',{}).get('approved_fields',{}).get('words',{})
                outside=sorted(set(fields)-{'meaning_tr','meaning_en','note_tr'})
                if outside:
                    items.append(dict(id=r['word_id'],status='publication_capability_required',
                        fields=outside,reason='Outside existing FA-010B publisher word allowlist; proposal retained, no publication attempted'))
        removed=[dict(r) for r in self.db.execute('SELECT s.word_id,s.status FROM states s LEFT JOIN inventory i ON i.word_id=s.word_id WHERE i.word_id IS NULL')]
        return {'open_decisions_and_mismatches':items,'removed_content_history_preserved':removed,
                'result_conflicts':[dict(r) for r in self.db.execute('SELECT * FROM conflicts ORDER BY id')]}

    def job_view(self,job_id):
        job=self.db.execute('SELECT * FROM jobs WHERE id=?',(job_id,)).fetchone()
        if job is None: raise ValueError('Unknown job')
        items=list(self.db.execute('SELECT * FROM items WHERE job_id=? ORDER BY position',(job_id,)))
        remaining=[]
        for i in items:
            if i['result_hash'] or i['resolution']:continue
            current=self.db.execute('SELECT fingerprint FROM inventory WHERE word_id=?',(i['word_id'],)).fetchone()
            remaining.append(dict(id=i['word_id'],position=i['position'],fingerprint=i['fingerprint'],
                current_fingerprint=current[0] if current else None,
                snapshot=json.loads(i['snapshot']),
                text_version_matches=current is not None and current[0]==i['fingerprint']))
        return {'job_id':job['id'],'owner':job['owner'],'status':job['status'],'algorithm':ALGORITHM,
            'total':len(items),'completed':sum(bool(i['result_hash']) for i in items),
            'superseded':sum(bool(i['resolution']) for i in items),'remaining':remaining,
            'continuation':'Use the same owner/job; no background worker runs after the active session ends.'}

    def next(self,size=25,owner='local-codex'):
        self.require_synced()
        if size<1 or size>100: raise ValueError('Job size must be 1..100')
        with self.transaction():
            active=self.db.execute("SELECT * FROM jobs WHERE status='open'").fetchone()
            if active:
                if active['owner']!=owner: raise ValueError('Open job belongs to another owner; use its explicit owner to resume')
                return self.job_view(active['id'])
            # Learning eligibility is a priority signal, not an editorial
            # exclusion: needs_review content must remain reachable for review.
            candidates=[r for r in self.status_rows() if self.effective_status(r) in ('unreviewed','stale')]
            candidates.sort(key=lambda r: (0 if r['level'] in ('A1','A2') else 1,
                            any(f['severity']=='structural_error' for f in json.loads(r['findings'])),
                            not r['eligible'],{'A1':0,'A2':1,'B1':2,'B2':3,'C1':4,'C2':5}.get(r['level'],6),
                            r['rank'] is not None,r['rank'] if r['rank'] is not None else 0,r['word_id']))
            if not candidates:return {'job_id':None,'remaining':[],'reason':'No unreviewed/stale inventory records'}
            job=self.db.execute('INSERT INTO jobs(owner,status,created) VALUES(?,?,?)',
                (owner,'open',datetime.now(timezone.utc).isoformat())).lastrowid
            for pos,r in enumerate(candidates[:size],1):
                self.db.execute('INSERT INTO items(job_id,word_id,position,fingerprint,snapshot) VALUES(?,?,?,?,?)',
                    (job,r['word_id'],pos,r['fingerprint'],r['data']))
            return self.job_view(job)

    def resume(self,job_id,owner='local-codex'):
        self.require_synced()
        view=self.job_view(job_id)
        if view['owner']!=owner: raise ValueError('Job owner mismatch')
        return view

    def complete(self,job_id,document,owner='local-codex'):
        self.require_synced()
        if not isinstance(document,dict) or not isinstance(document.get('results'),list):
            raise ValueError('Expected JSON object with results array; nothing completed')
        job=self.db.execute('SELECT * FROM jobs WHERE id=?',(job_id,)).fetchone()
        if job is None or job['owner']!=owner: raise ValueError('Unknown job or wrong owner')
        accepted=[];repeated=[];rejected=[]
        for result in document['results']:
            wid=result.get('id') if isinstance(result,dict) else None
            try:
                with self.transaction():
                    item=self.db.execute('SELECT * FROM items WHERE job_id=? AND word_id=?',(job_id,wid)).fetchone()
                    if item is None: raise ValueError('ID is not part of this fixed job')
                    h=digest(canonical(result).encode())
                    if item['result_hash']:
                        if item['result_hash']!=h: raise ValueError('Conflicting result for already completed item')
                        repeated.append(wid);continue
                    if item['resolution']: raise ValueError('Job item already superseded; obtain a new job')
                    state=self.db.execute('SELECT * FROM states WHERE word_id=?',(wid,)).fetchone()
                    if state and state['fingerprint']==item['fingerprint']:
                        raise ValueError('Current review/decision already exists; fixed job cannot overwrite it')
                    current=self.db.execute('SELECT fingerprint FROM inventory WHERE word_id=?',(wid,)).fetchone()
                    if current is None or current[0]!=item['fingerprint'] or result.get('fingerprint')!=item['fingerprint']:
                        raise ValueError('Text fingerprint mismatch; sync/resume and supersede explicitly')
                    if result.get('algorithm')!=ALGORITHM or result.get('scope')!=SCOPE:
                        raise ValueError('Review fingerprint algorithm/scope mismatch')
                    status=result.get('status')
                    if status not in RESULT_STATUSES: raise ValueError('Completion cannot grant editorial approval or application')
                    review=result.get('review')
                    if not isinstance(review,dict): raise ValueError('Missing record-level review')
                    snapshot=json.loads(item['snapshot'])
                    ex=snapshot['displayed_examples']
                    sample={'records':[dict(id=wid,current=snapshot['current'],displayed_example=ex[0] if len(ex)==1 else None)]}
                    validate_review(sample,{'records':[review]})
                    if not review.get('target_sense') or not (review.get('reason') or review.get('issue')):
                        raise ValueError('Target sense and record-specific rationale are required')
                    if not result.get('reviewer') or not result.get('date'):
                        raise ValueError('Reviewer type and date are required')
                    if status in ('proposed_keep','proposal') and review['french_source_status']!='source_supported':
                        raise ValueError('No reported body inspection; use blocked_source instead')
                    if status=='blocked_source' and review['french_source_status']!='not_externally_verified':
                        raise ValueError('Blocked source cannot claim source verification')
                    if status=='proposed_keep' and review['proposed_fields']: raise ValueError('Keep result includes changes')
                    if status=='proposal' and not review['proposed_fields']: raise ValueError('Proposal has no changes')
                    event=self.event(wid,'review',item['fingerprint'],dict(result=result,
                        source_visits='worker-reported; not fetched or independently proved by this CLI',
                        human_expert_review=False,source_content_sha256=self.meta_value('content_snapshot')['sha256']))
                    self.set_state(wid,item['fingerprint'],status,event)
                    self.db.execute('UPDATE items SET result_hash=?,result=? WHERE job_id=? AND word_id=?',
                        (h,canonical(result),job_id,wid))
                accepted.append(wid)
            except (ValueError,KeyError,TypeError,sqlite3.Error) as error:
                rejected.append({'id':wid,'reason':str(error)})
                with self.transaction():
                    self.db.execute('INSERT INTO conflicts(job_id,word_id,reason,details) VALUES(?,?,?,?)',
                                    (job_id,wid,str(error),canonical(result)))
        summary={'job_id':job_id,'accepted':accepted,'repeated':repeated,'rejected':rejected}
        with self.transaction():
            left=self.db.execute('SELECT COUNT(*) FROM items WHERE job_id=? AND result_hash IS NULL AND resolution IS NULL',(job_id,)).fetchone()[0]
            if not left:self.db.execute("UPDATE jobs SET status='complete' WHERE id=?",(job_id,))
            self.db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)',('last_completion',canonical(summary)))
        summary['remaining']=left
        return summary

    def supersede(self,job_id,word_id,owner='local-codex'):
        """Explicitly release changed/removed text, never pretend it was reviewed."""
        self.resume(job_id,owner)
        with self.transaction():
            item=self.db.execute('SELECT * FROM items WHERE job_id=? AND word_id=?',(job_id,word_id)).fetchone()
            current=self.db.execute('SELECT fingerprint FROM inventory WHERE word_id=?',(word_id,)).fetchone()
            if item is None or item['result_hash'] or (current and current[0]==item['fingerprint']):
                raise ValueError('Only uncompleted, changed/removed text can be superseded')
            self.db.execute('UPDATE items SET resolution=? WHERE job_id=? AND word_id=?',('superseded_text',job_id,word_id))
            left=self.db.execute('SELECT COUNT(*) FROM items WHERE job_id=? AND result_hash IS NULL AND resolution IS NULL',(job_id,)).fetchone()[0]
            if not left:self.db.execute("UPDATE jobs SET status='complete' WHERE id=?",(job_id,))
        return self.job_view(job_id)

    def spot_check(self,size,seed):
        if size<0:raise ValueError('Negative sample size')
        rows=sorted((r for r in self.status_rows() if self.effective_status(r)=='proposed_keep'),key=lambda r:r['word_id'])
        selected=random.Random(seed).sample(rows,min(size,len(rows)))
        return {'seed':seed,'population':len(rows),'selection_rule':'Python Random.sample of ID-sorted current proposed_keep worker results',
                'algorithm':'spot-check-v1','selected':[{'id':r['word_id'],'fingerprint':r['fingerprint']} for r in selected],
                'approval_granted':False,'unselected_records_certified':False}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work',required=True)
    sub=parser.add_subparsers(dest='command',required=True)
    init=sub.add_parser('init');init.add_argument('--db',required=True)
    sub.add_parser('sync')
    imp=sub.add_parser('import-history');imp.add_argument('--package',required=True)
    imp.add_argument('--manifest',required=True);imp.add_argument('--manifest-sha256',required=True)
    for name in ('status','report','exceptions'):
        p=sub.add_parser(name);p.add_argument('--output')
    p=sub.add_parser('next');p.add_argument('--size',type=int,default=25);p.add_argument('--owner',default='local-codex');p.add_argument('--output')
    p=sub.add_parser('resume');p.add_argument('--job',type=int,required=True);p.add_argument('--owner',default='local-codex');p.add_argument('--output')
    p=sub.add_parser('complete');p.add_argument('--job',type=int,required=True);p.add_argument('--owner',default='local-codex');p.add_argument('--results',required=True)
    p=sub.add_parser('supersede');p.add_argument('--job',type=int,required=True);p.add_argument('--owner',default='local-codex');p.add_argument('--id',required=True)
    p=sub.add_parser('spot-check');p.add_argument('--size',type=int,default=5);p.add_argument('--seed',type=int,required=True)
    args=parser.parse_args();queue=None
    try:
        queue=ReviewQueue(args.work,getattr(args,'db',None))
        cmd=args.command
        if cmd in ('init','sync'):value=queue.sync()
        elif cmd=='import-history':value=queue.import_history(args.package,args.manifest,args.manifest_sha256)
        elif cmd=='status':value=queue.short_report()
        elif cmd=='report':value=queue.report()
        elif cmd=='exceptions':value=queue.exceptions()
        elif cmd=='next':value=queue.next(args.size,args.owner)
        elif cmd=='resume':value=queue.resume(args.job,args.owner)
        elif cmd=='complete':value=queue.complete(args.job,read_json(args.results),args.owner)
        elif cmd=='supersede':value=queue.supersede(args.job,args.id,args.owner)
        else:value=queue.spot_check(args.size,args.seed)
        output=getattr(args,'output',None)
        if output:
            immutable_file(output,(json.dumps(value,ensure_ascii=False,indent=2)+'\n').encode('utf-8'),queue.protected+[queue.path])
            print(json.dumps({'output':output,'sha256':digest(Path(output).read_bytes())}))
        else:print(json.dumps(value,ensure_ascii=False,indent=2))
        return 1 if value.get('rejected') else 0
    except (ValueError,KeyError,TypeError,OSError,sqlite3.Error,AssertionError) as error:
        print(json.dumps({'error':str(error)},ensure_ascii=False),file=sys.stderr)
        return 2
    finally:
        if queue:queue.close()


if __name__=='__main__':
    sys.exit(main())
