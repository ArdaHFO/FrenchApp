"""Pure/read-only v1 journey revision calculation. No producer imports or writes.

V1 intentionally ignores frequency, ordered station content and question rules.
Changing that contract requires a separate, versioned compatibility decision.
"""

import hashlib
import sqlite3

LEVELS = ("A1", "A2", "B1", "B2", "C1", "C2")
ALGORITHM = "sorted-ids-newline-utf8-sha256-first12"


def revision_for_ids(word_ids: list[str], verb_ids: list[str]) -> str:
    ids = word_ids + verb_ids
    if any(not isinstance(value, str) for value in ids):
        raise ValueError("Revision identifiers must be text")
    return hashlib.sha256("\n".join(sorted(ids)).encode("utf-8")).hexdigest()[:12]


def calculate_revisions(db: sqlite3.Connection) -> list[dict]:
    rows = []
    for level in LEVELS:
        groups = [
            [row[0] for row in db.execute(
                f"SELECT id FROM {table} WHERE level=? AND needs_review=0", (level,)
            )]
            for table in ("words", "verbs")
        ]
        rows.append({"level": level, "word_count": len(groups[0]),
                     "verb_count": len(groups[1]),
                     "computed": revision_for_ids(*groups)})
    return rows
