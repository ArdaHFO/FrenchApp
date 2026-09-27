"""Asama 9 - Donusluk fiiller (verbes pronominaux).

Girdi : stages/s7_verbs.jsonl
Cikti : stages/s9_reflexives.jsonl, reports/stage9_reflexives.md

Neden ayri bir asama ve neden ELLE yazilmis liste:

Donusluk fiil, temel fiilin "se" almis hali degildir; cogu zaman BASKA bir
fiildir. Otomatik uretim burada anlam kaymasi yapar:

  rendre      geri vermek        se rendre      gitmek / teslim olmak
  rappeler    geri cagirmak      se rappeler    hatirlamak
  passer      gecmek             se passer      olmak, yasanmak
  attendre    beklemek           s'attendre a   ummak, tahmin etmek
  tromper     aldatmak           se tromper     yanilmak
  douter      suphelenmek        se douter      tahmin etmek
  entendre    duymak             s'entendre     anlasmak

Bu yuzden Turkce karsiliklar ve tur bilgisi elle yazildi. Otomatik olan
tek sey CEKIM: o tamamen kurala bagli oldugu icin uretilebiliyor ve
uretmek elle yazmaktan daha guvenli.

Cekim kurallari:

  1. Basit zamanlar: zamir + temel cekim.
     je me lave · tu te laves · il se lave · nous nous lavons

  2. Elizyon: me/te/se, sesli harf ya da sessiz h onunde m'/t'/s' olur.
     je m'appelle · il s'habille

  3. Bilesik zamanlar HER ZAMAN etre ile kurulur, avoir ile degil.
     Temel fiil avoir alsa bile: j'ai lave ama je me suis lave.

  4. Ortac uyumu: donusluk zamir DUZ nesne ise ortac uyum saglar
     (se laver -> lavee, laves). Zamir DOLAYLI nesne ise uyum yoktur
     (se parler -> elles se sont parle). Bu ayrim listede accord
     alaniyla elle isaretlendi.

  5. Emir kipi: zamir fiilin arkasina tire ile gelir ve te -> toi olur.
     leve-toi · levons-nous · levez-vous
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA_ROOT = Path(os.environ.get("FRENCHAPP_DATA", Path.home() / "dev" / "french-data"))
STAGES = DATA_ROOT / "stages"
REPORTS = ROOT / "content" / "reports"

T0 = time.time()

VOWELS = "aàâeéèêëiîïoôöuùûüyh"
ASPIRATED_H_BASES = {"heurter"}

PRONOUNS = {
    "je": "me", "tu": "te", "il": "se",
    "nous": "nous", "vous": "vous", "ils": "se",
}

ETRE_PRESENT = {
    "je": "suis", "tu": "es", "il": "est",
    "nous": "sommes", "vous": "êtes", "ils": "sont",
}
ETRE_IMPARFAIT = {
    "je": "étais", "tu": "étais", "il": "était",
    "nous": "étions", "vous": "étiez", "ils": "étaient",
}

# Ortac uyum ekleri. Parantezli gosterim ders kitabi standardidir:
# "je me suis lave(e)" hem eril hem disil okuyucuya dogru gelir.
ACCORD_SUFFIX = {
    "je": "(e)", "tu": "(e)", "il": "",
    "nous": "(e)s", "vous": "(e)(s)", "ils": "s",
}

# --------------------------------------------------------------------------
# Elle yazilan liste.
#
#   (donusluk mastar, temel fiil, turkce, tur, ortac uyumu, not)
#
# tur:  reflechi   ozneye donuyor      (se laver = kendini yikamak)
#       reciproque karsilikli          (se parler = birbiriyle konusmak)
#       essentiel  sadece donusluk var (se souvenir)
#       sens       anlami degisiyor    (se rendre != rendre)
# --------------------------------------------------------------------------
VERBS: list[tuple[str, str, str, str, bool, str | None]] = [
    # --- gunluk rutin (A1). Turkce'de -n / -in catisiyla karsilanir.
    ("se laver", "laver", "yıkanmak", "reflechi", True, None),
    ("se lever", "lever", "kalkmak", "reflechi", True, None),
    ("se coucher", "coucher", "yatmak", "reflechi", True, None),
    ("se réveiller", "réveiller", "uyanmak", "reflechi", True, None),
    ("s'habiller", "habiller", "giyinmek", "reflechi", True, None),
    ("se déshabiller", "déshabiller", "soyunmak", "reflechi", True, None),
    ("se raser", "raser", "tıraş olmak", "reflechi", True, None),
    ("se peigner", "peigner", "saçını taramak", "reflechi", True, None),
    ("se maquiller", "maquiller", "makyaj yapmak", "reflechi", True, None),
    ("se doucher", "doucher", "duş almak", "reflechi", True, None),
    ("se baigner", "baigner", "yıkanmak, denize girmek", "reflechi", True, None),
    ("se préparer", "préparer", "hazırlanmak", "reflechi", True, None),
    ("se dépêcher", "dépêcher", "acele etmek", "essentiel", True, None),
    ("se reposer", "reposer", "dinlenmek", "reflechi", True, None),
    ("se promener", "promener", "gezmek", "reflechi", True, None),
    ("s'asseoir", "asseoir", "oturmak", "reflechi", True,
     "asseoir başkasını oturtmak, s'asseoir kendi oturmak."),
    ("s'arrêter", "arrêter", "durmak", "sens", True,
     "arrêter bir şeyi durdurmak, s'arrêter kendi durmak."),
    ("s'installer", "installer", "yerleşmek", "reflechi", True, None),
    ("se coiffer", "coiffer", "saçını yapmak", "reflechi", True, None),

    # --- duygular ve haller
    ("s'amuser", "amuser", "eğlenmek", "reflechi", True, None),
    ("s'ennuyer", "ennuyer", "sıkılmak", "reflechi", True, None),
    ("s'inquiéter", "inquiéter", "endişelenmek", "reflechi", True, None),
    ("se fâcher", "fâcher", "kızmak", "reflechi", True, None),
    ("s'énerver", "énerver", "sinirlenmek", "reflechi", True, None),
    ("se calmer", "calmer", "sakinleşmek", "reflechi", True, None),
    ("s'étonner", "étonner", "şaşırmak", "reflechi", True, None),
    ("se sentir", "sentir", "kendini hissetmek", "sens", True,
     "sentir koklamak, se sentir kendini bir halde hissetmek: je me sens bien."),
    ("s'intéresser", "intéresser", "ilgilenmek", "sens", True,
     "s'intéresser À bir şeye ilgi duymak."),
    ("s'occuper", "occuper", "ilgilenmek, bakmak", "sens", True,
     "occuper işgal etmek, s'occuper DE biriyle ilgilenmek."),
    ("s'habituer", "habituer", "alışmak", "reflechi", True,
     "s'habituer À bir şeye alışmak."),
    ("s'attendre", "attendre", "beklemek, ummak", "sens", True,
     "attendre birini beklemek, s'attendre À bir şeyi ummak/tahmin etmek."),
    ("se plaindre", "plaindre", "şikâyet etmek", "sens", True,
     "plaindre birine acımak, se plaindre şikâyet etmek."),
    ("s'excuser", "excuser", "özür dilemek", "sens", True,
     "excuser affetmek, s'excuser özür dilemek."),

    # --- anlami degisenler: en tehlikeli grup
    ("s'appeler", "appeler", "adı ... olmak", "sens", True,
     "appeler çağırmak, s'appeler adı olmak: je m'appelle Arda."),
    ("se rappeler", "rappeler", "hatırlamak", "sens", False,
     "rappeler geri çağırmak, se rappeler hatırlamak. Ortaç uyum almaz."),
    ("se souvenir", "souvenir", "hatırlamak", "essentiel", True,
     "se souvenir DE ile kullanılır: je me souviens de toi."),
    ("se rendre", "rendre", "gitmek; teslim olmak", "sens", True,
     "rendre geri vermek, se rendre bir yere gitmek ya da teslim olmak."),
    ("se passer", "passer", "olmak, yaşanmak", "sens", True,
     "passer geçmek, se passer bir olayın olması: qu'est-ce qui se passe ?"),
    ("se tromper", "tromper", "yanılmak", "sens", True,
     "tromper aldatmak, se tromper yanılmak."),
    ("se douter", "douter", "tahmin etmek", "sens", True,
     "douter şüphelenmek, se douter DE tam tersine tahmin etmek/emin olmak."),
    ("s'entendre", "entendre", "anlaşmak", "sens", True,
     "entendre duymak, s'entendre AVEC biriyle iyi geçinmek."),
    ("se trouver", "trouver", "bulunmak", "sens", True,
     "trouver bulmak, se trouver bir yerde bulunmak."),
    ("se mettre", "mettre", "başlamak; girmek", "sens", True,
     "mettre koymak, se mettre À bir işe başlamak."),
    ("se faire", "faire", "olmak, alışmak", "sens", False,
     "se faire + isim: kendine yaptırmak. Kalıp olarak öğrenilmeli."),
    ("se demander", "demander", "kendi kendine sormak", "sens", False,
     "demander sormak, se demander merak etmek. Ortaç uyum almaz."),
    ("se servir", "servir", "kullanmak", "sens", True,
     "servir hizmet etmek, se servir DE bir şeyi kullanmak."),
    ("s'agir", "agir", "söz konusu olmak", "sens", False,
     "Sadece il şahsıyla: il s'agit de… = … söz konusu."),
    ("se taire", "taire", "susmak", "essentiel", True, None),

    # --- karsilikli (reciproque): ortac uyumu nesneye gore degisir
    ("se parler", "parler", "birbiriyle konuşmak", "reciproque", False,
     "parler À olduğu için ortaç uyum almaz: elles se sont parlé."),
    ("se voir", "voir", "görüşmek", "reciproque", True, None),
    ("se rencontrer", "rencontrer", "karşılaşmak", "reciproque", True, None),
    ("se retrouver", "retrouver", "buluşmak", "reciproque", True, None),
    ("s'aimer", "aimer", "birbirini sevmek", "reciproque", True, None),
    ("s'embrasser", "embrasser", "öpüşmek", "reciproque", True, None),
    ("se disputer", "disputer", "tartışmak, kavga etmek", "reciproque", True, None),
    ("se quitter", "quitter", "ayrılmak", "reciproque", True, None),
    ("se marier", "marier", "evlenmek", "reflechi", True, None),
    ("se séparer", "séparer", "ayrılmak", "reciproque", True, None),
    ("s'écrire", "écrire", "yazışmak", "reciproque", False,
     "écrire À olduğu için ortaç uyum almaz."),
    ("se téléphoner", "téléphoner", "telefonlaşmak", "reciproque", False,
     "téléphoner À olduğu için ortaç uyum almaz."),
    ("se battre", "battre", "dövüşmek", "reciproque", True, None),

    # --- hareket ve gunluk eylemler
    ("s'approcher", "approcher", "yaklaşmak", "reflechi", True,
     "s'approcher DE bir şeye yaklaşmak."),
    ("s'éloigner", "éloigner", "uzaklaşmak", "reflechi", True, None),
    ("se diriger", "diriger", "yönelmek", "sens", True,
     "diriger yönetmek, se diriger VERS bir yöne gitmek."),
    ("se perdre", "perdre", "kaybolmak", "sens", True,
     "perdre kaybetmek, se perdre kendi kaybolmak."),
    ("se cacher", "cacher", "saklanmak", "reflechi", True, None),
    ("se casser", "casser", "kırmak (kendi uzvunu)", "sens", False,
     "je me suis cassé le bras: kolumu kırdım. Nesne varsa uyum yok."),
    ("se blesser", "blesser", "yaralanmak", "reflechi", True, None),
    ("se brûler", "brûler", "kendini yakmak", "reflechi", True, None),
    ("se couper", "couper", "kesmek (kendini)", "reflechi", True, None),
    ("se noyer", "noyer", "boğulmak", "reflechi", True, None),
    ("se garer", "garer", "park etmek", "reflechi", True, None),

    # --- dusunce ve dil
    ("s'exprimer", "exprimer", "kendini ifade etmek", "reflechi", True, None),
    ("se comprendre", "comprendre", "anlaşmak", "reciproque", True, None),
    ("s'expliquer", "expliquer", "durumu açıklamak, anlaşmak", "sens", True,
     "expliquer bir şeyi açıklamak, s'expliquer kendini/durumu açıklamak."),
    ("s'améliorer", "améliorer", "gelişmek", "reflechi", True, None),
    ("se développer", "développer", "gelişmek", "reflechi", True, None),
    ("se produire", "produire", "meydana gelmek", "sens", True,
     "produire üretmek, se produire bir olayın gerçekleşmesi."),
    ("se terminer", "terminer", "bitmek", "sens", True,
     "terminer bitirmek, se terminer kendi bitmek."),
    ("se transformer", "transformer", "dönüşmek", "reflechi", True, None),
    ("se répéter", "répéter", "tekrarlanmak", "reflechi", True, None),

    # --- yalnizca donusluk olanlar
    ("se moquer", "moquer", "alay etmek", "essentiel", True,
     "se moquer DE biriyle alay etmek."),
    ("s'enfuir", "enfuir", "kaçmak", "essentiel", True, None),
    ("se méfier", "méfier", "güvenmemek", "essentiel", True,
     "se méfier DE birinden şüphelenmek."),
    ("s'évanouir", "évanouir", "bayılmak", "essentiel", True, None),
    ("s'écrouler", "écrouler", "çökmek", "essentiel", True, None),
    ("se soucier", "soucier", "kaygılanmak", "essentiel", True, None),
    ("s'efforcer", "efforcer", "çabalamak", "essentiel", True, None),
    ("se réfugier", "réfugier", "sığınmak", "essentiel", True, None),

    # --- genisletilmis cekirdek: A2-C1 metinlerinde cok gecen kullanımlar
    # Bu satırlar da otomatik "se + fiil" üretimi değildir. Her birinin
    # dönüşlü anlamı, türü ve ortaç uyumu ayrı değerlendirildi.
    ("s'adapter", "adapter", "uyum sağlamak", "reflechi", True, None),
    ("s'adresser", "adresser", "hitap etmek; başvurmak", "sens", True,
     "adresser göndermek, s'adresser À birine hitap etmek veya başvurmak."),
    ("s'aggraver", "aggraver", "kötüleşmek", "sens", True,
     "aggraver kötüleştirmek, s'aggraver kötüleşmek."),
    ("s'allonger", "allonger", "uzanmak", "reflechi", True, None),
    ("s'apercevoir", "apercevoir", "fark etmek", "sens", True,
     "apercevoir görmek, s'apercevoir DE bir şeyin farkına varmak."),
    ("s'appliquer", "appliquer", "özen göstermek; uygulanmak", "sens", True,
     "appliquer uygulamak, s'appliquer À özen göstermek; bir şeye uygulanmak."),
    ("s'assurer", "assurer", "emin olmak", "sens", True,
     "assurer sağlamak, s'assurer DE emin olmak."),
    ("s'attacher", "attacher", "bağlanmak", "reflechi", True, None),
    ("s'accrocher", "accrocher", "tutunmak", "reflechi", True, None),
    ("se comporter", "comporter", "davranmak", "essentiel", True, None),
    ("se concentrer", "concentrer", "odaklanmak", "reflechi", True, None),
    ("se conformer", "conformer", "uymak", "essentiel", True,
     "se conformer À bir kurala veya karara uymak."),
    ("se consacrer", "consacrer", "kendini adamak", "reflechi", True,
     "se consacrer À bir işe kendini adamak."),
    ("se contenter", "contenter", "yetinmek", "sens", True,
     "contenter memnun etmek, se contenter DE ile yetinmek."),
    ("se distinguer", "distinguer", "öne çıkmak; ayırt edilmek", "sens", True,
     "distinguer ayırt etmek, se distinguer öne çıkmak veya ayırt edilmek."),
    ("s'effondrer", "effondrer", "çökmek", "essentiel", True, None),
    ("s'emparer", "emparer", "ele geçirmek", "essentiel", True,
     "s'emparer DE bir şeyi ele geçirmek."),
    ("s'empresser", "empresser", "acele etmek", "essentiel", True,
     "s'empresser DE bir şeyi yapmak için acele etmek."),
    ("s'enfoncer", "enfoncer", "batmak; derine ilerlemek", "sens", True,
     "enfoncer içeri sokmak, s'enfoncer batmak veya derine ilerlemek."),
    ("s'engager", "engager", "taahhüt etmek; girişmek", "sens", True,
     "engager işe almak, s'engager À taahhüt etmek; bir işe girişmek."),
    ("s'entretenir", "entretenir", "görüşmek; konuşmak", "reciproque", True,
     "entretenir sürdürmek, s'entretenir AVEC biriyle görüşmek."),
    ("s'exposer", "exposer", "kendini maruz bırakmak", "reflechi", True,
     "s'exposer À bir riske kendini maruz bırakmak."),
    ("se fier", "fier", "güvenmek", "essentiel", True,
     "se fier À birine veya bir şeye güvenmek."),
    ("se heurter", "heurter", "çarpmak; karşılaşmak", "sens", True,
     "heurter çarpmak, se heurter À bir engelle karşılaşmak."),
    ("s'inscrire", "inscrire", "kaydolmak", "sens", True,
     "inscrire kaydetmek, s'inscrire À bir programa kaydolmak."),
    ("s'inspirer", "inspirer", "esinlenmek", "sens", True,
     "inspirer ilham vermek, s'inspirer DE esinlenmek."),
    ("s'interposer", "interposer", "araya girmek", "reflechi", True, None),
    ("s'interroger", "interroger", "kendi kendine sormak", "reflechi", True,
     "interroger birini sorgulamak, s'interroger kendi kendine sormak."),
    ("se joindre", "joindre", "katılmak", "sens", True,
     "joindre birleştirmek veya ulaşmak, se joindre À birine katılmak."),
    ("s'obstiner", "obstiner", "inat etmek", "essentiel", True,
     "s'obstiner À bir şeyi yapmakta inat etmek."),
    ("se pencher", "pencher", "eğilmek; üzerinde durmak", "sens", True,
     "se pencher SUR bir konuyu incelemek anlamında da kullanılır."),
    ("se porter", "porter", "olmak; sağlığı yerinde olmak", "sens", True,
     "Comment allez-vous ? ile benzer biçimde comment vous portez-vous denir."),
    ("se procurer", "procurer", "edinmek", "sens", False,
     "procurer sağlamak, se procurer bir şeyi edinmek. Ortaç genellikle uyum almaz."),
    ("se prononcer", "prononcer", "görüş bildirmek", "sens", True,
     "prononcer telaffuz etmek, se prononcer SUR görüş bildirmek."),
    ("se rapprocher", "rapprocher", "yaklaşmak; yakınlaşmak", "reflechi", True,
     None),
    ("se recueillir", "recueillir", "sessizce düşünmek; anmak", "essentiel", True,
     None),
    ("se remettre", "remettre", "iyileşmek; yeniden başlamak", "sens", True,
     "remettre geri koymak, se remettre iyileşmek veya yeniden başlamak."),
    ("se renseigner", "renseigner", "bilgi edinmek", "sens", True,
     "renseigner bilgi vermek, se renseigner SUR bilgi edinmek."),
    ("se repentir", "repentir", "pişman olmak", "essentiel", True, None),
    ("se retourner", "retourner", "arkasını dönmek", "reflechi", True, None),
    ("se situer", "situer", "bulunmak; konumlanmak", "sens", True,
     "situer konumlandırmak, se situer bir yerde bulunmak."),
    ("se soumettre", "soumettre", "boyun eğmek; tabi olmak", "sens", True,
     "soumettre sunmak veya tabi tutmak, se soumettre À boyun eğmek."),
    ("se suicider", "suicider", "intihar etmek", "essentiel", True, None),
    ("se tenir", "tenir", "durmak; kendini tutmak", "sens", True,
     "tenir tutmak, se tenir ayakta durmak veya belirli biçimde davranmak."),
    ("se tourner", "tourner", "dönmek; yönelmek", "sens", True,
     "tourner çevirmek/dönmek, se tourner VERS bir şeye yönelmek."),
    ("se vanter", "vanter", "övünmek", "sens", True,
     "vanter övmek, se vanter DE bir şeyle övünmek."),
]

# Kurala uymayan emir kipleri.
IMPERATIVE_OVERRIDE: dict[str, dict[str, str]] = {
    "s'asseoir": {"tu": "assieds-toi", "nous": "asseyons-nous",
                  "vous": "asseyez-vous"},
    "se taire": {"tu": "tais-toi", "nous": "taisons-nous",
                 "vous": "taisez-vous"},
    "s'agir": {},  # sahsiz fiil, emir kipi yok
}

# Sadece "il" sahsiyla kullanilan fiiller.
IMPERSONAL = {"s'agir"}

SIMPLE_TENSES = ["present", "imparfait", "futur_simple", "conditionnel",
                 "subjonctif"]


def log(msg: str) -> None:
    print(f"[{time.time() - T0:6.1f}s] {msg}", flush=True)


def human(n: int) -> str:
    return f"{n:,}".replace(",", ".")


# Kaikki bazi fiillerin cekimini ZATEN donusluk halde tasiyor
# (souvenir -> "me souviens"). Kendi zamirimizi eklemeden once
# oradakini sokup atiyoruz, yoksa "me me souviens" cikiyor.
PRONOUN_PREFIXES = ("me ", "te ", "se ", "nous ", "vous ", "m'", "t'", "s'")
IMPERATIVE_SUFFIXES = ("-toi", "-nous", "-vous", "-moi")


def strip_pronoun(form: str) -> str:
    f = form.strip()
    for pref in PRONOUN_PREFIXES:
        if f.lower().startswith(pref):
            return f[len(pref):].strip()
    return f


def strip_imperative_pronoun(form: str) -> str:
    f = form.strip()
    for suf in IMPERATIVE_SUFFIXES:
        if f.lower().endswith(suf):
            return f[: -len(suf)].rstrip("-").strip()
    return f


def elide(pronoun: str, word: str, *, aspirated_h: bool = False) -> str:
    """me + appelle -> m'appelle. nous/vous elizyon yapmaz."""
    if pronoun in ("nous", "vous") or not word:
        return f"{pronoun} {word}"
    if word[0].lower() in VOWELS and not aspirated_h:
        return f"{pronoun[0]}'{word}"
    return f"{pronoun} {word}"


def build_tenses(
    base: dict,
    accord: bool,
    infinitive: str,
) -> dict[str, dict[str, str]]:
    src = base.get("tenses") or {}
    participle = strip_pronoun(base.get("past_participle") or "")
    aspirated_h = base.get("lemma") in ASPIRATED_H_BASES
    out: dict[str, dict[str, str]] = {}

    persons = ["il"] if infinitive in IMPERSONAL else list(PRONOUNS)

    for tense in SIMPLE_TENSES:
        row = src.get(tense)
        if not row:
            continue
        built: dict[str, str] = {}
        for person in persons:
            form = row.get(person)
            if not form:
                continue
            built[person] = elide(
                PRONOUNS[person],
                strip_pronoun(form),
                aspirated_h=aspirated_h,
            )
        if built:
            out[tense] = built

    # Bilesik zamanlar her zaman etre ile. Temel fiilin yardimci fiili
    # ne olursa olsun.
    for tense, aux_table in (
        ("passe_compose", ETRE_PRESENT),
        ("plus_que_parfait", ETRE_IMPARFAIT),
    ):
        if not participle:
            continue
        built = {}
        for person in persons:
            suffix = ACCORD_SUFFIX[person] if accord else ""
            # -s ya da -x ile biten ortac cogul -s almaz: assis -> assis.
            if participle[-1:] in ("s", "x"):
                suffix = suffix.replace("s", "").replace("()", "")
            aux = aux_table[person]
            built[person] = elide(PRONOUNS[person], f"{aux} {participle}{suffix}")
        out[tense] = built

    # Emir kipi: zamir arkaya gelir, te -> toi olur.
    override = IMPERATIVE_OVERRIDE.get(infinitive)
    if override is not None:
        if override:
            out["imperatif"] = dict(override)
    else:
        row = src.get("imperatif") or {}
        built = {}
        for person, suffix in (("tu", "toi"), ("nous", "nous"),
                               ("vous", "vous")):
            form = row.get(person)
            if form:
                stem = strip_imperative_pronoun(strip_pronoun(form))
                built[person] = f"{stem}-{suffix}"
        if built:
            out["imperatif"] = built

    return out


def main() -> int:
    src_path = STAGES / "s7_verbs.jsonl"
    if not src_path.exists():
        print("once: python content/tools/10_verbs.py")
        return 2

    log("temel fiiller yukleniyor")
    base_by_lemma: dict[str, dict] = {}
    for line in src_path.open(encoding="utf-8"):
        v = json.loads(line)
        base_by_lemma[v["lemma"]] = v
    log(f"temel fiil: {len(base_by_lemma)}")

    out_path = STAGES / "s9_reflexives.jsonl"
    missing: list[str] = []
    rows: list[dict] = []

    for infinitive, base_lemma, tr, kind, accord, note in VERBS:
        base = base_by_lemma.get(base_lemma)
        if base is None:
            missing.append(f"{infinitive} (temel: {base_lemma})")
            continue
        tenses = build_tenses(base, accord, infinitive)
        if not tenses.get("present"):
            missing.append(f"{infinitive} (present yok)")
            continue
        rows.append({
            "lemma": infinitive,
            "base": base_lemma,
            "meaning_tr": tr,
            "meaning_en": base.get("meaning_en") or [],
            "kind": kind,
            "accord": accord,
            "note_tr": note,
            "level": base.get("level", "A2"),
            "freq_rank": base.get("freq_rank", 99999),
            "ipa": None,
            "auxiliary": "être",
            "past_participle": base.get("past_participle"),
            "tenses": tenses,
        })

    with out_path.open("w", encoding="utf-8") as f:
        for r in sorted(rows, key=lambda x: x["freq_rank"]):
            f.write(json.dumps(r, ensure_ascii=False) + "\n")

    n_conj = sum(len(t) for r in rows for t in r["tenses"].values())
    log(f"yazildi: {out_path} ({len(rows)} fiil, {n_conj} cekim)")
    if missing:
        log(f"atlanan {len(missing)}: {', '.join(missing[:12])}")

    kinds: dict[str, int] = {}
    for r in rows:
        kinds[r["kind"]] = kinds.get(r["kind"], 0) + 1

    sample = next((r for r in rows if r["lemma"] == "se laver"), None)
    lines = [
        "# Aşama 9 — Dönüşlü Fiiller",
        "",
        f"Tarih: {time.strftime('%Y-%m-%d %H:%M')}",
        "",
        f"**{human(len(rows))} dönüşlü fiil**, {human(n_conj)} çekim satırı.",
        "",
        "## Neden elle yazıldı",
        "",
        "Dönüşlü fiil, temel fiilin `se` almış hâli değildir; çoğu zaman",
        "başka bir fiildir. Otomatik üretim burada anlam kayması yapar:",
        "",
        "| Temel | Dönüşlü |",
        "|---|---|",
        "| rendre — geri vermek | se rendre — gitmek, teslim olmak |",
        "| rappeler — geri çağırmak | se rappeler — hatırlamak |",
        "| passer — geçmek | se passer — olmak, yaşanmak |",
        "| attendre — beklemek | s'attendre à — ummak |",
        "| tromper — aldatmak | se tromper — yanılmak |",
        "| entendre — duymak | s'entendre — anlaşmak |",
        "",
        "Türkçe karşılıklar ve tür bilgisi elle yazıldı. Otomatik olan tek",
        "şey çekim: o tamamen kurala bağlı olduğu için üretmek elle",
        "yazmaktan daha güvenli.",
        "",
        "## Tür dağılımı",
        "",
        "| Tür | Sayı | Anlamı |",
        "|---|---|---|",
        f"| `reflechi` | {kinds.get('reflechi', 0)} | Özneye dönüyor (se laver) |",
        f"| `reciproque` | {kinds.get('reciproque', 0)} | Karşılıklı (se parler) |",
        f"| `essentiel` | {kinds.get('essentiel', 0)} | Sadece dönüşlü var (se souvenir) |",
        f"| `sens` | {kinds.get('sens', 0)} | Anlamı değişiyor (se rendre) |",
        "",
        "## Örnek çıktı — se laver",
        "",
    ]
    if sample:
        for tense in ("present", "passe_compose", "imperatif"):
            row = sample["tenses"].get(tense) or {}
            forms = " · ".join(f"{p} {f}" if p in ("je", "tu", "il", "nous",
                                                   "vous", "ils") and
                               tense != "imperatif" else f
                               for p, f in row.items())
            lines.append(f"- **{tense}**: {forms}")
    (REPORTS / "stage9_reflexives.md").write_text("\n".join(lines),
                                                  encoding="utf-8")
    log(f"rapor: {REPORTS / 'stage9_reflexives.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
