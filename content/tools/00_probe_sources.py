"""Kaynak adreslerinin gercekten calistigini dogrular.

Bos yere 3 GB indirmeden once her adresin var oldugunu, boyutunu ve
icerik turunu olcer. Calismayan adresler icin yedek adaylari dener.

Kullanim:  python content/tools/00_probe_sources.py
Cikti:     content/reports/source_probe.txt
"""

from __future__ import annotations

import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REPORTS = ROOT / "content" / "reports"

UA = "Mozilla/5.0 (compatible; FrenchApp-pipeline/0.1)"

# Her kaynak icin sirayla denenecek aday adresler.
# Ilk calisan kullanilir. Bu tablo 01_fetch.py tarafindan da okunur.
CANDIDATES: dict[str, list[str]] = {
    "lexique": [
        "http://www.lexique.org/databases/Lexique383/Lexique383.tsv",
        "https://raw.githubusercontent.com/chrplr/openlexicon/master/datasets-info/Lexique383/Lexique383.tsv",
        "http://www.lexique.org/databases/Lexique383/Lexique383.zip",
    ],
    "freq_fr": [
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/fr/fr_50k.txt",
    ],
    "freq_tr": [
        "https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/tr/tr_50k.txt",
    ],
    "tatoeba_sentences": [
        "https://downloads.tatoeba.org/exports/sentences.tar.bz2",
    ],
    "tatoeba_links": [
        "https://downloads.tatoeba.org/exports/links.tar.bz2",
    ],
    "tatoeba_audio": [
        "https://downloads.tatoeba.org/exports/sentences_with_audio.tar.bz2",
    ],
    "kaikki_fr": [
        "https://kaikki.org/dictionary/French/kaikki.org-dictionary-French.jsonl",
        "https://kaikki.org/dictionary/downloads/fr/fr-extract.jsonl.gz",
    ],
    "dbnary_fra": [
        "http://kaiko.getalp.org/static/ontolex/latest/fr_dbnary_ontolex.ttl.bz2",
        "https://kaiko.getalp.org/static/ontolex/latest/fr_dbnary_ontolex.ttl.bz2",
    ],
    "dbnary_tur": [
        "http://kaiko.getalp.org/static/ontolex/latest/tr_dbnary_ontolex.ttl.bz2",
    ],
    "dbnary_eng": [
        "http://kaiko.getalp.org/static/ontolex/latest/en_dbnary_ontolex.ttl.bz2",
    ],
    "verbiste": [
        "https://perso.b2b2c.ca/~sarrazip/dev/verbiste-0.1.48.tar.gz",
        "http://sarrazip.com/dev/verbiste-0.1.48.tar.gz",
    ],
    "flelex": [
        "https://cental.uclouvain.be/cefrlex/flelex/download/",
    ],
}


def probe(url: str, timeout: int = 30) -> tuple[bool, str]:
    """Adresi indirmeden yoklar. Ilk baytini isteyerek boyutu ve turu okur."""
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Range": "bytes=0-0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            status = resp.status
            ctype = resp.headers.get("Content-Type", "?")
            crange = resp.headers.get("Content-Range")
            clen = resp.headers.get("Content-Length", "?")
            if crange and "/" in crange:
                total = crange.rsplit("/", 1)[1]
                size = _human(total)
            else:
                size = f"{_human(clen)} (aralik desteklenmiyor)"
            return True, f"HTTP {status}  {size}  {ctype}"
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code} {e.reason}"
    except Exception as e:  # noqa: BLE001 - ag hatalarinin hepsi ayni sekilde raporlanir
        return False, f"{type(e).__name__}: {e}"


def _human(n: str | int) -> str:
    try:
        v = float(n)
    except (TypeError, ValueError):
        return "? bayt"
    for unit in ("B", "KB", "MB", "GB"):
        if v < 1024 or unit == "GB":
            return f"{v:.1f} {unit}"
        v /= 1024
    return f"{v:.1f} GB"


def main() -> int:
    REPORTS.mkdir(parents=True, exist_ok=True)
    lines: list[str] = []
    resolved: dict[str, str] = {}
    failed: list[str] = []

    for name, urls in CANDIDATES.items():
        lines.append(f"\n[{name}]")
        ok_url = None
        for url in urls:
            ok, detail = probe(url)
            mark = "OK  " if ok else "FAIL"
            lines.append(f"  {mark} {detail}")
            lines.append(f"       {url}")
            if ok and ok_url is None:
                ok_url = url
                break
        if ok_url:
            resolved[name] = ok_url
        else:
            failed.append(name)

    lines.append("\n" + "=" * 60)
    lines.append(f"cozulen : {len(resolved)}/{len(CANDIDATES)}")
    if failed:
        lines.append(f"basarisiz: {', '.join(failed)}")

    text = "\n".join(lines)
    print(text)
    (REPORTS / "source_probe.txt").write_text(text, encoding="utf-8")

    # 01_fetch.py bu dosyayi okur
    import json

    (REPORTS / "resolved_sources.json").write_text(
        json.dumps(resolved, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
