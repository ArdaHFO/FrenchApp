"""Read-only editorial sample export; no semantic verification is inferred."""
import argparse
from contextlib import closing
import hashlib
import json
from pathlib import Path
import sqlite3


def extract(db_path, quotas=None, excluded_ids=(), task='FA-010A'):
    path = Path(db_path).resolve(strict=True)
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    quotas = quotas if quotas is not None else {'A1': 30, 'A2': 20}
    excluded_ids = sorted(set(excluded_ids))
    excluded = set(excluded_ids)
    records, pools, ties, before_exclusion = [], {}, {}, {}
    with closing(sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)) as db:
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA query_only=ON')
        for level, count in quotas.items():
            if count < 0:
                raise ValueError('Negative quota')
            pool = db.execute('''SELECT * FROM words WHERE level=?
                AND is_function<>1 AND needs_review<>1
                ORDER BY freq_rank, id COLLATE BINARY''', (level,)).fetchall()
            before_exclusion[level] = len(pool)
            pool = [row for row in pool if row['id'] not in excluded]
            pools[level] = len(pool)
            selected = pool[:count]
            ranks = [row['freq_rank'] for row in selected]
            ties[level] = sorted({rank for rank in ranks if
                sum(row['freq_rank'] == rank for row in pool) > 1})
            for index, row in enumerate(selected, 1):
                examples = db.execute('SELECT * FROM examples WHERE word_id=? AND ordinal=0 ORDER BY id',
                                      (row['id'],)).fetchall()
                if len(examples) > 1:
                    raise ValueError(f"Ambiguous ordinal=0 example: {row['id']}")
                ex = dict(examples[0]) if examples else None
                shared = [] if ex is None else [dict(r) for r in db.execute('''
                    SELECT word_id, id AS example_row_id, ordinal FROM examples
                    WHERE sentence_fr_id=? ORDER BY word_id,ordinal,id''', (ex['sentence_fr_id'],))]
                records.append({'id': row['id'], 'level_order': index,
                                'current': dict(row), 'displayed_example': ex,
                                'same_fr_sentence_links': shared,
                                'external_verification': 'not_performed_by_extractor',
                                'human_review_performed': False})
    after = hashlib.sha256(path.read_bytes()).hexdigest()
    if before != after:
        raise ValueError('Input database changed during extraction')
    return {'task': task, 'input_db': {'path': str(db_path), 'sha256': before,
             'size_bytes': path.stat().st_size}, 'selection': {
             'quotas': quotas, 'eligible_counts': pools,
             'eligible_counts_before_exclusion': before_exclusion,
             'excluded_ids': excluded_ids, 'exclusion_order': 'Before quota, after normal content eligibility; no progress read.',
             'filter': 'level exact; is_function != 1; needs_review != 1; no theme; reviewed unrestricted',
             'order': 'freq_rank ASC, id COLLATE BINARY ASC', 'tie_ranks_in_selected_pool': ties,
             'app_order_difference': 'App orders only by freq_rank; id is an explicit pilot-only tie-break. No production ordering is changed.',
             'progress': 'No user progress read. Eligible candidates before SRS, independently per level; not an SRS session.',
             'code': ['lib/data/repositories.dart:87-148', 'lib/data/repositories.dart:187-234'],
             'example_rule': 'Only examples.ordinal=0, as WordRepository.load and WordCard use it; front visibility is a user setting.',
             'ids': [r['id'] for r in records]}, 'records': records}


def validate_review(sample, review):
    """Structural/provenance consistency only, not French/Turkish correctness."""
    base = {r['id']: r for r in sample['records']}
    records = review['records']
    if len(records) != len(base) or {r['id'] for r in records} != set(base):
        raise ValueError('Review IDs do not match sample exactly')
    if [r['id'] for r in records] != [r['id'] for r in sample['records']]:
        raise ValueError('Review order differs from selected sample')
    forbidden = {'id', 'lemma_fr', 'pos', 'level', 'freq_rank', 'reviewed',
                 'needs_review', 'is_function', 'is_idiom'}
    for row in records:
        if row['current'] != base[row['id']]['current']:
            raise ValueError('Original word fields changed')
        if row['current_example'] != base[row['id']]['displayed_example']:
            raise ValueError('Original example fields changed')
        if forbidden.intersection(row['proposed_fields'].get('words', {})):
            raise ValueError('Identity/order/flag mutation proposed')
        allowed = {'meaning_tr', 'meaning_en', 'meaning_en_2', 'note_tr',
                   'literal_tr', 'article', 'gender', 'register'}
        if set(row['proposed_fields'].get('words', {})) - allowed:
            raise ValueError('Non-editorial field mutation proposed')
        if set(row['proposed_fields'].get('example', {})) - {
                'sentence_fr', 'sentence_en', 'sentence_tr'}:
            raise ValueError('Example identity/attribution must not be inherited in text patch')
        if row['human_review_performed'] is not False:
            raise ValueError('This pilot has no human approval')
        if row['french_source_status'] not in {'source_supported', 'not_externally_verified'}:
            raise ValueError('Unknown verification status')
        if row['french_source_status'] == 'source_supported':
            if not row['sources'] or not all(s.get('access_status') == 'body_inspected'
                    and s.get('url') and s.get('supports') and s.get('access_date')
                    for s in row['sources']):
                raise ValueError('Unsupported source claim')
        original = row['current_example'] or {}
        proposed = row['proposed_fields'].get('example', {})
        changed = {lang: proposed.get('sentence_' + lang, original.get('sentence_' + lang))
                   != original.get('sentence_' + lang) for lang in ('fr', 'en', 'tr')}
        if any(changed.values()):
            plan = row.get('language_attribution_plan', {})
            for lang, is_changed in changed.items():
                item = plan.get(lang, {})
                if (item.get('text_changed') is not is_changed or
                        item.get('retain_original_id_author') is not (not is_changed) or
                        item.get('action') != ('new_local_on_application' if is_changed else 'preserve_existing')):
                    raise ValueError('Changed example needs actual per-language provenance plan')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--a1', type=int, default=30)
    parser.add_argument('--a2', type=int, default=20)
    parser.add_argument('--exclude-sample', help='Previous sample; exclude every record ID before quotas')
    parser.add_argument('--task', default='FA-010A')
    args = parser.parse_args()
    db, output = Path(args.db).resolve(strict=True), Path(args.output).resolve()
    if db == output or (output.exists() and db.samefile(output)):
        parser.error('Output cannot overwrite input DB')
    if output.exists():
        parser.error('Refusing to overwrite an existing sample')
    excluded_ids = []
    if args.exclude_sample:
        previous = json.loads(Path(args.exclude_sample).read_text(encoding='utf-8'))
        excluded_ids = [record['id'] for record in previous['records']]
        if len(excluded_ids) != len(set(excluded_ids)):
            parser.error('Duplicate ID in excluded sample')
    sample = extract(args.db, {'A1': args.a1, 'A2': args.a2}, excluded_ids, args.task)
    if args.exclude_sample:
        excluded_path = Path(args.exclude_sample)
        sample['selection']['exclusion_source'] = {
            'path': args.exclude_sample,
            'sha256': hashlib.sha256(excluded_path.read_bytes()).hexdigest(),
            'origin': previous.get('origin', 'Previous sample records'),
        }
    with output.open('x', encoding='utf-8') as stream:
        json.dump(sample, stream, ensure_ascii=False, indent=2)
        stream.write('\n')


if __name__ == '__main__':
    main()
