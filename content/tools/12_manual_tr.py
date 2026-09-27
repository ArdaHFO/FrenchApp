"""Asama 4.5 - Elle yazilan Turkce karsiliklari havuza katar.

Girdi : stages/s3_english.jsonl + stages/s4_turkish.jsonl + overrides/manual.json
Cikti : stages/s4_turkish.jsonl (uzerine yazar)

Neden ayri bir asama:

Otomatik cozumleme (07_turkish.py) havuzun bir kismini karsiliksiz birakiyor.
Karsiliksiz kalanlar rastgele degil, tam tersi: en sik kullanilan kelimeler
sozluklerde en cok anlamli olanlar oldugu icin en cok onlar eleniyor.
"comme", "nouveau", "changer" gibi A1 kelimeleri boyle dusuyordu.

manual.json'daki bir kayit sadece duzeltme degil, EKLEME de olabilir. Lemma
s4'te yoksa ama s3_english'te varsa buradan enjekte edilir; seviyesi, kelime
turu, IPA'si ve ingilizce anlami zaten s3'te hazir.

Bu asama 08_examples.py'den ONCE calismali, yoksa eklenen kelimelere ornek
cumle baglanmaz.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
STAGES = DATA_ROOT / "stages"
OVERRIDES = ROOT / "content" / "overrides" / "manual.json"

FUNCTION_POS = {"PRE", "CON", "PRO", "PRO:per", "PRO:ind", "PRO:dem",
                "PRO:rel", "PRO:pos"}


def main() -> int:
    s3 = STAGES / "s3_english.jsonl"
    s4 = STAGES / "s4_turkish.jsonl"
    if not (s3.exists() and s4.exists()):
        print("once: python content/tools/07_turkish.py")
        return 2
    if not OVERRIDES.exists():
        print("manual.json yok, atlaniyor")
        return 0

    raw = json.loads(OVERRIDES.read_text(encoding="utf-8"))
    manual = {
        k: v for k, v in raw.items()
        if not k.startswith("_") and isinstance(v, dict) and v.get("meaning_tr")
    }

    english: dict[str, dict] = {}
    for line in s3.open(encoding="utf-8"):
        e = json.loads(line)
        english.setdefault(e["lemma"], e)

    rows = [json.loads(line) for line in s4.open(encoding="utf-8")]
    have = {r["lemma"] for r in rows}

    added = 0
    skipped: list[str] = []
    for lemma, ov in manual.items():
        if lemma in have:
            continue
        base = english.get(lemma)
        if base is None:
            skipped.append(lemma)
            continue
        e = dict(base)
        e["meaning_tr"] = ov["meaning_tr"]
        if ov.get("note_tr"):
            e["note_tr"] = ov["note_tr"]
        e["tr_path"] = "manual"
        e["tr_paths"] = ["manual"]
        e["tr_confidence"] = 1.0
        e["is_function_word"] = e["pos"] in FUNCTION_POS
        rows.append(e)
        added += 1

    rows.sort(key=lambda r: r["freq_rank"])
    with s4.open("w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    print(f"elle eklenen: {added} · toplam: {len(rows)}")
    if skipped:
        print(f"s3_english'te bulunamadigi icin atlanan {len(skipped)}: "
              f"{', '.join(sorted(skipped)[:20])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
