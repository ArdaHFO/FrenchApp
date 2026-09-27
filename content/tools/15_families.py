"""Asama 8 - Kelime aileleri.

Girdi : sources/kaikki/kaikki-French.jsonl + stages/s5_examples.jsonl
Cikti : stages/s8_families.jsonl, reports/stage8_families.md

Kaikki her madde icin iki alan tasiyor:

  derived : bu kelimeden turemis kelimeler
            chanter -> chantable, chantage, chanteur, chantonner, dechanter
  related : ayni kokten gelen akrabalar
            chanter -> chant, chanson, chantre, enchanter, incantation

Ikisini birlestirip yonlu olmayan bir komsuluk grafigi kuruyoruz.

Bilincli bir tasarim karari: **baglantili bilesen (transitive closure)
KULLANILMIYOR.** Zincirleme birlestirme yapilirsa "faire" gibi uretken bir
kok yuzlerce kelimeyi tek bir aileye topluyor ve aile bilgisi anlamini
yitiriyor. Onun yerine her kelimenin sadece DOGRUDAN komsulari saklaniyor;
ekranda "ayni kokten" derken kastedilen tam olarak bu.

Havuzda olmayan kelimeler atilir: kullaniciya sozlukte bulunmayan bir
kelimeyi gostermenin anlami yok.
"""

from __future__ import annotations

import io
import json
import os
import sys
import time
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

# Bir kelime icin en fazla kac akraba saklanir. Kartta dort tanesi
# gosteriliyor, arama sayfasinda hepsi.
MAX_PER_WORD = 10


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def main() -> int:
    pool_path = STAGES / "s5_examples.jsonl"
    if not pool_path.exists():
        print("once: python content/tools/08_examples.py")
        return 2

    log("havuz yukleniyor")
    freq: dict[str, int] = {}
    for line in pool_path.open(encoding="utf-8"):
        e = json.loads(line)
        freq[e["lemma"]] = e.get("freq_rank", 999999)
    log(f"havuz: {human(len(freq))} lemma")

    kaikki = SOURCES / "kaikki" / "kaikki-French.jsonl"
    if not kaikki.exists():
        print("kaikki dosyasi yok")
        return 2

    log("kaikki taraniyor (547 MB)")
    edges: dict[str, set[str]] = defaultdict(set)
    seen_entries = 0
    with io.open(kaikki, encoding="utf-8") as f:
        for line in f:
            # Ucuz on eleme: iki alandan biri yoksa JSON'u hic acma.
            if '"derived"' not in line and '"related"' not in line:
                continue
            o = json.loads(line)
            word = o.get("word")
            if not word or word not in freq:
                continue
            seen_entries += 1
            for field in ("derived", "related"):
                for item in o.get(field) or []:
                    other = item.get("word") if isinstance(item, dict) else item
                    if not other or other == word or other not in freq:
                        continue
                    edges[word].add(other)
                    edges[other].add(word)

    log(f"akrabaligi olan madde: {human(seen_entries)} | "
        f"grafikteki kelime: {human(len(edges))}")

    out_path = STAGES / "s8_families.jsonl"
    total_links = 0
    with out_path.open("w", encoding="utf-8") as fout:
        for word in sorted(edges, key=lambda w: freq[w]):
            # Akrabalar siklik sirasina gore: en tanidik olan basta.
            kin = sorted(edges[word], key=lambda w: freq[w])[:MAX_PER_WORD]
            if not kin:
                continue
            total_links += len(kin)
            fout.write(json.dumps(
                {"lemma": word, "kin": kin}, ensure_ascii=False) + "\n")

    log(f"yazildi: {out_path} ({human(len(edges))} kelime, "
        f"{human(total_links)} bag)")

    sizes = [len(v) for v in edges.values()]
    avg = sum(sizes) / len(sizes) if sizes else 0
    biggest = sorted(edges.items(), key=lambda kv: -len(kv[1]))[:8]

    report = [
        "# Aşama 8 — Kelime Aileleri",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · "
        f"Süre: {time.time() - T0:.0f} saniye",
        "",
        f"Havuzdaki {human(len(freq))} kelimenin **{human(len(edges))}**'inde "
        f"en az bir akraba var ({100.0 * len(edges) / max(len(freq), 1):.1f}%).",
        f"Toplam bağ: {human(total_links)} · kelime başına ortalama "
        f"{avg:.1f} akraba (en fazla {MAX_PER_WORD} saklanır).",
        "",
        "## Yöntem",
        "",
        "Kaikki'nin `derived` (bu kelimeden türeyenler) ve `related` (aynı",
        "kökten akrabalar) alanları birleştirilip yönsüz bir komşuluk",
        "grafiği kuruldu. **Bağlantılı bileşen kullanılmadı**: zincirleme",
        "birleştirme yapılırsa `faire` gibi üretken bir kök yüzlerce kelimeyi",
        "tek aileye toplar ve bilgi anlamını yitirir. Her kelime yalnızca",
        "doğrudan komşularını taşır.",
        "",
        "## En kalabalık aileler",
        "",
        "| Kelime | Akraba |",
        "|---|---|",
    ]
    for word, kin in biggest:
        sample = ", ".join(sorted(kin, key=lambda w: freq[w])[:6])
        report.append(f"| {word} | {len(kin)} — {sample}… |")
    (REPORTS / "stage8_families.md").write_text("\n".join(report),
                                                encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage8_families.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
