"""Asama 7 - fiil cekim tablolari.

Girdi : stages/s3_verb_forms.jsonl (kaikki forms), stages/s4_turkish.jsonl
Cikti : stages/s7_verbs.jsonl

Basit zamanlar kaikki'nin etiketli form listesinden dogrudan okunur.
Bilesik zamanlar (passe compose, plus-que-parfait) bizim kuralimizla
kurulur: yardimci fiil + gecmis zaman ortaci.

Verbiste kullanilmiyor; gerekce DATA_PIPELINE.md bolum 1.
"""

from __future__ import annotations

import json
import os
import sys
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

PERSONS = ["je", "tu", "il", "nous", "vous", "ils"]

PERSON_FROM_TAGS = {
    ("first-person", "singular"): "je",
    ("second-person", "singular"): "tu",
    ("third-person", "singular"): "il",
    ("first-person", "plural"): "nous",
    ("second-person", "plural"): "vous",
    ("third-person", "plural"): "ils",
}

# Basit zamanlar ve hangi etiketlerin onu isaret ettigi
SIMPLE_TENSES = [
    ("present", {"indicative", "present"}, set()),
    ("imparfait", {"indicative", "imperfect"}, set()),
    ("futur_simple", {"indicative", "future"}, set()),
    ("conditionnel", {"conditional"}, set()),
    ("subjonctif", {"subjunctive", "present"}, set()),
    ("imperatif", {"imperative"}, {"present"}),
]

TENSE_LEVEL = {
    "present": "A1",
    "passe_compose": "A1",
    "imparfait": "A1",
    "imperatif": "A1",
    "futur_simple": "A2",
    "conditionnel": "A2",
    "plus_que_parfait": "A2",
    "subjonctif": "B1",
}

TENSE_LABEL = {
    "present": "Présent",
    "passe_compose": "Passé composé",
    "imparfait": "Imparfait",
    "futur_simple": "Futur simple",
    "conditionnel": "Conditionnel présent",
    "subjonctif": "Subjonctif présent",
    "imperatif": "Impératif",
    "plus_que_parfait": "Plus-que-parfait",
}

# être ile cekilen fiiller (DR MRS VANDERTRAMP). Kapali bir listedir.
ETRE_VERBS = {
    "aller", "arriver", "descendre", "redescendre", "entrer", "rentrer",
    "monter", "remonter", "mourir", "naître", "partir", "repartir",
    "passer", "rester", "retourner", "revenir", "sortir", "ressortir",
    "tomber", "retomber", "venir", "devenir", "parvenir", "intervenir",
}

# Ortacin ozneye uyumu (sadece être alan fiillerde)
AGREEMENT = {"je": "", "tu": "", "il": "", "nous": "s", "vous": "s", "ils": "s"}


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def build_simple(forms: list[dict]) -> dict[str, dict[str, str]]:
    """kaikki form listesinden basit zaman tablolarini cikarir."""
    table: dict[str, dict[str, str]] = {}
    for item in forms:
        tags = set(item.get("tags") or [])
        form = (item.get("form") or "").strip()
        if not form or form in {"-", "—"}:
            continue

        person = None
        for (p1, p2), name in PERSON_FROM_TAGS.items():
            if p1 in tags and p2 in tags:
                person = name
                break
        if person is None:
            continue

        for tense, required, forbidden in SIMPLE_TENSES:
            if required <= tags and not (forbidden & tags):
                # Impératif sadece tu/nous/vous
                if tense == "imperatif" and person not in {"tu", "nous", "vous"}:
                    continue
                table.setdefault(tense, {})
                table[tense].setdefault(person, form)
                break
    return table


def past_participle(forms: list[dict]) -> str | None:
    for item in forms:
        tags = set(item.get("tags") or [])
        if "participle" in tags and "past" in tags:
            f = (item.get("form") or "").strip()
            if f:
                return f
    return None


def main() -> int:
    forms_path = STAGES / "s3_verb_forms.jsonl"
    words_path = STAGES / "s4_turkish.jsonl"
    if not forms_path.exists() or not words_path.exists():
        print("once: 06_english.py ve 07_turkish.py")
        return 2

    log("fiil formlari yukleniyor")
    raw_forms: dict[str, list[dict]] = {}
    for line in forms_path.open(encoding="utf-8"):
        d = json.loads(line)
        raw_forms[d["lemma"]] = d["forms"]
    log(f"form tablosu olan fiil: {human(len(raw_forms))}")

    log("kelime bilgileri yukleniyor")
    words: dict[str, dict] = {}
    for line in words_path.open(encoding="utf-8"):
        e = json.loads(line)
        if e["pos"] == "VER":
            words[e["lemma"]] = e
    log(f"turkce karsiligi olan fiil: {human(len(words))}")

    # Yardimci fiillerin tablolari bilesik zamanlar icin sart
    aux_tables: dict[str, dict[str, dict[str, str]]] = {}
    for aux in ("avoir", "être"):
        if aux in raw_forms:
            aux_tables[aux] = build_simple(raw_forms[aux])
    missing_aux = [a for a in ("avoir", "être") if a not in aux_tables]
    if missing_aux:
        log(f"UYARI: yardimci fiil tablosu eksik: {missing_aux}")

    log("cekim tablolari kuruluyor")
    out_path = STAGES / "s7_verbs.jsonl"
    stat = Counter()
    tense_stat = Counter()
    kept = 0

    with out_path.open("w", encoding="utf-8") as fout:
        for lemma, entry in sorted(words.items(), key=lambda kv: kv[1]["freq_rank"]):
            forms = raw_forms.get(lemma)
            if not forms:
                stat["form_yok"] += 1
                continue

            table = build_simple(forms)
            if "present" not in table or len(table["present"]) < 6:
                stat["present_eksik"] += 1
                continue

            pp = past_participle(forms)
            aux = "être" if lemma in ETRE_VERBS else "avoir"

            # Bilesik zamanlar
            if pp and aux in aux_tables:
                for compound, aux_tense in (
                    ("passe_compose", "present"),
                    ("plus_que_parfait", "imparfait"),
                ):
                    aux_row = aux_tables[aux].get(aux_tense)
                    if not aux_row or len(aux_row) < 6:
                        continue
                    row: dict[str, str] = {}
                    for person in PERSONS:
                        a = aux_row.get(person)
                        if not a:
                            continue
                        participle = pp
                        if aux == "être":
                            participle = pp + AGREEMENT[person]
                        row[person] = f"{a} {participle}"
                    if len(row) == 6:
                        table[compound] = row
            else:
                stat["ortac_yok"] += 1

            # Eksik zamanlari at, altı sahsi tam olanlari tut
            clean: dict[str, dict[str, str]] = {}
            for tense, row in table.items():
                needed = 3 if tense == "imperatif" else 6
                if len(row) >= needed:
                    clean[tense] = row
                    tense_stat[tense] += 1

            if "present" not in clean:
                stat["present_eksik"] += 1
                continue

            fout.write(
                json.dumps(
                    {
                        "lemma": lemma,
                        "level": entry["level"],
                        "freq_rank": entry["freq_rank"],
                        "meaning_tr": entry["meaning_tr"],
                        "meaning_en": entry["meaning_en"],
                        "ipa": entry.get("ipa"),
                        "auxiliary": aux,
                        "past_participle": pp,
                        "tenses": clean,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
            kept += 1

    log(f"yazildi: {out_path} ({human(kept)} fiil)")
    log(f"zaman dagilimi: {dict(tense_stat)}")
    log(f"elenenler: {dict(stat)}")

    report = [
        "# Aşama 7 — Fiil Çekim Tabloları",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        f"**Çekim tablosu üretilen fiil: {human(kept)}**",
        "",
        "Basit zamanlar kaikki.org'un etiketli form listesinden okundu.",
        "Bileşik zamanlar (passé composé, plus-que-parfait) yardımcı fiil +",
        "geçmiş zaman ortacı kuralıyla kuruldu. `être` alan fiillerde ortaç",
        "özneye uyumlu çekildi.",
        "",
        "## Zaman başına tablo sayısı",
        "",
        "| Zaman | Seviye | Tablo |",
        "|---|---|---|",
    ]
    for tense, n in sorted(tense_stat.items(), key=lambda kv: -kv[1]):
        report.append(
            f"| {TENSE_LABEL.get(tense, tense)} | {TENSE_LEVEL.get(tense, '?')} | {human(n)} |"
        )
    report += [
        "",
        "## Elenenler",
        "",
        "| Sebep | Sayı |",
        "|---|---|",
        *[f"| {k} | {human(v)} |" for k, v in stat.items()],
    ]
    (REPORTS / "stage7_verbs.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage7_verbs.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
