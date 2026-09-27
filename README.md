# FrenchApp

Kaydırmalı kart mantığıyla Fransızca kelime, deyim, fiil çekimi ve dilbilgisi
öğreten Android uygulaması.

- Ürün ve teknik plan: [PLAN.md](PLAN.md)
- İçerik veri boru hattı: [DATA_PIPELINE.md](DATA_PIPELINE.md)
- Ölçüm ve aşama raporları: [content/reports/](content/reports/)

## Durum

Uygulama çalışır durumda ve **gerçek içerikle** dolu.

| | |
|---|---|
| Kelime | **15.423** (128 deyim dahil) |
| Örnek cümle | **17.832** (14.525'inde Türkçe de var) |
| Fiil | **2.698** (132 dönüşlü dahil) |
| Çekim satırı | **121.354** (8 zamana kadar × 6 şahıs) |
| Dilbilgisi dersi | **19** (A1'den C2'ye) |
| Kelime ailesi bağı | **7.560** (4.921 kelime) |
| Veritabanı boyutu | 23,2 MB |

### Çalışan ekranlar

- **Seviye seçimi** — 6 seviye + 20 soruluk uyarlanabilir yerleştirme testi
- **Kelimeler** — seviye/tema filtresi, SRS bağlı kaydırma oturumu,
  Zorlandıklarım / Yıldızlılar / Deyimler desteleri, sözlük araması
- **Fiiller** — zaman seçimi, çekim kartları, **dönüşlü fiil** süzgeci,
  **çekim tabloları** ekranı ve zamir/çekim/combo odaklı **Dönüşlü Fiil Arenası**
- **Dilbilgisi** — 19 ders (A1-C2), tablolarıyla, ilgili çekim destesine geçiş
- **Macera** — A1-C2 için toplam 12 dallanan bölüm, bölüm kütüphanesi ve
  sırayla kilit açma; normal/yavaş seslendirme, metni gizleyen dinleme modu,
  dokunulabilir kelime açıklamaları ve bölüm sınavı
- **Cümle Atölyesi** — Türkçe durumdan serbest Fransızca üretim; kabul edilen
  farklı cevaplar ve artikel/çekim/edat/kelime sırası odaklı geri bildirim
- **Şarkı Sahnesi** — altı modern Fransızca hit ve yedi geleneksel karaoke
  videosu için YouTube oynatıcısı, canlı yazı/CC, müzikle ilerleyen Türkçe anlam
  kartı ve A1–B1 filtreleri; ayrıca üç açık lisanslı kayıtta zamanlı tam söz,
  Türkçe kelime anlamları, desteye kaydetme ve XP oyunu; internet videoları ve
  ses kayıtları APK'ya gömülmez
- **Ders Yolculuğu** — Macera merkezinden açılan kıvrımlı harita; her durak bir
  quiz, geçince sonraki açılıyor ve yıldız kazandırıyor
- **Quiz** — 4 soru tipi, kurala göre çeldirici (haritadan bağımsız
  serbest mod olarak da duruyor)
- **İlerleme** — günlük seri, **30 günlük etkinlik ızgarası**, kutu
  dağılımı, seviye çubukları, **XP/oyuncu seviyesi**, coin, günlük görevler,
  başarımlar, **Karakter Stüdyosu**, **yedekleme**, ayarlar
- **Sözlük** — çift yönlü Fransızca ↔ Türkçe arama ("gitmek" → `aller`),
  aksan duyarsız yazım ("etre" → `être`), yön filtresi ve **kelime aileleri**
  arasında gezinme (chanter → chanson → chanteur…)

İlerleme ve ayarlar `progress.db` içinde kalıcıdır, uygulama kapanınca kaybolmaz.
Oyun profili, görevler, başarımlar, hikâye seçimleri ve cümle çözüm kayıtları da
aynı yedeğe dahildir. A1–C2 dünyaları bağımsızdır; seçilen seviyenin ilk durağı
doğrudan açılır. Hikâye ve cümlelerde ilk tamamlama bonusu yalnız bir kez verilir.

## Kurulum ve çalıştırma

Araç zinciri `~/dev` altında kurulu (Flutter 3.44.9, JDK 17, Android SDK 36).
Ortam değişkenleri kullanıcı PATH'ine yazıldı, yeni bir terminalde hazır gelir.

```sh
flutter pub get
flutter run --debug            # telefon USB ile bağlıyken
```

Yerel test APK'sı `flutter build apk --debug` ile üretilir. Çıktı
`build/app/outputs/flutter-apk/app-debug.apk` dosyasındadır. Adım adım test
yönergesi: [TEST.md](TEST.md)

Release derlemesi debug anahtarını kullanmaz. Önce
`android/key.properties.example` dosyasını `android/key.properties` olarak
kopyalayıp özel release anahtarının bilgilerini gir. Bu dosya ve anahtar Git'e
eklenmez. Yapılandırma yoksa release derlemesi bilinçli olarak durur.

## Animasyonu ayarlamak

Bütün süre, eğri, yay ve eşik değerleri tek dosyada:
`lib/motion/motion_tokens.dart`

Arayüz ortak bir oyun tasarım sistemi kullanır: hareketli atmosfer zemini,
cam yüzeyler, basılınca sıkışan kartlar, ışıklı ilerleme çubukları, seviye
arması ve XP/coin ödül animasyonları `lib/ui/game_ui.dart` içinde toplanmıştır.
Bu hareketlerin tamamı **Azaltılmış hareket** ayarına uyar.

Macera merkezindeki yol arkadaşı tamamen koddan çizilir. **Lumi, Moka, Pipou
ve Nox** arasından seçim yapılabilir; karakter rengi ile bere, kulaklık ve taç
ayrı ayrı değiştirilebilir. Seçimler kalıcıdır ve ilerleme yedeğine dahildir.
Karakterler nefes alma, göz kırpma, el sallama ve parıltı hareketleriyle yaşar;
azaltılmış hareket ayarında sakinleşir.

Öncelikle oynanacak değerler:

| Değer | Etkisi |
|---|---|
| `returnSpring.stiffness` | Yükseltirsen keskin ama sert, düşürürsen yumuşak ama gecikmeli |
| `returnSpring.damping` | Düşürürsen daha çok salınım |
| `thresholdFraction` | Kartın uçması için gereken sürükleme mesafesi |
| `maxRotationRadians` | Kartın dönme açısı |
| `perspective` | Çevirmedeki derinlik hissi |
| `cardFlip` | Çevirme süresi |

Uygulama içinde İlerleme sekmesinden animasyon hızı 0.75x / 1x / 1.25x
arasında değiştirilebilir. Kelimeler sekmesindeki "Hareket prototipi"
bağlantısı stres testi düğmesiyle birlikte duruyor: 10 kartı 120 ms arayla
kaydırır. Komutlar kuyruklanır ve on ayrı kartı sırasıyla işler.

Kare düşüşünü ölçmek için:

```sh
flutter run --profile
```

Sonra DevTools performans katmanını aç. **Ölçüm gerçek telefonda yapılır,
emülatör yanıltır.**

## İçerik boru hattı

Ham veri proje klasörünün dışında durur (`~/dev/french-data`), sebebi proje
OneDrive'da ve 1,2 GB ham veriyi buluta senkronlamak gereksiz.

```sh
python content/tools/00_probe_sources.py     # adresleri doğrula
python content/tools/01_fetch.py             # 1,23 GB indir
python content/tools/02_measure.py           # üç kilit ölçüm
python content/tools/04_lemmas.py            # aday havuz
python content/tools/05_levels.py            # seviye ataması
python content/tools/06_english.py           # İngilizce + IPA + fiil formu
python content/tools/07_turkish.py           # Türkçe karşılık
python content/tools/12_manual_tr.py         # elle yazılan karşılıkları kat
python content/tools/08_examples.py          # örnek cümleler
python content/tools/09_idioms.py            # deyimler
python content/tools/11_idiom_tr.py          # deyimlere Türkçe
python content/tools/10_verbs.py             # çekim tabloları
python content/tools/13_build_db.py          # content.db üret
python content/tools/14_validate_db.py       # yapı ve öğrenme güvenliği denetimi
```

Üçüncü taraf Python paketi gerekmez, hepsi standart kütüphane.

## Test etme

Uçtan uca duman testi gerçek `content.db`'yi açar, gerçek `AppState`'i kurar
ve telefon ölçüsünde bir yüzeyde ekranlarda gezinir:

```sh
flutter test
```

77 test. `flutter analyze` derleme hatalarını görür ama "push edilen sayfa
InheritedWidget'ı göremiyor" ya da "deyim destesi normal desteyi gösteriyor"
gibi hataları göremez — bunlar duman testiyle yakalandı.

## Kaynaklar ve lisanslar

| Kaynak | Lisans |
|---|---|
| Lexique 3.83 | CC BY-SA |
| FLELex (CENTAL, UCLouvain) | Araştırma için serbest |
| Wiktionary (kaikki.org, DBnary) | CC BY-SA |
| Tatoeba | CC BY 2.0 FR |
| FrequencyWords içeriği | CC BY-SA 4.0 |
| Wikimedia Commons şarkı kayıtları | Parça bazında CC BY-SA 3.0, CC BY 3.0 veya kamu malı |

Dağıtımdan önce [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) okunmalıdır.
Özellikle FLELex sayfası kullanımı araştırma ve öğretimle sınırlar; ticari veya
genel dağıtım için ayrıca izin/uygunluk teyidi gerekir.

## Görsel dil

Her seviyenin kendi rengi var: A1 yeşilden C2 mora. Renk kartın üst
şeridinde, zemin gradyanında, seviye rozetinde, seviye seçim kartlarında,
örnek cümle kutusunda ve ilerleme çubuklarında aynı anlamı taşır —
kullanıcı seviyeyi yazı okumadan görür. Palet `lib/app/theme.dart`
içindeki `AppTheme.levelColors`.

Haritada bir **gezgin** var: yol üzerinde durur, durak geçilince iki
durak arasındaki kübik eğri boyunca yürüyerek yenisine geçer ve harita
onu takip eder. İlerleme bir sayı değil, bir hareket olarak görünüyor.

Harita açılırken yol yukarıdan aşağı çizilir, duraklar sırayla oturur;
bulunduğun durağın halkası nabız gibi atar. Durak geçilince parçacıklar
saçılır (`lib/motion/celebration.dart`), yanlış cevap sönümlenen bir
titremeyle belirtilir. Bütün bunlar `CustomPainter` ile çizilir, widget
olarak eklenmez — yerleşim ağacına dokunmadıkları için kare düşürmezler.

Örnek cümle, sol kenarı seviye rengiyle çizilmiş bir alıntı kutusunda
duruyor ve **hedef kelime cümle içinde kalın**. Çekimli biçimi bulmak için
kök benzerliğine bakılıyor (`manger` → "je **mange**"); ölçtüğümüzde
cümlelerin **%91'inde** hedef kelime bulunuyor. Sezgi tutmazsa cümle
olduğu gibi, vurgusuz görünür — `test/highlight_test.dart` bunu garanti
ediyor.

## Bilinen eksikler

- Bildirim yok (Faz 9)
- Kelime ailesi bilgisi havuzun %32'sinde var; gerisinde kaikki verisi yok
- Deyim destesinde 128 kalıp var, 81'i elle yazıldı; kalan otomatik
  kalıpların bir kısmının Türkçesi hâlâ zayıf
- Tema ataması anahtar kelimeye dayalı, kaba; kelimelerin çoğu `general`
- İçeriğin tamamı elle gözden geçirilmedi. Ters sözlük eşleşmeleri ve
  doğrulanmamış zayıf köprü çevirileri sözlükte görünür ancak öğrenme,
  yolculuk ve quiz havuzlarına girmez.
  Kartın arka yüzündeki bayrak düğmesi
  hatalı kartı `progress.db > flagged_cards` tablosuna kaydeder; bu liste
  sonraki içerik turunda `content/overrides/manual.json` düzeltmesine
  dönüştürülecek
- APK hata ayıklama anahtarıyla imzalı; Play Store'a çıkmaz, yan yükleme olur
- Elle denetlenen kelime/deyim: **997** (A1 737, A2 231, B1 18, B2 8,
  C1 3, C2 0). Üst seviyeler bilinen en büyük içerik açığıdır.
