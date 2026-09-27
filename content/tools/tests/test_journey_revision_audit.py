"""Synthetic, temporary fixtures only; no packaged database is modified."""

import hashlib
from contextlib import closing, contextmanager
import importlib.util
import json
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / "journey_revision_audit.py"
sys.path.insert(0, str(TOOL.parent))
SPEC = importlib.util.spec_from_file_location("journey_revision_audit", TOOL)
AUDIT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(AUDIT)

# Independent fixed oracle: UTF-8 bytes b"a\nb\nv_z", no trailing newline.
ORDERED_IDS = ["a", "b", "v_z"]
EXPECTED_A1 = "1632ead7b94b"
EMPTY_REVISION = "e3b0c44298fc"


class JourneyRevisionAuditTest(unittest.TestCase):
    @contextmanager
    def connection(self):
        with closing(sqlite3.connect(self.path)) as db:
            with db:
                yield db

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fa003a_audit_")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "fixture.db"
        with self.connection() as db:
            for table in ("words", "verbs"):
                db.execute(f"""CREATE TABLE {table} (
                    id TEXT, level TEXT, needs_review INTEGER,
                    freq_rank INTEGER, reviewed INTEGER, is_function INTEGER,
                    is_idiom INTEGER, meaning TEXT)""")
            # Insertion/frequency order differs from the explicit sorted oracle.
            db.executemany("INSERT INTO words VALUES (?,?,?,?,?,?,?,?)", [
                ("b", "A1", 0, 1, 0, 1, 0, "function word included by legacy hash"),
                ("a", "A1", 0, 2, 0, 0, 1, "unreviewed eligible idiom"),
                ("hidden", "A1", 1, 0, 1, 0, 0, "excluded"),
            ])
            db.executemany("INSERT INTO verbs VALUES (?,?,?,?,?,?,?,?)", [
                ("v_z", "A1", 0, 1, 0, 0, 0, "eligible verb"),
                ("v_hidden", "A1", 1, 2, 1, 0, 0, "excluded verb"),
            ])
            db.execute("CREATE TABLE meta (key TEXT, value)")
            db.executemany("INSERT INTO meta VALUES (?,?)", [
                ("journey_revision_" + level,
                 EXPECTED_A1 if level == "A1" else EMPTY_REVISION)
                for level in ("A1", "A2", "B1", "B2", "C1", "C2")
            ])

    def run_cli(self, path=None):
        path = self.path if path is None else path
        before = path.read_bytes() if path.is_file() else None
        entries = sorted(p.name for p in Path(self.temp.name).iterdir())
        result = subprocess.run(
            [sys.executable, "-B", str(TOOL), "--db", str(path), "--json"],
            capture_output=True, text=True, check=False,
        )
        self.assertEqual(path.read_bytes() if path.is_file() else None, before)
        self.assertEqual(sorted(p.name for p in Path(self.temp.name).iterdir()), entries)
        report = json.loads(result.stdout)
        self.assertEqual(report["exit_code"], result.returncode)
        return result.returncode, report

    def test_matches_explicit_oracle_and_includes_words_and_verbs(self):
        self.assertEqual("\n".join(ORDERED_IDS).encode(), b"a\nb\nv_z")
        self.assertEqual(hashlib.sha256(b"a\nb\nv_z").hexdigest()[:12], EXPECTED_A1)
        code, report = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["levels"][0], {
            "level": "A1", "word_count": 2, "verb_count": 1,
            "recorded": EXPECTED_A1, "computed": EXPECTED_A1, "status": "match",
        })
        self.assertTrue(all(row["status"] == "match" for row in report["levels"]))

    def test_correct_length_wrong_revision_fails(self):
        with self.connection() as db:
            db.execute("UPDATE meta SET value='000000000000' WHERE key='journey_revision_A1'")
        code, report = self.run_cli()
        self.assertEqual(code, 1)
        self.assertEqual(report["levels"][0]["status"], "mismatch")

    def test_missing_meta_is_comparison_failure(self):
        with self.connection() as db:
            db.execute("DELETE FROM meta WHERE key='journey_revision_B2'")
        code, report = self.run_cli()
        self.assertEqual(code, 1)
        self.assertEqual(report["levels"][3]["status"], "missing_meta")

    def test_malformed_and_duplicate_meta_are_not_matches(self):
        for value in (None, 12, "short", "zzzzzzzzzzzz", EXPECTED_A1.upper()):
            with self.subTest(value=value):
                with self.connection() as db:
                    db.execute("UPDATE meta SET value=? WHERE key='journey_revision_A1'", (value,))
                code, report = self.run_cli()
                self.assertEqual(code, 1)
                self.assertEqual(report["levels"][0]["status"], "invalid_meta")
        with self.connection() as db:
            db.execute("UPDATE meta SET value=? WHERE key='journey_revision_A1'", (EXPECTED_A1,))
            db.execute("INSERT INTO meta VALUES ('journey_revision_A1',?)", (EXPECTED_A1,))
        self.assertEqual(self.run_cli()[1]["levels"][0]["status"], "invalid_meta")

    def test_schema_failure_is_exit_two(self):
        with self.connection() as db:
            db.execute("ALTER TABLE words RENAME COLUMN needs_review TO unavailable")
        code, report = self.run_cli()
        self.assertEqual(code, 2)
        self.assertIn("needs_review", report["error"])

    def test_missing_meta_table_is_schema_failure(self):
        with self.connection() as db:
            db.execute("DROP TABLE meta")
        self.assertEqual(self.run_cli()[0], 2)

    def test_missing_or_unreadable_database_is_not_created_or_repaired(self):
        self.assertEqual(self.run_cli(Path(self.temp.name) / "absent.db")[0], 2)
        self.path.write_bytes(b"not a sqlite database")
        self.assertEqual(self.run_cli()[0], 2)

    def test_review_flag_changes_membership(self):
        for table, identifier in (("words", "hidden"), ("verbs", "v_hidden")):
            with self.subTest(table=table):
                with self.connection() as db:
                    db.execute(f"UPDATE {table} SET needs_review=0 WHERE id=?", (identifier,))
                code, report = self.run_cli()
                self.assertEqual(code, 1)
                self.assertNotEqual(report["levels"][0]["computed"], EXPECTED_A1)
                with self.connection() as db:
                    db.execute(f"UPDATE {table} SET needs_review=1 WHERE id=?", (identifier,))

    def test_unrelated_excluded_record_changes_do_not_change_revision(self):
        with self.connection() as db:
            db.execute("UPDATE words SET meaning='different', freq_rank=987, reviewed=0 WHERE id='hidden'")
        self.assertEqual(self.run_cli()[0], 0)

    def test_legacy_algorithm_ignores_frequency_and_candidate_order(self):
        with self.connection() as db:
            before = db.execute("SELECT id FROM words WHERE needs_review=0 ORDER BY freq_rank").fetchall()
            db.execute("UPDATE words SET freq_rank=CASE id WHEN 'a' THEN 0 ELSE 100 END")
            after = db.execute("SELECT id FROM words WHERE needs_review=0 ORDER BY freq_rank").fetchall()
        self.assertNotEqual(before, after)
        code, report = self.run_cli()
        self.assertEqual(code, 0)
        self.assertEqual(report["levels"][0]["computed"], EXPECTED_A1)


if __name__ == "__main__":
    unittest.main()
