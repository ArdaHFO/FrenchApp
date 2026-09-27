"""Asama 10 - content.db uretimi.

Girdi : stages/s5_examples.jsonl, stages/s7_verbs.jsonl, content/grammar/*.md
Cikti : assets/db/content.db  (uygulamaya gomulur)

Sema PLAN.md bolum 8.1'e uyar. Icerik ve ilerleme ayri veritabanlaridir;
bu dosya sadece icerik tarafidir ve salt okunurdur.
"""

from __future__ import annotations

import json
import hashlib
import os
import re
import sqlite3
import sys
import time
import unicodedata
from collections import Counter
from pathlib import Path

from content_finalization import update_journey_revisions, validate_output_paths, write_version
from editorial_overrides import finalize_content

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"
GRAMMAR = ROOT / "content" / "grammar"
OVERRIDES = ROOT / "content" / "overrides" / "manual.json"
IDIOM_OVERRIDES = ROOT / "content" / "overrides" / "idioms.json"
OUT_DIR = ROOT / "assets" / "db"

T0 = time.time()
VOWELS = set("aàâeéèêëiîïoôöuùûüyh")
ASPIRATED_H_NOUNS = {
    "hache", "haie", "haine", "halte", "hangar", "haricot", "hasard",
    "hâte", "hauteur", "héros", "honte", "houille", "houle", "hublot",
}
ASPIRATED_H_VERBS = {
    "haïr", "haleter", "harceler", "hausser", "héler", "hennir",
    "heurter", "hurler",
}

# Kaba tema atamasi. Ingilizce tanimda gecen anahtar kelimeye bakar.
# Bilincli olarak basit tutuldu; tema sadece bir filtre kolayligi.
THEME_KEYWORDS = {
    "food": ["food", "eat", "drink", "bread", "meat", "fruit", "vegetable",
             "meal", "cook", "wine", "cheese", "milk", "sugar", "dish",
             "restaurant", "taste", "hungry", "kitchen"],
    "travel": ["travel", "train", "car", "road", "journey", "station", "city",
               "town", "street", "map", "airport", "plane", "ticket", "hotel",
               "village", "country", "abroad", "bus", "bicycle"],
    "home": ["house", "home", "room", "door", "window", "furniture", "bed",
             "table", "chair", "garden", "roof", "wall", "floor", "kitchen"],
    "work": ["work", "job", "office", "company", "employee", "money", "salary",
             "business", "manager", "factory", "career", "meeting", "trade"],
    "emotions": ["love", "hate", "fear", "happy", "sad", "angry", "emotion",
                 "feeling", "joy", "sorrow", "hope", "worry", "afraid",
                 "laugh", "cry", "smile"],
    "health": ["health", "doctor", "illness", "disease", "pain", "medicine",
               "hospital", "body", "blood", "heal", "sick", "nurse", "injury"],
    "time": ["time", "day", "year", "month", "week", "hour", "minute",
             "morning", "evening", "night", "clock", "season", "today",
             "tomorrow", "yesterday", "number"],
    "nature": ["tree", "flower", "animal", "water", "sea", "mountain", "river",
               "forest", "sky", "sun", "rain", "wind", "earth", "plant",
               "bird", "fish", "stone", "snow"],
    "daily": ["friend", "family", "child", "man", "woman", "people", "speak",
              "say", "walk", "sleep", "clothes", "school", "book", "phone"],
}


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def article_for(lemma: str, gender: str | None, pos: str) -> str | None:
    if pos != "NOM" or not gender:
        return None
    if lemma.lower() not in ASPIRATED_H_NOUNS and lemma[:1].lower() in VOWELS:
        return "l'"
    return "le" if gender == "m" else "la"


def stable_id(kind: str, *parts: str) -> str:
    """Order-independent identifier. Semantic key changes intentionally create a new id."""
    key = "\x1f".join((kind, *(unicodedata.normalize("NFC", p).casefold()
                                  for p in parts)))
    return f"{kind}_{hashlib.sha256(key.encode('utf-8')).hexdigest()[:20]}"


def local_sentence_id(language: str, text: str) -> int:
    """Elle yazılan örneğe Tatoeba kimliği taklit etmeden kararlı kimlik ver."""
    key = f"manual\x1f{language}\x1f{unicodedata.normalize('NFC', text)}"
    return -int(hashlib.sha256(key.encode("utf-8")).hexdigest()[:15], 16)


def verb_group(lemma: str, tenses: dict) -> int:
    base = re.sub(r"^s(?:e\s+|')", "", lemma).strip()
    if base == "aller":
        return 3
    if base.endswith("er"):
        return 1
    present = tenses.get("present") or {}
    if (base.endswith("ir") and str(present.get("nous", "")).endswith("issons")
            and str(present.get("ils", "")).endswith("issent")):
        return 2
    return 3


def guess_theme(meanings: list[str]) -> str:
    text = " ".join(meanings).lower()
    best, best_hits = "general", 0
    for theme, keys in THEME_KEYWORDS.items():
        hits = sum(1 for k in keys if re.search(rf"\b{re.escape(k)}", text))
        if hits > best_hits:
            best, best_hits = theme, hits
    return best


def confidence_for(entry: dict) -> float:
    score = float(entry.get("tr_confidence") or 0.0) * 0.55
    if entry.get("meaning_en"):
        score += 0.15
    if entry.get("ipa"):
        score += 0.10
    if entry.get("level_source", "").startswith("flelex"):
        score += 0.15
    else:
        score += 0.05
    ex = entry.get("examples") or []
    if ex and ex[0].get("tr"):
        score += 0.10
    elif ex:
        score += 0.05
    if entry.get("gender_conflict"):
        score -= 0.10
    if entry.get("level_needs_review"):
        score -= 0.05
    return round(max(0.0, min(1.0, score)), 3)


SCHEMA = """
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;

CREATE TABLE words (
  id            TEXT PRIMARY KEY,
  lemma_fr      TEXT NOT NULL,
  article       TEXT,
  pos           TEXT NOT NULL,
  gender        TEXT,
  plural_fr     TEXT,
  ipa           TEXT,
  level         TEXT NOT NULL,
  level_source  TEXT,
  theme         TEXT NOT NULL,
  meaning_en    TEXT NOT NULL,
  meaning_en_2  TEXT,
  meaning_tr    TEXT NOT NULL,
  literal_tr    TEXT,
  note_tr       TEXT,
  register      TEXT,
  freq_rank     INTEGER NOT NULL,
  confidence    REAL NOT NULL,
  tr_path       TEXT,
  reviewed      INTEGER NOT NULL DEFAULT 0,
  is_idiom      INTEGER NOT NULL DEFAULT 0,
  is_function   INTEGER NOT NULL DEFAULT 0,
  needs_review  INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE examples (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  word_id     TEXT NOT NULL REFERENCES words(id),
  sentence_fr TEXT NOT NULL,
  sentence_en TEXT NOT NULL,
  sentence_tr TEXT,
  tr_direct   INTEGER NOT NULL DEFAULT 0,
  max_level   TEXT,
  ordinal     INTEGER NOT NULL DEFAULT 0,
  sentence_fr_id INTEGER NOT NULL,
  author_fr      TEXT NOT NULL,
  sentence_en_id INTEGER NOT NULL,
  author_en      TEXT NOT NULL,
  sentence_tr_id INTEGER,
  author_tr      TEXT
);

CREATE TABLE verbs (
  id              TEXT PRIMARY KEY,
  infinitive      TEXT NOT NULL,
  auxiliary       TEXT NOT NULL,
  past_participle TEXT,
  level           TEXT NOT NULL,
  ipa             TEXT,
  meaning_en      TEXT NOT NULL,
  meaning_tr      TEXT NOT NULL,
  freq_rank       INTEGER NOT NULL,
  is_reflexive    INTEGER NOT NULL DEFAULT 0,
  base_infinitive TEXT,
  reflexive_kind  TEXT,
  note_tr         TEXT,
  group_no        INTEGER NOT NULL,
  aspirated_h     INTEGER NOT NULL DEFAULT 0,
  needs_review    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE conjugations (
  id       INTEGER PRIMARY KEY AUTOINCREMENT,
  verb_id  TEXT NOT NULL REFERENCES verbs(id),
  tense    TEXT NOT NULL,
  person   TEXT NOT NULL,
  form     TEXT NOT NULL,
  level    TEXT NOT NULL
);

CREATE TABLE grammar_lessons (
  id         TEXT PRIMARY KEY,
  slug       TEXT NOT NULL UNIQUE,
  title_tr   TEXT NOT NULL,
  level      TEXT NOT NULL,
  tense_key  TEXT,
  sort_order INTEGER NOT NULL,
  body_md    TEXT NOT NULL
);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);

CREATE TABLE content_aliases (
  alias_id     TEXT PRIMARY KEY,
  canonical_id TEXT NOT NULL,
  kind         TEXT NOT NULL CHECK(kind IN ('word', 'verb'))
);

CREATE INDEX idx_words_level_rank ON words(level, freq_rank);
CREATE INDEX idx_words_theme_level ON words(theme, level);
CREATE TABLE word_relations (
  word_id     TEXT NOT NULL,
  related_id  TEXT NOT NULL,
  ordinal     INTEGER NOT NULL,
  PRIMARY KEY (word_id, related_id)
);
CREATE INDEX idx_relations_word ON word_relations(word_id);
CREATE INDEX idx_words_idiom ON words(is_idiom);
CREATE INDEX idx_examples_word ON examples(word_id);
CREATE INDEX idx_verbs_level_rank ON verbs(level, freq_rank);
CREATE INDEX idx_verbs_reflexive ON verbs(is_reflexive);
CREATE INDEX idx_conj_verb ON conjugations(verb_id);
CREATE INDEX idx_conj_tense ON conjugations(tense, level);
"""

TENSE_LEVEL = {
    "present": "A1", "passe_compose": "A1", "imparfait": "A1",
    "imperatif": "A1", "futur_simple": "A2", "conditionnel": "A2",
    "plus_que_parfait": "A2", "subjonctif": "B1",
}


def main() -> int:
    words_path = STAGES / "s5_examples.jsonl"
    verbs_path = STAGES / "s7_verbs.jsonl"
    if not words_path.exists():
        print("once: python content/tools/08_examples.py")
        return 2

    db_path = OUT_DIR / "content.db"
    # Reject existing output aliases before replacing content or touching temp DBs.
    try:
        validate_output_paths(
            db_path, dart_output=ROOT / "lib" / "data" / "content_version.dart"
        )
    except (OSError, ValueError, RuntimeError) as error:
        print(f"invalid content output plan: {error}")
        return 2
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tmp_path = OUT_DIR / "content.db.tmp"
    if tmp_path.exists():
        tmp_path.unlink()

    old_ids: dict[tuple[str, str, str], str] = {}
    inherited_aliases: list[tuple[str, tuple[str, str, str]]] = []
    if db_path.exists():
        old = sqlite3.connect(f"file:{db_path.as_posix()}?mode=ro", uri=True)
        try:
            semantic_by_id: dict[str, tuple[str, str, str]] = {}
            for old_id, lemma, pos in old.execute(
                    "SELECT id, lemma_fr, pos FROM words"):
                key = ("word", lemma, pos)
                old_ids[key] = old_id
                semantic_by_id[old_id] = key
            for old_id, infinitive in old.execute(
                    "SELECT id, infinitive FROM verbs"):
                key = ("verb", infinitive, "")
                old_ids[key] = old_id
                semantic_by_id[old_id] = key
            has_aliases = old.execute(
                "SELECT count(*) FROM sqlite_master WHERE type='table' "
                "AND name='content_aliases'"
            ).fetchone()[0]
            if has_aliases:
                for alias_id, canonical_id in old.execute(
                        "SELECT alias_id, canonical_id FROM content_aliases"):
                    key = semantic_by_id.get(canonical_id)
                    if key is not None:
                        inherited_aliases.append((alias_id, key))
        finally:
            old.close()

    con = sqlite3.connect(tmp_path)
    con.executescript(SCHEMA)

    # Elle yapilan duzeltmeler. Boru hattinin ciktisinin uzerine yazilir,
    # boylece boru hatti kac kez calisirsa calissin duzeltmeler korunur.
    overrides: dict[str, dict] = {}
    if OVERRIDES.exists():
        raw = json.loads(OVERRIDES.read_text(encoding="utf-8"))
        overrides = {
            k: v for k, v in raw.items()
            if not k.startswith("_") and isinstance(v, dict)
        }
        log(f"elle duzeltme: {len(overrides)} kayit")

    # ------------------------------------------------------------- kelimeler
    log("kelimeler yaziliyor")
    theme_counter: Counter[str] = Counter()
    level_counter: Counter[str] = Counter()
    word_rows = []
    example_rows = []
    applied_overrides: set[str] = set()
    n_words = 0

    for line in words_path.open(encoding="utf-8"):
        e = json.loads(line)
        lemma = e["lemma"]
        pos = e["pos"]
        gender = e.get("gender") or e.get("gender_kaikki")
        meanings = e.get("meaning_en") or []
        theme = guess_theme(meanings)
        conf = confidence_for(e)
        wid = stable_id("w", lemma, pos)

        override = overrides.get(lemma)
        reviewed = 0
        if override:
            if override.get("meaning_tr"):
                e["meaning_tr"] = override["meaning_tr"]
            if override.get("note_tr"):
                e["note_tr"] = override["note_tr"]
            conf = 1.0
            reviewed = 1
            applied_overrides.add(lemma)

        word_rows.append(
            (
                wid,
                lemma,
                article_for(lemma, gender, pos),
                pos,
                gender,
                e.get("plural"),
                e.get("ipa"),
                e["level"],
                e.get("level_source"),
                theme,
                meanings[0] if meanings else "",
                meanings[1] if len(meanings) > 1 else None,
                e["meaning_tr"],
                None,
                None,
                e.get("register"),
                e["freq_rank"],
                conf,
                "manual" if reviewed else e.get("tr_path"),
                reviewed,
                # Tek kelimelik lemma deyim olamaz. 06_english.py'nin
                # sezgisi "herhangi bir anlami deyimsel" diyordu, bu yuzden
                # "avoir", "quoi", "couper" deyim sayiliyor ve deyim destesi
                # normal desteden farksiz gorunuyordu.
                1 if (e.get("is_idiom") and " " in lemma) else 0,
                1 if e.get("is_function_word") else 0,
                0 if reviewed else (
                    1 if (conf < 0.6
                          or e.get("tr_path") in {
                              "reverse", "bridge_weak", "bridge_supported"
                          }
                          or e.get("level_needs_review")
                          or e.get("gender_conflict")) else 0
                ),
            )
        )
        for i, ex in enumerate(e.get("examples") or []):
            example_rows.append(
                (
                    wid,
                    ex["fr"],
                    ex["en"],
                    ex.get("tr"),
                    1 if ex.get("tr_direct") else 0,
                    ex.get("max_level"),
                    i,
                    ex["fr_id"],
                    ex["fr_author"],
                    ex["en_id"],
                    ex["en_author"],
                    ex.get("tr_id"),
                    ex.get("tr_author"),
                )
            )
        theme_counter[theme] += 1
        level_counter[e["level"]] += 1
        n_words += 1

    # ------------------------------------------------------------- deyimler
    idiom_path = STAGES / "s6_idioms_tr.jsonl"
    n_idioms = 0
    if idiom_path.exists():
        log("deyimler yaziliyor")
        # Deyim ornek cumleleri (08_examples.py'nin alt dizi taramasi)
        idiom_examples: dict[str, list[dict]] = {}
        iex_path = STAGES / "s5_idiom_examples.jsonl"
        if iex_path.exists():
            for line in iex_path.open(encoding="utf-8"):
                d = json.loads(line)
                idiom_examples[d["lemma"]] = d.get("examples") or []

        idioms: dict[str, dict] = {}
        for line in idiom_path.open(encoding="utf-8"):
            d = json.loads(line)
            idioms[d["lemma"]] = d

        # Elle kuratorlu deyim katmani: cikar / duzelt / ekle
        idiom_manual = 0
        if IDIOM_OVERRIDES.exists():
            ov = json.loads(IDIOM_OVERRIDES.read_text(encoding="utf-8"))
            for lemma in ov.get("cikar", []):
                idioms.pop(lemma, None)
            for lemma, patch in (ov.get("duzelt") or {}).items():
                d = idioms.get(lemma)
                if d is None:
                    continue
                if patch.get("meaning_en"):
                    d["meaning_en"] = [patch["meaning_en"]]
                for key in ("meaning_tr", "literal_tr", "level",
                            "note_tr", "register"):
                    if patch.get(key):
                        d[key] = patch[key]
                d["reviewed"] = True
                idiom_manual += 1
            for lemma, patch in (ov.get("ekle") or {}).items():
                if lemma in idioms:
                    continue
                idioms[lemma] = {
                    "lemma": lemma,
                    "level": patch.get("level", "B1"),
                    "meaning_en": [patch.get("meaning_en", "")],
                    "meaning_tr": patch["meaning_tr"],
                    "literal_tr": patch.get("literal_tr"),
                    "note_tr": patch.get("note_tr"),
                    "register": patch.get("register"),
                    "reviewed": True,
                }
                idiom_manual += 1

            # Sık kullanılan deyimlere öğretim notu, kullanım düzeyi ve
            # elle doğrulanmış kısa örnek eklenir. Otomatik Tatoeba örneği
            # varsa korunur; küratörlü örnek ilk sırada gösterilir.
            for lemma, lesson in (ov.get("ogretim") or {}).items():
                d = idioms.get(lemma)
                if d is None:
                    continue
                for key in ("literal_tr", "note_tr", "register"):
                    if lesson.get(key):
                        d[key] = lesson[key]
                manual_examples = lesson.get("examples") or []
                if manual_examples:
                    idiom_examples[lemma] = (
                        manual_examples + idiom_examples.get(lemma, [])
                    )
                d["reviewed"] = True
                idiom_manual += 1

        # Seviye sirasi, sonra alfabetik: A1 kaliplari once gelsin.
        order = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}
        for d in sorted(idioms.values(),
                        key=lambda x: (order.get(x["level"], 9), x["lemma"])):
            meanings = d.get("meaning_en") or []
            wid = stable_id("i", d["lemma"])
            word_rows.append(
                (
                    wid,
                    d["lemma"],
                    None,
                    "PHR",
                    None,
                    None,
                    d.get("ipa"),
                    d["level"],
                    "components",
                    guess_theme(meanings),
                    meanings[0] if meanings else "",
                    meanings[1] if len(meanings) > 1 else None,
                    d["meaning_tr"],
                    d.get("literal_tr"),
                    d.get("note_tr"),
                    d.get("register"),
                    # Deyimler kelime sirasinin sonuna konur, boylece once
                    # tek kelimeler gelir.
                    500000 + n_idioms,
                    1.0 if d.get("reviewed") else
                    round(float(d.get("tr_confidence") or 0.5), 3),
                    "manual" if d.get("reviewed") else d.get("tr_path"),
                    1 if d.get("reviewed") else 0,
                    1,  # is_idiom
                    0,
                    0 if d.get("reviewed") else 1,
                )
            )
            for i, ex in enumerate(idiom_examples.get(d["lemma"], [])):
                example_rows.append(
                    (
                        wid,
                        ex["fr"],
                        ex.get("en"),
                        ex.get("tr"),
                        1 if ex.get("tr_direct") else 0,
                        ex.get("max_level"),
                        i,
                        ex.get("fr_id") or local_sentence_id("fr", ex["fr"]),
                        ex.get("fr_author") or "FrenchApp kürasyonu",
                        ex.get("en_id") or local_sentence_id("en", ex["en"]),
                        ex.get("en_author") or "FrenchApp kürasyonu",
                        ex.get("tr_id") or (
                            local_sentence_id("tr", ex["tr"])
                            if ex.get("tr") else None
                        ),
                        ex.get("tr_author") or (
                            "FrenchApp kürasyonu" if ex.get("tr") else None
                        ),
                    )
                )
            level_counter[d["level"]] += 1
            n_idioms += 1
        log(f"deyim {human(n_idioms)} (elle yazilan/duzeltilen {idiom_manual})")

    con.executemany(
        "INSERT INTO words VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        word_rows,
    )
    con.executemany(
        "INSERT INTO examples (word_id, sentence_fr, sentence_en, sentence_tr,"
        " tr_direct, max_level, ordinal, sentence_fr_id, author_fr,"
        " sentence_en_id, author_en, sentence_tr_id, author_tr)"
        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
        example_rows,
    )
    log(f"kelime {human(len(word_rows))} | ornek cumle {human(len(example_rows))}")

    # ------------------------------------------------------ kelime aileleri
    fam_path = STAGES / "s8_families.jsonl"
    n_relations = 0
    if fam_path.exists():
        # word_rows[1] lemma, word_rows[0] id
        id_of = {r[1]: r[0] for r in word_rows}
        relation_rows = []
        seen: set[tuple[str, str]] = set()
        for line in fam_path.open(encoding="utf-8"):
            d = json.loads(line)
            wid = id_of.get(d["lemma"])
            if wid is None:
                continue
            ordinal = 0
            for kin in d.get("kin") or []:
                rid = id_of.get(kin)
                if rid is None or rid == wid or (wid, rid) in seen:
                    continue
                seen.add((wid, rid))
                relation_rows.append((wid, rid, ordinal))
                ordinal += 1
        con.executemany(
            "INSERT INTO word_relations VALUES (?,?,?)", relation_rows
        )
        n_relations = len(relation_rows)
        log(f"kelime ailesi bagi {human(n_relations)}")

    # ----------------------------------------------------------------- fiiller
    n_verbs = 0
    n_conj = 0
    if verbs_path.exists():
        log("fiiller yaziliyor")
        unsafe_lemmas = {row[1] for row in word_rows if row[22] == 1}
        verb_rows = []
        conj_rows = []
        for line in verbs_path.open(encoding="utf-8"):
            v = json.loads(line)
            vid = stable_id("v", v["lemma"])
            meanings = v.get("meaning_en") or []
            verb_rows.append(
                (
                    vid,
                    v["lemma"],
                    v["auxiliary"],
                    v.get("past_participle"),
                    v["level"],
                    v.get("ipa"),
                    meanings[0] if meanings else "",
                    # Elle duzeltmeler fiil tablosuna da uygulanir: tek
                    # dogru kaynak manual.json olsun, kelime karti ile
                    # fiil karti farkli sey soylemesin.
                    (overrides.get(v["lemma"], {}).get("meaning_tr")
                     or v["meaning_tr"]),
                    v["freq_rank"],
                    0,
                    None,
                    None,
                    None,
                    verb_group(v["lemma"], v.get("tenses") or {}),
                    1 if v["lemma"].lower() in ASPIRATED_H_VERBS else 0,
                    1 if v["lemma"] in unsafe_lemmas else 0,
                )
            )
            for tense, row in (v.get("tenses") or {}).items():
                for person, form in row.items():
                    conj_rows.append(
                        (vid, tense, person, form, TENSE_LEVEL.get(tense, "B1"))
                    )
                    n_conj += 1
            n_verbs += 1
        # ------------------------------------------------ donusluk fiiller
        # Kendi satirlari var: "se rendre" ile "rendre" ayri fiillerdir,
        # anlamlari da cekimleri de farkli. Ayni satira sikistirmak anlam
        # kaymasina yol acardi.
        refl_path = STAGES / "s9_reflexives.jsonl"
        n_refl = 0
        if refl_path.exists():
            for line in refl_path.open(encoding="utf-8"):
                r = json.loads(line)
                vid = stable_id("r", r["lemma"])
                en = r.get("meaning_en") or []
                verb_rows.append(
                    (
                        vid,
                        r["lemma"],
                        "être",
                        r.get("past_participle"),
                        r["level"],
                        r.get("ipa"),
                        en[0] if en else "",
                        r["meaning_tr"],
                        # Temel fiilin hemen ardina dussun.
                        r["freq_rank"] + 1,
                        1,
                        r["base"],
                        r["kind"],
                        r.get("note_tr"),
                        verb_group(r["lemma"], r.get("tenses") or {}),
                        1 if re.sub(r"^s(?:e\s+|')", "", r["lemma"]).lower()
                        in ASPIRATED_H_VERBS else 0,
                        0,
                    )
                )
                for tense, row in (r.get("tenses") or {}).items():
                    for person, form in row.items():
                        conj_rows.append(
                            (vid, tense, person, form,
                             TENSE_LEVEL.get(tense, "B1"))
                        )
                        n_conj += 1
                n_refl += 1
                n_verbs += 1
            log(f"donusluk fiil {human(n_refl)}")

        # Yanlış/eksik haricî snapshot'ın sağlam content.db'yi sessizce
        # küçültmesini engelle. Uygulamanın doğrulanmış tabanı 132 dönüşlü
        # fiil içeriyor; 100 altı açık bir veri hattı gerilemesidir.
        if n_refl < 100:
            raise RuntimeError(
                f"guvenlik freni: yalnizca {n_refl} donuslu fiil uretildi"
            )

        con.executemany(
            "INSERT INTO verbs VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", verb_rows
        )
        con.executemany(
            "INSERT INTO conjugations (verb_id, tense, person, form, level)"
            " VALUES (?,?,?,?,?)",
            conj_rows,
        )
        log(f"fiil {human(n_verbs)} | cekim {human(n_conj)}")

    # -------------------------------------------------------------- dersler
    n_lessons = 0
    if GRAMMAR.exists():
        log("dilbilgisi dersleri yaziliyor")
        lesson_rows = []
        for path in sorted(GRAMMAR.glob("*.md")):
            text = path.read_text(encoding="utf-8")
            meta: dict[str, str] = {}
            body = text
            if text.startswith("---"):
                _, front, body = text.split("---", 2)
                for line in front.strip().splitlines():
                    if ":" in line:
                        k, v = line.split(":", 1)
                        meta[k.strip()] = v.strip()
            lesson_rows.append(
                (
                    f"g{n_lessons + 1:03d}",
                    meta.get("slug", path.stem),
                    meta.get("title", path.stem),
                    meta.get("level", "A1"),
                    meta.get("tense") or None,
                    int(meta.get("order", n_lessons + 1)),
                    body.strip(),
                )
            )
            n_lessons += 1
        con.executemany(
            "INSERT INTO grammar_lessons VALUES (?,?,?,?,?,?,?)", lesson_rows
        )
        log(f"ders {human(n_lessons)}")

    # ------------------------------------------------------------------ meta
    alias_rows = []
    for row in word_rows:
        old_id = old_ids.get(("word", row[1], row[3]))
        if old_id and old_id != row[0]:
            alias_rows.append((old_id, row[0], "word"))
    for row in verb_rows if verbs_path.exists() else []:
        old_id = old_ids.get(("verb", row[1], ""))
        if old_id and old_id != row[0]:
            alias_rows.append((old_id, row[0], "verb"))
    new_ids = {
        **{("word", row[1], row[3]): row[0] for row in word_rows},
        **{("verb", row[1], ""): row[0]
           for row in verb_rows if verbs_path.exists()},
    }
    for alias_id, key in inherited_aliases:
        canonical_id = new_ids.get(key)
        if canonical_id is not None and alias_id != canonical_id:
            alias_rows.append((alias_id, canonical_id, key[0]))
    con.executemany(
        "INSERT OR REPLACE INTO content_aliases VALUES (?,?,?)", alias_rows
    )

    con.executemany(
        "INSERT INTO meta VALUES (?,?)",
        [
            ("schema_version", "2"),
            ("built_at", time.strftime("%Y-%m-%d %H:%M")),
            ("word_count", str(len(word_rows))),
            ("example_count", str(len(example_rows))),
            ("verb_count", str(n_verbs)),
            ("conjugation_count", str(n_conj)),
            ("lesson_count", str(n_lessons)),
            (
                "sources",
                "Lexique 3.83 (CC BY-SA), FLELex (CENTAL UCLouvain), "
                "Wiktionary via kaikki.org ve DBnary (CC BY-SA), "
                "Tatoeba (CC BY 2.0 FR), FrequencyWords content (CC BY-SA 4.0)",
            ),
        ],
    )
    finalize_content(con)
    con.commit()
    con.execute("VACUUM")
    con.close()

    os.replace(tmp_path, db_path)

    version_path = db_path.with_suffix(".version")
    dart_version_path = ROOT / "lib" / "data" / "content_version.dart"
    version_value = write_version(db_path, dart_output=dart_version_path)

    size_mb = db_path.stat().st_size / (1024 * 1024)
    log(f"yazildi: {db_path} ({size_mb:.1f} MB)")
    log(f"surum: {version_path}")
    log(f"dart surumu: {dart_version_path}")

    report = [
        "# Aşama 10 — content.db",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Boyut: **{size_mb:.1f} MB**",
        "",
        "| Tablo | Satır |",
        "|---|---|",
        f"| words | {human(len(word_rows))} |",
        f"| examples | {human(len(example_rows))} |",
        f"| verbs | {human(n_verbs)} |",
        f"| conjugations | {human(n_conj)} |",
        f"| grammar_lessons | {human(n_lessons)} |",
        "",
        f"Elle düzeltilen kelime: **{len(applied_overrides)}** "
        f"(tanımlı {len(overrides)})",
        "",
        "## Seviye dağılımı",
        "",
        "| Seviye | Kelime |",
        "|---|---|",
        *[f"| {lv} | {human(level_counter[lv])} |" for lv in
          ["A1", "A2", "B1", "B2", "C1", "C2"]],
        "",
        "## Tema dağılımı",
        "",
        "| Tema | Kelime |",
        "|---|---|",
        *[f"| {t} | {human(n)} |" for t, n in theme_counter.most_common()],
    ]
    (REPORTS / "stage10_build_db.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage10_build_db.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
