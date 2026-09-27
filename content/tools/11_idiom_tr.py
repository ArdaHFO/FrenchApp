"""Asama 6b - deyimlere Turkce karsilik.

Girdi : stages/s6_idioms.jsonl + dbnary fr/tr/en
Cikti : stages/s6_idioms_tr.jsonl

Asama 4'un mantiginin deyimlere uyarlanmis hali. Fark: deyimlerde kelime
turu bilgisi yok, o yuzden tur uyumu kontrolu yapilamiyor. Bunun yerine
guven esigi yukseltildi ve butun deyimler zaten gozden gecirme kuyrugunda.

Birebir ceviri (literal_tr) burada uretilmez. Otomatik uretimin en cok hata
yaptigi alan orasi ve deyimin akilda kalmasini saglayan sey tam da o.
Elle yazilmasi icin bos birakilir.
"""

from __future__ import annotations

import bz2
import json
import os
import re
import sys
import time
import unicodedata
import urllib.parse
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

RE_SRC = re.compile(r"dbnary:isTranslationOf[ \t]+(\S+?)[ \t]*[;.]")
RE_LANG = re.compile(r"dbnary:targetLanguage[ \t]+lexvo:(\w+)")
RE_FORM = re.compile('dbnary:writtenForm[ \t]+"([^"]*)"')
RE_PREFIXED = re.compile(r"^\w+:(.+)$")
RE_FULL = re.compile(r"^<https?://[^>]*/dbnary/\w+/(.+)>$")


def log(m: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {m}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def fold(s: str) -> str:
    s = unicodedata.normalize("NFD", s.strip().lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def entry_lemma(uri: str) -> str | None:
    m = RE_FULL.match(uri) or RE_PREFIXED.match(uri)
    if not m:
        return None
    raw = urllib.parse.unquote(m.group(1))
    lemma = raw.split("__")[0].replace("_", " ").strip()
    return lemma or None


def translations(path: Path):
    cur: dict | None = None
    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "dbnary:Translation" in line:
                cur = {}
                continue
            if cur is None:
                continue
            m = RE_SRC.search(line)
            if m:
                cur["src"] = m.group(1)
            m = RE_LANG.search(line)
            if m:
                cur["lang"] = m.group(1)
            m = RE_FORM.search(line)
            if m:
                cur["form"] = m.group(1)
            if line.rstrip().endswith("."):
                if cur.get("src") and cur.get("lang") and cur.get("form"):
                    yield cur
                cur = None


def norm_en(w: str) -> str:
    w = re.sub(r"^to[ ]+", "", w.strip().lower())
    return re.sub(r"[ ]*\([^)]*\)", "", w).strip()


def en_candidates(gloss: str) -> list[str]:
    out = []
    for piece in re.split(r"[;,]", gloss):
        w = norm_en(piece)
        if w and len(w.split()) <= 4 and not any(c.isdigit() for c in w):
            out.append(w)
    return out


def main() -> int:
    src = STAGES / "s6_idioms.jsonl"
    if not src.exists():
        print("once: python content/tools/09_idioms.py")
        return 2

    log("deyimler yukleniyor")
    idioms: dict[str, dict] = {}
    for line in src.open(encoding="utf-8"):
        d = json.loads(line)
        idioms[d["lemma"]] = d
    log(f"deyim: {human(len(idioms))}")

    # --- fransizca: dogrudan turkce + ingilizce karsiliklar
    log("fransizca dbnary")
    direct: dict[str, list[str]] = defaultdict(list)
    to_en: dict[str, set[str]] = defaultdict(set)
    for rec in translations(SOURCES / "dbnary" / "fr_dbnary_ontolex.ttl.bz2"):
        lemma = entry_lemma(rec["src"])
        if lemma is None or lemma not in idioms:
            continue
        if rec["lang"] == "tur":
            direct[lemma].append(rec["form"].strip().lower())
        elif rec["lang"] == "eng":
            to_en[lemma].add(norm_en(rec["form"]))
    log(f"dogrudan turkce: {human(len(direct))} | ingilizce: {human(len(to_en))}")

    # --- ingilizce pivotlar
    needed: set[str] = set()
    for lemma, d in idioms.items():
        needed.update(to_en.get(lemma, ()))
        for g in d.get("meaning_en") or []:
            needed.update(en_candidates(g))
    needed.discard("")
    log(f"pivot: {human(len(needed))}")

    log("ingilizce dbnary")
    en_tur: dict[str, list[str]] = defaultdict(list)
    for rec in translations(SOURCES / "dbnary" / "en_dbnary_ontolex.ttl.bz2"):
        if rec["lang"] != "tur":
            continue
        lemma = entry_lemma(rec["src"])
        if lemma is None:
            continue
        key = norm_en(lemma)
        if key in needed:
            en_tur[key].append(rec["form"].strip().lower())
    log(f"pivotun karsiligi: {human(len(en_tur))}")

    # --- turkce: geri kontrol
    log("turkce dbnary")
    tur_en: dict[str, set[str]] = defaultdict(set)
    for rec in translations(SOURCES / "dbnary" / "tr_dbnary_ontolex.ttl.bz2"):
        if rec["lang"] != "eng":
            continue
        lemma = entry_lemma(rec["src"])
        if lemma:
            tur_en[lemma.strip().lower()].add(norm_en(rec["form"]))

    # ------------------------------------------------------------- birlestir
    out_path = STAGES / "s6_idioms_tr.jsonl"
    paths: Counter[str] = Counter()
    kept = 0
    samples: list[str] = []

    with out_path.open("w", encoding="utf-8") as fout:
        for lemma, d in idioms.items():
            chosen: str | None = None
            conf = 0.0
            path = "none"

            if direct.get(lemma):
                counts = Counter(direct[lemma])
                chosen = max(counts, key=lambda w: counts[w])
                conf, path = 0.95, "direct"
            else:
                pivots = set(to_en.get(lemma, ()))
                for g in d.get("meaning_en") or []:
                    pivots.update(en_candidates(g))
                score: dict[str, list] = defaultdict(lambda: [0, False])
                for pivot in pivots:
                    cands = en_tur.get(pivot)
                    if not cands or len(cands) > 8:
                        continue
                    for tr in cands:
                        if fold(tr) == fold(lemma):
                            continue
                        score[tr][0] += 1
                        if pivot in tur_en.get(tr, ()):
                            score[tr][1] = True
                if score:
                    verified = {w: s for w, s in score.items() if s[1]}
                    pool = verified or {w: s for w, s in score.items() if s[0] >= 2}
                    if pool:
                        chosen = max(pool, key=lambda w: pool[w][0])
                        conf = 0.75 if verified else 0.55
                        path = "bridge_verified" if verified else "bridge_supported"

            if chosen is None:
                paths["none"] += 1
                continue

            d["meaning_tr"] = chosen
            d["tr_path"] = path
            d["tr_confidence"] = conf
            # Birebir ceviri elle yazilacak, otomatik uretilmiyor
            d["literal_tr"] = None
            fout.write(json.dumps(d, ensure_ascii=False) + "\n")
            paths[path] += 1
            kept += 1
            if len(samples) < 20:
                samples.append(f"| {lemma} | {chosen} | {d['level']} | {path} |")

    log(f"yazildi: {out_path} ({human(kept)} deyim)")
    log(f"yol dagilimi: {dict(paths)}")

    report = [
        "# Aşama 6b — Deyimlere Türkçe Karşılık",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        f"Deyim {human(len(idioms))} · **Karşılığı bulunan {human(kept)}** "
        f"({100.0 * kept / max(len(idioms), 1):.1f}%)",
        "",
        "| Yol | Sayı |",
        "|---|---|",
        *[f"| {k} | {human(v)} |" for k, v in paths.items()],
        "",
        "Birebir çeviri (`literal_tr`) bilerek boş bırakıldı. Otomatik üretimin",
        "en çok hata yaptığı alan orası ve deyimin akılda kalmasını sağlayan şey",
        "tam da o; elle yazılacak.",
        "",
        "## Örnekler",
        "",
        "| Deyim | Türkçe | Seviye | Yol |",
        "|---|---|---|---|",
        *samples,
    ]
    (REPORTS / "stage6b_idiom_tr.md").write_text("\n".join(report), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
