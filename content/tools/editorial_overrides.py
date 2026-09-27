"""Approved, ID-scoped editorial text package. No I/O at import time.

The caller owns the database connection. A savepoint makes the entire package
atomic both standalone and inside a producer's existing transaction.
"""
import hashlib
import json
import sqlite3
import unicodedata
from pathlib import Path

from content_finalization import update_journey_revisions

MANIFEST = Path(__file__).resolve().parents[1] / 'overrides/editorial_fa010b.json'
WORD_FIELDS = frozenset(('meaning_tr', 'meaning_en', 'note_tr'))
WORD_CONTEXT_FIELDS = WORD_FIELDS | frozenset(
    ('meaning_en_2', 'literal_tr', 'register', 'article', 'gender'))
EXAMPLE_FIELDS = frozenset(
    ['sentence_' + lang for lang in ('fr', 'en', 'tr')]
    + ['sentence_' + lang + '_id' for lang in ('fr', 'en', 'tr')]
    + ['author_' + lang for lang in ('fr', 'en', 'tr')]
    + ['tr_direct', 'max_level'])
AUTHOR = 'FrenchApp editoryal · FA-010B'


def local_sentence_id(language, text):
    """Existing manual-example namespace, never a positive external ID."""
    key = f'manual\x1f{language}\x1f{unicodedata.normalize("NFC", text)}'
    return -int(hashlib.sha256(key.encode('utf-8')).hexdigest()[:15], 16)


def load_entries():
    return json.loads(MANIFEST.read_text(encoding='utf-8'))['entries']


def _rows(db, table, where, args):
    cursor = db.execute(f'SELECT * FROM {table} WHERE {where}', args)
    names = [column[0] for column in cursor.description]
    return [dict(zip(names, row)) for row in cursor.fetchall()]


def plan_overrides(db, entries):
    """Validate every target and actual language difference before any SQL write."""
    if len({entry['id'] for entry in entries}) != len(entries):
        raise ValueError('Duplicate editorial word ID')
    plan = []
    local_ids = {}
    for entry in entries:
        word_id = entry['id']
        words = _rows(db, 'words', 'id=?', (word_id,))
        examples = _rows(db, 'examples', 'word_id=? AND ordinal=0', (word_id,))
        if len(words) != 1 or len(examples) != 1:
            raise ValueError(f'{word_id}: expected one word and one ordinal=0 example')
        word, example = words[0], examples[0]
        if (word['lemma_fr'], word['pos']) != (entry['lemma_fr'], entry['pos']):
            raise ValueError(f'{word_id}: lemma/POS mismatch')
        initial_word, final_word = entry['initial_words'], entry['final_words']
        if not set(final_word) <= WORD_FIELDS:
            raise ValueError(f'{word_id}: unapproved word field')
        # Even an example-only correction relies on the approved word sense.
        # Reject a third text in unchanged context instead of silently applying
        # the example to a meaning that this package never reviewed.
        for field in WORD_CONTEXT_FIELDS:
            if word[field] not in (initial_word[field], final_word.get(field, initial_word[field])):
                raise ValueError(f'{word_id}: unexpected words.{field}')
        word_changes = {}
        for field, after in final_word.items():
            if word[field] != after:
                word_changes[field] = after

        initial, final = entry['initial_example'], entry['final_example']
        if set(final) != set(initial):
            raise ValueError(f'{word_id}: example field set changed')
        for field in set(final) - EXAMPLE_FIELDS:
            if final[field] != initial[field]:
                raise ValueError(f'{word_id}: unapproved example field {field}')
        for lang in ('fr', 'en', 'tr'):
            field = 'sentence_' + lang
            changed = initial[field] != final[field]
            expected_id = local_sentence_id(lang, final[field]) if changed else initial[field + '_id']
            expected_author = AUTHOR if changed else initial['author_' + lang]
            if final[field + '_id'] != expected_id or final['author_' + lang] != expected_author:
                raise ValueError(f'{word_id}: invalid {lang} attribution')
            if changed:
                normalized = unicodedata.normalize('NFC', final[field])
                identity = (lang, normalized)
                if expected_id in local_ids and local_ids[expected_id] != identity:
                    raise ValueError(f'{word_id}: local ID collision')
                local_ids[expected_id] = identity
                for other_lang in ('fr', 'en', 'tr'):
                    other_field = 'sentence_' + other_lang
                    for row in _rows(db, 'examples', f'{other_field}_id=?', (expected_id,)):
                        if other_lang != lang or unicodedata.normalize('NFC', row[other_field]) != normalized:
                            raise ValueError(f'{word_id}: existing local ID collision')
        if final['sentence_tr'] != initial['sentence_tr'] and final['tr_direct'] != 0:
            raise ValueError(f'{word_id}: editorial Turkish is not a Tatoeba direct link')
        # Physical example IDs may be regenerated. Validate the complete semantic
        # row (including attribution), never apply a global sentence-ID update.
        fields = set(initial) - {'id'}
        if not any(all(example[f] == state[f] for f in fields) for state in (initial, final)):
            raise ValueError(f'{word_id}: unexpected example text/attribution')
        example_changes = {f: final[f] for f in EXAMPLE_FIELDS if example[f] != final[f]}
        plan.append((word_id, word_changes, example_changes))
    return plan


def apply_overrides(db, entries=None):
    """Apply only approved differences; return counts, not a new version marker."""
    entries = load_entries() if entries is None else entries
    db.execute('SAVEPOINT editorial_package')
    try:
        plan = plan_overrides(db, entries)
        counts = {'cards': 0, 'word_fields': 0, 'examples': 0}
        for word_id, word_changes, example_changes in plan:
            if word_changes or example_changes:
                counts['cards'] += 1
            for table, changes, where in (
                ('words', word_changes, 'id=?'),
                ('examples', example_changes, 'word_id=? AND ordinal=0'),
            ):
                if changes:
                    assignments = ','.join(f'{field}=?' for field in changes)
                    db.execute(f'UPDATE {table} SET {assignments} WHERE {where}',
                               (*changes.values(), word_id))
            counts['word_fields'] += len(word_changes)
            counts['examples'] += bool(example_changes)
        db.execute('RELEASE editorial_package')
        return counts
    except Exception:
        db.execute('ROLLBACK TO editorial_package')
        db.execute('RELEASE editorial_package')
        raise


def finalize_content(db):
    """Shared final-content stage; producers commit before hashing closed DB."""
    db.execute('SAVEPOINT editorial_finalization')
    try:
        result = apply_overrides(db)
        update_journey_revisions(db)
        db.execute('RELEASE editorial_finalization')
        return result
    except Exception:
        db.execute('ROLLBACK TO editorial_finalization')
        db.execute('RELEASE editorial_finalization')
        raise
