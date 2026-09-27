"""Synthetic structural checks; these do not certify translation quality."""
import copy
from contextlib import closing
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from editorial_pilot import extract, validate_review


class EditorialPilotTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.db = Path(self.temp.name) / 'synthetic.db'
        with closing(sqlite3.connect(self.db)) as db, db:
            db.executescript('''
                CREATE TABLE words(id TEXT PRIMARY KEY, lemma_fr TEXT, pos TEXT,
                  level TEXT, freq_rank INTEGER, is_function INTEGER,
                  needs_review INTEGER, reviewed INTEGER, meaning_tr TEXT, note_tr TEXT);
                CREATE TABLE examples(id INTEGER, word_id TEXT, ordinal INTEGER,
                  sentence_fr_id INTEGER, sentence_fr TEXT, sentence_tr TEXT, author_tr TEXT);
            ''')
            db.executemany('INSERT INTO words VALUES(?,?,?,?,?,?,?,?,?,?)', [
                ('b', 'mot', 'NOM', 'A1', 5, 0, 0, 0, 'sözcük', None),
                ('a', 'mot', 'ADJ', 'A1', 5, 0, 0, 1, 'sentetik ayrı tür', None),
                ('review', 'x', 'NOM', 'A1', 1, 0, 1, 1, 'hariç', None),
                ('function', 'x', 'ADV', 'A1', 2, 1, 0, 1, 'hariç', None),
                ('a2', 'autre', 'ADJ', 'A2', 1, 0, 0, 0, 'başka', None),
            ])
            db.executemany('INSERT INTO examples VALUES(?,?,?,?,?,?,?)', [
                (1, 'b', 1, 11, 'Autre exemple.', 'Diğer örnek.', None),
                (2, 'b', 0, 12, 'Un mot.', 'Bir sözcük.', None),
                (3, 'a2', 0, 12, 'Un mot.', None, None),
            ])

    def review(self, sample):
        return {'records': [dict(id=r['id'], current=copy.deepcopy(r['current']),
            current_example=copy.deepcopy(r['displayed_example']), proposed_fields={},
            human_review_performed=False, french_source_status='not_externally_verified',
            sources=[], example_origin='mevcut') for r in sample['records']]}

    def test_repeatable_order_filters_and_distinct_homograph_ids(self):
        s = extract(self.db, {'A1': 2, 'A2': 1})
        self.assertEqual(s, extract(self.db, {'A1': 2, 'A2': 1}))
        self.assertEqual(s['selection']['ids'], ['a', 'b', 'a2'])
        self.assertEqual(s['selection']['tie_ranks_in_selected_pool']['A1'], [5])
        self.assertEqual([r['current']['reviewed'] for r in s['records']], [1, 0, 0])

    def test_exact_fields_ordinal_zero_missing_values_and_input_unchanged(self):
        before = self.db.read_bytes()
        s = extract(self.db)
        self.assertEqual(self.db.read_bytes(), before)
        r = s['records'][1]
        self.assertEqual(r['current']['meaning_tr'], 'sözcük')
        self.assertEqual(r['displayed_example']['id'], 2)
        self.assertEqual(r['displayed_example']['sentence_fr'], 'Un mot.')
        self.assertIsNone(s['records'][0]['displayed_example'])
        self.assertIsNone(s['records'][2]['displayed_example']['sentence_tr'])
        self.assertFalse(r['human_review_performed'])
        self.assertEqual(r['external_verification'], 'not_performed_by_extractor')
        self.assertEqual(len(r['same_fr_sentence_links']), 2)

    def test_missing_or_title_only_source_cannot_be_verified(self):
        s = extract(self.db)
        review = self.review(s)
        validate_review(s, review)
        r = review['records'][0]
        r['french_source_status'] = 'source_supported'
        with self.assertRaisesRegex(ValueError, 'Unsupported source'):
            validate_review(s, review)
        r['sources'] = [{'url': 'https://example.invalid/synthetic', 'access_date': '2026-09-12',
                         'supports': 'synthetic claim', 'access_status': 'title_only'}]
        with self.assertRaisesRegex(ValueError, 'Unsupported source'):
            validate_review(s, review)

    def test_review_preserves_ids_originals_flags_and_provenance(self):
        s = extract(self.db)
        for mutation in ('id', 'order', 'original', 'flag', 'confidence', 'human',
                         'attribution', 'example_id'):
            with self.subTest(mutation=mutation):
                review = self.review(s)
                r = review['records'][0]
                if mutation == 'id': r['id'] = 'absent'
                if mutation == 'order': review['records'].reverse()
                if mutation == 'original': r['current']['meaning_tr'] = 'changed'
                if mutation == 'flag': r['proposed_fields'] = {'words': {'reviewed': 1}}
                if mutation == 'confidence': r['proposed_fields'] = {'words': {'confidence': 1}}
                if mutation == 'human': r['human_review_performed'] = True
                if mutation == 'example_id': r['proposed_fields'] = {'example': {'sentence_fr_id': 12}}
                if mutation == 'attribution':
                    r['proposed_fields'] = {'example': {'sentence_tr': 'new'}}
                    r['example_origin'] = 'bu görevde oluşturuldu'
                with self.assertRaises(ValueError): validate_review(s, review)

    def test_cli_output_and_collision_rejection_preserve_db(self):
        script = Path(__file__).resolve().parents[1] / 'editorial_pilot.py'
        before = self.db.read_bytes()
        output = self.db.with_suffix('.json')
        command = [sys.executable, '-B', str(script), '--db', str(self.db), '--output']
        result = subprocess.run(command + [str(output)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(output.read_text(encoding='utf-8')), extract(self.db))
        result = subprocess.run(command + [str(self.db)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Output cannot overwrite input DB', result.stderr)
        self.assertEqual(self.db.read_bytes(), before)

    def test_ambiguous_displayed_example_is_not_arbitrarily_chosen(self):
        with closing(sqlite3.connect(self.db)) as db, db:
            db.execute("INSERT INTO examples VALUES(4,'b',0,14,'Autre.',NULL,NULL)")
        before = self.db.read_bytes()
        with self.assertRaisesRegex(ValueError, 'Ambiguous ordinal=0'):
            extract(self.db)
        self.assertEqual(self.db.read_bytes(), before)

    def test_exclusion_precedes_quota_and_default_pilot_is_unchanged(self):
        before = self.db.read_bytes()
        old = extract(self.db)
        self.assertEqual(old['selection']['quotas'], {'A1': 30, 'A2': 20})
        self.assertEqual(old['selection']['ids'], ['a', 'b', 'a2'])
        new = extract(self.db, {'A1': 1, 'A2': 1}, ['a'], 'FA-011A')
        self.assertEqual(new, extract(self.db, {'A1': 1, 'A2': 1}, ['a'], 'FA-011A'))
        self.assertEqual(new['selection']['ids'], ['b', 'a2'])
        self.assertFalse(set(new['selection']['ids']) & {'a'})
        self.assertEqual(new['selection']['eligible_counts'], {'A1': 1, 'A2': 1})
        self.assertEqual(self.db.read_bytes(), before)

    def test_cli_custom_quotas_and_existing_output_are_safe(self):
        script = Path(__file__).resolve().parents[1] / 'editorial_pilot.py'
        prior = self.db.with_name('previous.json')
        prior.write_text(json.dumps({'records': [{'id': 'a'}]}), encoding='utf-8')
        output = self.db.with_name('next.json')
        command = [sys.executable, '-B', str(script), '--db', str(self.db),
                   '--output', str(output), '--exclude-sample', str(prior),
                   '--a1', '1', '--a2', '1', '--task', 'FA-011A']
        db_before, prior_before = self.db.read_bytes(), prior.read_bytes()
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        sample = json.loads(output.read_text(encoding='utf-8'))
        self.assertEqual(sample['selection']['ids'], ['b', 'a2'])
        self.assertEqual(sample['task'], 'FA-011A')
        before_output = output.read_bytes()
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to overwrite', result.stderr)
        self.assertEqual(output.read_bytes(), before_output)
        self.assertEqual(prior.read_bytes(), prior_before)
        self.assertEqual(self.db.read_bytes(), db_before)

    def test_changed_translation_cannot_inherit_mevcut_attribution(self):
        sample = extract(self.db)
        review = self.review(sample)
        row = review['records'][1]
        row['proposed_fields'] = {'example': {'sentence_tr': 'Editorial translation'}}
        self.assertEqual(row['example_origin'], 'mevcut')
        with self.assertRaisesRegex(ValueError, 'per-language provenance'):
            validate_review(sample, review)
        row['language_attribution_plan'] = {
            lang: {'text_changed': lang == 'tr',
                   'retain_original_id_author': lang != 'tr',
                   'action': 'new_local_on_application' if lang == 'tr' else 'preserve_existing'}
            for lang in ('fr', 'en', 'tr')}
        validate_review(sample, review)
        row['language_attribution_plan']['tr']['retain_original_id_author'] = True
        with self.assertRaisesRegex(ValueError, 'per-language provenance'):
            validate_review(sample, review)

    def test_duplicate_review_id_or_changed_original_example_is_rejected(self):
        sample = extract(self.db)
        review = self.review(sample)
        review['records'][1] = copy.deepcopy(review['records'][0])
        with self.assertRaisesRegex(ValueError, 'IDs'):
            validate_review(sample, review)
        review = self.review(sample)
        review['records'][1]['current_example']['sentence_tr'] = 'silently changed'
        with self.assertRaisesRegex(ValueError, 'Original example'):
            validate_review(sample, review)


if __name__ == '__main__':
    unittest.main()
