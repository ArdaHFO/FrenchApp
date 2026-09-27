"""Asama 6 - deyimler.

Girdi : kaikki/kaikki-French.jsonl, stages/s2_levels.jsonl, dbnary
Cikti : stages/s6_idioms.jsonl

ONEMLI: Bu asama Lexique havuzundan BAGIMSIZ calisir.

Ilk denemede sadece 9 deyim yakalanmisti. Sebep: aday havuzumuz Lexique'ten
geliyor ve Lexique tek kelimelik lemmalar icerir. "avoir le cafard" gibi cok
kelimeli deyimler o havuzda hic yok, dolayisiyla kesisim bos kaliyordu.
Bu yuzden burada kaikki dogrudan taranir.

Deyimin seviyesi bilesenlerinin en yuksek seviyesinin bir ustudur (C2 ile
sinirli): bir deyimi anlamak icindeki kelimeleri bilmeyi ve ustune mecazi
cozmeyi gerektirir.
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
LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]

TOKEN_RE = re.compile(r"[a-zA-ZàâäçéèêëîïôöùûüÿœæÀ-Ü'’-]+")
FORM_OF_RE = re.compile(
    r"^\s*(alternative|obsolete|misspelling|plural|inflection|synonym of)\b",
    re.IGNORECASE,
)
LEADING_LABEL_RE = re.compile(r"^\(([^)]{1,60})\)\s*")


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def is_idiom(entry: dict) -> bool:
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
    kaikki = SOURCES / "kaikki" / "kaikki-French.jsonl"
    levels_path = STAGES / "s2_levels.jsonl"
    if not levels_path.exists():
        print("once: python content/tools/05_levels.py")
        return 2

    log("bilesen seviyeleri yukleniyor")
    lemma_level: dict[str, int] = {}
    for line in levels_path.open(encoding="utf-8"):
        e = json.loads(line)
        lemma_level[e["lemma"]] = LEVELS.index(e["level"])
    log(f"seviye bilinen lemma: {human(len(lemma_level))}")

    log("kaikki deyim taramasi")
    found: dict[str, dict] = {}
    lines = 0
    for line in kaikki.open(encoding="utf-8", errors="replace"):
        lines += 1
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("lang_code") != "fr":
            continue
        word = (entry.get("word") or "").strip()
        if not word or " " not in word:
            continue  # deyim en az iki kelimedir
        if len(word) > 60 or not is_idiom(entry):
            continue

        glosses: list[str] = []
        for sense in entry.get("senses", []) or []:
            for raw in sense.get("glosses") or []:
                if FORM_OF_RE.match(raw):
                    continue
                text = LEADING_LABEL_RE.sub("", raw).strip()
                if text and len(text) <= 160 and text not in glosses:
                    glosses.append(text)
                if len(glosses) >= 2:
                    break
            if len(glosses) >= 2:
                break
        if not glosses:
            continue

        ipa = None
        for s in entry.get("sounds") or []:
            if s.get("ipa"):
                ipa = s["ipa"]
                break

        existing = found.get(word)
        if existing and len(existing["meaning_en"]) >= len(glosses):
            continue
        found[word] = {"word": word, "meaning_en": glosses, "ipa": ipa}

    log(f"{human(lines)} satir tarandi, {human(len(found))} deyim adayi")

    # ----------------------------------------------------------- seviyelendir
    out_path = STAGES / "s6_idioms.jsonl"
    level_counter: Counter[str] = Counter()
    kept = 0
    skipped_unknown = 0

    with out_path.open("w", encoding="utf-8") as fout:
        for word, data in found.items():
            tokens = [t.lower() for t in TOKEN_RE.findall(word)]
            known = [lemma_level[t] for t in tokens if t in lemma_level]
            if len(known) < max(1, len(tokens) - 1):
                # Bilesenlerin cogunu tanimiyorsak seviye tahmini guvenilmez
                skipped_unknown += 1
                continue
            level_index = min(len(LEVELS) - 1, max(known) + 1)
            level = LEVELS[level_index]

            # Birebir ceviri bilesenlerden kurulur ama HER ZAMAN gozden
            # gecirme kuyruguna girer: otomatik uretimin en cok hata
            # yaptigi yer burasidir ve deyimin akilda kalmasini saglayan
            # alan tam da budur.
            data.update(
                {
                    "lemma": word,
                    "pos": "PHR",
                    "level": level,
                    "level_source": "components",
                    "is_idiom": True,
                    "needs_review": True,
                    "component_count": len(tokens),
                }
            )
            fout.write(json.dumps(data, ensure_ascii=False) + "\n")
            level_counter[level] += 1
            kept += 1

    log(f"yazildi: {out_path} ({human(kept)} deyim)")
    log(f"seviye dagilimi: {dict(level_counter)}")
    log(f"bilesenleri taninmadigi icin elenen: {human(skipped_unknown)}")

    report = [
        "# Aşama 6 — Deyimler",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        "Bu aşama Lexique havuzundan **bağımsız** çalışır. İlk denemede sadece",
        "9 deyim yakalanmıştı çünkü Lexique tek kelimelik lemmalar içerir ve",
        "çok kelimeli deyimlerle kesişmiyordu.",
        "",
        f"- Taranan satır: {human(lines)}",
        f"- **Bulunan deyim: {human(kept)}**",
        f"- Bileşenleri tanınmadığı için elenen: {human(skipped_unknown)}",
        "",
        "## Seviye dağılımı",
        "",
        "| Seviye | Deyim |",
        "|---|---|",
        *[f"| {lv} | {human(level_counter[lv])} |" for lv in LEVELS],
        "",
        "Not: Türkçe karşılıkları henüz yok. Deyimler için sonraki adım",
        "aşama 4'ün deyim havuzu üzerinde tekrar çalıştırılmasıdır.",
    ]
    (REPORTS / "stage6_idioms.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage6_idioms.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
