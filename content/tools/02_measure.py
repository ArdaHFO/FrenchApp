"""DATA_PIPELINE.md bolum 9'daki uc olcumu yapar.

Bu uc sayi planin kalanini belirler:
  1. Tatoeba'da dogrudan Fransizca-Turkce bagli cumle sayisi
     -> Kartlarda Turkce ornek cumle satiri olacak mi
  2. FLELex'in Lexique havuzunu kapsama orani
     -> Seviye atamasinin ne kadari gercek pedagojik veriden gelecek
  3. DBnary'de dogrudan fra-tur ceviri sayisi
     -> Turkce karsiliklarin ne kadari koprusuz bulunacak

Sadece standart kutuphane. Buyuk dosyalar akitilarak okunur, belleğe alinmaz.

Kullanim:  python content/tools/02_measure.py
Cikti:     content/reports/measurements.md
"""

from __future__ import annotations

import bz2
import csv
import io
import os
import sys
import tarfile
import time
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


# ---------------------------------------------------------------- olcum 1


def measure_tatoeba() -> dict[str, object]:
    """Fransizca cumlelerin kac tanesinin dogrudan Turkce cevirisi var."""
    sent_path = SOURCES / "tatoeba" / "sentences.tar.bz2"
    link_path = SOURCES / "tatoeba" / "links.tar.bz2"

    log("tatoeba: cumleler okunuyor (birkac dakika surer)")
    fra: set[int] = set()
    eng: set[int] = set()
    tur: set[int] = set()
    total = 0

    with tarfile.open(sent_path, "r:bz2") as tf:
        member = next(m for m in tf if m.isfile())
        stream = tf.extractfile(member)
        assert stream is not None
        reader = csv.reader(
            io.TextIOWrapper(stream, encoding="utf-8", errors="replace"),
            delimiter="\t",
            quoting=csv.QUOTE_NONE,
        )
        for row in reader:
            if len(row) < 2:
                continue
            total += 1
            lang = row[1]
            if lang == "fra":
                fra.add(int(row[0]))
            elif lang == "eng":
                eng.add(int(row[0]))
            elif lang == "tur":
                tur.add(int(row[0]))

    log(f"tatoeba: {human(total)} cumle | fra {human(len(fra))} "
        f"| eng {human(len(eng))} | tur {human(len(tur))}")

    log("tatoeba: baglar okunuyor")
    fra_to_tur: set[int] = set()
    fra_to_eng: set[int] = set()
    pair_tur = 0
    pair_eng = 0
    links = 0

    with tarfile.open(link_path, "r:bz2") as tf:
        member = next(m for m in tf if m.isfile())
        stream = tf.extractfile(member)
        assert stream is not None
        reader = csv.reader(
            io.TextIOWrapper(stream, encoding="utf-8", errors="replace"),
            delimiter="\t",
            quoting=csv.QUOTE_NONE,
        )
        for row in reader:
            if len(row) < 2:
                continue
            links += 1
            try:
                a, b = int(row[0]), int(row[1])
            except ValueError:
                continue
            if a in fra:
                if b in tur:
                    fra_to_tur.add(a)
                    pair_tur += 1
                elif b in eng:
                    fra_to_eng.add(a)
                    pair_eng += 1

    both = fra_to_tur & fra_to_eng
    log(f"tatoeba: fra->tur {human(len(fra_to_tur))} cumle, "
        f"fra->eng {human(len(fra_to_eng))}, ikisi birden {human(len(both))}")

    return {
        "total_sentences": total,
        "fra": len(fra),
        "eng": len(eng),
        "tur": len(tur),
        "links": links,
        "fra_with_tur": len(fra_to_tur),
        "fra_with_eng": len(fra_to_eng),
        "fra_with_both": len(both),
        "pair_tur": pair_tur,
        "pair_eng": pair_eng,
    }


# ---------------------------------------------------------------- olcum 2


def measure_flelex() -> dict[str, object]:
    """FLELex, Lexique lemma havuzunun ne kadarini kapsiyor."""
    lex_path = SOURCES / "lexique" / "Lexique383.tsv"
    fle_path = SOURCES / "flelex" / "FleLex_TT.csv"

    log("lexique: lemmalar okunuyor")
    lex_lemmas: set[str] = set()
    pos_counter: Counter[str] = Counter()
    with lex_path.open(encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            if row.get("islem") != "1":
                continue
            lemma = (row.get("lemme") or "").strip()
            if not lemma:
                continue
            lex_lemmas.add(lemma)
            pos_counter[(row.get("cgram") or "?").strip()] += 1
    log(f"lexique: {human(len(lex_lemmas))} benzersiz lemma (islem=1)")

    log("flelex: lemmalar okunuyor")
    fle_lemmas: set[str] = set()
    fle_header: list[str] = []
    with fle_path.open(encoding="utf-8", errors="replace", newline="") as f:
        sample = f.read(4096)
        f.seek(0)
        delim = "\t" if sample.count("\t") > sample.count(",") else ","
        reader = csv.reader(f, delimiter=delim)
        fle_header = next(reader, [])
        for row in reader:
            if row and row[0].strip():
                fle_lemmas.add(row[0].strip())
    log(f"flelex: {human(len(fle_lemmas))} lemma, sutunlar: {fle_header[:8]}")

    overlap = lex_lemmas & fle_lemmas
    return {
        "lexique_lemmas": len(lex_lemmas),
        "flelex_lemmas": len(fle_lemmas),
        "overlap": len(overlap),
        "coverage_pct": 100.0 * len(overlap) / max(len(lex_lemmas), 1),
        "flelex_columns": fle_header,
        "lexique_pos": dict(pos_counter.most_common(10)),
    }


# ---------------------------------------------------------------- olcum 3


def measure_dbnary() -> dict[str, object]:
    """Fransizca DBnary'de hangi hedef dillere kac ceviri var."""
    path = SOURCES / "dbnary" / "fr_dbnary_ontolex.ttl.bz2"
    log("dbnary: fransizca dosya taraniyor (birkac dakika surer)")

    lang_counter: Counter[str] = Counter()
    translations = 0
    lines = 0

    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            lines += 1
            if "targetLanguage" not in line:
                continue
            translations += 1
            # ornek:  dbnary:targetLanguage lexvo:tur ;
            idx = line.find("lexvo:")
            if idx >= 0:
                code = line[idx + 6 : idx + 6 + 3].strip(" ;.\n\t")
                lang_counter[code] += 1

    log(f"dbnary: {human(lines)} satir, {human(translations)} ceviri kaydi")
    log(f"dbnary: tur -> {human(lang_counter.get('tur', 0))}")

    return {
        "lines": lines,
        "translations": translations,
        "tur": lang_counter.get("tur", 0),
        "eng": lang_counter.get("eng", 0),
        "top_languages": dict(lang_counter.most_common(12)),
    }


# ------------------------------------------------------------------ rapor


def main() -> int:
    REPORTS.mkdir(parents=True, exist_ok=True)
    missing = [
        p
        for p in [
            SOURCES / "tatoeba" / "sentences.tar.bz2",
            SOURCES / "tatoeba" / "links.tar.bz2",
            SOURCES / "lexique" / "Lexique383.tsv",
            SOURCES / "flelex" / "FleLex_TT.csv",
            SOURCES / "dbnary" / "fr_dbnary_ontolex.ttl.bz2",
        ]
        if not p.exists()
    ]
    if missing:
        for p in missing:
            print(f"eksik kaynak: {p}")
        print("once: python content/tools/01_fetch.py")
        return 2

    tat = measure_tatoeba()
    fle = measure_flelex()
    dbn = measure_dbnary()

    fra_tur_pct = 100.0 * tat["fra_with_tur"] / max(tat["fra"], 1)  # type: ignore[operator]
    both_pct = 100.0 * tat["fra_with_both"] / max(tat["fra"], 1)  # type: ignore[operator]

    md = f"""# Faz 1 Ölçümleri

Ölçüm tarihi: {time.strftime('%Y-%m-%d %H:%M')}
Süre: {time.time() - T0:.0f} saniye

Bu üç sayı DATA_PIPELINE.md bölüm 9'da planın kalanını belirleyen ölçümler
olarak tanımlanmıştı.

## 1. Tatoeba — Fransızca/Türkçe cümle bağı

| Ölçüm | Sayı |
|---|---|
| Toplam cümle (tüm diller) | {human(tat['total_sentences'])} |
| Fransızca cümle | {human(tat['fra'])} |
| İngilizce cümle | {human(tat['eng'])} |
| Türkçe cümle | {human(tat['tur'])} |
| Toplam çeviri bağı | {human(tat['links'])} |
| **Türkçe çevirisi olan Fransızca cümle** | **{human(tat['fra_with_tur'])}** ({fra_tur_pct:.1f}%) |
| İngilizce çevirisi olan Fransızca cümle | {human(tat['fra_with_eng'])} |
| **Hem İngilizce hem Türkçe çevirisi olan** | **{human(tat['fra_with_both'])}** ({both_pct:.1f}%) |

## 2. FLELex — seviye kapsaması

| Ölçüm | Sayı |
|---|---|
| Lexique benzersiz lemma (islem=1) | {human(fle['lexique_lemmas'])} |
| FLELex lemma | {human(fle['flelex_lemmas'])} |
| **Kesişim** | **{human(fle['overlap'])}** |
| **Kapsama oranı** | **{fle['coverage_pct']:.1f}%** |

FLELex sütunları: `{fle['flelex_columns']}`

Lexique kelime türü dağılımı (ilk 10): `{fle['lexique_pos']}`

## 3. DBnary — Fransızca'dan Türkçe'ye doğrudan çeviri

| Ölçüm | Sayı |
|---|---|
| Taranan satır | {human(dbn['lines'])} |
| Toplam çeviri kaydı | {human(dbn['translations'])} |
| **Türkçe hedefli çeviri** | **{human(dbn['tur'])}** |
| İngilizce hedefli çeviri | {human(dbn['eng'])} |

En çok çeviri olan diller: `{dbn['top_languages']}`
"""

    out = REPORTS / "measurements.md"
    out.write_text(md, encoding="utf-8")
    # Windows konsolu cp1252 kullaniyor ve Turkce karakterleri basamiyor.
    # Rapor dosyaya yazildi, konsola basmak zorunlu degil.
    try:
        print()
        print(md)
    except UnicodeEncodeError:
        print("(konsol Turkce karakter basamiyor, rapora bakiniz)")
    log(f"rapor yazildi: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
