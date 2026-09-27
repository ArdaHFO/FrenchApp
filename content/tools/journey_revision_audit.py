"""Read-only audit of the CURRENT sorted-ID journey revision contract.

This deliberately does not fingerprint frequency/order, translations or station
parameters. It does not import or run either content producer.
"""

from __future__ import annotations

import argparse
from contextlib import closing
import json
from pathlib import Path
import re
import sqlite3

from journey_revisions import ALGORITHM, calculate_revisions


def audit_database(path: Path) -> dict:
    """Return all comparisons; raise on file/schema/read errors.

    Missing, duplicate or malformed revision metadata is a comparison failure
    (exit 1), whereas an unavailable table/column prevents the audit (exit 2).
    """
    path = path.resolve(strict=True)
    if not path.is_file():
        raise ValueError("Database path is not a file")
    rows = []
    with closing(sqlite3.connect(path.as_uri() + "?mode=ro", uri=True)) as db:
        db.execute("PRAGMA query_only=ON")
        db.execute("BEGIN")
        for calculation in calculate_revisions(db):
            level = calculation["level"]
            computed = calculation["computed"]
            values = db.execute(
                "SELECT value FROM meta WHERE key=?",
                (f"journey_revision_{level}",),
            ).fetchall()
            recorded = values[0][0] if len(values) == 1 else None
            valid = (
                len(values) == 1
                and isinstance(recorded, str)
                and re.fullmatch(r"[0-9a-f]{12}", recorded) is not None
            )
            status = (
                "missing_meta" if not values else
                "invalid_meta" if not valid else
                "match" if recorded == computed else "mismatch"
            )
            rows.append({
                "level": level,
                "word_count": calculation["word_count"],
                "verb_count": calculation["verb_count"],
                "recorded": recorded if isinstance(recorded, str) else None,
                "computed": computed,
                "status": status,
            })
    return {
        "algorithm": ALGORITHM,
        "levels": rows,
        "exit_code": 0 if all(row["status"] == "match" for row in rows) else 1,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True, type=Path)
    parser.add_argument("--json", action="store_true", help="Machine-readable output")
    args = parser.parse_args(argv)
    try:
        report = audit_database(args.db)
    except (OSError, sqlite3.Error, ValueError) as error:
        report = {"algorithm": ALGORITHM, "levels": [],
                  "exit_code": 2, "error": str(error)}
    if args.json:
        print(json.dumps(report, ensure_ascii=True, indent=2))
    elif report["exit_code"] == 2:
        print(f"ERROR: {report['error']}")
    else:
        for row in report["levels"]:
            print(
                f"{row['level']} words={row['word_count']} verbs={row['verb_count']} "
                f"recorded={row['recorded']} computed={row['computed']} "
                f"{row['status']}"
            )
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
