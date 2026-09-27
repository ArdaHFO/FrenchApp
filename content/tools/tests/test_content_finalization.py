"""Finalization/CLI regression tests, using disposable public-content copies.

The raw 13_build_db input pipeline is deliberately not run by these tests.
No real progress database or backup is read.
"""

from contextlib import closing
import hashlib
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
from content_finalization import update_journey_revisions
from journey_revisions import revision_for_ids
from journey_revision_audit import audit_database


def load_tool(name):
    spec = importlib.util.spec_from_file_location(name, TOOLS / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


BUILD = load_tool('13_build_db')
ENRICH = load_tool('17_enrich_idioms')


class ContentFinalizationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fa003b_content_')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.db = self.directory / 'fixture.db'
        shutil.copyfile(ROOT / 'assets/db/content.db', self.db)
        self.real_markers = [ROOT / 'assets/db/content.version',
                             ROOT / 'lib/data/content_version.dart']
        self.marker_bytes = [p.read_bytes() for p in self.real_markers]
        self.addCleanup(self.assert_real_markers_unchanged)

    def assert_real_markers_unchanged(self):
        self.assertEqual([p.read_bytes() for p in self.real_markers], self.marker_bytes)

    def cli(self, *args, expect=0):
        result = subprocess.run([sys.executable, '-B', str(TOOLS / '17_enrich_idioms.py'),
                                 '--db', str(self.db), *map(str, args)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, expect, result.stdout + result.stderr)
        return result

    def mutate(self, sql, args=()):
        with closing(sqlite3.connect(self.db)) as db:
            with db:
                db.execute(sql, args)

    def current_fixture(self):
        self.cli()
        self.assertEqual(audit_database(self.db)['exit_code'], 0)

    def test_v1_retains_duplicates_and_fixed_independent_oracle(self):
        self.assertEqual(revision_for_ids(['b', 'a'], ['v_z']), '1632ead7b94b')
        # Independent payload; removing the second 'a' must change the digest.
        expected = hashlib.sha256(b'a\na\nb\nv_z').hexdigest()[:12]
        self.assertEqual(revision_for_ids(['b', 'a'], ['a', 'v_z']), expected)
        self.assertNotEqual(expected, '1632ead7b94b')

    def test_both_producer_finalizers_and_auditor_agree_on_final_rows(self):
        self.current_fixture()
        self.mutate("UPDATE meta SET value='000000000000' WHERE key='journey_revision_A1'")
        with closing(sqlite3.connect(self.db)) as db:
            with db:
                self.assertEqual(BUILD.update_journey_revisions(db), 1)
                self.assertEqual(ENRICH.update_journey_revisions(db), 0)
        self.assertEqual(audit_database(self.db)['exit_code'], 0)

    def test_current_lessons_fast_path_repairs_stale_revision_then_is_byte_stable(self):
        self.current_fixture()
        self.mutate("UPDATE meta SET value='000000000000' WHERE key='journey_revision_B2'")
        result = self.cli()
        self.assertIn('zaten guncel', result.stdout)
        self.assertEqual(audit_database(self.db)['exit_code'], 0)
        marker = self.db.with_suffix('.version')
        before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.db, marker)]
        self.cli()
        self.assertEqual([(p.read_bytes(), p.stat().st_mtime_ns) for p in (self.db, marker)], before)

    def test_review_flags_are_part_of_current_check_and_revision_membership(self):
        self.current_fixture()
        lessons = json.loads(ENRICH.OVERRIDES.read_text(encoding='utf-8'))['ogretim']
        lemma = next(iter(lessons))
        with closing(sqlite3.connect(self.db)) as db:
            row = db.execute('SELECT id,level FROM words WHERE lemma_fr=? AND is_idiom=1', (lemma,)).fetchone()
        original = audit_database(self.db)['levels']
        self.mutate('UPDATE words SET needs_review=1,reviewed=0 WHERE id=?', (row[0],))
        changed = audit_database(self.db)['levels']
        self.assertNotEqual(changed, original)
        self.assertNotEqual(next(x for x in changed if x['level']==row[1])['computed'],
                            next(x for x in original if x['level']==row[1])['computed'])
        with closing(sqlite3.connect(self.db)) as db:
            with db:
                update_journey_revisions(db)
            self.assertFalse(ENRICH.lessons_are_current(db, lessons))
        self.assertIn('uygulandi', self.cli().stdout)
        self.assertEqual(audit_database(self.db)['levels'], original)
        self.mutate('UPDATE words SET reviewed=0 WHERE id=?', (row[0],))
        self.assertIn('uygulandi', self.cli().stdout)
        with closing(sqlite3.connect(self.db)) as db:
            self.assertEqual(db.execute('SELECT reviewed,needs_review FROM words WHERE id=?', (row[0],)).fetchone(), (1,0))

    def test_custom_db_cli_and_explicit_dart_destination_keep_real_markers_untouched(self):
        self.cli()
        self.assertFalse((self.directory / 'content_version.dart').exists())
        dart = self.directory / 'requested.dart'
        self.cli('--dart-output', dart)
        data = self.db.read_bytes()
        expected = f'{hashlib.sha256(data).hexdigest().upper()}:{len(data)}'
        self.assertEqual(self.db.with_suffix('.version').read_text().strip(), expected)
        self.assertIn(expected, dart.read_text())
        before = (dart.read_bytes(), dart.stat().st_mtime_ns, self.db.read_bytes())
        self.cli('--dart-output', dart)
        self.assertEqual((dart.read_bytes(), dart.stat().st_mtime_ns, self.db.read_bytes()), before)
        self.assertEqual({p.name for p in self.directory.iterdir()}, {'fixture.db','fixture.version','requested.dart'})

    def test_missing_or_invalid_db_does_not_create_database_or_markers(self):
        self.db = self.directory / 'absent.db'
        self.cli(expect=1)
        self.assertFalse(self.db.exists())
        self.assertFalse(self.db.with_suffix('.version').exists())
        self.db.write_bytes(b'not sqlite')
        self.cli(expect=1)
        self.assertEqual(self.db.read_bytes(), b'not sqlite')
        self.assertFalse(self.db.with_suffix('.version').exists())

    def test_validator_rejects_wrong_missing_and_malformed_meta_without_writes(self):
        self.current_fixture()
        original = next(x for x in audit_database(self.db)['levels'] if x['level']=='A1')['computed']
        for value in ('000000000000', 'zzzzzzzzzzzz', None):
            with self.subTest(value=value):
                if value is None:
                    self.mutate("DELETE FROM meta WHERE key='journey_revision_A1'")
                else:
                    self.mutate("UPDATE meta SET value=? WHERE key='journey_revision_A1'", (value,))
                before = self.db.read_bytes()
                result = subprocess.run([sys.executable, '-B', str(TOOLS / '14_validate_db.py'), str(self.db)],
                                        capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('journey revision A1:', result.stdout)
                self.assertEqual(self.db.read_bytes(), before)
                self.mutate("INSERT OR REPLACE INTO meta VALUES ('journey_revision_A1',?)", (original,))


if __name__ == '__main__':
    unittest.main()
