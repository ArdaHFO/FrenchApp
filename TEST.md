# Adım adım test yönergesi

İki yol var. **Yol A** en hızlısı: telefona bir dosya atıp kuruyorsun,
bilgisayara kablo bağlamana gerek yok. **Yol B** geliştirme yolu: kabloyla
bağlayıp bilgisayardan çalıştırıyorsun, animasyon ölçümü ancak böyle yapılır.

---

## Yol A — APK'yı telefona kur (5 dakika)

### A1. Dosyayı telefona geçir

Önce proje kökünde yerel test APK'sını üret:

```powershell
flutter build apk --debug
```

Kurulacak dosya `build/app/outputs/flutter-apk/app-debug.apk`. Telefona
geçirmenin üç yolu, hangisi kolaysa:

- **OneDrive ile:** APK'yı OneDrive'da uygun bir klasöre kopyala ve telefondaki
  OneDrive uygulamasından indir.
- **USB kablo ile:** Telefonu tak, bildirimden "Dosya aktarımı (MTP)" seç,
  bilgisayarda telefonun `Download` klasörüne kopyala.
- **WhatsApp/Telegram ile:** Kendine "Kaydedilenler" sohbetinde gönder,
  telefondan indir.

### A2. Bilinmeyen kaynağa izin ver

APK Play Store'dan gelmediği için Android bir kez izin ister.

1. Telefonda dosyaya dokun (Dosyalar → İndirilenler → `app-debug.apk`).
2. "Güvenlik nedeniyle telefonun bu kaynaktan gelen uygulamaları kurmasına
   izin verilmiyor" uyarısı çıkarsa → **Ayarlar** düğmesine bas.
3. Açılan ekranda **"Bu kaynaktan izin ver"** anahtarını aç.
4. Geri dön, **Yükle** → **Aç**.

> Play Protect "bilinmeyen geliştirici" uyarısı verirse **Yine de yükle**
> de. Uygulama hata ayıklama anahtarıyla imzalı, Google'ın tanıdığı bir
> yayıncı imzası yok — beklenen durum.

Ana ekranda **FrenchApp** adıyla, mavi zemin üstünde iki eğik beyaz kart
simgesiyle görünür.

---

## Yol B — Bilgisayardan çalıştır (geliştirme)

Telefonda **Geliştirici seçenekleri** ve **USB hata ayıklama** açık olmalı:
Ayarlar → Telefon hakkında → **Yapı numarasına 7 kez** dokun → geri → Sistem
→ Geliştirici seçenekleri → USB hata ayıklama açık.

Telefonu tak, çıkan "USB hata ayıklamasına izin verilsin mi?" penceresinde
**İzin ver**. Sonra yeni bir PowerShell aç:

```powershell
cd "$env:USERPROFILE\OneDrive - University of Luxembourg\Desktop\FrenchApp"
flutter devices          # telefonun listede göründüğünü doğrula
flutter run --debug      # kurar ve başlatır
```

Animasyonu ölçmek istersen `--debug` yerine `--profile` kullan; terminalde
çıkan DevTools bağlantısını tarayıcıda aç, Performance sekmesine geç.
**Ölçümü emülatörde yapma, yanıltır.**

---

## Test senaryosu — 15 dakikada her şeye dokun

Sırayla git; her adımda ne görmen gerektiğini yazdım.

### 1. İlk açılış ve seviye seçimi

- Uygulama **koyu** temayla açılır, açılışta beyaz parlama olmamalı.
- Altı seviye kartı (A1…C2) sırayla aşağıdan yukarı süzülerek gelir.
- **A1**'i seç → "Başla" ile devam et.
- İstersen **Seviyeni ölç** ile 20 soruluk yerleştirme testini dene: doğru
  bildikçe sorular zorlaşır, yanlışta kolaylaşır, sonunda bir seviye önerir.

### 2. Kaydırma — asıl olay burası

Kelimeler sekmesinde **Oturumu başlat**.

| Hareket | Beklenen |
|---|---|
| Yavaşça sağa sürükle | Kart parmağını takip eder, hafifçe döner, **yeşil** "ÖĞRENDİM" rozeti büyüyerek belirir |
| Yarı yolda bırak | Kart yaya benzer bir hareketle **ortaya geri döner**, hafif salınır |
| Eşiği geçip bırak | Kart ekrandan uçar, arkadaki kart öne gelip büyür |
| Sola kaydır | **Sarı** "TEKRAR" rozeti, kart destede geride bir yere geri konur |
| Yukarı kaydır | **Yıldız** — kelime "Yıldızlılar" destesine girer |
| Karta dokun | Kart 3B döner, arka yüzde **EN** ve **TR** anlamlar + aynı cümlenin çevirileri |
| Uçarken hemen tekrar tut | Animasyon durur, kart **anında parmağına yapışır** — takılma olmamalı |
| Alt kenardan tut ve sürükle | Kart **ters yöne** eğilir (üstten tutmakla farkı hisset) |

Kartın üst köşesindeki hoparlör simgesi Fransızca telaffuzu okur. Ses
gelmiyorsa telefonda Fransızca TTS dili yüklü değildir: Ayarlar → Erişilebilirlik
→ Metin okuma çıkışı → dilleri yükle → Français.

**Geri al**: yanlış kaydırdıysan üstteki geri oku son kartı geri getirir.

### 3. Özel desteler

Kelimeler sekmesinin altında:

- **Zorlandıklarım** — altı kez bilemediğin kelimeler (başta boş, normal)
- **Yıldızlılar** — az önce yukarı kaydırdıkların burada olmalı
- **Deyimler ve kalıplar** — 128 kalıp, her seviyeden. `avoir faim`,
  `s'il vous plaît`, `coup de foudre` gibi. Arka yüzde birebir çeviri de var:
  `tomber dans les pommes` = "elmaların içine düşmek" = bayılmak.
> Hareket laboratuvarı artık burada değil: **İlerleme → Ayarlar → Hareket
> laboratuvarı**. Orada 10 kartı 120 ms arayla kaydıran stres testi var;
> her kart bir öncekinin uçma animasyonu bitmeden gelir. **Takılma, atlama,
> kilitlenme olmamalı.**

### 4. Sözlük araması

Kelimeler sekmesinin sağ üstündeki **büyüteç**.

- `etre` yaz → aksansız yazmana rağmen **être** çıkmalı.
- `gitmek` yaz → Türkçe tam anlamdan **aller** ilk sıralarda çıkmalı ve
  **Türkçe → Fransızca** yönü görünmeli.
- `kadin` yaz → Türkçe aksanı yazmadan **femme** çıkmalı.
- **Türkçe → Fransızca** filtresini seç → yalnızca Türkçe anlam alanında
  aramalı; **Fransızca → Türkçe** filtresi yalnızca Fransızca başlığı aramalı.
- Bir sonuca dokun → alttan açılan sayfada IPA, anlamlar, örnek cümle,
  etiketler ve **aynı kökten gelenler** görünür.
- Aile kelimelerinden birine dokun → o kelimenin sayfası açılır. `chanter`
  → `chanson` → `chant` diye kök boyunca gezebilirsin.

### 5. Fiiller

- Zaman seç (présent, passé composé, imparfait, futur simple…).
- Kart ön yüzünde mastar + şahıs, dokununca çekim.
- Kartta "Tam tablo" ile o fiilin altı şahsının hepsi görünür.
- Sayfanın en altındaki **Çekim tabloları** ile bir fiilin **sekiz zamanı**
  yan yana: `aller` ara → je vais / j'irai / j'allais / que j'aille yan yana.
- Elizyonu kontrol et: `je` + `ai` → **j'ai** yazmalı, "je ai" değil.
- `être` çekimi: je suis / tu es / il est / nous sommes / vous êtes / ils sont.

**Dönüşlü fiiller.** "Fiil türü" satırından **Dönüşlü**'yü seç, oturumu başlat:

- Kartın arka yüzünde sarı kutu: fiilin türü (dönüşlü / karşılıklı /
  yalnızca dönüşlü / anlamı değişir) ve temel fiille farkı.
- Çekim tablosunda `se laver` ara: `je me lave`, passé composé
  `je me suis lavé(e)` — **avoir değil être** almalı.
- `se rappeler` ara: passé composé `je me suis rappelé` (ortaç uyum
  almaz), kutuda "rappeler geri çağırmak, se rappeler hatırlamak" yazmalı.
- Emir kipinde özne zamiri olmamalı: **lève-toi**, "tu lève-toi" değil.
- Subjonctif artık `que je me lave` diye görünüyor.

### 6. Dilbilgisi

19 ders, seviyeye göre gruplu:

- **A1 (6):** présent düzenli, présent düzensiz, futur proche,
  passé composé, imparfait, impératif
- **A2 (4):** futur simple, olumsuzluk, nesne zamirleri (le/la/lui/leur),
  tanımlıklar (le / un / du farkı)
- **A2 (+1):** dönüşlü fiiller (se lever, s'appeler)
- **B1 (2):** conditionnel, subjonctif
- **B2 (3):** `y` ve `en`, dolaylı anlatım + zaman uyumu,
  participe/gérondif + edilgen çatı
- **C1 (2):** passé simple ve edebî zamanlar, vurgu (`c'est ... qui`)
- **C2 (1):** kayıt düzeyleri (soutenu / courant / familier)

Her dersin sonunda küçük bir alıştırma ve cevapları var.
- Bir derse gir, tablolar düzgün hizalanmalı.
- Dersin sonundaki bağlantı seni o zamanın çekim destesine götürür.

### 7. Macera, cümle atölyesi ve yolculuk haritası

**Macera** sekmesini aç.

- Dünya kartındaki yol arkadaşına dokununca **Karakter Stüdyosu** açılmalı.
  Lumi/Moka seçimi, beş renk ve açık aksesuarlar anında önizlemeye ve üst XP
  çubuğuna yansımalı; uygulama yeniden açıldığında seçim korunmalı.
- Pipou, Nox, kulaklık ve taç üzerinde gereken oyuncu seviyesi görünmeli.
  Kilitli seçime dokununca seviye uyarısı çıkmalı.
- Karakter nefes almalı, göz kırpmalı ve el sallamalı. Azaltılmış hareket
  açıkken sakin ve sabit durmalı.
- **Nasıl oynanır?** paneli mod seç → görevi bitir → XP kazan akışını açıkça
  göstermeli; dar telefonda yazılar taşmamalı.

- Seçili seviyenin **Hikâye Dünyası**nı aç. İlk bölüm açık, ikinci bölüm
  kilitli olmalı; ilk bölüm bitince ikinci bölüm otomatik açılmalı.
- Bir hikâyeyi başlat. Normal ve yavaş ses düğmelerini dene.
- **Dinleme modu** ile metni gizle; kelime çipine dokunup anlamını aç.
- İki farklı diyalog seçimini dene ve koç notunun değiştiğini doğrula.
- Bölüm sonundaki sınavı tamamla; ilerleme ve XP'nin kaydolduğunu kontrol et.
- **Cümle Atölyesi** içinde doğru ve kasıtlı hatalı birer cevap yaz. Artikel,
  çekim, edat veya kelime sırası geri bildirimlerinin ayrı göründüğünü doğrula.
- A1-C2 seviye çiplerinin her birinde ayrı hikâye ve senaryolar açılmalı.

Ardından **Ders Yolculuğu** bağlantısını aç. Yukarıdan aşağı kıvrılan bir yol,
üzerinde duraklar görünür.

- Sadece ilk durak açık, kalanlar **kilitli**. Kilitliye dokununca uyarı çıkar.
- Bulunduğun durağın etrafında **nabız gibi atan bir halka** var.
- Haritayı ilk açtığında **yol yukarıdan aşağı çizilir**, duraklar sırayla oturur.
- Bir durağa dokun: önce **tanıtım sayfası** (kaç soru, neyden, en iyi skorun).
- **%70** geçmek için yeter, **hatasız** üç yıldız.
- Yanlış şıkta kutu **titrer**, doğruda onay simgesi büyüyerek gelir.
- Durağı geçince **parçacıklar saçılır** — kaybedince saçılmaz.
- Haritaya dönünce **gezgin yol boyunca yürüyerek** yeni durağa geçer,
  harita onu takip eder, telefon hafifçe titrer.
- Quizde üç doğruyu üst üste yaparsan **kombo rozeti** çıkar; 5'te sarıya,
  8'de turuncuya döner. Yanlışta sıfırlanır.
- Doğru cevapta hafif, yanlışta belirgin **titreşim**.
- Geçince harita yenilenir: düğüm dolar, yol o parçada renklenir, bir
  sonraki durak açılır.
- Her seviyenin sonunda **sınav durağı** (kupa simgesi): 12 soru, %80 gerek.
- Sağ üstteki karıştır simgesi eski **serbest quizi** açar — o hâlâ SRS
  havuzundan, yani sadece bildiğin kelimelerden soruyor.

Duraklar: kelime · deyim · fiil · sınav. Renkleri seviyeye göre.

### 7b. Serbest quiz

Kaydırma oturumunda **en az 8-10 kelimeyi sağa** kaydırdıktan sonra
Yolculuk → karıştır simgesine gir (havuz sağa kaydırdıklarından oluşur).

Dört soru tipi dönüşümlü gelir:

- Fransızca kelime → Türkçe anlam (4 şık)
- Türkçe anlam → Fransızca kelime
- Cümlede boşluk doldurma
- Fiil çekimi: verilen şahıs için doğru çekim

Doğru şıkta yeşil dolgu + onay, yanlışta kırmızı titreme ve doğrunun
gösterilmesi olmalı.

### 7c. Şarkı Sahnesi

**Macera → Şarkı Sahnesi** yolunu aç.

- Vitrin, arama ve **Tümü / Modern / Geleneksel / A1 / A2 / B1** filtreleri
  görünmeli. Modern listede altı; geleneksel koleksiyonda yedi karaoke videosu
  ve üç zamanlı tam-söz kaydı bulunmalı.
- Aramaya `umut` yazınca Indila — Dernière danse; `neşe` yazınca ZAZ — Je veux
  görünmeli. `lahanalar` araması Savez-vous planter les choux sonucunu vermeli.
- Modern parçaya girince resmî YouTube videosu açılmalı. Varsa **CC** ile
  Fransızca altyazı seçilebilmeli. Video ilerlerken sabit boylu **Canlı söz +
  anlam** kartındaki Türkçe kelime akmalı; karta dokununca telaffuz ve desteye
  kaydetme açılmalı.
- **Kelime kelime** filtresinde Frère Jacques, Sur le pont d'Avignon ve
  Alouette görünmeli.
- Parçaya girince ses otomatik başlamamalı. Oynat düğmesine basınca internetten
  yüklenmeli; yükleme sırasında dönen gösterge görünmeli.
- Süre ilerledikçe etkin söz satırı renklenmeli. Satırın zamanına dokununca
  oynatma o noktaya gitmeli.
- Bir kelimeye dokununca Türkçe anlamı ve telaffuz düğmesi açılmalı. Ana
  sözlükte bulunan kelimelerde **Kelime desteme ekle** çalışmalı.
- Şarkı oyunundaki beş soruyu bitirince sonuç, XP ve günlük ilerlemeye işlenmeli.
- İnterneti kapatıp oynata basınca uygulama çökmemeli; bağlantı uyarısı vermeli.

### 8. İlerleme

- **Günlük seri** kartı (bugün çalıştıysan 1 gün) — alev nefes alıyor
- **Son 30 gün ızgarası**: dolu kareler çalıştığın günler, koyusu daha
  çok kart. Çerçeveli kare bugün. Kareye basılı tut, o günün sayısı çıkar.
- **Kutu dağılımı** — kaydırdıkça sağa doğru dolar
- **Seviye çubukları**
- Ayarlar: seviye değiştir, **animasyon hızı** (0.75x / 1x / 1.25x),
  kart ön yüzünde örnek cümle anahtarı, kaynaklar ekranı

Animasyon hızını 0.75x yapıp kaydırmaya geri dön — fark net hissedilmeli.
Beğendiğin hız hangisiyse söyle, varsayılanı ona çekerim.

### 8b. Yedekleme — bunu bir kez dene

**İlerleme → Ayarlar → Yedekleme**

1. **Yedek al**: dosya `Android/data/.../files/frenchapp-*.json` altına
   yazılır ve aynı anda panoya kopyalanır. Yol ekranda görünür.
2. Metni bir yere (kendine WhatsApp mesajı, not defteri) kaydet.
3. Geri yüklemeyi denemek istersen: **Panodan al** → **Geri yükle**.
   Uyarı çıkar çünkü **birleştirme yapmaz, üzerine yazar**.
4. Geri yükledikten sonra uygulamayı kapatıp aç.

Yedek; kart durumlarını, günlük seriyi, harita ilerlemesini, işaretlediğin
hataları ve ayarları taşır. İçerik veritabanı yedeklenmez, o zaten
uygulamayla geliyor.

### 9. Kalıcılık — bunu atlama

1. Birkaç kart kaydır, birkaç quiz çöz.
2. Uygulamayı **tamamen kapat** (son uygulamalardan yukarı sürükle).
3. Yeniden aç.

İlerleme, seri, seviye, ayarlar **aynen durmalı**. Durmuyorsa bu bir hata,
bana söyle.

### 10. İçerik hatası bildirme

İçerik otomatik üretildi, hatalı Türkçe karşılık **çıkacaktır** — 15.423
kelimenin hepsi elle gözden geçirilmedi. Bir kısmı tek kaynağa
dayandığı için "gözden geçirilmedi" işaretli; kartta sarı uyarı rozetiyle
görünürler.

Yanlış bir kart görürsen: karta dokun (arka yüz) → sağ alttaki **bayrak**
simgesine bas. Sarıya döner ve kaydedilir. İşaretlediklerinin sayısı
İlerleme → Ayarlar'ın altında görünür.

Bir hafta kullanıp işaretlediklerini bana ilettiğinde
`content/overrides/manual.json` düzeltme katmanına eklerim ve veritabanını
yeniden üretirim; **ilerlemen silinmez**, içerik ve ilerleme ayrı
veritabanlarında duruyor.

---

## Sorun çıkarsa

| Belirti | Sebep / çözüm |
|---|---|
| "Uygulama yüklenmedi" | Eski bir sürüm kuruluysa önce kaldır, sonra kur |
| Play Protect engelliyor | "Ayrıntılar" → "Yine de yükle" |
| Ses gelmiyor | Fransızca TTS dili yüklü değil (bkz. bölüm 2) |
| Türkçe cümle satırı yok | Normal: Fransızca cümlelerin %81'inde Türkçe var, kalanında satır gizleniyor |
| `flutter devices` telefonu görmüyor | USB hata ayıklama kapalı ya da telefondaki izin penceresi onaylanmadı |
| Açılış birkaç saniye sürüyor | İlk açılışta 15,2 MB veritabanı cihaza kopyalanır, sadece bir kez olur |

---

## Bana ne söylemen faydalı

1. **Animasyon** — nerede ağır/takık hissettin, hangi hız iyi geldi
   (senin için en önemlisi buydu, en çok bunu duymak istiyorum)
2. **İçerik** — bayrakladığın kartlar
3. **Eksik** — hangi ekranda "şu da olmalıydı" dedin

Not: Hiçbir şey commit'lenmedi. `git init` yapıldı, dosyalar hazır ama
istemeden commit atmadım. "Commit'le" dersen atarım.
