"""Asama 3 - Ingilizce anlam, okunus, dilbilgisi bilgisi ve fiil formlari.

Girdi : stages/s2_levels.jsonl, kaikki/kaikki-French.jsonl (547 MB)
Cikti : stages/s3_english.jsonl

547 MB'lik dosya satir satir akitilir, bellege alinmaz. Fiil cekim formlari
da ayni gecişte toplanir, boylece dosya iki kez taranmaz.

Cikarilanlar:
  - Ingilizce tanim (en fazla iki tane, kullanim etiketleri ayiklanmis)
  - IPA (lehce etiketi olmayan tercih edilir)
  - Cinsiyet (Lexique ile karsilastirilir, uyusmazsa isaretlenir)
  - Cogul bicim
  - Deyim etiketi
  - Fiil icin etiketli cekim formlari (Verbiste yerine, ayni CC BY-SA lisansi)
"""

from __future__ import annotations

import json
import os
import re
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

# kaikki kelime turu -> Lexique kelime turu
KAIKKI_POS = {
    "noun": "NOM",
    "verb": "VER",
    "adj": "ADJ",
    "adv": "ADV",
    "prep": "PRE",
    "conj": "CON",
    "pron": "PRO",
    "num": "ADJ:num",
    "phrase": "PHR",
    "intj": "INT",
}

# Bunlar tanim degil, baska maddeye yonlendirmedir. Atlanir.
FORM_OF_RE = re.compile(
    r"^\s*(alternative|obsolete|archaic|dated|misspelling|eye dialect|"
    r"plural|singular|feminine|masculine|inflection|past participle|"
    r"present participle|abbreviation|initialism|acronym|contraction|"
    r"synonym of|superseded)\b",
    re.IGNORECASE,
)

# Tanimin basindaki parantezli kullanim etiketi: "(transitive) to eat"
LEADING_LABEL_RE = re.compile(r"^\(([^)]{1,60})\)\s*")

REGISTER_HINTS = {
    "colloquial": "familier",
    "informal": "familier",
    "slang": "familier",
    "vulgar": "vulgaire",
    "literary": "soutenu",
    "formal": "soutenu",
    "dated": "soutenu",
}


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def clean_gloss(text: str) -> tuple[str, str | None]:
    """Tanimi temizler, basindaki kullanim etiketini register olarak dondurur."""
    register: str | None = None
    m = LEADING_LABEL_RE.match(text)
    if m:
        label = m.group(1).lower()
        for hint, value in REGISTER_HINTS.items():
            if hint in label:
                register = value
                break
        text = LEADING_LABEL_RE.sub("", text, count=1)
    return text.strip(), register


def pick_ipa(sounds: list) -> str | None:
    if not sounds:
        return None
    plain: list[str] = []
    tagged: list[str] = []
    for s in sounds:
        ipa = s.get("ipa")
        if not ipa:
            continue
        if s.get("tags"):
            tagged.append(ipa)
        else:
            plain.append(ipa)
    chosen = plain[0] if plain else (tagged[0] if tagged else None)
    return chosen


def pick_gender(entry: dict) -> str | None:
    def scan(tags) -> str | None:
        if not tags:
            return None
        if "feminine" in tags:
            return "f"
        if "masculine" in tags:
            return "m"
        return None

    g = scan(entry.get("tags"))
    if g:
        return g
    for sense in entry.get("senses", []) or []:
        g = scan(sense.get("tags"))
        if g:
            return g
    for form in entry.get("forms", []) or []:
        tags = form.get("tags") or []
        if "canonical" in tags:
            g = scan(tags)
            if g:
                return g
    return None


def is_idiomatic(entry: dict) -> bool:
    # Tek kelimelik lemma deyim degildir. Bu kontrol olmadan "avoir" gibi
    # deyimsel anlami olan her fiil deyim isaretleniyordu.
    if " " not in (entry.get("word") or ""):
        return False
    if entry.get("pos") == "phrase":
        return True
    for sense in entry.get("senses", []) or []:
        if "idiomatic" in (sense.get("tags") or []):
            return True
        for cat in sense.get("categories") or []:
            name = cat.get("name") if isinstance(cat, dict) else str(cat)
            if name and "idiom" in name.lower():
                return True
    return False


def main() -> int:
    levels_path = STAGES / "s2_levels.jsonl"
    kaikki_path = SOURCES / "kaikki" / "kaikki-French.jsonl"
    if not levels_path.exists():
        print("once: python content/tools/05_levels.py")
        return 2

    log("lemma havuzu yukleniyor")
    pool: dict[str, dict] = {}
    for line in levels_path.open(encoding="utf-8"):
        e = json.loads(line)
        pool[e["lemma"]] = e
    log(f"havuz: {human(len(pool))} lemma")

    log("kaikki taraniyor (547 MB, birkac dakika)")
    enriched: dict[str, dict] = {}
    verb_forms: dict[str, list] = {}
    lines = 0
    matched = 0
    skipped_form_of = 0
    pos_mismatch = 0

    with kaikki_path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            lines += 1
            if lines % 200000 == 0:
                log(f"  {human(lines)} satir, {human(matched)} eslesme")
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if entry.get("lang_code") != "fr":
                continue

            word = entry.get("word")
            if not word or word not in pool:
                continue

            our = pool[word]
            kaikki_pos = KAIKKI_POS.get(entry.get("pos") or "")
            # Deyim maddeleri tur eslesmesi aramaz
            idiom = is_idiomatic(entry)
            if not idiom and kaikki_pos is not None and kaikki_pos != our["pos"]:
                # Ayni kelimenin baska turdeki maddesi; atla ama say
                pos_mismatch += 1
                continue

            glosses: list[str] = []
            register: str | None = None
            for sense in entry.get("senses", []) or []:
                for raw in sense.get("glosses") or []:
                    if FORM_OF_RE.match(raw):
                        skipped_form_of += 1
                        continue
                    text, reg = clean_gloss(raw)
                    if not text or len(text) > 160:
                        continue
                    register = register or reg
                    if text not in glosses:
                        glosses.append(text)
                    if len(glosses) >= 2:
                        break
                if len(glosses) >= 2:
                    break

            if not glosses:
                continue

            existing = enriched.get(word)
            if existing is not None and len(existing["meaning_en"]) >= len(glosses):
                continue

            plural = None
            for form in entry.get("forms", []) or []:
                tags = form.get("tags") or []
                if "plural" in tags and "canonical" not in tags:
                    plural = form.get("form")
                    break

            enriched[word] = {
                "meaning_en": glosses,
                "ipa": pick_ipa(entry.get("sounds") or []),
                "gender_kaikki": pick_gender(entry),
                "plural": plural,
                "register": register,
                "is_idiom": idiom,
            }
            matched += 1

            # Fiil cekim formlarini ayni geciste topla
            if entry.get("pos") == "verb":
                forms = [
                    {"form": fm.get("form"), "tags": fm.get("tags")}
                    for fm in entry.get("forms") or []
                    if fm.get("form") and fm.get("tags")
                ]
                if forms:
                    verb_forms[word] = forms

    log(f"kaikki: {human(lines)} satir tarandi, {human(matched)} lemma zenginlestirildi")
    log(f"fiil formu toplanan lemma: {human(len(verb_forms))}")

    # ------------------------------------------------------------- birlestir
    out_path = STAGES / "s3_english.jsonl"
    forms_path = STAGES / "s3_verb_forms.jsonl"
    gender_conflicts = 0
    with_ipa = 0
    without_english = 0
    idioms = 0

    with out_path.open("w", encoding="utf-8") as fout:
        for lemma, base in pool.items():
            extra = enriched.get(lemma)
            if extra is None:
                without_english += 1
                continue

            lex_gender = base.get("gender")
            k_gender = extra["gender_kaikki"]
            conflict = bool(lex_gender and k_gender and lex_gender != k_gender)
            if conflict:
                gender_conflicts += 1
            if extra["ipa"]:
                with_ipa += 1
            if extra["is_idiom"]:
                idioms += 1

            base.update(
                {
                    "meaning_en": extra["meaning_en"],
                    "ipa": extra["ipa"],
                    "plural": extra["plural"],
                    "register": extra["register"],
                    "is_idiom": extra["is_idiom"],
                    "gender_kaikki": k_gender,
                    "gender_conflict": conflict,
                }
            )
            fout.write(json.dumps(base, ensure_ascii=False) + "\n")

    with forms_path.open("w", encoding="utf-8") as fout:
        for lemma, forms in verb_forms.items():
            fout.write(
                json.dumps({"lemma": lemma, "forms": forms}, ensure_ascii=False) + "\n"
            )

    kept = len(pool) - without_english
    level_counter: Counter[str] = Counter()
    for line in out_path.open(encoding="utf-8"):
        level_counter[json.loads(line)["level"]] += 1

    report = [
        "# Aşama 3 — İngilizce Anlam, Okunuş ve Fiil Formları",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        f"- Taranan kaikki satırı: **{human(lines)}**",
        f"- İngilizce tanımı bulunan lemma: **{human(kept)}** / {human(len(pool))}",
        f"- Tanım bulunamadığı için elenen: {human(without_english)}",
        f"- IPA bulunan: {human(with_ipa)}",
        f"- Deyim işaretlenen: {human(idioms)}",
        f"- Cinsiyet çakışması (Lexique ile kaikki farklı): {human(gender_conflicts)}",
        f"- Çekim formu toplanan fiil: **{human(len(verb_forms))}**",
        f"- Yönlendirme tanımı atlandı (\"alternative form of\" gibi): {human(skipped_form_of)}",
        f"- Tür uyuşmadığı için atlanan madde: {human(pos_mismatch)}",
        "",
        "## Kalan havuzun seviye dağılımı",
        "",
        "| Seviye | Sayı |",
        "|---|---|",
    ]
    for lv in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        report.append(f"| {lv} | {human(level_counter[lv])} |")

    (REPORTS / "stage3_english.md").write_text("\n".join(report), encoding="utf-8")
    log(f"yazildi: {out_path} ({human(kept)} lemma)")
    log(f"yazildi: {forms_path} ({human(len(verb_forms))} fiil)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
