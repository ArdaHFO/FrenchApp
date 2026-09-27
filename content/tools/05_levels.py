"""Asama 2 - seviye atamasi.

Girdi : stages/s1_lemmas.jsonl, flelex/FleLex_TT.csv
Cikti : stages/s2_levels.jsonl

FLELex her lemma icin A1'den C2'ye seviye basina normalize siklik verir.
Sik kelimeler A1 derleminde yogun, seyrek kelimeler ust seviyelerde belirir.

Seviye kurali:
    seviye = sikligin esigi ilk astigi seviye
    esik   = max(0.5,  0.10 * o kelimenin en yuksek seviye sikligi)

Mutlak taban (0.5) gurultuyu eler. Goreli olcut (%10) ise kelimeye gore
uyarlanir: her seviyede yuksek degeri olan bir kelimede %10 esigi anlamli
bir baslangic noktasi verir. Ornek: "-ci" parcaciginin A1 degeri 0.83 ama
tepe degeri 297; sadece mutlak esik kullanilsa yanlislikla A1 olurdu.

FLELex havuzun tamamini kapsamaz (olcum: %29.5). Kapsanmayanlar siklik
bandina duser. Iki yontem iki seviyeden fazla ayrisirsa satir isaretlenir.
"""

from __future__ import annotations

import csv
import json
import os
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

LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]

# Lexique kelime turu -> FLELex (TreeTagger) etiketi
POS_MAP = {
    "NOM": "NOM",
    "ADJ": "ADJ",
    "VER": "VER",
    "ADV": "ADV",
    "PRE": "PRP",
    "CON": "KON",
    "PRO:per": "PRO",
    "PRO:ind": "PRO",
    "PRO:dem": "PRO",
    "PRO:rel": "PRO",
    "PRO:pos": "PRO",
    "ADJ:num": "NUM",
}

ABSOLUTE_FLOOR = 0.5
RELATIVE_SHARE = 0.10

# Siklik bandi yedegi. Sinirlar DATA_PIPELINE.md asama 2'deki tabloya uyar.
FREQ_BANDS = [
    (600, "A1"),
    (1600, "A2"),
    (3600, "B1"),
    (7000, "B2"),
    (12000, "C1"),
]


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def level_from_flelex(freqs: list[float]) -> str | None:
    peak = max(freqs)
    if peak <= 0:
        return None
    threshold = max(ABSOLUTE_FLOOR, RELATIVE_SHARE * peak)
    for i, value in enumerate(freqs):
        if value >= threshold:
            return LEVELS[i]
    return LEVELS[-1]


def level_from_rank(rank: int) -> str:
    for limit, level in FREQ_BANDS:
        if rank <= limit:
            return level
    return "C2"


def main() -> int:
    lemmas_path = STAGES / "s1_lemmas.jsonl"
    flelex_path = SOURCES / "flelex" / "FleLex_TT.csv"
    if not lemmas_path.exists():
        print("once: python content/tools/04_lemmas.py")
        return 2

    # ------------------------------------------------------- FLELex'i oku
    log("flelex okunuyor")
    # (kelime, etiket) -> seviye   ve   kelime -> seviye  (etiketsiz yedek)
    by_word_tag: dict[tuple[str, str], str] = {}
    by_word: dict[str, str] = {}

    with flelex_path.open(encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        header = next(reader, [])
        idx = {name: i for i, name in enumerate(header)}
        cols = [idx[f"freq_{lv}"] for lv in LEVELS]
        for row in reader:
            if len(row) <= max(cols):
                continue
            word = row[idx["word"]].strip()
            tag = row[idx["tag"]].strip()
            try:
                freqs = [float(row[c]) for c in cols]
            except ValueError:
                continue
            level = level_from_flelex(freqs)
            if level is None:
                continue
            by_word_tag[(word, tag)] = level
            # Etiketsiz yedekte en dusuk (en kolay) seviye tutulur
            prev = by_word.get(word)
            if prev is None or LEVELS.index(level) < LEVELS.index(prev):
                by_word[word] = level

    log(f"flelex: {human(len(by_word_tag))} kelime-etiket, {human(len(by_word))} kelime")

    # ---------------------------------------------------- lemmalari isle
    log("seviyeler ataniyor")
    out_path = STAGES / "s2_levels.jsonl"
    source_counter: Counter[str] = Counter()
    level_counter: Counter[str] = Counter()
    level_by_source: dict[str, Counter[str]] = {
        "flelex": Counter(),
        "flelex_untagged": Counter(),
        "frequency": Counter(),
    }
    disagreements = 0
    examples: list[str] = []
    total = 0

    with lemmas_path.open(encoding="utf-8") as fin, out_path.open(
        "w", encoding="utf-8"
    ) as fout:
        for line in fin:
            entry = json.loads(line)
            total += 1
            lemma = entry["lemma"]
            tag = POS_MAP.get(entry["pos"])
            rank = entry["freq_rank"]

            band_level = level_from_rank(rank)

            level = None
            source = "frequency"
            if tag is not None and (lemma, tag) in by_word_tag:
                level = by_word_tag[(lemma, tag)]
                source = "flelex"
            elif lemma in by_word:
                level = by_word[lemma]
                source = "flelex_untagged"
            else:
                level = band_level

            # Iki yontem iki seviyeden fazla ayrisiyorsa isaretle
            gap = abs(LEVELS.index(level) - LEVELS.index(band_level))
            needs_review = source != "frequency" and gap >= 2
            if needs_review:
                disagreements += 1
                if len(examples) < 12:
                    examples.append(
                        f"| {lemma} | {entry['pos']} | {level} | {band_level} | {rank} |"
                    )

            entry["level"] = level
            entry["level_source"] = source
            entry["level_from_rank"] = band_level
            entry["level_needs_review"] = needs_review
            fout.write(json.dumps(entry, ensure_ascii=False) + "\n")

            source_counter[source] += 1
            level_counter[level] += 1
            level_by_source[source][level] += 1

    log(f"yazildi: {out_path} ({human(total)} lemma)")
    log(f"kaynak dagilimi: {dict(source_counter)}")
    log(f"seviye dagilimi: {dict(level_counter)}")
    log(f"ayrisan satir: {human(disagreements)}")

    # ------------------------------------------------------------- rapor
    flelex_total = source_counter["flelex"] + source_counter["flelex_untagged"]
    coverage = 100.0 * flelex_total / max(total, 1)

    report = [
        "# Aşama 2 — Seviye Ataması",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        "## Kural",
        "",
        "```",
        "seviye = sıklığın eşiği ilk aştığı seviye",
        f"eşik   = max({ABSOLUTE_FLOOR}, {RELATIVE_SHARE:.2f} × kelimenin en yüksek seviye sıklığı)",
        "```",
        "",
        "Mutlak taban gürültüyü eler, göreli ölçüt kelimeye göre uyarlanır.",
        "",
        "## Kaynak dağılımı",
        "",
        "| Kaynak | Sayı | Oran |",
        "|---|---|---|",
        f"| FLELex (kelime + tür eşleşti) | {human(source_counter['flelex'])} | {100.0 * source_counter['flelex'] / total:.1f}% |",
        f"| FLELex (sadece kelime eşleşti) | {human(source_counter['flelex_untagged'])} | {100.0 * source_counter['flelex_untagged'] / total:.1f}% |",
        f"| Sıklık bandı yedeği | {human(source_counter['frequency'])} | {100.0 * source_counter['frequency'] / total:.1f}% |",
        "",
        f"**FLELex kapsaması: {coverage:.1f}%** ({human(flelex_total)} / {human(total)})",
        "",
        "## Seviye dağılımı",
        "",
        "| Seviye | Toplam | FLELex'ten | Sıklık bandından |",
        "|---|---|---|---|",
    ]
    for lv in LEVELS:
        fl = level_by_source["flelex"][lv] + level_by_source["flelex_untagged"][lv]
        fr = level_by_source["frequency"][lv]
        report.append(f"| {lv} | {human(level_counter[lv])} | {human(fl)} | {human(fr)} |")

    report += [
        "",
        f"## Ayrışan atamalar: {human(disagreements)}",
        "",
        "İki yöntem iki seviyeden fazla ayrıştığında satır gözden geçirme",
        "kuyruğuna girer. Genelde iki sebepten olur: kelime öğretim",
        "kitaplarında geçmiyordur ama günlük dilde çok kullanılır, ya da tersi.",
        "",
        "| Lemma | Tür | FLELex | Sıklık bandı | Sıra |",
        "|---|---|---|---|---|",
        *examples,
    ]

    (REPORTS / "stage2_levels.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage2_levels.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
