"""Real output-writer and CLI tests. Fixtures stay in disposable directories."""
import atexit
from contextlib import closing
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

TOOLS = Path(__file__).resolve().parents[1]
ROOT = TOOLS.parents[1]
sys.path.insert(0, str(TOOLS))
from content_finalization import write_version

SCENARIOS = []


def save_report():
    destination = os.environ.get('FA003C_SCENARIO_REPORT')
    if destination:
        Path(destination).write_text(json.dumps(SCENARIOS, indent=2), encoding='utf-8')


atexit.register(save_report)


class OutputPathTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fa003c_paths_')
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.real_markers = [ROOT / 'assets/db/content.version',
                             ROOT / 'lib/data/content_version.dart']
        self.marker_bytes = [p.read_bytes() for p in self.real_markers]
        self.addCleanup(lambda: self.assertEqual(
            [p.read_bytes() for p in self.real_markers], self.marker_bytes))

    def database(self, path, mode, revision='000000000000'):
        if mode == 'cli':
            shutil.copyfile(ROOT / 'assets/db/content.db', path)
        with closing(sqlite3.connect(path)) as db:
            with db:
                if mode == 'writer':
                    db.execute('CREATE TABLE meta (key TEXT PRIMARY KEY,value TEXT)')
                    db.execute("INSERT INTO meta VALUES ('journey_revision_B2',?)", (revision,))
                else:
                    db.execute("UPDATE meta SET value=? WHERE key='journey_revision_B2'", (revision,))

    def link(self, source, target, kind, mode, case):
        try:
            if kind == 'symlink':
                target.symlink_to(source)
            else:
                os.link(source, target)
        except OSError as error:
            reason = f'{kind}: {type(error).__name__}, errno={error.errno}, winerror={getattr(error, "winerror", None)}: {error}'
            SCENARIOS.append({'mode': mode, 'case': case, 'status': 'skipped', 'reason': reason})
            self.skipTest(reason)

    def snapshot(self):
        out = {}
        for path in self.folder.iterdir():
            if path.is_file() or path.is_symlink():
                data = path.read_bytes()
                out[path.name] = {
                    'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data),
                    'mtime_ns': path.stat().st_mtime_ns,
                    'symlink': os.readlink(path) if path.is_symlink() else None,
                }
        return out

    def invoke(self, mode, db, dart=None, source=None):
        if mode == 'writer':
            try:
                value = write_version(db, dart_output=dart, source_db=source)
                return {'exit_code': None, 'exception': None, 'value': value}
            except (OSError, ValueError) as error:
                return {'exit_code': None, 'exception': type(error).__name__, 'error': str(error)}
        command = [sys.executable, '-B', str(TOOLS / '17_enrich_idioms.py'), '--db', str(db)]
        if dart is not None:
            command += ['--dart-output', str(dart)]
        if source is not None:
            command += ['--source', str(source)]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        return {'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}

    def exercise(self, mode, case):
        db = self.folder / ('content.version' if case == 'version_name' else 'content.db')
        self.database(db, mode)
        marker = db.with_suffix('.version')
        dart = self.folder / 'output.dart'
        source = None
        if case == 'normal_enrichment':
            with closing(sqlite3.connect(db)) as connection:
                with connection:
                    connection.execute('UPDATE words SET reviewed=0,needs_review=1 WHERE is_idiom=1')
            dart = db
        elif case.startswith('marker_db_'):
            self.link(db, marker, case.rsplit('_', 1)[1], mode, case)
        elif case == 'dart_db_direct':
            marker.write_bytes(b'existing marker must survive')
            dart = db
        elif case.startswith('dart_db_'):
            marker.write_bytes(b'existing marker must survive')
            self.link(db, dart, case.rsplit('_', 1)[1], mode, case)
        elif case.startswith('dart_marker_'):
            marker.write_bytes(b'existing marker must survive')
            if case.endswith('_direct'):
                dart = marker
            else:
                self.link(marker, dart, case.rsplit('_', 1)[1], mode, case)
        elif '_source_' in case:
            source = self.folder / 'source.db'
            self.database(source, mode, revision='111111111111')
            if case.startswith('marker_source_'):
                if case.endswith('_direct'):
                    source.rename(marker)
                    source = marker
                else:
                    self.link(source, marker, case.rsplit('_', 1)[1], mode, case)
            else:
                marker.write_bytes(b'existing marker must survive')
                if case.endswith('_direct'):
                    dart = source
                else:
                    self.link(source, dart, case.rsplit('_', 1)[1], mode, case)
        before = self.snapshot()
        outcome = self.invoke(mode, db, dart, source)
        after = self.snapshot()
        preserved = before == after
        record = {'mode': mode, 'case': case, **outcome,
                  'all_input_and_existing_output_bytes_preserved': preserved,
                  'new_files': sorted(set(after) - set(before)), 'before': before, 'after': after}
        SCENARIOS.append(record)
        # Original red assertion: detect damage, not merely an exit code.
        self.assertTrue(preserved, f'Valid SQLite input was overwritten; result={outcome}')
        self.assertEqual(record['new_files'], [])
        for input_db in (db, source):
            if input_db is not None:
                with closing(sqlite3.connect(input_db.as_uri() + '?mode=ro', uri=True)) as connection:
                    self.assertEqual(connection.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
                    connection.execute('SELECT key,value FROM meta').fetchall()
        if mode == 'writer':
            self.assertEqual(outcome['exception'], 'ValueError')
            self.assertIn('collision', outcome['error'])
        else:
            self.assertEqual(outcome['exit_code'], 2, outcome)
            self.assertIn('invalid content output plan', outcome['stderr'])
            for success in ('zaten guncel', 'surum:', 'temel DB geri alindi'):
                self.assertNotIn(success, outcome['stdout'])
        record['db_readable_after'] = True
        record['status'] = 'passed'

    def test_version_named_database_is_rejected_before_cli_writes(self):
        self.exercise('cli', 'version_name')

    def test_cli_normal_enrichment_is_rejected_before_content_updates(self):
        self.exercise('cli', 'normal_enrichment')

    def safe(self, mode, source_copy=False):
        # A non-.db extension remains legal if output paths are distinct.
        db = self.folder / 'content.sqlite'
        source = None
        if source_copy:
            source = self.folder / 'source.sqlite'
            self.database(source, mode)
        else:
            self.database(db, mode)
        dart = self.folder / 'output.dart'
        input_bytes = (source or db).read_bytes()
        first = self.invoke(mode, db, dart, source)
        if mode == 'writer':
            self.assertIsNone(first['exception'], first)
            self.assertEqual(db.read_bytes(), input_bytes)
        else:
            self.assertEqual(first['exit_code'], 0, first)
        if source is not None:
            self.assertEqual(source.read_bytes(), input_bytes)
        data = db.read_bytes()
        marker_value = f'{hashlib.sha256(data).hexdigest().upper()}:{len(data)}'
        self.assertEqual(db.with_suffix('.version').read_text().strip(), marker_value)
        self.assertIn(marker_value, dart.read_text())
        before_repeat = self.snapshot()
        again = self.invoke(mode, db, dart)  # no repeated --source copy
        self.assertIsNone(again.get('exception'))
        if mode == 'cli':
            self.assertEqual(again['exit_code'], 0)
        self.assertEqual(self.snapshot(), before_repeat)
        with closing(sqlite3.connect(db.as_uri() + '?mode=ro', uri=True)) as connection:
            self.assertEqual(connection.execute('PRAGMA integrity_check').fetchone()[0], 'ok')
        SCENARIOS.append({'mode': mode, 'case': 'safe_source_copy' if source_copy else 'safe',
                          'status': 'passed', **first, 'db_readable_after': True,
                          'db_bytes_unchanged': db.read_bytes() == input_bytes,
                          'revision_repair_expected': mode == 'cli',
                          'new_outputs': [db.with_suffix('.version').name, dart.name],
                          'repeat_bytes_and_mtimes_unchanged': True,
                          'source_unchanged': source is None or source.read_bytes() == input_bytes,
                          'real_project_markers_unchanged': True})

    def test_writer_safe_plan_and_idempotence(self):
        self.safe('writer')

    def test_cli_safe_plan_and_idempotence(self):
        self.safe('cli')

    def test_cli_safe_nonexistent_destination_with_source(self):
        self.safe('cli', source_copy=True)

    def test_build_preflight_rejects_before_touching_temporary_database(self):
        spec = importlib.util.spec_from_file_location('build_output_preflight', TOOLS / '13_build_db.py')
        build = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(build)
        db = self.folder / 'content.db'
        self.database(db, 'writer')
        os.link(db, self.folder / 'content.version')
        (self.folder / 's5_examples.jsonl').write_bytes(b'')
        temporary = self.folder / 'content.db.tmp'
        temporary.write_bytes(b'preexisting temporary file must not be unlinked')
        before = self.snapshot()
        # Only inject directory locations, not the validation or writing code.
        with patch.object(build, 'OUT_DIR', self.folder), patch.object(build, 'STAGES', self.folder):
            code = build.main()
        self.assertEqual(code, 2)
        self.assertEqual(self.snapshot(), before)
        SCENARIOS.append({'mode': 'build_main', 'case': 'marker_db_hardlink',
                          'exit_code': code, 'status': 'passed',
                          'all_input_and_existing_output_bytes_preserved': True,
                          'temporary_db_untouched': True, 'new_files': []})


CASES = (
    'version_name', 'marker_db_symlink', 'marker_db_hardlink',
    'dart_db_direct', 'dart_db_symlink', 'dart_db_hardlink',
    'dart_marker_direct', 'dart_marker_symlink', 'dart_marker_hardlink',
    'marker_source_direct', 'marker_source_symlink', 'marker_source_hardlink',
    'dart_source_direct', 'dart_source_symlink', 'dart_source_hardlink',
)
for mode in ('writer', 'cli'):
    for case in CASES:
        if mode == 'cli' and case == 'version_name':
            continue  # Covered by the named red/green regression.

        def make_test(selected_mode, selected_case):
            return lambda self: self.exercise(selected_mode, selected_case)

        setattr(OutputPathTest, f'test_{mode}_{case}', make_test(mode, case))


if __name__ == '__main__':
    unittest.main()
