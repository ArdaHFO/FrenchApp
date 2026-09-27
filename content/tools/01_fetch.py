"""Kaynak veri kumelerini indirir.

Adresler 00_probe_sources.py ile dogrulandi (2026-08-09).
Sadece standart kutuphane kullanir, pip kurulumu gerekmez.

Ozellikler:
  - Yarim kalan indirmeyi kaldigi yerden surdurur (HTTP Range)
  - Once .part dosyasina yazar, bitince adini degistirir (yarim dosya kalmaz)
  - Zaten tam inmis dosyayi atlar
  - Ilerlemeyi content/reports/fetch.log dosyasina yazar

Kullanim:  python content/tools/01_fetch.py [ad ...]
           Ad verilmezse hepsi indirilir.
"""

from __future__ import annotations

import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Ham veri ve ara dosyalar proje klasorunun DISINDA durur.
# Sebep: proje OneDrive icinde ve 1.2 GB ham veriyi buluta senkronlamak
# hem yavas hem gereksiz. Sadece kucuk raporlar ve son urun projede kalir.
# FRENCHAPP_DATA ortam degiskeni ile bu konum degistirilebilir.
DATA_ROOT = Path(
    os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data")
)
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"

REPORTS = ROOT / "content" / "reports"
LOG = REPORTS / "fetch.log"

UA = "Mozilla/5.0 (compatible; FrenchApp-pipeline/0.1)"
CHUNK = 1 << 20  # 1 MB

# ad -> (adres, hedef dosya, yaklasik boyut MB)
SOURCE_TABLE: dict[str, tuple[str, str, int]] = {
    "lexique": (
        "http://www.lexique.org/databases/Lexique383/Lexique383.tsv",
        "lexique/Lexique383.tsv",
        25,
    ),
    "flelex": (
        "https://cental.uclouvain.be/cefrlex/static/resources/fr/FleLex_TT.csv",
        "flelex/FleLex_TT.csv",
        3,
    ),
    "freq_fr": (
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/fr/fr_50k.txt",
        "freq/fr_50k.txt",
        1,
    ),
    "freq_tr": (
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/tr/tr_50k.txt",
        "freq/tr_50k.txt",
        1,
    ),
    "tatoeba_sentences": (
        "https://downloads.tatoeba.org/exports/sentences.tar.bz2",
        "tatoeba/sentences.tar.bz2",
        208,
    ),
    "tatoeba_detailed": (
        "https://downloads.tatoeba.org/exports/sentences_detailed.tar.bz2",
        "tatoeba/sentences_detailed.tar.bz2",
        302,
    ),
    "tatoeba_users_sentences": (
        "https://downloads.tatoeba.org/exports/users_sentences.csv",
        "tatoeba/users_sentences.csv",
        99,
    ),
    "tatoeba_fra_detailed": (
        "https://downloads.tatoeba.org/exports/per_language/fra/fra_sentences_detailed.tsv.bz2",
        "tatoeba/fra_sentences_detailed.tsv.bz2",
        15,
    ),
    "tatoeba_eng_detailed": (
        "https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences_detailed.tsv.bz2",
        "tatoeba/eng_sentences_detailed.tsv.bz2",
        35,
    ),
    "tatoeba_tur_detailed": (
        "https://downloads.tatoeba.org/exports/per_language/tur/tur_sentences_detailed.tsv.bz2",
        "tatoeba/tur_sentences_detailed.tsv.bz2",
        14,
    ),
    "tatoeba_fra_eng_links": (
        "https://downloads.tatoeba.org/exports/per_language/fra/fra-eng_links.tsv.bz2",
        "tatoeba/fra-eng_links.tsv.bz2",
        3,
    ),
    "tatoeba_fra_tur_links": (
        "https://downloads.tatoeba.org/exports/per_language/fra/fra-tur_links.tsv.bz2",
        "tatoeba/fra-tur_links.tsv.bz2",
        1,
    ),
    "tatoeba_eng_tur_links": (
        "https://downloads.tatoeba.org/exports/per_language/eng/eng-tur_links.tsv.bz2",
        "tatoeba/eng-tur_links.tsv.bz2",
        5,
    ),
    "tatoeba_links": (
        "https://downloads.tatoeba.org/exports/links.tar.bz2",
        "tatoeba/links.tar.bz2",
        142,
    ),
    "tatoeba_audio": (
        "https://downloads.tatoeba.org/exports/sentences_with_audio.tar.bz2",
        "tatoeba/sentences_with_audio.tar.bz2",
        6,
    ),
    "kaikki_fr": (
        "https://kaikki.org/dictionary/French/kaikki.org-dictionary-French.jsonl",
        "kaikki/kaikki-French.jsonl",
        547,
    ),
    "dbnary_fra": (
        "http://kaiko.getalp.org/static/ontolex/latest/fr_dbnary_ontolex.ttl.bz2",
        "dbnary/fr_dbnary_ontolex.ttl.bz2",
        93,
    ),
    "dbnary_tur": (
        "http://kaiko.getalp.org/static/ontolex/latest/tr_dbnary_ontolex.ttl.bz2",
        "dbnary/tr_dbnary_ontolex.ttl.bz2",
        14,
    ),
    "dbnary_eng": (
        "http://kaiko.getalp.org/static/ontolex/latest/en_dbnary_ontolex.ttl.bz2",
        "dbnary/en_dbnary_ontolex.ttl.bz2",
        197,
    ),
}

# Verbiste bilerek listede yok. Fiil cekimleri kaikki.org verisindeki
# "forms" alanindan uretilecek: ayni CC BY-SA lisansi, GPL sorunu yok,
# ekstra indirme yok. Gerekce DATA_PIPELINE.md bolum 1.2'de.


def log(msg: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(line, flush=True)
    REPORTS.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def human(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def remote_size(url: str) -> int | None:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": "bytes=0-0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            cr = r.headers.get("Content-Range")
            if cr and "/" in cr:
                total = cr.rsplit("/", 1)[1]
                return int(total) if total.isdigit() else None
    except Exception:  # noqa: BLE001
        return None
    return None


def download(name: str, url: str, dest: Path) -> bool:
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    total = remote_size(url)

    if dest.exists():
        if total is None or dest.stat().st_size == total:
            log(f"[{name}] zaten var, atlaniyor ({human(dest.stat().st_size)})")
            return True
        log(f"[{name}] boyut uyusmuyor, yeniden indiriliyor")
        dest.unlink()

    have = part.stat().st_size if part.exists() else 0
    headers = {"User-Agent": UA}
    if have and total:
        headers["Range"] = f"bytes={have}-"
        log(f"[{name}] {human(have)} yerden devam ediliyor")

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            # Sunucu Range'i yok saydiysa bastan yaz
            mode = "ab" if resp.status == 206 and have else "wb"
            if mode == "wb":
                have = 0
            started = time.time()
            last_report = 0.0
            with part.open(mode) as f:
                while True:
                    chunk = resp.read(CHUNK)
                    if not chunk:
                        break
                    f.write(chunk)
                    have += len(chunk)
                    now = time.time()
                    if now - last_report >= 10:
                        last_report = now
                        speed = have / max(now - started, 0.01)
                        pct = f" ({have / total * 100:.0f}%)" if total else ""
                        log(f"[{name}] {human(have)}{pct}  {human(speed)}/s")
    except urllib.error.HTTPError as e:
        log(f"[{name}] HATA HTTP {e.code} {e.reason}")
        return False
    except Exception as e:  # noqa: BLE001
        log(f"[{name}] HATA {type(e).__name__}: {e}")
        return False

    if total and part.stat().st_size != total:
        log(f"[{name}] EKSIK: {human(part.stat().st_size)} / {human(total)}")
        return False

    part.replace(dest)
    log(f"[{name}] TAMAM {human(dest.stat().st_size)}")
    return True


def main(argv: list[str]) -> int:
    wanted = argv[1:] or list(SOURCE_TABLE)
    unknown = [w for w in wanted if w not in SOURCE_TABLE]
    if unknown:
        print(f"bilinmeyen kaynak: {', '.join(unknown)}")
        print(f"gecerli adlar: {', '.join(SOURCE_TABLE)}")
        return 2

    total_mb = sum(SOURCE_TABLE[w][2] for w in wanted)
    log(f"=== FETCH BASLIYOR: {len(wanted)} kaynak, yaklasik {total_mb} MB ===")

    failed: list[str] = []
    for name in wanted:
        url, rel, _ = SOURCE_TABLE[name]
        if not download(name, url, SOURCES / rel):
            failed.append(name)

    if failed:
        log(f"=== FETCH BITTI, BASARISIZ: {', '.join(failed)} ===")
        return 1
    log("=== FETCH BITTI, HEPSI TAMAM ===")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
