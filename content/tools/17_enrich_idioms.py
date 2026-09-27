"""Küratörlü deyim öğretim katmanını mevcut content.db üzerine uygular.

Tam veri hattını yeniden çalıştırmadan yalnızca `idioms.json/ogretim` alanını
günceller. Böylece doğrulanmış kelime ve fiil snapshot'ı aynen korunur.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
import unicodedata
from pathlib import Path

from content_finalization import (
    update_journey_revisions, validate_output_paths, write_version as publish_version,
)
from editorial_overrides import finalize_content

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DB = ROOT / "assets" / "db" / "content.db"
OVERRIDES = ROOT / "content" / "overrides" / "idioms.json"
AUTHOR = "FrenchApp kürasyonu"


def sentence_id(language: str, text: str) -> int:
    key = f"manual\x1f{language}\x1f{unicodedata.normalize('NFC', text)}"
    return -int(hashlib.sha256(key.encode("utf-8")).hexdigest()[:15], 16)


def version_output_plan(db_path: Path, dart_output: Path | None = None,
                        source_db: Path | None = None):
    if dart_output is None and db_path.resolve() == DEFAULT_DB.resolve():
        dart_output = ROOT / "lib" / "data" / "content_version.dart"
    return validate_output_paths(db_path, dart_output=dart_output, source_db=source_db)


def write_version(db_path: Path, dart_output: Path | None = None,
                  source_db: Path | None = None) -> str:
    plan = version_output_plan(db_path, dart_output, source_db)
    return publish_version(plan.db, dart_output=plan.dart, source_db=plan.source)


def lessons_are_current(db: sqlite3.Connection, lessons: dict) -> bool:
    for lemma, lesson in lessons.items():
        word = db.execute(
            """SELECT id, literal_tr, note_tr, register, reviewed, needs_review, confidence, tr_path
               FROM words WHERE lemma_fr=? AND is_idiom=1""",
            (lemma,),
        ).fetchone()
        if word is None:
            return False
        word_id, literal_tr, note_tr, register, reviewed, needs_review, confidence, tr_path = word
        expected_literal = lesson.get("literal_tr")
        if expected_literal is None:
            expected_literal = literal_tr
        if (
            literal_tr != expected_literal
            or note_tr != lesson.get("note_tr")
            or register != lesson.get("register")
            or reviewed != 1 or needs_review != 0
            or confidence != 1.0 or tr_path != "manual"
        ):
            return False
        actual_examples = db.execute(
            """SELECT sentence_fr, sentence_en, sentence_tr, ordinal
               FROM examples WHERE word_id=? AND author_fr=?
               ORDER BY ordinal""",
            (word_id, AUTHOR),
        ).fetchall()
        expected_examples = [
            (example["fr"], example["en"], example.get("tr"), index)
            for index, example in enumerate(lesson.get("examples") or [])
        ]
        if actual_examples != expected_examples:
            return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, help="Once bu dogrulanmis DB'yi kullan")
    parser.add_argument("--db", type=Path, default=DEFAULT_DB)
    parser.add_argument("--dart-output", type=Path, help="Explicit Dart marker destination")
    args = parser.parse_args()

    # Reject the complete output plan before source copying or either SQL path.
    try:
        plan = version_output_plan(args.db, args.dart_output, args.source)
    except (OSError, ValueError, RuntimeError) as error:
        parser.error(f"invalid content output plan: {error}")
    db_path = plan.db
    if plan.source is not None:
        source = plan.source
        if not source.is_file():
            raise SystemExit(f"kaynak DB bulunamadi: {source}")
        source_db = sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)
        try:
            source_db.execute("SELECT id FROM words LIMIT 1").fetchall()
            source_db.execute("SELECT key,value FROM meta LIMIT 1").fetchall()
        finally:
            source_db.close()
        db_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, db_path)
        print(f"temel DB geri alindi: {source}")

    lessons = json.loads(OVERRIDES.read_text(encoding="utf-8")).get(
        "ogretim", {}
    )
    if not lessons:
        raise SystemExit("idioms.json icinde ogretim katmani yok")

    if not db_path.is_file():
        raise SystemExit(f"DB bulunamadi: {db_path}")
    probe = sqlite3.connect(db_path.as_uri() + "?mode=rw", uri=True)
    try:
        reflexives = probe.execute(
            "SELECT count(*) FROM verbs WHERE is_reflexive=1"
        ).fetchone()[0]
        if reflexives < 100:
            raise SystemExit(
                f"guvenlik freni: temel DB yalnizca {reflexives} donuslu fiil iceriyor"
            )
        current = lessons_are_current(probe, lessons)
        if current:
            with probe:
                finalize_content(probe)
    finally:
        probe.close()

    if current:
        version = write_version(db_path, plan.dart, plan.source)
        print(f"zaten guncel: {len(lessons)} deyim - {reflexives} donuslu fiil korundu")
        print(f"surum: {version}")
        return 0

    db = sqlite3.connect(db_path.as_uri() + "?mode=rw", uri=True)
    try:
        reflexives = db.execute(
            "SELECT count(*) FROM verbs WHERE is_reflexive=1"
        ).fetchone()[0]
        if reflexives < 100:
            raise SystemExit(
                f"guvenlik freni: temel DB yalnizca {reflexives} donuslu fiil iceriyor"
            )

        applied = 0
        example_count = 0
        with db:
            for lemma, lesson in lessons.items():
                row = db.execute(
                    "SELECT id, level FROM words WHERE lemma_fr=? AND is_idiom=1",
                    (lemma,),
                ).fetchone()
                if row is None:
                    print(f"UYARI: deyim bulunamadi: {lemma}")
                    continue
                word_id, level = row
                db.execute(
                    """UPDATE words
                       SET literal_tr=COALESCE(?, literal_tr), note_tr=?,
                           register=?, reviewed=1, needs_review=0,
                           confidence=1.0, tr_path='manual'
                       WHERE id=?""",
                    (
                        lesson.get("literal_tr"),
                        lesson.get("note_tr"),
                        lesson.get("register"),
                        word_id,
                    ),
                )

                db.execute(
                    "DELETE FROM examples WHERE word_id=? AND author_fr=?",
                    (word_id, AUTHOR),
                )
                existing = db.execute(
                    "SELECT id FROM examples WHERE word_id=? ORDER BY ordinal, id",
                    (word_id,),
                ).fetchall()
                for ordinal, (example_row_id,) in enumerate(existing, start=1):
                    db.execute(
                        "UPDATE examples SET ordinal=? WHERE id=?",
                        (ordinal, example_row_id),
                    )

                for index, example in enumerate(lesson.get("examples") or []):
                    fr = example["fr"]
                    en = example["en"]
                    tr = example.get("tr")
                    db.execute(
                        """INSERT INTO examples (
                           id, word_id, sentence_fr, sentence_en, sentence_tr,
                           tr_direct, max_level, ordinal,
                           sentence_fr_id, author_fr,
                           sentence_en_id, author_en,
                           sentence_tr_id, author_tr
                         ) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                        (
                            sentence_id("row", f"{word_id}\x1f{fr}"),
                            word_id,
                            fr,
                            en,
                            tr,
                            1 if tr else 0,
                            level,
                            index,
                            sentence_id("fr", fr),
                            AUTHOR,
                            sentence_id("en", en),
                            AUTHOR,
                            sentence_id("tr", tr) if tr else None,
                            AUTHOR if tr else None,
                        ),
                    )
                    example_count += 1
                applied += 1

            total_examples = db.execute("SELECT count(*) FROM examples").fetchone()[0]
            db.execute(
                "UPDATE meta SET value=? WHERE key='example_count'",
                (str(total_examples),),
            )
            finalize_content(db)
        integrity = db.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise SystemExit(f"SQLite butunluk hatasi: {integrity}")
        db.execute("VACUUM")
    finally:
        db.close()

    version = write_version(db_path, plan.dart, plan.source)
    print(
        f"uygulandi: {applied} deyim - {example_count} kuratorlu ornek - "
        f"{reflexives} donuslu fiil korundu"
    )
    print(f"surum: {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
