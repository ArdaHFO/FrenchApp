"""Asama 1 - aday kelime havuzu.

Girdi : Lexique383.tsv, freq/fr_50k.txt
Cikti : <FRENCHAPP_DATA>/stages/s1_lemmas.jsonl

Lexique zaten lemma duzeyinde film ve kitap sikligi veriyor. OpenSubtitles
listesi ise yuzey bicim duzeyinde. Ikisini birlestirmek icin Lexique'in
ortho -> lemme eslemesiyle OpenSubtitles sayimlarini lemmaya toplariz.
Boylece iki kaynak da anlamli katki verir.

Siralama iki listenin sira ortalamasiyla yapilir (0.6 konusma, 0.4 yazi).
Ham frekanslari harmanlamak yerine sira harmanlamak dagilim farklarina
karsi daha dayanikli.
"""

from __future__ import annotations

import csv
import json
import math
import os
import sys
import time
import unicodedata
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

# Uygulamaya girecek kelime turleri. Ozel isim, kisaltma ve unlem disarida.
ALLOWED_POS = {
    "NOM": "isim",
    "ADJ": "sıfat",
    "VER": "fiil",
    "ADV": "zarf",
    "PRE": "edat",
    "CON": "bağlaç",
    "PRO:per": "zamir",
    "PRO:ind": "zamir",
    "PRO:dem": "zamir",
    "PRO:rel": "zamir",
    "PRO:pos": "zamir",
    "ADJ:num": "sayı",
}


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def is_proper_noun(ortho: str) -> bool:
    return bool(ortho) and ortho[0].isupper()


def looks_usable(lemma: str) -> bool:
    if len(lemma) < 2:
        return False
    if any(ch.isdigit() for ch in lemma):
        return False
    # Kesme isareti ve tire kabul, baska noktalama hayir
    for ch in lemma:
        if ch.isalpha() or ch in "'-":
            continue
        return False
    return True


def strip_accents(s: str) -> str:
    return "".join(
        c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn"
    )


def main() -> int:
    lex_path = SOURCES / "lexique" / "Lexique383.tsv"
    freq_path = SOURCES / "freq" / "fr_50k.txt"
    if not lex_path.exists() or not freq_path.exists():
        print("once: python content/tools/01_fetch.py")
        return 2

    STAGES.mkdir(parents=True, exist_ok=True)
    REPORTS.mkdir(parents=True, exist_ok=True)

    # --------------------------------------------- 1) Lexique'i tek geciste oku
    log("lexique okunuyor")
    surface_to_lemma: dict[str, str] = {}
    lemmas: dict[str, dict] = {}
    rows_read = 0
    skipped_proper = 0

    with lex_path.open(encoding="utf-8", errors="replace", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            rows_read += 1
            ortho = (row.get("ortho") or "").strip()
            lemme = (row.get("lemme") or "").strip()
            cgram = (row.get("cgram") or "").strip()
            if not ortho or not lemme:
                continue

            # Yuzey bicim -> lemma eslemesi (OpenSubtitles toplamasi icin)
            key = ortho.lower()
            if key not in surface_to_lemma:
                surface_to_lemma[key] = lemme

            if row.get("islem") != "1":
                continue
            if cgram not in ALLOWED_POS:
                continue
            if is_proper_noun(ortho):
                skipped_proper += 1
                continue
            if not looks_usable(lemme):
                continue

            def as_float(name: str) -> float:
                try:
                    return float(row.get(name) or 0)
                except ValueError:
                    return 0.0

            films = as_float("freqlemfilms2")
            livres = as_float("freqlemlivres")
            if films <= 0 and livres <= 0:
                continue

            entry = lemmas.get(lemme)
            if entry is None or cgram == "VER":
                # Ayni lemma birden fazla turde gecebilir. Fiil onceliklidir,
                # cunku cekim tablosu ona bagli.
                lemmas[lemme] = {
                    "lemma": lemme,
                    "pos": cgram,
                    "pos_tr": ALLOWED_POS[cgram],
                    "gender": (row.get("genre") or "").strip() or None,
                    "phon": (row.get("phon") or "").strip() or None,
                    "nb_syll": row.get("nbsyll") or None,
                    "freq_films": films,
                    "freq_livres": livres,
                    "surface_count": 0,
                }

    log(
        f"lexique: {human(rows_read)} satir, {human(len(lemmas))} aday lemma, "
        f"{human(skipped_proper)} ozel isim atlandi"
    )

    # ------------------------------- 2) OpenSubtitles sayimlarini lemmaya topla
    log("opensubtitles sayimlari lemmaya toplaniyor")
    lemma_subs: dict[str, int] = defaultdict(int)
    matched = 0
    unmatched = 0
    with freq_path.open(encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            word, count = parts[0].lower(), parts[1]
            if not count.isdigit():
                continue
            lemma = surface_to_lemma.get(word)
            if lemma is None:
                unmatched += 1
                continue
            matched += 1
            lemma_subs[lemma] += int(count)

    log(
        f"opensubtitles: {human(matched)} bicim eslesti, "
        f"{human(unmatched)} eslesmedi"
    )

    for lemma, entry in lemmas.items():
        entry["surface_count"] = lemma_subs.get(lemma, 0)

    # ------------------------------------------------ 3) Siralamalari harmanla
    log("siklik siralamasi hesaplaniyor")
    items = list(lemmas.values())

    spoken_sorted = sorted(
        items,
        key=lambda e: (e["surface_count"], e["freq_films"]),
        reverse=True,
    )
    written_sorted = sorted(items, key=lambda e: e["freq_livres"], reverse=True)

    spoken_rank = {e["lemma"]: i for i, e in enumerate(spoken_sorted)}
    written_rank = {e["lemma"]: i for i, e in enumerate(written_sorted)}

    for e in items:
        # Konusma diline daha fazla agirlik: amac konusulan dili ogrenmek.
        e["blend"] = 0.6 * spoken_rank[e["lemma"]] + 0.4 * written_rank[e["lemma"]]

    items.sort(key=lambda e: e["blend"])
    for i, e in enumerate(items, start=1):
        e["freq_rank"] = i
        e.pop("blend", None)
        # log siklik, sonraki asamalarda seviye bandi icin kullanisli
        e["log_freq"] = round(math.log1p(e["freq_films"] + e["freq_livres"]), 4)

    out = STAGES / "s1_lemmas.jsonl"
    with out.open("w", encoding="utf-8") as f:
        for e in items:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    # ------------------------------------------------------------- 4) rapor
    pos_counts: dict[str, int] = defaultdict(int)
    for e in items:
        pos_counts[e["pos"]] += 1

    top = items[:25]
    report = [
        "# Aşama 1 — Aday Kelime Havuzu",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        f"- Lexique satırı okundu: **{human(rows_read)}**",
        f"- Aday lemma: **{human(len(items))}**",
        f"- Özel isim atlandı: {human(skipped_proper)}",
        f"- OpenSubtitles biçimi eşleşti: {human(matched)} (eşleşmeyen {human(unmatched)})",
        "",
        "## Kelime türü dağılımı",
        "",
        "| Tür | Sayı |",
        "|---|---|",
    ]
    for pos, n in sorted(pos_counts.items(), key=lambda kv: -kv[1]):
        report.append(f"| {pos} ({ALLOWED_POS[pos]}) | {human(n)} |")

    report += [
        "",
        "## En sık 25 lemma",
        "",
        "| # | Lemma | Tür | Film sıklığı | Kitap sıklığı | Altyazı sayımı |",
        "|---|---|---|---|---|---|",
    ]
    for e in top:
        report.append(
            f"| {e['freq_rank']} | {e['lemma']} | {e['pos']} | "
            f"{e['freq_films']:.1f} | {e['freq_livres']:.1f} | {human(e['surface_count'])} |"
        )

    (REPORTS / "stage1_lemmas.md").write_text("\n".join(report), encoding="utf-8")
    log(f"yazildi: {out} ({human(len(items))} lemma)")
    log(f"rapor: {REPORTS / 'stage1_lemmas.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
