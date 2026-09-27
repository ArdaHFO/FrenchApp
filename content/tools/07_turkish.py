"""Asama 4 - Turkce karsilik. Boru hattinin en riskli asamasi.

Girdi : stages/s3_english.jsonl + dbnary fr/tr/en + freq/tr_50k.txt
Cikti : stages/s4_turkish.jsonl, reports/stage4_turkish.md, reports/missing_tr.csv

DBnary'nin kritik avantaji: ceviriler ANLAM duzeyinde bagli ve kaynak URI
hem lemmayi hem kelime turunu tasiyor (fra:pas__adv__1 ile fra:pas__nom__1
ayri kayitlar). Bu sayede kor kelime eslestirmesi yapmak zorunda degiliz.

Ilk surumde bulunan ve bu surumde giderilen hatalar:

  1. Kelime turu filtresinde "or" yedegi vardi; filtre bos kalinca
     filtrelenmemis listeye dusuyordu, yani filtre fiilen calismiyordu.
     Sonuc: "pas" (zarf) icin isim anlami "adim", "pouvoir" (fiil) icin
     isim anlami "guc" seciliyordu. Yedek kaldirildi, tur uyumu zorunlu.

  2. Geri kontrol 2. yolla ayni veriyi kullaniyordu, dolayisiyla asla
     calismiyordu (bridge_verified sayisi sifirdi). Artik bagimsiz bir
     yon kullaniliyor: turkce kelimenin INGILIZCE cevirileri arasinda
     kopru pivotu var mi. Ucgen boylece gercekten kapaniyor.

  3. Yanlis dost tuzagi: fransizca "dans" ile turkce "dans" ayni yazilir,
     farkli anlamdadir. Aksan sadelestirilmis hali ayni olan adaylar
     reddediliyor.

  4. Cok anlamli pivotlar tamamen atlaniyordu (len > 6). Bu tam da en sik
     kelimeleri eliyordu; ingilizce "be" cok karsiliga sahip oldugu icin
     "etre" karsiliksiz kaliyordu. Artik atilmiyor, agirligi dusuruluyor.

  5. Secim sadece siklikla yapiliyordu. Artik once kac farkli yolun ayni
     karsiligi isaret ettigine, sonra siklige bakiliyor.

  6. (Ikinci tur) 4. maddedeki agirlik dusurmesi eklendikten sonra mutlak
     esik (score >= 1.5) fiilen ulasilamaz hale gelmisti: cok anlamli bir
     pivot 0.3 civari puan uretiyor, 1.5'e ancak bes ayri pivot ayni
     karsiligi isaret ederse ulasiliyordu. Sonuc: havuzun %71'i (23.482
     lemma) karsiliksiz kaldi, aralarinda "etre" de vardi. Fransizcanin
     en sik fiili uygulamada hic yoktu.

     Neden "etre" hicbir yoldan gecemedi:
       - fransizca dbnary'de fra:etre__* ceviri kaydi YOK
       - turkce dbnary'de fransizca cevirisi "etre" olan kayit YOK
       - ingilizce dbnary'de eng:be__Verb__1 -> olmak/bulunmak/var VAR
     yani tek yol kopruydu ve esik onu kesiyordu.

     Artik mutlak esik yok. Kabul olcusu kanit sayisi: ayni karsiligi kac
     ayri pivot ve kac ayri kayit isaret ediyor. Tek kayitli adaylar da
     alinir ama guveni dusuk isaretlenir, uygulamada "gozden gecirilmedi"
     rozetiyle gorunur ve kullanici bayrak dugmesiyle bildirir.
"""

from __future__ import annotations

import bz2
import csv
import json
import math
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

RE_TRANSLATION_OF = re.compile(r"dbnary:isTranslationOf[ \t]+(\S+?)[ \t]*[;.]")
RE_TARGET_LANG = re.compile(r"dbnary:targetLanguage[ \t]+lexvo:(\w+)")
RE_WRITTEN_FORM = re.compile('dbnary:writtenForm[ \t]+"([^"]*)"')
RE_PREFIXED = re.compile(r"^\w+:(.+)$")
RE_FULL_URI = re.compile(r"^<https?://[^>]*/dbnary/\w+/(.+)>$")

# DBnary URI'sindeki kelime turu jetonu -> Lexique turu.
# Fransizca, ingilizce ve turkce wiktionary farkli jetonlar kullanir.
POS_TOKENS = {
    # fransizca
    "nom": "NOM", "verb": "VER", "adj": "ADJ", "adv": "ADV",
    "prep": "PRE", "conj": "CON", "pron": "PRO", "num": "ADJ:num",
    # ingilizce
    "noun": "NOM", "verbe": "VER", "adjective": "ADJ", "adverb": "ADV",
    "preposition": "PRE", "conjunction": "CON", "pronoun": "PRO",
    "numeral": "ADJ:num",
    # turkce
    "isim": "NOM", "ad": "NOM", "fiil": "VER", "eylem": "VER",
    "sıfat": "ADJ", "sifat": "ADJ", "önad": "ADJ", "onad": "ADJ",
    "zarf": "ADV", "belirteç": "ADV", "belirtec": "ADV",
    "edat": "PRE", "ilgeç": "PRE", "ilgec": "PRE",
    "bağlaç": "CON", "baglac": "CON", "zamir": "PRO", "adıl": "PRO",
}

# Bu turler kelime karti olmaz, dilbilgisi dersine aittir.
FUNCTION_POS = {"PRE", "CON", "PRO", "PRO:per", "PRO:ind", "PRO:dem",
                "PRO:rel", "PRO:pos"}


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


def fold(s: str) -> str:
    """Aksanlari sadelestirip kucult. Yanlis dost kontrolu icin."""
    s = unicodedata.normalize("NFD", s.strip().lower())
    return "".join(c for c in s if unicodedata.category(c) != "Mn")


def parse_entry_uri(uri: str) -> tuple[str | None, str | None, str | None]:
    """fra:pas__adv__1 -> ("pas", "ADV", "adv")"""
    m = RE_FULL_URI.match(uri)
    raw = m.group(1) if m else None
    if raw is None:
        m = RE_PREFIXED.match(uri)
        if not m:
            return None, None, None
        raw = m.group(1)
    raw = urllib.parse.unquote(raw)
    parts = raw.split("__")
    if not parts or not parts[0]:
        return None, None, None
    lemma = parts[0].replace("_", " ").strip()
    token = parts[1].strip("-").lower() if len(parts) >= 2 else None
    return (lemma or None), (POS_TOKENS.get(token) if token else None), token


def pos_ok(a: str | None, b: str | None) -> bool:
    """Bilgi yoksa engelleme, varsa uyum sart."""
    if a is None or b is None:
        return True
    return a == b


def iter_translations(path: Path):
    cur: dict | None = None
    with bz2.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            if "dbnary:Translation" in line:
                cur = {}
                continue
            if cur is None:
                continue
            m = RE_TRANSLATION_OF.search(line)
            if m:
                cur["src"] = m.group(1)
            m = RE_TARGET_LANG.search(line)
            if m:
                cur["lang"] = m.group(1)
            m = RE_WRITTEN_FORM.search(line)
            if m:
                cur["form"] = m.group(1)
            if line.rstrip().endswith("."):
                if cur.get("src") and cur.get("lang") and cur.get("form"):
                    yield cur
                cur = None


def norm_en(word: str) -> str:
    w = word.strip().lower()
    w = re.sub(r"^to[ ]+", "", w)
    w = re.sub(r"[ ]*\([^)]*\)", "", w)
    return w.strip()


RE_WIKI_LINK = re.compile(r"\[\[([^\]|]*\|)?([^\]]*)\]\]")


def norm_tr(word: str) -> str:
    """Wiktionary bag markupu sizabiliyor: "[[ne]] ... [[ne]]" ya da
    "[[geri]] [[koymak]]" gibi. Koseli parantezler temizlenir."""
    w = RE_WIKI_LINK.sub(lambda m: m.group(2), word)
    w = w.replace("[", "").replace("]", "")
    return " ".join(w.split()).strip().lower()


def en_from_gloss(gloss: str) -> list[str]:
    out: list[str] = []
    for piece in re.split(r"[;,]", gloss):
        w = norm_en(piece)
        if not w or len(w.split()) > 3 or any(c.isdigit() for c in w):
            continue
        out.append(w)
    return out


def main() -> int:
    pool_path = STAGES / "s3_english.jsonl"
    if not pool_path.exists():
        print("once: python content/tools/06_english.py")
        return 2

    log("havuz yukleniyor")
    pool: dict[str, dict] = {}
    for line in pool_path.open(encoding="utf-8"):
        e = json.loads(line)
        pool[e["lemma"]] = e
    log(f"havuz: {human(len(pool))} lemma")

    # ---------------------------------------------- 1. gecis: fransizca
    log("fransizca dbnary (93 MB)")
    direct_tur: dict[str, list[tuple[str, str | None]]] = defaultdict(list)
    fr_to_en: dict[str, set[tuple[str, str | None]]] = defaultdict(set)
    fr_pos_tokens: Counter[str] = Counter()

    for rec in iter_translations(SOURCES / "dbnary" / "fr_dbnary_ontolex.ttl.bz2"):
        lemma, pos, token = parse_entry_uri(rec["src"])
        if lemma is None or lemma not in pool:
            continue
        if token:
            fr_pos_tokens[token] += 1
        if rec["lang"] == "tur":
            direct_tur[lemma].append((norm_tr(rec["form"]), pos))
        elif rec["lang"] == "eng":
            fr_to_en[lemma].add((norm_en(rec["form"]), pos))

    log(f"fransizca: dogrudan {human(len(direct_tur))} lemma | "
        f"ingilizce {human(len(fr_to_en))} lemma")

    # ------------------------------------------------ 2. gecis: turkce
    log("turkce dbnary (14 MB)")
    reverse_tur: dict[str, list[tuple[str, str | None]]] = defaultdict(list)
    tur_to_eng: dict[str, set[str]] = defaultdict(set)
    # Turkce kelimenin kendi turu. Kopru adayini elemek icin.
    # Ornek: "pouvoir" (fiil) icin ingilizce "may" pivotundan "mayis" (isim)
    # geliyordu; bu dizin onu eler.
    tur_pos: dict[str, set[str]] = defaultdict(set)
    tr_pos_tokens: Counter[str] = Counter()

    for rec in iter_translations(SOURCES / "dbnary" / "tr_dbnary_ontolex.ttl.bz2"):
        tr_lemma, tr_pos, token = parse_entry_uri(rec["src"])
        if tr_lemma is None:
            continue
        if token:
            tr_pos_tokens[token] += 1
        key = norm_tr(tr_lemma)
        if tr_pos:
            tur_pos[key].add(tr_pos)
        if rec["lang"] == "fra":
            fr_word = rec["form"].strip()
            if fr_word in pool:
                reverse_tur[fr_word].append((key, tr_pos))
        elif rec["lang"] == "eng":
            # Bagimsiz geri kontrol yonu
            tur_to_eng[key].add(norm_en(rec["form"]))

    log(f"turkce: ters {human(len(reverse_tur))} lemma | "
        f"geri kontrol {human(len(tur_to_eng))} turkce kelime")

    # ---------------------------------------- kopru icin gereken ingilizce
    needed_en: set[str] = set()
    for lemma, entry in pool.items():
        needed_en.update(w for w, _ in fr_to_en.get(lemma, ()))
        for gloss in entry.get("meaning_en") or []:
            needed_en.update(en_from_gloss(gloss))
    needed_en.discard("")
    log(f"kopru pivotu: {human(len(needed_en))} ingilizce kelime")

    # ------------------------------------------------ 3. gecis: ingilizce
    log("ingilizce dbnary (197 MB)")
    en_to_tur: dict[str, list[tuple[str, str | None]]] = defaultdict(list)
    for rec in iter_translations(SOURCES / "dbnary" / "en_dbnary_ontolex.ttl.bz2"):
        if rec["lang"] != "tur":
            continue
        en_lemma, en_pos, _ = parse_entry_uri(rec["src"])
        if en_lemma is None:
            continue
        key = norm_en(en_lemma)
        if key in needed_en:
            en_to_tur[key].append((norm_tr(rec["form"]), en_pos))
    log(f"ingilizce: {human(len(en_to_tur))} pivotun turkce karsiligi var")

    # ------------------------------------------------------ turkce siklik
    tr_freq: dict[str, int] = {}
    p = SOURCES / "freq" / "tr_50k.txt"
    if p.exists():
        for line in p.open(encoding="utf-8", errors="replace"):
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                tr_freq[parts[0].lower()] = int(parts[1])

    # Turkcenin en sik 10.000 kelimesi. Ayni pivottan gelen adaylar
    # arasinda gunluk kelimeyi tercih etmek icin.
    tr_common = {
        w for w, _ in sorted(tr_freq.items(), key=lambda kv: -kv[1])[:10000]
    }

    def is_common(word: str) -> int:
        parts = [t for t in word.replace("-", " ").split() if t]
        return 1 if any(t in tr_common for t in parts) else 0

    # ----------------------------------------------------------- birlestir
    log("karsiliklar seciliyor")
    out_path = STAGES / "s4_turkish.jsonl"
    missing: list[tuple[str, int, str]] = []
    path_counter: Counter[str] = Counter()
    rejected_cognate = 0
    rejected_pos = 0
    rejected_rare = 0
    kept = 0
    samples: list[str] = []

    with out_path.open("w", encoding="utf-8") as fout:
        for lemma, entry in sorted(pool.items(), key=lambda kv: kv[1]["freq_rank"]):
            fr_pos = entry["pos"]
            folded_lemma = fold(lemma)

            # tr_word -> {"paths": set, "score": float, "verified": bool}
            cand: dict[str, dict] = defaultdict(
                lambda: {
                    "paths": set(),
                    "score": 0.0,
                    "verified": False,
                    # Kac ayri ingilizce pivot ve kac ayri ceviri kaydi bu
                    # karsiligi isaret ediyor. Kanit sayisi mutlak puandan
                    # daha guvenilir, cunku puan pivotun cok anlamliligina
                    # gore bastiriliyor.
                    "pivots": set(),
                    "hits": 0,
                }
            )

            # --- yol 1: dogrudan (tur uyumu ZORUNLU, yedek yok)
            for w, p_ in direct_tur.get(lemma, []):
                if not pos_ok(fr_pos, p_):
                    continue
                c = cand[w]
                c["paths"].add("direct")
                c["score"] += 3.0

            # --- yol 2: ters
            for w, p_ in reverse_tur.get(lemma, []):
                if not pos_ok(fr_pos, p_):
                    continue
                c = cand[w]
                c["paths"].add("reverse")
                c["score"] += 2.0

            # --- yol 3: ingilizce kopru
            dbn_en = {w for w, p_ in fr_to_en.get(lemma, ()) if pos_ok(fr_pos, p_)}
            kaikki_en: set[str] = set()
            for gloss in entry.get("meaning_en") or []:
                kaikki_en.update(en_from_gloss(gloss))
            strong = dbn_en & kaikki_en
            weak = (dbn_en | kaikki_en) - strong

            for pivots, base_weight in ((strong, 2.0), (weak, 1.0)):
                for pivot in pivots:
                    pairs = en_to_tur.get(pivot)
                    if not pairs:
                        continue
                    # Cok anlamli pivot atilmaz, agirligi dusurulur
                    damp = 1.0 / math.log2(2 + len(pairs))
                    for tr_word, en_pos in pairs:
                        if not pos_ok(fr_pos, en_pos):
                            continue
                        c = cand[tr_word]
                        c["score"] += base_weight * damp
                        c["paths"].add("bridge")
                        c["pivots"].add(pivot)
                        c["hits"] += 1
                        # Bagimsiz geri kontrol: turkce kelimenin ingilizce
                        # cevirileri arasinda pivot var mi
                        if pivot in tur_to_eng.get(tr_word, ()):
                            c["verified"] = True

            # --- cok nadir turkce kelime elemesi
            # Tek tanikli kopru adaylari zaman zaman sozlukte kalmis eski
            # ya da cok teknik kelimeler getiriyordu: 17 ayri fransizca
            # kelime "tesevvus" ile eslesmisti. Turkce 50k siklik
            # listesinde hicbir parcasi gecmiyorsa aday elenir.
            # Sadece TEK TANIKLI kopru adaylarina uygulanir. Ilk denemede
            # butun kopru adaylarina uygulanmisti ve dogrulanmis, saglam
            # karsiliklari da eliyordu (A1 kapsamasi %80,4'ten %77,5'e
            # dusmustu). Kanit varsa nadir kelime de kabul edilir.
            if tr_freq:
                for w in list(cand):
                    info_ = cand[w]
                    weak = (
                        info_["paths"] == {"bridge"}
                        and not info_["verified"]
                        and len(info_["pivots"]) < 2
                        and info_["hits"] < 2
                    )
                    if not weak:
                        continue
                    parts = [t for t in w.replace("-", " ").split() if t]
                    if parts and not any(t in tr_freq for t in parts):
                        del cand[w]
                        rejected_rare += 1

            # --- yanlis dost elemesi
            for w in list(cand):
                if fold(w) == folded_lemma:
                    del cand[w]
                    rejected_cognate += 1

            # --- turkce adayin kendi turu uyusmuyorsa ele
            #     (sadece kopruden gelen adaylar icin; dogrudan ve ters
            #     yollar zaten kaynakta anlam duzeyinde bagli)
            for w in list(cand):
                if cand[w]["paths"] == {"bridge"}:
                    known = tur_pos.get(w)
                    if known and fr_pos not in known:
                        del cand[w]
                        rejected_pos += 1

            if not cand:
                missing.append((lemma, entry["freq_rank"], entry["level"]))
                path_counter["none"] += 1
                continue

            # --- sec: once yol sayisi, sonra dogrulanmislik, sonra skor,
            #     en son turkce siklik
            def rank(info: dict) -> int:
                """Yol kalitesi. Kaynakta anlam duzeyinde bagli olan yollar
                kopruden her zaman ustundur; kanit sayisi ancak esit
                kalitedeki adaylari ayirmak icin kullanilir."""
                if "direct" in info["paths"]:
                    return 3
                if "reverse" in info["paths"]:
                    return 2
                return 1

            best = max(
                cand.items(),
                key=lambda kv: (
                    rank(kv[1]),
                    len(kv[1]["paths"]),
                    # Gunluk kelime, dogrulanmis ama nadir olana tercih
                    # edilir. Ingilizce pivotun baskin anlami saptirabiliyor:
                    # "kid" pivotu 15 fransizca kelimeye "oglak" veriyordu,
                    # cunku turkce wiktionary oglak -> kid baglantisini
                    # dogruluyor, "cocuk" ise dogrulanmiyordu.
                    is_common(kv[0]),
                    kv[1]["verified"],
                    len(kv[1]["pivots"]),
                    kv[1]["hits"],
                    kv[1]["score"],
                    tr_freq.get(kv[0], 0),
                ),
            )
            word, info = best
            paths = info["paths"]

            if "direct" in paths:
                conf, path = 0.95, "direct"
            elif "reverse" in paths:
                conf, path = 0.85, "reverse"
            elif info["verified"]:
                conf, path = 0.75, "bridge_verified"
            elif len(info["pivots"]) >= 2 or info["hits"] >= 2:
                # Iki ayri pivot ya da ayni pivotun iki ayri kaydi
                conf, path = 0.55, "bridge_supported"
            elif info["hits"] >= 1:
                # Tek tanik. Yanlis olma ihtimali gercek, ama kelimeyi hic
                # gostermemekten iyi: dusuk guvenle isaretlenip uygulamada
                # "gozden gecirilmedi" rozetiyle cikiyor.
                conf, path = 0.40, "bridge_weak"
            else:
                missing.append((lemma, entry["freq_rank"], entry["level"]))
                path_counter["none"] += 1
                continue

            # Birden fazla bagimsiz yol ayni karsiligi isaret ediyorsa guven artar
            if len(paths) >= 2:
                conf = min(0.98, conf + 0.08)

            entry["meaning_tr"] = word
            entry["tr_path"] = path
            entry["tr_paths"] = sorted(paths)
            entry["tr_confidence"] = round(conf, 2)
            entry["is_function_word"] = fr_pos in FUNCTION_POS
            fout.write(json.dumps(entry, ensure_ascii=False) + "\n")
            path_counter[path] += 1
            kept += 1
            if len(samples) < 30 and entry["level"] in ("A1", "A2"):
                samples.append(
                    f"| {entry['freq_rank']} | {lemma} | {fr_pos} | "
                    f"{word} | {path} | {conf:.2f} |"
                )

    missing.sort(key=lambda t: t[1])
    with (REPORTS / "missing_tr.csv").open("w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["lemma", "freq_rank", "level"])
        w.writerows(missing)

    log(f"yazildi: {out_path} ({human(kept)} lemma)")
    log(f"yol dagilimi: {dict(path_counter)}")
    log(f"yanlis dost elendi: {human(rejected_cognate)} | nadir kelime elendi: {human(rejected_rare)}")

    level_kept: Counter[str] = Counter()
    level_total: Counter[str] = Counter()
    for e in pool.values():
        level_total[e["level"]] += 1
    for line in out_path.open(encoding="utf-8"):
        level_kept[json.loads(line)["level"]] += 1

    report = [
        "# Aşama 4 — Türkçe Karşılık",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')} · Süre: {time.time() - T0:.0f} saniye",
        "",
        f"Havuz {human(len(pool))} lemma · **Karşılığı bulunan {human(kept)}** "
        f"({100.0 * kept / max(len(pool), 1):.1f}%)",
        "",
        "## Yol dağılımı",
        "",
        "| Yol | Güven | Sayı |",
        "|---|---|---|",
        f"| `direct` Fransızca Wiktionary'de doğrudan | 0.95 | {human(path_counter['direct'])} |",
        f"| `reverse` Türkçe Wiktionary'den ters | 0.85 | {human(path_counter['reverse'])} |",
        f"| `bridge_verified` köprü + bağımsız geri kontrol | 0.75 | {human(path_counter['bridge_verified'])} |",
        f"| `bridge_supported` köprü + çoklu tanık | 0.55 | {human(path_counter['bridge_supported'])} |",
        f"| `bridge_weak` köprü + tek tanık | 0.40 | {human(path_counter['bridge_weak'])} |",
        f"| bulunamadı | — | {human(path_counter['none'])} |",
        "",
        f"Birden fazla bağımsız yol aynı karşılığı işaret ettiğinde güven +0.08 artar.",
        f"Yanlış dost olarak elenen aday: **{human(rejected_cognate)}** · "
        f"Türkçe kelime türü uyuşmadığı için elenen: **{human(rejected_pos)}** · "
        f"Türkçede çok nadir olduğu için elenen: **{human(rejected_rare)}**",
        "",
        "## Seviye bazında kapsama",
        "",
        "| Seviye | Havuzda | Karşılığı var | Oran |",
        "|---|---|---|---|",
    ]
    for lv in ["A1", "A2", "B1", "B2", "C1", "C2"]:
        t, k = level_total[lv], level_kept[lv]
        report.append(f"| {lv} | {human(t)} | {human(k)} | {100.0 * k / t if t else 0:.1f}% |")

    report += [
        "",
        "## Örnek çıktı (A1/A2, sıklık sırasına göre)",
        "",
        "| Sıra | Fransızca | Tür | Türkçe | Yol | Güven |",
        "|---|---|---|---|---|---|",
        *samples,
        "",
        "## Gözlenen kelime türü jetonları",
        "",
        f"- Fransızca: `{dict(fr_pos_tokens.most_common(10))}`",
        f"- Türkçe: `{dict(tr_pos_tokens.most_common(10))}`",
        "",
        "## En sık eksikler",
        "",
        "| Sıra | Lemma | Seviye |",
        "|---|---|---|",
        *[f"| {r} | {w} | {lv} |" for w, r, lv in missing[:20]],
    ]
    (REPORTS / "stage4_turkish.md").write_text("\n".join(report), encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage4_turkish.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
