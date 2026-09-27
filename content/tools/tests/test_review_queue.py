"""Synthetic ledger/CLI tests. Source visits below are synthetic worker claims."""
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
import copy
import hashlib
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import threading
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from review_queue import (ALGORITHM, SCOPE, ReviewQueue, adapt_legacy, canonical,
                          digest, fingerprint, immutable_file, read_json)

TOOLS=Path(__file__).resolve().parents[1]


def create_content(path,count=210):
    with closing(sqlite3.connect(path)) as db, db:
        db.executescript('''CREATE TABLE words(id TEXT PRIMARY KEY,lemma_fr TEXT,pos TEXT,
            level TEXT,freq_rank INTEGER,is_function INTEGER,needs_review INTEGER,reviewed INTEGER,
            confidence REAL,tr_path TEXT,article TEXT,gender TEXT,plural_fr TEXT,ipa TEXT,
            meaning_tr TEXT,meaning_en TEXT,meaning_en_2 TEXT,note_tr TEXT,literal_tr TEXT,
            register TEXT,is_idiom INTEGER);
            CREATE TABLE examples(id INTEGER PRIMARY KEY,word_id TEXT,ordinal INTEGER,
            sentence_fr TEXT,sentence_en TEXT,sentence_tr TEXT,sentence_fr_id INTEGER,
            sentence_en_id INTEGER,sentence_tr_id INTEGER,author_fr TEXT,author_en TEXT,
            author_tr TEXT,tr_direct INTEGER,max_level TEXT);
            CREATE TABLE meta(key TEXT PRIMARY KEY,value TEXT);
            CREATE TABLE verbs(id TEXT,meaning_tr TEXT);
        ''')
        for i in range(count):
            wid=f'synthetic_{i:04d}'
            db.execute('INSERT INTO words VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (wid,f'mot{i}','NOM','A1' if i%2==0 else 'A2',i,0,0,i%2,1.0,'synthetic',
                 'le','m',None,None,f'anlam{i}',f'meaning{i}',None,None,None,None,0))
            db.execute('INSERT INTO examples VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (i+1,wid,0,f'Exemple synthétique {i}.',f'Synthetic {i}.',f'Sentetik {i}.',
                 i+1000,i+2000,i+3000,'synthetic FR','synthetic EN','synthetic TR',1,'A1'))


def capture(db_path,ids):
    with closing(sqlite3.connect(db_path)) as db:
        db.row_factory=sqlite3.Row
        records=[]
        for wid in ids:
            word=dict(db.execute('SELECT * FROM words WHERE id=?',(wid,)).fetchone())
            ex=dict(db.execute('SELECT * FROM examples WHERE word_id=? AND ordinal=0',(wid,)).fetchone())
            records.append(dict(id=wid,current=word,displayed_example=ex,same_fr_sentence_links=[]))
    return {'records':records,'input_db':{'sha256':digest(db_path.read_bytes())}}


def base_review(sample):
    return {'input_db':sample['input_db'],'records':[
        dict(id=r['id'],current=copy.deepcopy(r['current']),current_example=copy.deepcopy(r['displayed_example']),
             proposed_fields={},human_review_performed=False,example_origin='mevcut',sources=[],
             french_source_status='not_externally_verified',target_sense='synthetic scope',reason='Synthetic control')
        for r in sample['records']]}


def history_fixture(root,db):
    package=root/'package';(package/'inputs').mkdir(parents=True)
    ids=[f'synthetic_{i:04d}' for i in range(150)]
    old=capture(db,ids[:50]);oldrev=base_review(old)
    manifest={'initial_db_sha256':old['input_db']['sha256'],'entries':[],
              'unchanged_pilot_ids':ids[36:50]}
    for r in old['records'][:36]:
        manifest['entries'].append(dict(id=r['id'],lemma_fr=r['current']['lemma_fr'],pos='NOM',
            initial_words=r['current'],initial_example=r['displayed_example'],
            final_words={'meaning_tr':'onaylı '+r['current']['meaning_tr']},final_example=r['displayed_example']))
    with closing(sqlite3.connect(db)) as conn, conn:
        for entry in manifest['entries']:
            conn.execute('UPDATE words SET meaning_tr=? WHERE id=?',
                         (entry['final_words']['meaning_tr'],entry['id']))
    new=capture(db,ids[50:]);newrev=base_review(new)
    decisions={'input_content_sha256':new['input_db']['sha256'],'entries':[]}
    for i,r in enumerate(new['records']):
        status='retained_current' if i<50 else 'approved_pending_application' if i<99 else 'blocked_structure'
        proposed={'words':{'meaning_tr':'öneri '+r['current']['meaning_tr']}} if status=='approved_pending_application' else {}
        newrev['records'][i]['proposed_fields']=proposed
        decisions['entries'].append(dict(id=r['id'],lemma_fr=r['current']['lemma_fr'],
            status=status,approved_fields=proposed,human_expert_review=False,
            review_scope=SCOPE,decision_note='Synthetic decision, not human approval'))
    def dump(name,data):
        p=package/'inputs'/name;p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        return digest(p.read_bytes())
    dump('FA-010A-sample.json',old)
    manifest['review_sha256']=dump('FA-010A-review.json',oldrev)
    decisions['input_sample_sha256']=dump('FA-011A-sample.json',new)
    newrev['sample_sha256']=decisions['input_sample_sha256']
    decisions['input_review_sha256']=dump('FA-011A-review.json',newrev)
    dump('FA-011A-decisions.json',decisions)
    dump('FA-011A-review-evidence.json',{'independently_opened_sources':[],
        'not_performed':['Synthetic fixture: no source visits took place']})
    for name in ('FA-010A-notes.md','FA-011A-notes.md'):
        (package/'inputs'/name).write_text('Synthetic history notes\n',encoding='utf-8')
    sums={p.relative_to(package).as_posix():{'sha256':digest(p.read_bytes()),'bytes':p.stat().st_size}
          for p in (package/'inputs').iterdir()}
    (package/'SHA256SUMS.json').write_text(json.dumps(sums),encoding='utf-8')
    mp=root/'approved.json';mp.write_text(json.dumps(manifest,ensure_ascii=False),encoding='utf-8')
    return package,mp,digest(mp.read_bytes())


def worker_result(item,status='proposed_keep'):
    snap=item['snapshot'];ex=snap['displayed_examples'][0]
    return dict(id=item['id'],fingerprint=item['fingerprint'],algorithm=ALGORITHM,scope=SCOPE,
        reviewer='synthetic worker; no actual visit',date='2026-09-12',status=status,
        review=dict(id=item['id'],current=snap['current'],current_example=ex,
            human_review_performed=False,proposed_fields={},example_origin='mevcut',
            french_source_status='source_supported',target_sense='synthetic meaning',
            reason='Controlled synthetic observation, not a language review',
            sources=[{'url':'https://example.invalid/synthetic','access_status':'body_inspected',
                      'access_date':'2026-09-12','supports':'synthetic test claim'}]))


class ReviewQueueTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='FA012-test-')
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name);self.content=self.root/'content.db'
        create_content(self.content)
        self.work=self.root/'work';self.q=ReviewQueue(self.work,self.content);self.q.sync()
        self.addCleanup(lambda:self.q.close())

    def import_history(self):
        args=history_fixture(self.root,self.content);self.q.sync()
        return args,self.q.import_history(*args)

    def mutate(self,sql,params=()):
        with closing(sqlite3.connect(self.content)) as db,db:db.execute(sql,params)

    def test_150_history_unique_idempotent_and_approval_is_not_application(self):
        args,result=self.import_history()
        self.assertEqual(result['records'],150)
        report=self.q.report()
        self.assertEqual(report['statuses'],{'applied':36,'approved_pending_application':49,
            'blocked_structure':1,'retained_current':64,'unreviewed':60})
        before=list(self.q.db.execute('SELECT * FROM events'))
        self.assertTrue(self.q.import_history(*args)['already_imported'])
        self.assertEqual([tuple(r) for r in self.q.db.execute('SELECT * FROM events')],[tuple(r) for r in before])
        job=self.q.next()
        self.assertTrue(all(int(x['id'].split('_')[1])>=150 for x in job['remaining']))
        self.assertEqual(self.q.report()['semantic_history_distinct_words'],150)
        self.assertFalse(report['human_expert_approval_inferred'])
        apps=[json.loads(r[0]) for r in self.q.db.execute("SELECT payload FROM events WHERE kind='application'")]
        self.assertEqual(len(apps),36)
        self.assertTrue(all(x['before_fingerprint']!=x['after_fingerprint'] for x in apps))

    def test_card_specific_fingerprint_stales_meaning_example_and_pos_only(self):
        self.import_history()
        self.mutate("UPDATE words SET meaning_tr='third text' WHERE id='synthetic_0000'")
        self.mutate("UPDATE examples SET sentence_tr='changed' WHERE word_id='synthetic_0050'")
        self.mutate("UPDATE words SET pos='ADJ' WHERE id='synthetic_0051'")
        self.q.sync()
        report=self.q.report()
        self.assertEqual(report['statuses']['stale'],3)
        self.assertEqual(report['statuses']['applied'],35)
        self.assertEqual(report['statuses']['retained_current'],62)
        self.assertEqual(report['semantic_history_distinct_words'],150)

    def test_global_hash_physical_row_id_and_review_flags_do_not_invalidate(self):
        self.import_history();before=self.q.report()
        self.mutate("INSERT INTO meta VALUES('unrelated','changed')")
        self.mutate('UPDATE examples SET id=id+10000')
        self.mutate('UPDATE words SET reviewed=1,confidence=0.2,tr_path=\'other\'')
        self.q.sync();after=self.q.report()
        self.assertNotEqual(before['content_snapshot']['sha256'],after['content_snapshot']['sha256'])
        self.assertEqual(before['statuses'],after['statuses'])

    def test_applied_status_requires_current_approved_fields_not_manifest_existence(self):
        args=history_fixture(self.root,self.content)
        self.mutate("UPDATE words SET meaning_tr='anlam0' WHERE id='synthetic_0000'")
        self.mutate("UPDATE words SET meaning_tr='unexpected' WHERE id='synthetic_0001'")
        self.q.sync();self.q.import_history(*args)
        statuses=self.q.report()['statuses']
        self.assertEqual(statuses['applied'],34)
        self.assertEqual(statuses['approved_pending_application'],50)
        self.assertEqual(statuses['stale'],1)

    def test_partial_sql_failure_restart_resume_idempotency_and_conflict(self):
        job=self.q.next(3);a,b,c=map(worker_result,job['remaining'])
        self.q.db.execute(f"""CREATE TRIGGER reject_one BEFORE INSERT ON states
            WHEN NEW.word_id='{b['id']}' BEGIN SELECT RAISE(ABORT,'synthetic failure'); END""")
        out=self.q.complete(job['job_id'],{'results':[a,b,c]})
        self.assertEqual(out['accepted'],[a['id'],c['id']]);self.assertEqual(out['remaining'],1)
        self.assertIn('synthetic failure',out['rejected'][0]['reason'])
        self.assertEqual(self.q.db.execute('SELECT COUNT(*) FROM events WHERE word_id=?',(b['id'],)).fetchone()[0],0)
        self.q.db.execute('DROP TRIGGER reject_one');self.q.close();self.q=ReviewQueue(self.work)
        self.assertEqual([x['id'] for x in self.q.next()['remaining']],[b['id']])
        self.assertEqual(self.q.complete(job['job_id'],{'results':[a]})['repeated'],[a['id']])
        conflict=copy.deepcopy(a);conflict['review']['reason']='conflicting rationale'
        self.assertIn('Conflicting result',self.q.complete(job['job_id'],{'results':[conflict]})['rejected'][0]['reason'])
        self.assertEqual(self.q.complete(job['job_id'],{'results':[b]})['remaining'],0)
        self.assertEqual(self.q.resume(job['job_id'])['completed'],3)

    def test_unsynced_and_changed_text_reject_result_and_can_be_superseded(self):
        job=self.q.next(1);result=worker_result(job['remaining'][0])
        self.mutate('UPDATE words SET meaning_tr=? WHERE id=?',('changed',result['id']))
        with self.assertRaisesRegex(ValueError,'run sync'):self.q.complete(job['job_id'],{'results':[result]})
        self.q.sync()
        out=self.q.complete(job['job_id'],{'results':[result]})
        self.assertIn('fingerprint mismatch',out['rejected'][0]['reason'])
        self.assertFalse(self.q.resume(job['job_id'])['remaining'][0]['text_version_matches'])
        self.q.supersede(job['job_id'],result['id'])
        next_job=self.q.next(1)
        self.assertNotEqual(next_job['job_id'],job['job_id'])
        self.assertEqual(next_job['remaining'][0]['id'],result['id'])
        self.assertNotEqual(next_job['remaining'][0]['fingerprint'],result['fingerprint'])

    def test_missing_source_title_only_expert_and_application_claims_rejected(self):
        job=self.q.next(1);good=worker_result(job['remaining'][0])
        for change in ('missing','title','expert','application'):
            result=copy.deepcopy(good)
            if change=='missing':result['review']['sources']=[]
            if change=='title':result['review']['sources'][0]['access_status']='title_only'
            if change=='expert':result['review']['human_review_performed']=True
            if change=='application':result['status']='applied'
            out=self.q.complete(job['job_id'],{'results':[result]})
            self.assertEqual(out['accepted'],[]);self.assertEqual(out['remaining'],1)
        blocked=copy.deepcopy(good);blocked['status']='blocked_source'
        blocked['review']['sources']=[];blocked['review']['french_source_status']='not_externally_verified'
        self.assertEqual(self.q.complete(job['job_id'],{'results':[blocked]})['accepted'],[blocked['id']])
        self.assertEqual(self.q.report()['statuses']['blocked_source'],1)
        self.assertEqual(len(self.q.exceptions()['open_decisions_and_mismatches']),1)

    def test_adapter_derives_attribution_without_inventing_visits(self):
        sample=capture(self.content,['synthetic_0000']);review=base_review(sample)
        original=copy.deepcopy(review)
        row=review['records'][0];row.pop('sources');row.pop('french_source_status')
        row['proposed_fields']={'example':{'sentence_tr':'adapted'}}
        adapted=adapt_legacy(sample,review)['records'][0]
        self.assertEqual(adapted['sources'],[])
        self.assertEqual(adapted['french_source_status'],'not_externally_verified')
        self.assertNotIn('sources',row)
        plan=adapted['language_attribution_plan']
        self.assertFalse(plan['tr']['retain_original_id_author']);self.assertTrue(plan['fr']['retain_original_id_author'])
        self.assertIn('adapter-derived',plan['tr']['derivation'])
        self.assertEqual(row['current'],original['records'][0]['current'])

    def test_same_next_two_connections_one_job_and_other_owner_rejected(self):
        gate=threading.Barrier(2)
        def run():
            q=ReviewQueue(self.work)
            try:gate.wait();return q.next(5)
            finally:q.close()
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures=[pool.submit(run) for _ in range(2)]
            first,second=[f.result() for f in futures]
        self.assertEqual(first,second)
        self.assertEqual(self.q.db.execute('SELECT COUNT(*) FROM jobs').fetchone()[0],1)
        with self.assertRaisesRegex(ValueError,'another owner'):self.q.next(owner='different-worker')

    def test_deterministic_spot_check_samples_kept_worker_results_not_only_issues(self):
        job=self.q.next(8);results=[worker_result(i) for i in job['remaining']]
        self.q.complete(job['job_id'],{'results':results})
        one=self.q.spot_check(3,2026);two=self.q.spot_check(3,2026)
        self.assertEqual(one,two);self.assertEqual(one['population'],8)
        self.assertEqual(len(one['selected']),3)
        self.assertFalse(one['approval_granted'])
        self.assertEqual(self.q.report()['approval_pending'],8)

    def test_readonly_scan_structural_hints_are_not_semantic_approval(self):
        self.mutate("UPDATE words SET meaning_tr='',needs_review=1 WHERE id='synthetic_0000'")
        self.mutate("UPDATE words SET meaning_tr='same' WHERE id IN ('synthetic_0002','synthetic_0003')")
        self.mutate("DELETE FROM examples WHERE word_id='synthetic_0001'")
        self.mutate("INSERT INTO examples(id,word_id,ordinal) VALUES(90000,'absent',0)")
        self.mutate("INSERT INTO examples(id,word_id,ordinal) VALUES(90001,'synthetic_0002',0)")
        before=self.content.read_bytes();report=self.q.sync()
        self.assertEqual(before,self.content.read_bytes())
        self.assertEqual(report['normal_eligible'],209)
        self.assertEqual(report['statuses'],{'unreviewed':210})
        self.assertEqual(report['structural_rule_counts']['ordinal_zero_multiple'],1)
        self.assertEqual(report['structural_rule_counts']['same_meaning_text_not_necessarily_error'],2)
        self.assertEqual(report['content_snapshot']['orphan_example_word_ids'],[{'word_id':'absent','row_count':1}])
        self.assertFalse(report['language_certification'])
        self.assertTrue(all(i['id'] not in {'synthetic_0000','synthetic_0001','synthetic_0002'} for i in self.q.next()['remaining']))

    def test_input_outputs_and_source_hardlink_collisions_preserve_bytes(self):
        before=self.content.read_bytes()
        with self.assertRaisesRegex(ValueError,'overlaps'):immutable_file(self.content,b'bad',[self.content])
        hard=self.root/'hard.json';hard.hardlink_to(self.content)
        with self.assertRaisesRegex(ValueError,'overlaps'):immutable_file(hard,b'bad',[self.content])
        output=self.root/'existing.json';output.write_bytes(b'existing')
        with self.assertRaisesRegex(ValueError,'overwrite'):immutable_file(output,b'new',[self.content])
        self.assertEqual(output.read_bytes(),b'existing')
        source=self.root/'source.json';source.write_bytes(b'original')
        ref=self.q.source_copy(source)
        self.assertEqual(Path(ref['path']).read_bytes(),b'original')
        self.assertEqual(self.q.source_copy(source),ref)
        # Pre-existing content-hardlink at future source-copy output is rejected.
        other=self.root/'other.json';other.write_bytes(b'other')
        dst=self.work/'sources'/(digest(b'other')+'.json');dst.hardlink_to(self.content)
        with self.assertRaisesRegex(ValueError,'overlaps'):self.q.source_copy(other)
        self.assertEqual(self.content.read_bytes(),before)
        protected=self.root/'bad-work';protected.mkdir()
        (protected/'registry.sqlite').hardlink_to(self.content)
        with self.assertRaisesRegex(ValueError,'overlaps'):ReviewQueue(protected,self.content)
        self.assertEqual(self.content.read_bytes(),before)

    def test_learning_ineligible_and_missing_example_remain_reachable_for_review(self):
        self.mutate('UPDATE words SET needs_review=1')
        self.mutate('DELETE FROM examples')
        self.q.sync()
        self.assertEqual(self.q.report()['normal_eligible'],0)
        job=self.q.next(1)
        self.assertEqual(len(job['remaining']),1)
        item=job['remaining'][0]
        result=dict(id=item['id'],fingerprint=item['fingerprint'],algorithm=ALGORITHM,scope=SCOPE,
            reviewer='synthetic structural reviewer',date='2026-09-12',status='blocked_structure',
            review=dict(id=item['id'],current=item['snapshot']['current'],current_example=None,
                proposed_fields={},human_review_performed=False,example_origin='mevcut',sources=[],
                french_source_status='not_externally_verified',target_sense='unresolved',reason='Missing ordinal=0 example'))
        self.assertEqual(self.q.complete(job['job_id'],{'results':[result]})['accepted'],[item['id']])
        self.assertEqual(self.q.report()['statuses']['blocked_structure'],1)

    def test_hash_mismatch_and_missing_id_import_do_not_grant_any_status(self):
        args=history_fixture(self.root,self.content);self.q.sync()
        sample=args[0]/'inputs/FA-011A-review.json';sample.write_bytes(sample.read_bytes()+b' ')
        with self.assertRaisesRegex(ValueError,'hash/size'):self.q.import_history(*args)
        self.assertEqual(self.q.report()['semantic_history_distinct_words'],0)
        sample.write_bytes(sample.read_bytes()[:-1])
        self.mutate("DELETE FROM words WHERE id='synthetic_0001'")
        self.q.sync()
        with self.assertRaisesRegex(ValueError,'missing content IDs'):self.q.import_history(*args)
        self.assertEqual(self.q.report()['semantic_history_distinct_words'],0)

    def test_cli_malformed_json_partial_and_fresh_report_output(self):
        script=TOOLS/'review_queue.py'
        def cli(*args):
            return subprocess.run([sys.executable,'-B',str(script),'--work',str(self.work),*map(str,args)],capture_output=True,text=True)
        job=self.q.next(2);bad=self.root/'bad.json';bad.write_text('{bad')
        out=cli('complete','--job',job['job_id'],'--results',bad)
        self.assertEqual(out.returncode,2);self.assertEqual(self.q.resume(job['job_id'])['completed'],0)
        data=self.root/'partial.json';data.write_text(json.dumps({'results':[worker_result(job['remaining'][0]),{'id':'unknown'}]}),encoding='utf-8')
        out=cli('complete','--job',job['job_id'],'--results',data)
        self.assertEqual(out.returncode,1,out.stderr)
        self.assertEqual(json.loads(out.stdout)['remaining'],1)
        report=self.root/'report.json'
        self.assertEqual(cli('report','--output',report).returncode,0)
        short=json.loads(cli('status').stdout)
        self.assertNotIn('sources',short)
        self.assertEqual(short['open_jobs'][0]['remaining'],1)
        before=self.content.read_bytes()
        self.assertEqual(cli('report','--output',self.content).returncode,2)
        self.assertEqual(self.content.read_bytes(),before)


if __name__=='__main__':unittest.main()
