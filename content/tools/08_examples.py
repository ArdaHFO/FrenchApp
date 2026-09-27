"""Asama 5 - ornek cumleler.

Girdi : stages/s4_turkish.jsonl, stages/s2_levels.jsonl, tatoeba, lexique
Cikti : stages/s5_examples.jsonl

Bu asamanin en degerli parcasi seviye filtresidir: bir cumlenin secilebilmesi
icin icindeki BUTUN kelimelerin hedef kelimenin seviyesinde veya altinda
olmasi gerekir. A1 kelimesini C1 kelimeleriyle dolu bir cumlede gostermek
ogretmez, yildirir.

Turkce ceviri icin iki adimli baglanti kullanilir (olcum: dogrudan 12.245,
iki adimli 259.378 cumle, 21 kat kazanc). Dogrudan baglanti varsa her zaman
tercih edilir; iki adimli cumleler daha dusuk guven alir.
"""

from __future__ import annotations

import csv
import bz2
import io
import json
import os
import re
import sys
import tarfile
import time
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
SOURCES = DATA_ROOT / "sources"
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()
LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"]
LEVEL_INDEX = {lv: i for i, lv in enumerate(LEVELS)}

MIN_TOKENS = 4
MAX_TOKENS = 12
KEEP_PER_WORD = 2

# Fransizca elizyon onekleri: l'eau -> eau
ELISION = re.compile(r"^(l|d|j|qu|n|s|c|m|t)['’]", re.IGNORECASE)
TOKEN_RE = re.compile(r"[a-zA-ZàâäçéèêëîïôöùûüÿœæÀÂÄÇÉÈÊËÎÏÔÖÙÛÜŸŒÆ'’-]+")


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def tar_rows(path: Path):
    with tarfile.open(path, "r:bz2") as tf:
        member = next(m for m in tf if m.isfile())
        stream = tf.extractfile(member)
        assert stream is not None
        yield from csv.reader(
            io.TextIOWrapper(stream, encoding="utf-8", errors="replace"),
            delimiter="\t",
            quoting=csv.QUOTE_NONE,
        )


def bz2_rows(path: Path):
    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as stream:
        yield from csv.reader(stream, delimiter="\t", quoting=csv.QUOTE_NONE)


def tokenize(text: str) -> list[str]:
    out: list[str] = []
    for raw in TOKEN_RE.findall(text):
        w = ELISION.sub("", raw).lower().strip("'’-")
        if w:
            out.append(w)
    return out


def main() -> int:
    words_path = STAGES / "s4_turkish.jsonl"
    if not words_path.exists():
        print("once: python content/tools/07_turkish.py")
        return 2

    # ---------------------------------------------- hedef kelimeler + seviye
    log("hedef kelimeler yukleniyor")
    targets: dict[str, dict] = {}
    for line in words_path.open(encoding="utf-8"):
        e = json.loads(line)
        targets[e["lemma"]] = e
    log(f"hedef: {human(len(targets))} kelime")

    log("tum lemmalarin seviyeleri yukleniyor (cumle zorlugu icin)")
    lemma_level: dict[str, int] = {}
    for line in (STAGES / "s2_levels.jsonl").open(encoding="utf-8"):
        e = json.loads(line)
        lemma_level[e["lemma"]] = LEVEL_INDEX[e["level"]]
    log(f"seviye bilinen lemma: {human(len(lemma_level))}")

    # ------------------------------------------------ yuzey bicim -> lemma
    log("lexique yuzey bicim eslemesi")
    surface_to_lemma: dict[str, str] = {}
    with (SOURCES / "lexique" / "Lexique383.tsv").open(
        encoding="utf-8", errors="replace", newline=""
    ) as f:
        for row in csv.DictReader(f, delimiter="\t"):
            o = (row.get("ortho") or "").strip().lower()
            l = (row.get("lemme") or "").strip()
            if o and l and o not in surface_to_lemma:
                surface_to_lemma[o] = l
    log(f"yuzey bicim: {human(len(surface_to_lemma))}")

    # ------------------------------------------------------ tatoeba cumleler
    log("tatoeba cumleleri okunuyor")
    fra: dict[int, tuple[str, str]] = {}
    eng: dict[int, tuple[str, str]] = {}
    tur: dict[int, tuple[str, str]] = {}
    detailed_files = {
        "fra": (SOURCES / "tatoeba" / "fra_sentences_detailed.tsv.bz2", fra),
        "eng": (SOURCES / "tatoeba" / "eng_sentences_detailed.tsv.bz2", eng),
        "tur": (SOURCES / "tatoeba" / "tur_sentences_detailed.tsv.bz2", tur),
    }
    missing = [path for path, _ in detailed_files.values() if not path.exists()]
    if missing:
        print("once: python content/tools/01_fetch.py "
              "tatoeba_fra_detailed tatoeba_eng_detailed tatoeba_tur_detailed "
              "tatoeba_fra_eng_links tatoeba_fra_tur_links tatoeba_eng_tur_links")
        return 2
    for lang, (path, target) in detailed_files.items():
        for row in bz2_rows(path):
            if len(row) < 4:
                continue
            author = row[3].strip()
            if row[1] == lang and author and author != r"\N":
                target[int(row[0])] = (row[2], author)
    log(f"fra {human(len(fra))} | eng {human(len(eng))} | tur {human(len(tur))}")

    log("baglar okunuyor")
    fra_eng: dict[int, int] = {}
    fra_tur: dict[int, int] = {}
    eng_tur: dict[int, int] = {}
    link_specs = (
        (SOURCES / "tatoeba" / "fra-eng_links.tsv.bz2", fra, eng, fra_eng),
        (SOURCES / "tatoeba" / "fra-tur_links.tsv.bz2", fra, tur, fra_tur),
        (SOURCES / "tatoeba" / "eng-tur_links.tsv.bz2", eng, tur, eng_tur),
    )
    for path, left, right, target in link_specs:
        for row in bz2_rows(path):
            if len(row) < 2:
                continue
            a, b = int(row[0]), int(row[1])
            if a in left and b in right and a not in target:
                target[a] = b
    log(
        f"fra->eng {human(len(fra_eng))} | fra->tur {human(len(fra_tur))} | "
        f"eng->tur {human(len(eng_tur))}"
    )

    # ---------------------------------------------------------- deyim havuzu
    # Deyimler cok kelimeli oldugu icin lemma indeksine dusmuyor; ayri bir
    # alt dizi taramasi gerekiyor. Her deyimi ilk kelimesine gore
    # gruplayip sadece o kelimeyi iceren cumlelerde ariyoruz.
    idiom_phrases: set[str] = set()
    idiom_path = STAGES / "s6_idioms_tr.jsonl"
    if idiom_path.exists():
        for line in idiom_path.open(encoding="utf-8"):
            idiom_phrases.add(json.loads(line)["lemma"])
    ov_path = ROOT / "content" / "overrides" / "idioms.json"
    if ov_path.exists():
        ov = json.loads(ov_path.read_text(encoding="utf-8"))
        idiom_phrases.update((ov.get("ekle") or {}).keys())
        idiom_phrases.difference_update(ov.get("cikar", []))
    idiom_by_head: dict[str, list[str]] = defaultdict(list)
    for phrase in idiom_phrases:
        head = tokenize(phrase)
        if head:
            idiom_by_head[head[0]].append(phrase)
    idiom_candidates: dict[str, list[dict]] = defaultdict(list)
    log(f"deyim taramasi: {human(len(idiom_phrases))} kalip")

    # ------------------------------------------------- kullanilabilir cumleler
    log("cumleler puanlaniyor")
    # lemma -> aday cumle listesi
    candidates: dict[str, list[dict]] = defaultdict(list)
    usable = 0
    with_tr_direct = 0
    with_tr_two_hop = 0

    for fid, (text, fr_author) in fra.items():
        eid = fra_eng.get(fid)
        if eid is None:
            continue  # Ingilizce cevirisi olmayan cumle karta konmaz

        tid = fra_tur.get(fid)
        tr_direct = tid is not None
        if tid is None:
            tid = eng_tur.get(eid)
        if tid is not None:
            if tr_direct:
                with_tr_direct += 1
            else:
                with_tr_two_hop += 1

        tokens = tokenize(text)
        n = len(tokens)
        if n < MIN_TOKENS or n > MAX_TOKENS:
            continue

        lemmas = [surface_to_lemma.get(t, t) for t in tokens]
        levels = [lemma_level.get(l) for l in lemmas]
        known = [x for x in levels if x is not None]
        if not known:
            continue
        max_level = max(known)

        present = {l for l in lemmas if l in targets}

        # Deyim taramasi kelime esleşmesinden bagimsiz calisir: cumlede
        # deyimin ilk kelimesi geciyorsa tam kalibi metinde ariyoruz.
        lowered = text.lower()
        hit_idioms: list[str] = []
        token_set = set(tokens)
        for tok in token_set:
            for phrase in idiom_by_head.get(tok, ()):  # nadiren bos degil
                if phrase.lower() in lowered:
                    hit_idioms.append(phrase)

        if not present and not hit_idioms:
            continue

        usable += 1
        record = {
            "fid": fid,
            "fr": text,
            "en": eng[eid][0],
            "tr": tur[tid][0] if tid is not None else None,
            "fr_id": fid,
            "fr_author": fr_author,
            "en_id": eid,
            "en_author": eng[eid][1],
            "tr_id": tid,
            "tr_author": tur[tid][1] if tid is not None else None,
            "tr_direct": tr_direct,
            "max_level": max_level,
            "n": n,
        }
        for lemma in present:
            if len(candidates[lemma]) < 400:
                candidates[lemma].append(record)
        for phrase in hit_idioms:
            if len(idiom_candidates[phrase]) < 60:
                idiom_candidates[phrase].append(record)

    log(
        f"kullanilabilir cumle {human(usable)} | "
        f"turkce dogrudan {human(with_tr_direct)} | iki adimli {human(with_tr_two_hop)}"
    )

    # ------------------------------------------------------------- sec ve yaz
    log("kelime basina en iyi cumleler seciliyor")
    out_path = STAGES / "s5_examples.jsonl"
    stat = Counter()
    with out_path.open("w", encoding="utf-8") as fout:
        for lemma, entry in sorted(targets.items(), key=lambda kv: kv[1]["freq_rank"]):
            target_level = LEVEL_INDEX[entry["level"]]
            pool = candidates.get(lemma) or []

            chosen: list[dict] = []
            # Kademeli gevseme: once tam seviye uyumu, sonra +1, +2,
            # sonra turkcesiz kabul
            for relax in (0, 1, 2):
                if len(chosen) >= KEEP_PER_WORD:
                    break
                for rec in pool:
                    if rec in chosen:
                        continue
                    if rec["max_level"] > target_level + relax:
                        continue
                    if rec["tr"] is None:
                        continue
                    chosen.append(rec)
                    if len(chosen) >= KEEP_PER_WORD:
                        break
            if len(chosen) < KEEP_PER_WORD:
                for rec in pool:
                    if rec in chosen:
                        continue
                    if rec["max_level"] > target_level + 2:
                        continue
                    chosen.append(rec)
                    if len(chosen) >= KEEP_PER_WORD:
                        break

            if not chosen:
                stat["cumlesiz"] += 1
                entry["examples"] = []
            else:
                # Puanla: dogrudan turkce > 7-10 kelime > tam seviye uyumu
                def score(r: dict) -> tuple:
                    return (
                        1 if r["tr_direct"] else 0,
                        1 if r["tr"] else 0,
                        1 if 7 <= r["n"] <= 10 else 0,
                        -abs(r["max_level"] - target_level),
                    )

                chosen.sort(key=score, reverse=True)
                entry["examples"] = [
                    {
                        "fr": r["fr"],
                        "en": r["en"],
                        "tr": r["tr"],
                        "tr_direct": r["tr_direct"],
                        "max_level": LEVELS[r["max_level"]],
                        "fr_id": r["fr_id"],
                        "fr_author": r["fr_author"],
                        "en_id": r["en_id"],
                        "en_author": r["en_author"],
                        "tr_id": r["tr_id"],
                        "tr_author": r["tr_author"],
                    }
                    for r in chosen[:KEEP_PER_WORD]
                ]
                stat["cumleli"] += 1
                if chosen[0]["tr"]:
                    stat["turkcesi_var"] += 1
                if chosen[0]["tr_direct"]:
                    stat["turkce_dogrudan"] += 1

            fout.write(json.dumps(entry, ensure_ascii=False) + "\n")

    log(f"yazildi: {out_path}")
    log(f"istatistik: {dict(stat)}")

    # ------------------------------------------------------- deyim ornekleri
    idiom_out = STAGES / "s5_idiom_examples.jsonl"
    n_idiom_ex = 0
    with idiom_out.open("w", encoding="utf-8") as fout:
        for phrase in sorted(idiom_phrases):
            pool = idiom_candidates.get(phrase) or []
            if not pool:
                continue
            # Turkcesi olan, orta uzunlukta ve basit cumle tercih edilir.
            pool.sort(key=lambda r: (
                r["tr"] is None,
                abs(r["n"] - 8),
                r["max_level"],
            ))
            fout.write(json.dumps({
                "lemma": phrase,
                "examples": [
                    {
                        "fr": r["fr"],
                        "en": r["en"],
                        "tr": r["tr"],
                        "tr_direct": r["tr_direct"],
                        "max_level": r["max_level"],
                        "fr_id": r["fr_id"],
                        "fr_author": r["fr_author"],
                        "en_id": r["en_id"],
                        "en_author": r["en_author"],
                        "tr_id": r["tr_id"],
                        "tr_author": r["tr_author"],
                    }
                    for r in pool[:KEEP_PER_WORD]
                ],
            }, ensure_ascii=False) + "\n")
            n_idiom_ex += 1
    log(f"deyim ornegi olan kalip: {human(n_idiom_ex)} / {human(len(idiom_phrases))}")

    total = len(targets)
    report = [
        "# Aşama 5 — Örnek Cümleler",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        "## Seviye filtresi",
        "",
        "Bir cümlenin seçilebilmesi için **içindeki bütün kelimelerin** hedef",
        "kelimenin seviyesinde veya altında olması gerekir. Aday bulunamazsa",
        "sırayla +1, +2 seviye gevşetilir, en son Türkçe çeviri şartı düşer.",
        "",
        "## Sonuç",
        "",
        "| Ölçüm | Sayı | Oran |",
        "|---|---|---|",
        f"| Hedef kelime | {human(total)} | |",
        f"| **Örnek cümlesi olan** | **{human(stat['cumleli'])}** | {100.0 * stat['cumleli'] / total:.1f}% |",
        f"| Türkçe çevirisi de olan | {human(stat['turkcesi_var'])} | {100.0 * stat['turkcesi_var'] / total:.1f}% |",
        f"| Türkçesi doğrudan bağlantıdan | {human(stat['turkce_dogrudan'])} | {100.0 * stat['turkce_dogrudan'] / total:.1f}% |",
        f"| Cümlesiz kalan | {human(stat['cumlesiz'])} | {100.0 * stat['cumlesiz'] / total:.1f}% |",
        "",
        f"Kullanılabilir Tatoeba cümlesi: {human(usable)}",
        f"(Türkçesi doğrudan {human(with_tr_direct)}, iki adımlı {human(with_tr_two_hop)})",
    ]
    (REPORTS / "stage5_examples.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage5_examples.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
