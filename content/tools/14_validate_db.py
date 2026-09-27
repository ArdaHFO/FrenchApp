"""Deterministic structural and learning-safety audit for content.db."""

from __future__ import annotations

import argparse
import sqlite3
import sys
from pathlib import Path

from journey_revision_audit import audit_database

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.db"
LEVELS = {"A1", "A2", "B1", "B2", "C1", "C2"}


def scalar(db: sqlite3.Connection, sql: str, args: tuple = ()) -> int:
    return int(db.execute(sql, args).fetchone()[0])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("db", nargs="?", type=Path, default=DEFAULT_DB)
    args = parser.parse_args()
    if not args.db.exists():
        print(f"FATAL missing database: {args.db}")
        return 2

    db = sqlite3.connect(f"file:{args.db.resolve().as_posix()}?mode=ro", uri=True)
    failures: list[str] = []

    def require(label: str, sql: str, expected: int = 0) -> None:
        actual = scalar(db, sql)
        if actual != expected:
            failures.append(f"{label}: expected {expected}, got {actual}")

    tables = {row[0] for row in db.execute(
        "SELECT name FROM sqlite_master WHERE type='table'"
    )}
    required = {
        "words", "examples", "verbs", "conjugations", "grammar_lessons",
        "word_relations", "meta", "content_aliases",
    }
    missing = sorted(required - tables)
    if missing:
        failures.append("missing tables: " + ", ".join(missing))
    else:
        meta = dict(db.execute("SELECT key, value FROM meta"))
        counts = {
            "word_count": scalar(db, "SELECT count(*) FROM words"),
            "example_count": scalar(db, "SELECT count(*) FROM examples"),
            "verb_count": scalar(db, "SELECT count(*) FROM verbs"),
            "conjugation_count": scalar(db, "SELECT count(*) FROM conjugations"),
            "lesson_count": scalar(db, "SELECT count(*) FROM grammar_lessons"),
        }
        for key, actual in counts.items():
            if meta.get(key) != str(actual):
                failures.append(f"meta {key}: expected {actual}, got {meta.get(key)!r}")
        if meta.get("schema_version") != "2":
            failures.append("meta schema_version must be 2")
        try:
            revision_audit = audit_database(args.db)
            for row in revision_audit["levels"]:
                if row["status"] != "match":
                    failures.append(
                        f"journey revision {row['level']}: {row['status']} "
                        f"recorded={row['recorded']!r} computed={row['computed']}"
                    )
        except (OSError, sqlite3.Error, ValueError) as error:
            failures.append(f"journey revision audit: {error}")

        require("foreign key violations", "SELECT count(*) FROM pragma_foreign_key_check")
        require("empty word fields", """
            SELECT count(*) FROM words
            WHERE trim(lemma_fr)='' OR trim(meaning_en)='' OR trim(meaning_tr)=''
        """)
        require("missing Tatoeba attribution", """
            SELECT count(*) FROM examples
            WHERE sentence_fr_id IS NULL OR trim(author_fr)=''
               OR sentence_en_id IS NULL OR trim(author_en)=''
               OR (sentence_tr IS NOT NULL AND
                   (sentence_tr_id IS NULL OR trim(coalesce(author_tr,''))=''))
        """)
        require("invalid word levels", "SELECT count(*) FROM words WHERE level NOT IN ('A1','A2','B1','B2','C1','C2')")
        require("non-deterministic current ids", """
            SELECT (SELECT count(*) FROM words
                    WHERE id NOT GLOB 'w_[0-9a-f]*'
                      AND id NOT GLOB 'i_[0-9a-f]*')
                 + (SELECT count(*) FROM verbs
                    WHERE id NOT GLOB 'v_[0-9a-f]*'
                      AND id NOT GLOB 'r_[0-9a-f]*')
        """)
        require("single-token idioms", """
            SELECT count(*) FROM words
            WHERE is_idiom=1 AND instr(trim(lemma_fr),' ')=0
              AND instr(trim(lemma_fr),'-')=0
        """)
        require("duplicate conjugations", """
            SELECT count(*) FROM (
              SELECT verb_id, tense, person FROM conjugations
              GROUP BY verb_id, tense, person HAVING count(*) > 1
            )
        """)
        require("invalid verb groups", "SELECT count(*) FROM verbs WHERE group_no NOT IN (1,2,3)")
        require("invalid verb review flags", "SELECT count(*) FROM verbs WHERE needs_review NOT IN (0,1)")
        require("dangling aliases", """
            SELECT count(*) FROM content_aliases a
            WHERE (a.kind='word' AND NOT EXISTS(SELECT 1 FROM words w WHERE w.id=a.canonical_id))
               OR (a.kind='verb' AND NOT EXISTS(SELECT 1 FROM verbs v WHERE v.id=a.canonical_id))
        """)
        require("unsafe weak translations exposed", """
            SELECT count(*) FROM words
            WHERE reviewed=0
              AND tr_path IN ('reverse','bridge_weak','bridge_supported')
              AND needs_review=0
        """)

        print("content.db audit")
        for key, count in counts.items():
            print(f"  {key}: {count}")
        print("  needs_review:", scalar(db, "SELECT count(*) FROM words WHERE needs_review=1"))
        print("  aliases:", scalar(db, "SELECT count(*) FROM content_aliases"))

    db.close()
    if failures:
        for failure in failures:
            print("FATAL", failure)
        return 1
    print("OK structural and learning-safety checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
