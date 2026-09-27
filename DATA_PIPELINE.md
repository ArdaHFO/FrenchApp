# İçerik Veri Boru Hattı

Altı CEFR seviyesi için yaklaşık 10.000 kelime, 600 deyim, 600 fiil ve 12.000 örnek cümleyi açık lisanslı veri kümelerinden üretme planı.

Bu içerik elle yazılamaz. Bunun yerine birden fazla kaynak birleştirilir, çakışanlar ayıklanır, sonuç doğrulanır ve tek bir SQLite dosyasına derlenir. Boru hattı istendiği zaman baştan çalıştırılabilir ve elle yapılan düzeltmeler kaybolmaz.

**Ana belge:** [PLAN.md](PLAN.md)

## Çalıştırıldı — sonuçlar

Boru hattı 2026-08-10'da uçtan uca çalıştırıldı. Ayrıntılı raporlar
[content/reports/](content/reports/) altında.

| Aşama | Çıktı | Rapor |
|---|---|---|
| Kaynak doğrulama | 11 kaynak, 1,23 GB | `source_probe.txt` |
| Üç kilit ölçüm | İki adımlı bağlantı **21 kat** kazanç | `measurements.md`, `measurements_fallback.md` |
| 1 — Aday havuz | 43.076 lemma, sıklık sıralı | `stage1_lemmas.md` |
| 2 — Seviye | A1-B1'in ~%97'si FLELex'ten | `stage2_levels.md` |
| 3 — İngilizce + IPA + fiil formu | 33.152 lemma, 4.727 fiil | `stage3_english.md` |
| 4 — Türkçe karşılık | 9.670 lemma (%29) | `stage4_turkish.md` |
| 5 — Örnek cümle | 6.572 kelimede (%68) | `stage5_examples.md` |
| 6 — Deyimler | 526 deyim, 62'sinde Türkçe | `stage6_idioms.md`, `stage6b_idiom_tr.md` |
| 7 — Fiil çekimi | 1.477 fiil × 8 zaman | `stage7_verbs.md` |
| 10 — content.db | **23,0 MB** | `stage10_build_db.md` |

Nihai içerik: **15.423 kelime** (128 deyim), **17.832 örnek cümle**,
**2.698 fiil**, **121.354 çekim** ve **19 dilbilgisi dersi**.
`14_validate_db.py` tablo sayılarını, referansları, benzersizlikleri, kimlik
eşlemelerini ve zayıf çevirilerin öğrenme havuzundan ayrılmasını denetler.

### Elle düzeltme katmanı

`content/overrides/manual.json` boru hattının çıktısının üzerine yazılır ve
hiçbir script tarafından değiştirilmez. Boru hattı kaç kez çalışırsa çalışsın
düzeltmeler korunur. Şu an en sık kullanılan 20 kelimede gözle görülür
hatalar düzeltilmiş durumda (`aller → gitmek`, `femme → kadın`,
`donner → vermek` gibi). Düzeltilen kayıt `reviewed=1` ve `confidence=1.0`
alır, gözden geçirme kuyruğundan çıkar.

---

## 1. Kaynaklar

Hepsi kontrol edildi, indirilebilir durumda ve açık lisanslı.

| # | Kaynak | Ne verir | Lisans | Adres |
|---|---|---|---|---|
| 1 | **Lexique 3.83** | 140.000 Fransızca kelime, lemma, kelime türü, cinsiyet, çoğul, fonetik yazım, kitap ve altyazı sıklığı | CC BY-SA | [lexique.org](http://www.lexique.org/) |
| 2 | **FLELex** | Her lemma için A1'den C2'ye seviye başına normalize sıklık. Fransızca öğretim kitapları derleminden üretilmiş | Araştırma için serbest | [cental.uclouvain.be/cefrlex/flelex](https://cental.uclouvain.be/cefrlex/flelex/download/) |
| 3 | **FrequencyWords (OpenSubtitles 2018)** | Konuşma diline yakın sıklık listesi, `fr_50k.txt` ve `tr_50k.txt` | İçerik CC BY-SA 4.0 | [github.com/hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords) |
| 4 | **kaikki.org Fransızca sözlüğü** | Wiktionary'den çıkarılmış makine okunur sözlük. İngilizce tanımlar, IPA, kelime türü, cinsiyet, deyim etiketleri | CC BY-SA | [kaikki.org/dictionary/French](https://kaikki.org/dictionary/French/index.html) |
| 5 | **DBnary** | 27 Wiktionary sürümünden anlam bağlantılı çeviriler. **Fransızca ve Türkçe ikisi de var** | CC BY-SA 3.0 | [kaiko.getalp.org](http://kaiko.getalp.org/about-dbnary/) |
| 6 | **Tatoeba** | Milyonlarca cümle ve aralarındaki çeviri bağlantıları. Fransızca, İngilizce ve Türkçe hepsi güçlü | CC BY 2.0 FR | [tatoeba.org/downloads](https://tatoeba.org/en/downloads) |
**Toplam indirme:** 1,23 GB. Adreslerin hepsi `content/tools/00_probe_sources.py` ile 2026-08-09'da doğrulandı, gerçek boyutlar ölçüldü. En büyük üç dosya: kaikki.org sözlüğü (547 MB), Tatoeba cümleleri (208 MB), DBnary İngilizce (197 MB).

> **Verbiste kullanılmıyor.** Plan başlangıçta fiil çekimleri için Verbiste'i öngörüyordu. İki sebeple vazgeçildi: sunucusu erişilemez durumda (bağlantıyı reddediyor) ve lisansı GPL v2, yani copyleft, bu da uygulamanın dağıtımını kısıtlar.
>
> Yerine **kaikki.org verisindeki `forms` alanı** kullanılacak. Kontrol edildi: `être` fiili kişi, sayı, zaman ve kip etiketli 189 form içeriyor (`['first-person', 'indicative', 'present', 'singular']` gibi). Aynı CC BY-SA lisansı, ek indirme yok, GPL sorunu yok. Bu değişiklik lisans bölümündeki Verbiste maddesini de ortadan kaldırır.

### 1.1 Her kaynağın neden gerekli olduğu

Tek bir kaynak yeterli olmuyor, çünkü hiçbirinde ihtiyacımız olan altı bilginin hepsi yok.

- **Seviye bilgisi** sadece FLELex'te var
- **Türkçe karşılık** sadece DBnary'de var
- **Üç dilli örnek cümle** sadece Tatoeba'da var
- **Güvenilir cinsiyet ve fonetik** en temiz haliyle Lexique'te var
- **Fiil çekimi** kaikki.org'un `forms` alanında kişi, sayı, zaman ve kip etiketli olarak var
- **İngilizce tanım ve deyim etiketi** en iyi kaikki.org'da var

---

## 2. Klasör Yapısı

Ham veri ve ara dosyalar **proje klasörünün dışında** durur, varsayılan olarak `~/dev/french-data` içinde. Sebebi proje OneDrive'da ve 1,2 GB ham veriyi buluta senkronlamak hem yavaş hem gereksiz. `FRENCHAPP_DATA` ortam değişkeni ile bu konum değiştirilebilir. Projenin içinde sadece scriptler, elle yazılan içerik, raporlar ve son ürün kalır.

```
content/
├── sources/                 # indirilen ham dosyalar, sürüm damgalı
│   ├── lexique/Lexique383.tsv
│   ├── flelex/FLELex_TreeTagger.tsv
│   ├── freq/fr_50k.txt, tr_50k.txt
│   ├── kaikki/kaikki-dictionary-French.jsonl
│   ├── dbnary/fra_dbnary.ttl.bz2, tur_dbnary.ttl.bz2, eng_dbnary.ttl.bz2
│   ├── tatoeba/sentences.csv, links.csv, sentences_with_audio.csv
│   └── verbiste/verbs-fr.xml, conjugation-fr.xml
│
├── stages/                  # her aşamanın çıktısı, JSONL
│   ├── s1_lemmas.jsonl
│   ├── s2_levels.jsonl
│   ├── s3_english.jsonl
│   ├── s4_turkish.jsonl
│   ├── s5_examples.jsonl
│   ├── s6_idioms.jsonl
│   ├── s7_verbs.jsonl
│   └── s8_themes.jsonl
│
├── overrides/               # ELLE YAPILAN DÜZELTMELER, asla üzerine yazılmaz
│   ├── manual.jsonl         # düzeltilmiş alanlar
│   ├── blocklist.txt        # istenmeyen kelimeler
│   └── theme_map.tsv        # Wiktionary kategorisi → tema eşlemesi
│
├── grammar/                 # elle yazılan dilbilgisi dersleri
│   ├── a1/01-present-regulier.md
│   └── ...
│
├── tools/
│   ├── 00_probe_sources.py      ✅ adresleri doğrular, indirmeden önce
│   ├── 01_fetch.py              ✅ kaynakları indirir (sürdürülebilir)
│   ├── 02_measure.py            ✅ üç kilit ölçüm
│   ├── 03_measure_fallbacks.py  ✅ yedek yolların kapsaması
│   ├── 04_lemmas.py             ✅ aşama 1, aday kelime havuzu
│   ├── 05_levels.py             ✅ aşama 2, seviye ataması
│   ├── 06_english.py            ✅ aşama 3, İngilizce anlam + IPA + fiil formları
│   ├── 07_turkish.py               aşama 4, Türkçe karşılık
│   ├── 08_examples.py              aşama 5, örnek cümleler
│   ├── 09_idioms.py                aşama 6, deyimler
│   ├── 10_verbs.py                 aşama 7, fiil çekim tablosu
│   ├── 11_themes.py                aşama 8, tema etiketleri
│   ├── 12_validate.py              aşama 9, doğrulama
│   ├── 13_build_db.py              aşama 10, content.db üretimi
│   ├── review_export.py            gözden geçirme kuyruğu üretir
│   └── review_apply.py             düzeltmeleri overrides/manual.jsonl'a yazar
│
├── reports/
│   ├── validation.txt
│   ├── coverage.md
│   ├── review_queue.csv
│   └── missing_tr.csv
│
└── out/content.db
```

**En önemli kural:** `overrides/manual.jsonl` dosyası boru hattının her aşamasında en son uygulanır ve hiçbir script tarafından yazılmaz. Böylece boru hattı istendiği kadar yeniden çalıştırılabilir, elle yapılan düzeltmeler hep korunur.

---

## 3. Aşamalar

### Aşama 1 — Aday kelime havuzu

**Girdi:** Lexique383.tsv, fr_50k.txt

Lexique'ten şu sütunlar okunur: `ortho`, `lemme`, `cgram`, `genre`, `nombre`, `phon`, `freqlemfilms2`, `freqlemlivres`, `islem`.

Filtreler:
- `islem == 1` (sadece sözlük biçimleri, çekimli biçimler değil)
- Kelime türü şu kümede: isim, sıfat, fiil, zarf, edat, bağlaç, zamir, ünlem
- Özel isimler dışarıda
- Tek harfli kelimeler dışarıda
- Her iki sıklık sütunu da sıfır olanlar dışarıda
- `overrides/blocklist.txt` içindekiler dışarıda

Ardından OpenSubtitles listesiyle birleştirilir ve birleşik sıklık skoru hesaplanır.

```
skor = 0.6 × normalize(log(altyazı_sıklığı + 1))
     + 0.4 × normalize(log(kitap_sıklığı + 1))
```

Altyazı sıklığına daha fazla ağırlık verilir, çünkü amaç konuşulan dili öğrenmektir.

**Çıktı:** `s1_lemmas.jsonl`, tahminen 35.000-45.000 satır.

---

### Aşama 2 — Seviye atama

**Girdi:** s1_lemmas.jsonl, FLELex_TreeTagger.tsv

FLELex her lemma için A1'den C2'ye kadar milyon kelimede normalize sıklık verir. Bir kelimenin seviyesi, sıklığının eşiği ilk aştığı seviyedir.

```
seviye = min{ L ∈ {A1..C2} : flelex_freq[L] ≥ 0.5 }
```

Eşleştirme `(lemma, kelime türü)` çifti üzerinden yapılır. Lexique ve FLELex farklı etiket kümeleri kullandığı için bir dönüşüm tablosu yazılır.

FLELex yaklaşık 17.000 girdi içerir, yani havuzumuzun tamamını kapsamaz. Kapsanmayan kelimeler için sıklık bandına düşülür.

| Birleşik sıklık sırası | Seviye |
|---|---|
| 1 - 600 | A1 |
| 601 - 1.600 | A2 |
| 1.601 - 3.600 | B1 |
| 3.601 - 7.000 | B2 |
| 7.001 - 12.000 | C1 |
| 12.001 ve sonrası | C2 |

Çakışma kuralı: FLELex varsa o kazanır. Ama FLELex ile sıklık bandı iki seviyeden fazla ayrışıyorsa satır `needs_review` işaretlenir. Bu ayrışmalar genelde iki durumda olur, ya kelime öğretim kitaplarında geçmiyordur ama günlük dilde çok kullanılır, ya da tersi.

`level_source` alanına `flelex`, `frequency` veya `manual` yazılır. Bu alan sonradan kalite ölçmeyi kolaylaştırır.

**Çıktı:** `s2_levels.jsonl`

---

### Aşama 3 — İngilizce anlam, okunuş, dilbilgisi bilgisi

**Girdi:** s2_levels.jsonl, kaikki-dictionary-French.jsonl

484 MB'lık dosya satır satır akıtılarak işlenir, belleğe tamamı yüklenmez.

Her kelime için çıkarılanlar:
- **İngilizce tanım:** `senses[].glosses`, en fazla iki tane. Parantez içindeki kullanım etiketleri (`transitive`, `colloquial`, `dated`) tanımdan ayrılıp `register` alanına taşınır
- **IPA:** `sounds[].ipa`, lehçe etiketi olmayan tercih edilir. Bulunamazsa Lexique'in `phon` sütunu bir dönüşüm tablosuyla IPA'ya çevrilir
- **Cinsiyet:** `tags` içindeki `masculine` veya `feminine`. Lexique ile karşılaştırılır, uyuşmazsa satır işaretlenir
- **Çoğul biçim:** `forms[]` içinden
- **Deyim etiketi:** `senses[].tags` içinde `idiomatic` varsa veya `pos == "phrase"` ise

Tanım temizliği önemlidir. Wiktionary tanımları bazen "Alternative form of X" veya "Obsolete spelling of Y" gibi işe yaramaz. Bu kalıplar bir kara listeyle atılır ve sonraki tanıma geçilir.

**Çıktı:** `s3_english.jsonl`

---

### Aşama 4 — Türkçe anlam

Boru hattının en riskli aşaması budur. Dört yol sırayla denenir, ilk başarılı olan kullanılır.

| Sıra | Yol | Güven |
|---|---|---|
| 1 | DBnary Fransızca sürümünden doğrudan `fra → tur` çeviri bağlantısı | 0.95 |
| 2 | DBnary Türkçe sürümünden ters bağlantı `tur → fra` | 0.85 |
| 3 | İngilizce üzerinden köprü, geri çeviri kontrolüyle | 0.55 |
| 4 | Hiçbiri | kelime pakete girmez |

**Üçüncü yolun ayrıntısı.** Fransızca kelimenin İngilizce tanımı tek kelimeyse, DBnary İngilizce sürümünden o İngilizce kelimenin Türkçe karşılıkları alınır. Sonra tersine kontrol yapılır: bulunan Türkçe kelimenin İngilizce karşılıkları arasında çıkış noktamız olan İngilizce kelime var mı. Yoksa aday atılır.

Bu geri çeviri kontrolü köprü yönteminin hatalarının büyük kısmını temizler. Kontrolsüz köprü çeviri kabul edilebilir kalitede değildir.

**Birden fazla aday çıktığında** seçim şöyle yapılır:
1. Birden fazla yoldan gelen aday öne alınır
2. Kalanlar arasından Türkçe sıklık listesinde (`tr_50k.txt`) en sık geçen seçilir

İkinci kural önemlidir. "araba" ile "otomobil" arasında seçim yaparken kullanıcının zaten bildiği yaygın kelimeyi vermek doğru olandır.

Türkçe karşılığı bulunamayan kelimeler pakete alınmaz ama `reports/missing_tr.csv` dosyasına yazılır. Bu dosya sıklık sırasına göre okunur ve en sık geçen eksikler elle doldurulur. Boş karşılıklı kart göstermek uygulamayı bozar, kelimeyi hiç göstermemek ise sadece kapsamı daraltır.

**DBnary dosyaları RDF Turtle biçimindedir ve büyüktür.** Tam RDF ayrıştırıcı kullanmak yavaştır. Sadece çeviri üçlülerini satır bazlı süzmek çok daha hızlıdır.

**Çıktı:** `s4_turkish.jsonl` ve `reports/missing_tr.csv`

---

### Aşama 5 — Örnek cümleler

**Girdi:** s4_turkish.jsonl, Tatoeba sentences.csv + links.csv + sentences_with_audio.csv

Önce bir dizin kurulur: her Fransızca cümlenin İngilizce ve Türkçe çevirileri.

> **Ölçüm sonucu: iki adımlı bağlantı kullanılıyor.** Plan başta sadece doğrudan bağlantıları öngörüyordu. Ölçüm bunun çalışmayacağını gösterdi: 723.290 Fransızca cümlenin sadece 12.245'inin (%1,7) doğrudan Türkçe çevirisi var.
>
> İngilizce üzerinden zincirleme (`fra → eng → tur`) bu sayıyı **259.378'e** çıkarıyor (%35,9), yani **21 kat**. Türkçe çevirisi olan 674.594 İngilizce cümle bu köprüyü mümkün kılıyor.
>
> Anlam kayması riski var, çünkü zincirin iki ucu birbirini doğrudan doğrulamıyor. Üç önlemle sınırlanıyor:
> 1. Doğrudan bağlantı varsa her zaman tercih edilir, iki adımlı sadece yoksa kullanılır
> 2. İki adımlı cümleler `confidence` skorunda daha düşük puan alır, gözden geçirme kuyruğunda öne çıkar
> 3. Köprü olarak kullanılan İngilizce cümlenin birden fazla Türkçe çevirisi varsa o zincir atlanır (belirsizlik işareti)

Bir cümlenin bir kelimeye aday olması için şu koşullar aranır:

1. Cümle hedef kelimeyi içerir (yüzey biçimden lemmaya çeviri Lexique tablosuyla yapılır)
2. Cümle uzunluğu 4 ile 12 kelime arasındadır
3. **Cümlede seviyesi bilinen kelimelerin en yükseği hedef seviyeyi aşmaz**
4. İngilizce çevirisi vardır; Türkçe için doğrudan bağlantı tercih edilir,
   kontrollü iki adımlı bağlantı yedek olarak kullanılabilir

Üçüncü koşul boru hattının en değerli parçasıdır. A1 kelimesini C1 kelimeleriyle dolu bir cümlede göstermek öğretmez, sadece yıldırır. Bu filtre karşılığında kapsam kaybı olur, o yüzden kademeli gevşetme uygulanır.

```
1. deneme: cümledeki max seviye ≤ kelime seviyesi
2. deneme: cümledeki max seviye ≤ kelime seviyesi + 1
3. deneme: cümledeki max seviye ≤ kelime seviyesi + 2
4. deneme: Türkçe çeviri şartı kaldırılır, sadece Fransızca ve İngilizce alınır
5. deneme: cümle bulunamadı, kelime pakete cümlesiz girer
```

Dördüncü basamakta kart Türkçe cümle satırını gizler. Beşinci basamakta kart örnek cümle bölümünü hiç göstermez.

Kalan adaylar puanlanır ve en iyi ikisi saklanır.

```
puan = 2.0 × (sesi var mı)
     + 1.5 × (tam seviye uyumu)
     + 1.0 × (7-10 kelime aralığında mı)
     + 0.5 × (cümledeki kelimelerin ortalama sıklığı)
```

İki cümle saklanmasının nedeni birinin kartta, diğerinin quizin boşluk doldurma sorusunda kullanılmasıdır.

> **Faz 1'de ilk ölçülecek şey:** Tatoeba'da doğrudan Fransızca-Türkçe bağlantılı cümle sayısı. Bu sayı Türkçe örnek cümle satırının var olup olmayacağını belirler. Sayı düşük çıkarsa dördüncü basamak varsayılan hale gelir ve kartlarda Türkçe cümle yerine sadece Türkçe kelime anlamı kalır.

**Çıktı:** `s5_examples.jsonl`

---

### Aşama 6 — Deyimler

**Girdi:** kaikki sözlüğü, DBnary, Tatoeba

Deyim adayları üç işaretten biriyle yakalanır: `pos == "phrase"`, anlam etiketlerinde `idiomatic`, veya Wiktionary kategorilerinde Fransızca deyim kategorisi.

Deyimlerde iki fark vardır.

**Seviye:** FLELex deyimleri neredeyse hiç kapsamaz. Bu yüzden deyimin seviyesi, içindeki kelimelerin en yüksek seviyesinin bir üstü olarak atanır, C2 ile sınırlanır. Mantığı şudur, bir deyimi anlamak içindeki kelimeleri bilmeyi gerektirir ve üstüne mecazı çözmeyi gerektirir.

**Birebir çeviri:** `literal_tr` alanı kelime kelime çeviri birleştirilerek üretilir, ama **her zaman gözden geçirme kuyruğuna girer**. Otomatik üretimin en çok hata yaptığı yer burasıdır ve bu alan tam da deyimin akılda kalmasını sağlayan alandır. 600 deyim elle kontrol edilebilir bir sayıdır.

**Çıktı:** `s6_idioms.jsonl`

---

### Aşama 7 — Fiil çekimi

**Girdi:** kaikki sözlüğünün `forms` alanı, s2_levels.jsonl, Lexique

Fiil seçimi: birleşik sıklık listesinden en sık 600 fiil. Her fiilin seviyesi kelime tablosundan gelir.

**Basit zamanlar** kaikki `forms` listesinden doğrudan okunur: présent, imparfait, futur simple, conditionnel présent, subjonctif présent, impératif. Her form bir etiket kümesiyle gelir, örneğin `['first-person', 'indicative', 'present', 'singular']`. Bu etiketler bizim `tense` ve `person` alanlarımıza bir eşleme tablosuyla çevrilir.

Etiket kümesi eksik veya çelişkili olan formlar atılır. Bir fiilin altı şahsından azı çıkarsa o fiil ve zaman çifti pakete alınmaz, doğrulama aşaması bunu hata olarak bildirir.

**Bileşik zamanlar** bizim yazdığımız kuralla kurulur: passé composé ve plus-que-parfait. Bunun için gereken iki bilgi vardır.

1. Yardımcı fiil seçimi. `être` alan fiiller kapalı bir listedir (aller, venir, partir, sortir, entrer, monter, descendre, naître, mourir, rester, tomber, arriver, retourner, passer, devenir, revenir, rentrer) ve bütün dönüşlü fiiller. Bu liste elle yazılır, yaklaşık 20 satırdır.
2. `être` alan fiillerde geçmiş zaman ortacının özneye uyumu. Kural basittir ve kod ile uygulanır.

Toplam: 600 fiil × 8 zaman × 6 şahıs = **28.800 çekim satırı**.

**Çekimli biçimin okunuşu** Lexique'ten gelir. Lexique bütün çekimli biçimleri fonetik yazımıyla birlikte içerir, yüzey biçim üzerinden eşleştirilir. Bu önemlidir çünkü `parlent` ile `parle` aynı okunur ve öğrenen kişinin bunu görmesi gerekir.

**Örnek cümle** Tatoeba'dan, o çekimli biçimi tam olarak içeren cümlelerden seçilir. Kapsam kısmi olacaktır, bu alan zorunlu değildir.

**Zaman seviyeleri:**

| Zaman | Seviye |
|---|---|
| Présent, passé composé, imparfait, futur proche, impératif | A1 |
| Futur simple, conditionnel présent, plus-que-parfait | A2 |
| Subjonctif présent, conditionnel passé | B1 |
| Subjonctif passé, edilgen çatı | B2 |
| Passé simple, subjonctif imparfait | C1 |

**Lisans notu:** Çekimler kaikki.org üzerinden Wiktionary'den geldiği için diğer kaynaklarla aynı CC BY-SA lisansına tabidir. Ayrı bir copyleft yükümlülüğü doğmaz.

**Çıktı:** `s7_verbs.jsonl`

---

### Aşama 8 — Tema etiketleri

kaikki sözlüğündeki Wiktionary kategorileri elle yazılan bir eşleme tablosuyla on temaya bağlanır (`overrides/theme_map.tsv`). Örnek: `fr:Foods` ve `fr:Beverages` kategorileri `food` temasına gider.

Eşleme tablosu yaklaşık 150 satırdır ve bir saatte yazılır. Eşleşmeyen kelimeler `general` temasına düşer.

Tema isteğe bağlı bir filtredir, buraya fazla emek harcanmaz.

**Çıktı:** `s8_themes.jsonl`

---

### Aşama 9 — Doğrulama

`10_validate.py` bütün aşama çıktılarını birleştirir, `overrides/manual.jsonl` dosyasını en son uygular ve kontrolleri çalıştırır.

**Derlemeyi durduran hatalar:**
- `meaning_tr` veya `meaning_en` boş
- Aynı `(lemma, kelime türü)` çifti iki kez var
- Örnek cümle hedef kelimeyi içermiyor
- İsim için cinsiyet veya tanımlık eksik
- Deyimde `literal_tr` boş
- Çekim satırında biçim boş
- Geçersiz seviye değeri
- Aynı fiil ve zaman için altı şahıstan azı var

**Uyarılar (derleme sürer):**
- Güven skoru 0.6 altında
- Örnek cümlenin seviyesi kelimenin seviyesinden yüksek
- `meaning_tr` altı kelimeden uzun (muhtemelen tanım yazılmış, karşılık değil)
- FLELex ile sıklık bandı iki seviyeden fazla ayrışıyor
- Kelimenin IPA'sı yok

Çıktı `reports/validation.txt` ve `reports/coverage.md` dosyalarıdır. İkincisi seviye başına kaç kelime, kaçında Türkçe karşılık var, kaçında üç dilli cümle var gibi sayıları verir.

---

### Aşama 10 — Veritabanı derleme

`11_build_db.py` birleşik veriyi SQLite'a yazar.

- PLAN.md bölüm 8'deki şema
- `(level, freq_rank)` ve `(theme, level)` üzerinde indeksler
- Sürüm damgası ve içerik özeti `meta` tablosunda
- `VACUUM` çalıştırılır

Çıktı `content/out/content.db`, oradan `assets/db/content.db` konumuna kopyalanır. Beklenen boyut 10-12 MB.

---

## 4. Güven Skoru

Her kelime bir güven skoru alır. Bu skor hangi satırların önce gözden geçirileceğini belirler.

| Bileşen | Puan |
|---|---|
| Türkçe karşılık doğrudan bağlantıdan | +0.45 |
| Türkçe karşılık ters bağlantıdan | +0.40 |
| Türkçe karşılık köprüden (geri kontrollü) | +0.25 |
| İngilizce tanım var | +0.15 |
| Seviye FLELex'ten | +0.15 |
| Seviye sıklık bandından | +0.07 |
| Cinsiyet iki kaynakta uyuşuyor | +0.10 |
| Üç dilli örnek cümle var | +0.15 |

Toplam 1.0 ile sınırlanır. 0.6 altındaki satırlar `needs_review` işaretlenir.

---

## 5. Gözden Geçirme Akışı

Otomatik üretilen içerikte hata olması kaçınılmazdır. Önemli olan hataların düzeltilebilir olması ve düzeltmenin kaybolmamasıdır.

```
review_export.py
   ↓
reports/review_queue.csv        (seviye ve sıklık sırasına göre dizili)
   ↓
Elle düzeltme (Excel veya herhangi bir tablo programı)
   ↓
review_apply.py
   ↓
overrides/manual.jsonl          (boru hattı yeniden çalışsa da korunur)
```

`review_queue.csv` sütunları: `id`, `lemma`, `pos`, `level`, `meaning_en`, `meaning_tr`, `sentence_fr`, `sentence_tr`, `confidence`, `issues`.

Kuyruk şu sırayla dizilir: önce uygulama içinden bayraklananlar, sonra güven skoru düşük olanlar, sonra seviye ve sıklık sırası. Böylece harcanan emek en çok göreceğin kelimelere gider.

**Gerçekçi hedef:** her seviyenin ilk 300 kelimesini elle gözden geçirmek. Altı seviye için 1.800 satır eder. Günde 100 satır bakılırsa üç haftada biter ve bu üç hafta uygulamayı kullanmaya engel değildir, çünkü uygulama zaten çalışıyor olur.

Kalan 8.000 kelime gözden geçirilmeden kalır. Bu kabul edilebilir, çünkü onlara ulaşman aylar sürecek ve o zamana kadar hatayı sen fark edip bayraklayabilecek seviyede olacaksın.

---

## 6. Lisans ve Atıf

| Kaynak | Lisans | Yükümlülük |
|---|---|---|
| Lexique 3.83 | CC BY-SA | Atıf, türev aynı lisansla paylaşılır |
| FLELex | Araştırma için serbest | Atıf, ticari kullanım için izin sorulmalı |
| FrequencyWords içeriği | CC BY-SA 4.0 | Atıf, türev aynı lisansla paylaşılır |
| kaikki.org / Wiktionary | CC BY-SA | Atıf, türev aynı lisansla paylaşılır |
| DBnary | CC BY-SA 3.0 | Atıf, türev aynı lisansla paylaşılır |
| Tatoeba | CC BY 2.0 FR | Atıf |

Yerel araştırma ve öğretim kullanımı dağıtım değildir. Bir APK veya
`content.db` yayımlanmadan önce aşağıdaki dağıtım koşulları ayrıca sağlanır.

**Uygulama dağıtılacaksa** üç şey gerekir.

1. Uygulama içinde bir "kaynaklar" ekranı, yukarıdaki tabloyu ve bağlantıları gösterir
2. `content.db` dosyası CC BY-SA altında paylaşılır (CC BY-SA kaynaklardan türetildiği için)
3. FLELex'in ticari olmayan kullanım şartına uyulur (uygulama ücretsiz olduğu için sorun yok)

FLELex ticari olmayan kullanım için sorunsuzdur. Bu uygulama ücretsiz olacağı için mesele yoktur.

---

## 7. Çalıştırma

**Gereksinimler:** Python 3.12 (kurulu). **Üçüncü taraf paket yok**, her şey standart kütüphaneyle yazılıyor: `urllib` indirme, `bz2` ve `tarfile` açma, `csv` ve `json` okuma, `sqlite3` yazma. Tam RDF kütüphanesine gerek yok, DBnary dosyaları satır bazlı süzülür.

Paket kurulumu gerektirmemesi bilinçli bir tercih. Boru hattı yıllar sonra tekrar çalıştırıldığında bağımlılık çakışmasıyla uğraşmamak için.

```
python tools/01_fetch.py        # kaynakları indirir, yaklaşık 2-3 GB
python tools/02_lemmas.py
python tools/03_levels.py
python tools/04_english.py      # en uzun adım, 484 MB dosya taranır
python tools/05_turkish.py
python tools/06_examples.py
python tools/07_idioms.py
python tools/08_verbs.py
python tools/09_themes.py
python tools/10_validate.py     # rapor üretir, hata varsa durur
python tools/11_build_db.py
```

Her script kendi aşama dosyasını yazar, önceki aşamalar yeniden çalışmaz. Bir aşamada kural değiştiğinde sadece o aşama ve sonrası çalıştırılır.

**Tahmini tam çalışma süresi:** dizüstü bilgisayarda 20-40 dakika. İndirme hariç.

---

## 8. Aşamaların Riskleri

| Aşama | Risk | Ne yapılır |
|---|---|---|
| 2 (Seviye) | FLELex havuzun yarısını kapsamaz | Sıklık bandı yedeği hazır, kapsama oranı `coverage.md` içinde ölçülür |
| 4 (Türkçe) | Kapsam beklenenin altında çıkar | Köprü yolunun geri kontrol eşiği gevşetilir, en sık eksikler elle doldurulur |
| 5 (Cümle) | Fransızca-Türkçe doğrudan bağlantı az çıkar | Kademeli gevşetme zaten planda, en kötü durumda Türkçe cümle satırı kartlardan kalkar |
| 6 (Deyim) | Birebir çeviriler bozuk çıkar | 600 satırın hepsi zaten gözden geçirme kuyruğunda |
| 7 (Fiil) | Bileşik zaman kuralında hata | Yirmi fiil için sonuç elle karşılaştırılır, uyum kuralı birim testiyle korunur |

Her aşamanın çıktısı ayrı dosya olduğu için bir aşamadaki sorun diğerlerini bloklamaz. Örneğin Türkçe kapsam düşük çıksa bile örnek cümle aşaması çalışmaya devam eder.

---

## 9. İlk Adım

Faz 1'e başlarken sırayla şunlar yapılır.

1. `01_fetch.py` yazılır ve kaynaklar indirilir
2. **Ölçüm yapılır:** Tatoeba'da doğrudan Fransızca-Türkçe bağlantılı cümle sayısı, FLELex'in Lexique havuzunu kapsama oranı, DBnary'de Fransızca-Türkçe doğrudan çeviri sayısı
3. Bu üç sayı planın kalanını ayarlar. Hepsi beklenenin üstündeyse hedefler yükseltilir, altındaysa yedek yollar varsayılan hale gelir
4. Sonra boru hattı **sadece A1 için** uçtan uca çalıştırılır. Küçük veriyle bütün aşamalar doğrulanır
5. A1 çıktısı doğru göründüğünde altı seviye için tam çalıştırma yapılır

Dördüncü adım önemlidir. On bin kelimeyi işleyip sonra bir kural hatası bulmak yerine 800 kelimeyle bütün zinciri denemek çok daha hızlıdır.


## Ek: 2026-08-10 ikinci tur düzeltmeleri

Uygulama telefonda denenince iki ciddi sorun çıktı ve boru hattına döndük.

### Aşama 4'te eşik hatası

`être` sözlükte hiç yoktu. Fransızcanın en sık fiili, uygulamada yok.
Nedeni tek tek bakınca çıktı:

| Yol | `être` için durum |
|---|---|
| Fransızca DBnary'de doğrudan çeviri | kayıt **yok** |
| Türkçe DBnary'den ters çeviri | kayıt **yok** |
| İngilizce köprü (`eng:be__Verb__1`) | `olmak`, `bulunmak`, `var` **var** |

Yani tek yol köprüydü ve köprünün kabul eşiği onu kesiyordu. İlk turda
çok anlamlı pivotların ağırlığını düşürmüştük (`1/log2(2+n)`); "be" gibi
bir pivot 0,3 civarı puan üretiyor, mutlak eşik ise 1,5 istiyordu. Bu eşiğe
ancak beş ayrı pivot aynı karşılığı gösterirse ulaşılıyordu.

Sonuç: havuzun **%71'i (23.482 lemma) karşılıksız** kalmıştı ve elenenler
rastgele değildi — en sık kelimeler sözlüklerde en çok anlamlı olanlar
olduğu için tam da onlar eleniyordu.

Çözüm: mutlak puan eşiği kaldırıldı, yerine **kanıt sayısı** kondu.

| Yol | Ölçüt | Güven |
|---|---|---|
| `direct` | Fransızca Wiktionary'de doğrudan | 0,95 |
| `reverse` | Türkçe Wiktionary'den ters | 0,85 |
| `bridge_verified` | köprü + bağımsız geri kontrol | 0,75 |
| `bridge_supported` | ≥2 ayrı pivot ya da ≥2 ayrı kayıt | 0,55 |
| `bridge_weak` | tek tanık | 0,40 |

`bridge_weak` kayıtlar `needs_review=1` alır ve kartta "gözden geçirilmedi"
rozetiyle görünür.

Aday seçimi de düzeltildi: kanıt sayısı eklendikten sonra köprü adayları
`direct` adaylarını geçmeye başlamıştı. Artık önce yol kalitesi
(direct > reverse > bridge), sonra kanıt sayısı bakılıyor.

Ayrıca Türkçe tarafta Wiktionary bağ markupu sızıyordu
(`[[ne]] … [[ne]]`, `[[geri]] [[koymak]]`); temizlendi.

**Sonuç:** A1 kapsaması %61,1 → **%80,4**, havuz 9.670 → 17.469 lemma.

### Aşama 4.5 — elle yazılan karşılıklar

`12_manual_tr.py` eklendi. `manual.json` artık sadece düzeltmiyor, **ekliyor**
de: havuzda hiç karşılığı olmayan bir lemma için elle Türkçe yazılırsa,
seviyesi/türü/IPA'sı/İngilizcesi `s3_english.jsonl`'dan alınarak havuza
katılıyor. Bu aşama `08_examples.py`'den önce çalışmalı, yoksa eklenen
kelimeye örnek cümle bağlanmıyor.

İlk turda **217 A1/A2 kelimesi** elle yazıldı (`comme`, `nouveau`, `changer`,
`peu`, `mieux`, `gens`, `oeil`, `nuit`, `écrire`…) ve **25 sık kelimenin**
yanlış karşılığı düzeltildi (`le → sizin`, `oui → efendim`, `bras → silah`,
`même → eşit`, `alors → buradan`…).

**Son durum:** 17.746 kelime · A1 2.064 · 19.201 örnek cümle · 11,8 MB.


## Ek: 2026-08-11 üçüncü tur — deyimler, fiiller, gürültü

Telefonda "deyimler, fiiller, hareket prototipi hep aynı listeyi gösteriyor"
denince üç ayrı hata çıktı.

### 1. Deyim işareti yanlıştı

`06_english.py` içindeki `is_idiomatic()` "kelimenin herhangi bir anlamı
deyimsel mi" diye bakıyordu. `avoir`, `quoi`, `couper` gibi tek kelimeler
böylece deyim sayıldı ve deyim destesi normal desteden farksız göründü.

Düzeltme: tek kelimelik lemma deyim olamaz (kaynakta ve `13_build_db.py`'de
iki kez kontrol ediliyor).

### 2. Deyim havuzu zaten çok küçüktü

09_idioms.py 526 kalıp çıkarmıştı ama Türkçesi sadece 60'ına ulaşmıştı ve
ulaşanların bir kısmı yanlıştı (`pas mal → ceza`, `en direct → yaşamak`).

`content/overrides/idioms.json` eklendi: **çıkar / düzelt / ekle** üç bölümlü
elle küratörlü katman. 75 gerçek gündelik kalıp elle yazıldı (`avoir besoin
de`, `il y a`, `s'il vous plaît`, `faire la queue`, `coup de foudre`,
`tomber dans les pommes`…), her birinde birebir çeviri de var — deyimin neden
mantıksız göründüğünü göstermek akılda kalmasını kolaylaştırıyor.

**Sonuç: 63 → 128 deyim**, hepsi çok kelimeli, 81'i elle doğrulanmış.

### 3. Deyimlerin örnek cümlesi yoktu

`08_examples.py` cümleleri lemma indeksine göre eşliyor; çok kelimeli kalıp
bu indekse hiç düşmüyordu. Kalıpları ilk kelimelerine göre gruplayıp sadece o
kelimeyi içeren cümlelerde alt dizi araması yapan bir geçiş eklendi.
**128 kalıbın 85'inde** artık üç dilli örnek cümle var.

### 4. `être` çekim tablosunda yoktu

Fiil listesi `s4_turkish.jsonl`'dan türüyor; `être` oradan düştüğü için
çekimi de yoktu. Aşama 4 düzeltilip elle eklendikten sonra `10_verbs.py`
yeniden çalıştırıldı: **1.477 → 2.434 fiil, 66.447 → 109.512 çekim**,
`être` dahil (je suis, tu es, il est, nous sommes, vous êtes, ils sont).

### 5. Nadir kelime gürültüsü

Tek tanıklı köprü yolu zaman zaman sözlükte kalmış eski/teknik kelimeler
getiriyordu: 17 ayrı Fransızca kelime `teşevvüş` ile eşleşmişti. Türkçe 50k
sıklık listesinde hiçbir parçası geçmeyen aday artık eleniyor.

Bu filtre önce bütün köprü adaylarına uygulandı ve doğrulanmış sağlam
karşılıkları da eledi (A1 kapsaması %80,4 → %77,5). Sadece **tek tanıklı**
adaylara uygulanacak şekilde daraltıldı: kanıt varsa nadir kelime de kabul.


### 6. Yaygın kelime tercihi

Köprü yolu bazen İngilizce pivotun **baskın olmayan** anlamını getiriyordu.
En net örnek: 15 ayrı Fransızca kelime `oğlak` ile eşleşmişti. Zincir şuydu:

```
gosse / gamin / môme  →  ingilizce "kid"  →  türkçe { çocuk, oğlak }
```

Seçim sırasında `verified` (bağımsız geri kontrol) sıklıktan önce
geliyordu. Türkçe Wiktionary `oğlak → kid` bağlantısını doğruluyor,
`çocuk → kid` bağlantısını doğrulamıyordu; sonuç: nadir olan kazanıyordu.

Düzeltme: aynı yol kalitesindeki adaylar arasında **Türkçenin en sık
10.000 kelimesinde geçen** aday, doğrulanmış ama nadir olana tercih edilir.
Dil öğreten bir uygulamada günlük kelimeyi göstermek doğrudur.

`oğlak` ve `teşevvüş` gitti, yerlerine `çocuk` geldi.


## Aşama 8 — Kelime aileleri (`15_families.py`)

Kaikki her madde için iki alan taşıyor:

```
chanter  derived: chantable, chantage, chanteur, chantonner, déchanter
         related: chant, chanson, chantre, enchanter, incantation
```

İkisi birleştirilip yönsüz bir komşuluk grafiği kuruldu.

**Bilinçli karar: bağlantılı bileşen (transitive closure) kullanılmadı.**
Zincirleme birleştirme yapılırsa `faire` gibi üretken bir kök yüzlerce
kelimeyi tek aileye toplar ve "aynı kökten" bilgisi anlamını yitirir. Her
kelime yalnızca **doğrudan** komşularını taşır; ekranda gösterilen tam
olarak budur.

Havuzda olmayan akrabalar atılır — kullanıcıya sözlükte bulunmayan bir
kelimeyi göstermenin anlamı yok.

**Sonuç:** havuzun %32'si (4.921 kelime) en az bir akrabaya sahip,
toplam 7.560 bağ. Veritabanında `word_relations` tablosunda durur ve
açılışta belleğe alınır (birkaç yüz kilobayt).


## Aşama 9 — Dönüşlü fiiller (`16_reflexives.py`)

Dönüşlü fiil, temel fiilin `se` almış hâli **değildir**; çoğu zaman başka
bir fiildir. Otomatik üretim burada anlam kayması yapar:

| Temel | Dönüşlü |
|---|---|
| rendre — geri vermek | se rendre — gitmek, teslim olmak |
| rappeler — geri çağırmak | se rappeler — hatırlamak |
| passer — geçmek | se passer — olmak, yaşanmak |
| attendre — beklemek | s'attendre à — ummak |
| tromper — aldatmak | se tromper — yanılmak |
| entendre — duymak | s'entendre — anlaşmak |

Bu yüzden **Türkçe karşılıklar ve tür bilgisi elle yazıldı** (132 fiil).
Otomatik olan tek şey çekim: o tamamen kurala bağlı olduğu için üretmek
elle yazmaktan daha güvenli.

### Üretilen çekim kuralları

1. Basit zamanlar: zamir + temel çekim (`je me lave`).
2. Elizyon: `me/te/se` → `m'/t'/s'` ünlü önünde (`je m'appelle`).
3. Bileşik zamanlar **her zaman** `être` ile — temel fiil `avoir` alsa bile.
4. Ortaç uyumu: zamir düz nesneyse uyum var (`lavé(e)`), dolaylıysa yok
   (`se sont parlé`). Bu ayrım listede elle işaretlendi.
5. Emir kipi: zamir arkaya, `te` → `toi` (`lève-toi`).

### Çıkan iki hata ve düzeltmeleri

- Kaikki bazı fiillerin çekimini **zaten dönüşlü** taşıyor
  (`souvenir` → "me souviens"). Kendi zamirimizi eklemeden önce
  oradakini söküyoruz; yoksa "me me souviens" çıkıyordu.
- `-s`/`-x` ile biten ortaç çoğul `-s` almaz: `assis` → `assis`,
  "assiss" değil.

### Veritabanı

Dönüşlüler `verbs` tablosunda **kendi satırlarında** durur; `se rendre`
ile `rendre` ayrı fiillerdir. Ek alanlar: `is_reflexive`,
`base_infinitive`, `reflexive_kind` (reflechi/reciproque/essentiel/sens),
`note_tr` (temel fiille anlam farkı).

**Sonuç:** 132 dönüşlü fiil, 5.902 çekim satırı.

### Yan düzeltme

Dönüşlüler eklenince 11 fiilin temel hâli ile dönüşlü hâli aynı Türkçeyi
taşıyor çıktı. Sebep, temel fiilin **geçişli** anlamının kaybolmuş
olmasıydı: `asseoir` "oturmak" yazıyordu, oysa "oturtmak"tır. Altı temel
fiil düzeltildi (asseoir, marier, approcher, reposer, brûler, taire).
Kalan yedisi gerçekten aynı (`se moquer`, `s'enfuir` gibi yalnızca
dönüşlü olanlar).

Ayrıca `13_build_db.py` artık elle düzeltmeleri **fiil tablosuna da**
uyguluyor: tek doğru kaynak `manual.json` olsun, kelime kartı ile fiil
kartı farklı şey söylemesin.
