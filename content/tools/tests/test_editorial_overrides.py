"""FA-010B approved-package tests. Only synthetic/public temporary databases."""
from collections import Counter
from contextlib import closing
import copy
import importlib.util
import json
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))
from editorial_overrides import apply_overrides, load_entries, local_sentence_id


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class EditorialOverrideTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fa010b_')
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / 'content.db'
        self.entries = copy.deepcopy(load_entries())
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        # Exact schema from public packaged content; no user data is opened.
        with closing(sqlite3.connect((ROOT / 'assets/db/content.db').as_uri() + '?mode=ro', uri=True)) as source:
            for (sql,) in source.execute("SELECT sql FROM sqlite_master WHERE type='table' AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'"):
                self.db.execute(sql)
        for entry in self.entries:
            self.insert('words', entry['initial_words'])
            self.insert('examples', entry['initial_example'])
        self.db.commit()

    def insert(self, table, row):
        self.db.execute(f'INSERT INTO {table} ({",".join(row)}) VALUES ({",".join("?" for _ in row)})', tuple(row.values()))

    def snapshot(self):
        return {table: Counter(self.db.execute(f'SELECT * FROM {table}').fetchall())
                for table in ('words', 'examples', 'verbs')}

    def test_approved_counts_notes_and_language_provenance(self):
        result = apply_overrides(self.db)
        self.assertEqual(result['cards'], 36)
        self.assertEqual(result['examples'], 31)
        french_changes = 0
        for entry in self.entries:
            row = self.db.execute('SELECT * FROM examples WHERE word_id=? AND ordinal=0', (entry['id'],))
            actual = dict(zip([c[0] for c in row.description], row.fetchone()))
            self.assertEqual(actual, entry['final_example'])
            french_changes += actual['sentence_fr'] != entry['initial_example']['sentence_fr']
            for field, value in entry['final_words'].items():
                self.assertEqual(self.db.execute(f'SELECT {field} FROM words WHERE id=?', (entry['id'],)).fetchone()[0], value)
        self.assertEqual(french_changes, 21)

    def test_homograph_verb_and_shared_sentence_are_not_changed(self):
        entry = next(e for e in self.entries if e['initial_example'] != e['final_example'])
        word = dict(entry['initial_words'], id='synthetic_homograph', pos='OTHER')
        example = dict(entry['initial_example'], id=987654321, word_id=word['id'])
        self.insert('words', word)
        self.insert('examples', example)
        self.db.execute("INSERT INTO verbs (id,infinitive,auxiliary,level,meaning_en,meaning_tr,freq_rank,group_no) VALUES (?,?,?,?,?,?,?,?)",
                        ('synthetic_verb', word['lemma_fr'], 'avoir', 'A1', 'keep', 'keep', 1, 1))
        before = self.snapshot()
        apply_overrides(self.db)
        self.assertIn(tuple(word.values()), self.db.execute('SELECT * FROM words').fetchall())
        self.assertIn(tuple(example.values()), self.db.execute('SELECT * FROM examples').fetchall())
        self.assertEqual(before['verbs'], self.snapshot()['verbs'])

    def test_missing_duplicate_pos_and_third_text_rejected_before_writes(self):
        for case in ('missing', 'duplicate_target', 'pos', 'third_word', 'third_unedited_word', 'third_example', 'duplicate_example'):
            with self.subTest(case=case):
                self.db.execute('SAVEPOINT fixture')
                entries = copy.deepcopy(self.entries)
                target = entries[-1]['id']
                if case == 'missing':
                    self.db.execute('DELETE FROM words WHERE id=?', (target,))
                elif case == 'duplicate_target':
                    entries.append(entries[0])
                elif case == 'pos':
                    self.db.execute("UPDATE words SET pos='OTHER' WHERE id=?", (target,))
                elif case == 'third_word':
                    self.db.execute("UPDATE words SET note_tr='unexpected third value' WHERE id=?", (entries[0]['id'],))
                elif case == 'third_unedited_word':
                    example_only = next(e for e in entries if not e['final_words'])
                    self.db.execute("UPDATE words SET meaning_tr='unexpected sense' WHERE id=?", (example_only['id'],))
                elif case == 'third_example':
                    self.db.execute("UPDATE examples SET sentence_fr='unexpected' WHERE word_id=?", (target,))
                else:
                    self.insert('examples', dict(entries[-1]['initial_example'], id=987654321))
                before = self.snapshot()
                with self.assertRaises(ValueError):
                    apply_overrides(self.db, entries)
                self.assertEqual(before, self.snapshot())
                self.db.execute('ROLLBACK TO fixture')
                self.db.execute('RELEASE fixture')

    def test_late_sql_failure_rolls_back_entire_package(self):
        target = next(e for e in reversed(self.entries) if e['final_words'])['id']
        self.db.execute(f"CREATE TRIGGER reject_editorial BEFORE UPDATE ON words WHEN NEW.id='{target}' BEGIN SELECT RAISE(ABORT,'editorial injection'); END")
        before = self.snapshot()
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'editorial injection'):
            apply_overrides(self.db)
        self.assertEqual(before, self.snapshot())

    def test_second_apply_is_byte_stable_and_does_not_duplicate(self):
        apply_overrides(self.db)
        before = self.path.read_bytes()
        self.assertEqual(apply_overrides(self.db), {'cards': 0, 'word_fields': 0, 'examples': 0})
        self.assertEqual(before, self.path.read_bytes())

    def test_changed_text_cannot_retain_external_attribution_even_if_origin_says_current(self):
        entries = copy.deepcopy(self.entries)
        entry = next(e for e in entries if e['initial_example']['sentence_tr'] != e['final_example']['sentence_tr'])
        entry['example_origin'] = 'mevcut'
        entry['final_example']['sentence_tr_id'] = entry['initial_example']['sentence_tr_id']
        before = self.snapshot()
        with self.assertRaisesRegex(ValueError, 'attribution'):
            apply_overrides(self.db, entries)
        self.assertEqual(before, self.snapshot())

    def test_local_id_collision_and_direct_translation_claim_rejected(self):
        entries = copy.deepcopy(self.entries)
        entry = next(e for e in entries if e['initial_example']['sentence_tr'] != e['final_example']['sentence_tr'])
        entry['final_example']['tr_direct'] = 1
        with self.assertRaisesRegex(ValueError, 'direct link'):
            apply_overrides(self.db, entries)
        collision = dict(entry['initial_example'], id=987654321,
                         sentence_tr_id=entry['final_example']['sentence_tr_id'], sentence_tr='different text')
        self.insert('examples', dict(collision, ordinal=9))
        with self.assertRaisesRegex(ValueError, 'collision'):
            apply_overrides(self.db)
        self.db.execute('DELETE FROM examples WHERE id=987654321')
        # The namespace also rejects an accidental collision in another language.
        collision = dict(entry['initial_example'], id=987654321, ordinal=9,
                         sentence_en_id=entry['final_example']['sentence_tr_id'])
        self.insert('examples', collision)
        with self.assertRaisesRegex(ValueError, 'collision'):
            apply_overrides(self.db)
        self.assertLess(local_sentence_id('fr', 'Bonjour.'), 0)
        self.assertEqual(local_sentence_id('fr', 'é'), local_sentence_id('fr', 'e\u0301'))

    def test_regenerated_physical_example_ids_are_preserved(self):
        self.db.execute('UPDATE examples SET id=id+1000000')
        ids = self.db.execute('SELECT id,word_id,ordinal FROM examples ORDER BY id').fetchall()
        apply_overrides(self.db)
        self.assertEqual(ids, self.db.execute('SELECT id,word_id,ordinal FROM examples ORDER BY id').fetchall())

    def test_real_producer_and_enrichment_finalizers_preserve_package(self):
        build, enrich = load_tool('13_build_db'), load_tool('17_enrich_idioms')
        self.assertIs(build.finalize_content, enrich.finalize_content)
        # Public copy has all idiom/verb prerequisites; reset only pilot texts
        # to approved originals, simulating the final pre-editorial stage.
        self.db.close()
        shutil.copyfile(ROOT / 'assets/db/content.db', self.path)
        self.db = sqlite3.connect(self.path)
        self.addCleanup(self.db.close)
        for entry in self.entries:
            for table, fields, where in (
                ('words', {f: entry['initial_words'][f] for f in entry['final_words']}, 'id=?'),
                ('examples', {k: v for k, v in entry['initial_example'].items() if k not in ('id', 'word_id', 'ordinal')}, 'word_id=? AND ordinal=0'),
            ):
                if fields:
                    self.db.execute(f'UPDATE {table} SET {",".join(f+"=?" for f in fields)} WHERE {where}', (*fields.values(), entry['id']))
        self.db.commit()
        before_markers = [(ROOT / p).read_bytes() for p in ('assets/db/content.version', 'lib/data/content_version.dart')]
        with self.db:
            self.assertEqual(build.finalize_content(self.db)['cards'], 36)
            self.assertEqual(enrich.finalize_content(self.db)['cards'], 0)
        # Make lessons current but one editorial field stale: CLI fast path must
        # still reapply the shared package, without touching real app markers.
        e = self.entries[0]
        self.db.execute('UPDATE words SET note_tr=? WHERE id=?', (e['initial_words']['note_tr'], e['id']))
        self.db.commit()
        self.db.close()
        command = [sys.executable, '-B', str(TOOLS / '17_enrich_idioms.py'), '--db', str(self.path)]
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(db.execute('SELECT note_tr FROM words WHERE id=?', (e['id'],)).fetchone()[0], e['final_words']['note_tr'])
        before = self.path.read_bytes()
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(before, self.path.read_bytes())
        # Exercise the normal enrichment path as well, with a stale editorial
        # note and one lesson review flag. Only the temporary copy is changed.
        with closing(sqlite3.connect(self.path)) as db:
            with db:
                db.execute('UPDATE words SET note_tr=? WHERE id=?', (e['initial_words']['note_tr'], e['id']))
                db.execute("UPDATE words SET reviewed=0 WHERE id=(SELECT id FROM words WHERE is_idiom=1 AND note_tr IS NOT NULL LIMIT 1)")
        result = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        with closing(sqlite3.connect(self.path)) as db:
            self.assertEqual(db.execute('SELECT note_tr FROM words WHERE id=?', (e['id'],)).fetchone()[0], e['final_words']['note_tr'])
            self.assertEqual(apply_overrides(db)['cards'], 0)
        self.assertEqual(before_markers, [(ROOT / p).read_bytes() for p in ('assets/db/content.version', 'lib/data/content_version.dart')])


if __name__ == '__main__':
    unittest.main()
