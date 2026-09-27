"""Yedek yollarin kapsamini olcer.

02_measure.py dogrudan yollarin dar oldugunu gosterdi:
  - Tatoeba'da dogrudan fra-tur bagli cumle: 12.245 (fransizcanin %1.7'si)
  - DBnary'de dogrudan fra-tur ceviri: 7.388

Bu script iki yedek yolu olcer:
  A) Tatoeba iki adimli baglanti: fra -> eng -> tur
     Tatoeba dogrudan baglantilari kurate eder ama ayni anlamin farkli
     dillerdeki karsiliklari genelde ingilizce uzerinden zincirlenir.
  B) DBnary ingilizce koprusu: fransizca kelimenin ingilizce karsiligi kac
     tanesinin turkce karsiligi var (geri kontrol olmadan ust sinir)

Kullanim:  python content/tools/03_measure_fallbacks.py
Cikti:     content/reports/measurements_fallback.md
"""

from __future__ import annotations

import bz2
import csv
import io
import os
import re
import sys
import tarfile
import time
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


def _tar_lines(path: Path):
    with tarfile.open(path, "r:bz2") as tf:
        member = next(m for m in tf if m.isfile())
        stream = tf.extractfile(member)
        assert stream is not None
        yield from csv.reader(
            io.TextIOWrapper(stream, encoding="utf-8", errors="replace"),
            delimiter="\t",
            quoting=csv.QUOTE_NONE,
        )


# ------------------------------------------------------------------ A yolu


def measure_two_hop() -> dict[str, int]:
    log("cumleler okunuyor")
    fra: set[int] = set()
    eng: set[int] = set()
    tur: set[int] = set()
    for row in _tar_lines(SOURCES / "tatoeba" / "sentences.tar.bz2"):
        if len(row) < 2:
            continue
        lang = row[1]
        if lang == "fra":
            fra.add(int(row[0]))
        elif lang == "eng":
            eng.add(int(row[0]))
        elif lang == "tur":
            tur.add(int(row[0]))
    log(f"fra {human(len(fra))} | eng {human(len(eng))} | tur {human(len(tur))}")

    log("1. gecis: turkceye bagli ingilizce cumleler")
    eng_with_tur: set[int] = set()
    for row in _tar_lines(SOURCES / "tatoeba" / "links.tar.bz2"):
        if len(row) < 2:
            continue
        try:
            a, b = int(row[0]), int(row[1])
        except ValueError:
            continue
        if a in eng and b in tur:
            eng_with_tur.add(a)
    log(f"turkce cevirisi olan ingilizce cumle: {human(len(eng_with_tur))}")

    log("2. gecis: bu ingilizce cumlelere bagli fransizca cumleler")
    fra_two_hop: set[int] = set()
    fra_direct_tur: set[int] = set()
    for row in _tar_lines(SOURCES / "tatoeba" / "links.tar.bz2"):
        if len(row) < 2:
            continue
        try:
            a, b = int(row[0]), int(row[1])
        except ValueError:
            continue
        if a in fra:
            if b in tur:
                fra_direct_tur.add(a)
            elif b in eng_with_tur:
                fra_two_hop.add(a)

    reachable = fra_direct_tur | fra_two_hop
    log(
        f"dogrudan {human(len(fra_direct_tur))} | "
        f"iki adimli {human(len(fra_two_hop))} | "
        f"toplam ulasan {human(len(reachable))}"
    )
    return {
        "fra": len(fra),
        "eng_with_tur": len(eng_with_tur),
        "direct": len(fra_direct_tur),
        "two_hop_only": len(fra_two_hop - fra_direct_tur),
        "reachable": len(reachable),
    }


# ------------------------------------------------------------------ B yolu

# DBnary ontolex biciminde ceviri kaydi soyle gorunur:
#   dbnary:targetLanguage lexvo:eng ;
#   dbnary:writtenForm "example"@eng ;
_LANG_RE = re.compile(r"targetLanguage\s+lexvo:(\w{3})")
_FORM_RE = re.compile(r'writtenForm\s+"([^"]{1,80})"')


def _translation_targets(path: Path, want_lang: str) -> set[str]:
    """Dosyadaki hedef dili want_lang olan cevirilerin yazili bicimleri."""
    found: set[str] = set()
    pending = False
    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if pending:
                m = _FORM_RE.search(line)
                if m:
                    found.add(m.group(1).strip().lower())
                    pending = False
                    continue
                if "targetLanguage" not in line and line.strip().endswith("."):
                    pending = False
            m = _LANG_RE.search(line)
            if m:
                pending = m.group(1) == want_lang
                # Ayni satirda writtenForm da olabilir
                if pending:
                    m2 = _FORM_RE.search(line)
                    if m2:
                        found.add(m2.group(1).strip().lower())
                        pending = False
    return found


def measure_bridge() -> dict[str, int]:
    log("dbnary: fransizcadan ingilizceye ceviriler")
    fr_to_en = _translation_targets(
        SOURCES / "dbnary" / "fr_dbnary_ontolex.ttl.bz2", "eng"
    )
    log(f"benzersiz ingilizce karsilik: {human(len(fr_to_en))}")

    log("dbnary: ingilizceden turkceye ceviriler (kaynak kelimeler)")
    # en_dbnary icinde kaynak kelime madde basidir; hedefi tur olan
    # cevirilerin yazili bicimi turkce kelimedir. Kopru icin bize
    # "turkce karsiligi olan ingilizce kelimeler" lazim; bunu madde
    # basi yerine kaba bir ust sinir olarak ceviri sayisiyla veriyoruz.
    en_to_tr_forms = _translation_targets(
        SOURCES / "dbnary" / "en_dbnary_ontolex.ttl.bz2", "tur"
    )
    log(f"ingilizceden turkceye benzersiz turkce bicim: {human(len(en_to_tr_forms))}")

    return {
        "fr_to_en_forms": len(fr_to_en),
        "en_to_tr_forms": len(en_to_tr_forms),
    }


def main() -> int:
    REPORTS.mkdir(parents=True, exist_ok=True)
    two = measure_two_hop()
    bridge = measure_bridge()

    pct_direct = 100.0 * two["direct"] / max(two["fra"], 1)
    pct_reach = 100.0 * two["reachable"] / max(two["fra"], 1)
    gain = two["reachable"] / max(two["direct"], 1)

    md = f"""# Yedek Yol Ölçümleri

Ölçüm tarihi: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye

## A. Tatoeba iki adımlı bağlantı (fra → eng → tur)

| Ölçüm | Sayı |
|---|---|
| Fransızca cümle | {human(two['fra'])} |
| Türkçe çevirisi olan İngilizce cümle | {human(two['eng_with_tur'])} |
| Doğrudan Türkçe çevirisi olan Fransızca cümle | {human(two['direct'])} ({pct_direct:.1f}%) |
| Sadece iki adımla ulaşılan | {human(two['two_hop_only'])} |
| **Türkçeye ulaşan toplam Fransızca cümle** | **{human(two['reachable'])}** ({pct_reach:.1f}%) |
| Kazanç | **{gain:.1f} kat** |

## B. DBnary İngilizce köprüsü (üst sınır)

| Ölçüm | Sayı |
|---|---|
| Fransızca maddelerin benzersiz İngilizce karşılığı | {human(bridge['fr_to_en_forms'])} |
| İngilizce maddelerin benzersiz Türkçe karşılığı | {human(bridge['en_to_tr_forms'])} |

Bu iki sayı köprünün üst sınırıdır. Gerçek kapsama, geri çeviri kontrolü
uygulandıktan sonra Aşama 4'te ölçülecek.
"""
    out = REPORTS / "measurements_fallback.md"
    out.write_text(md, encoding="utf-8")
    log(f"rapor yazildi: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
