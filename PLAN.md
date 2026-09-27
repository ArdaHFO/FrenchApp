# FrenchApp — Ürün ve Teknik Planı

Kaydırmalı kart mantığıyla Fransızca kelime, deyim, fiil çekimi ve dilbilgisi öğreten Android uygulaması.

**Durum:** çalışır durumda, gerçek içerikle dolu
**Kullanıcı:** tek kişi, anadili Türkçe, İngilizce biliyor, Fransızcaya sıfırdan başlıyor
**Ek belge:** içerik kaynakları ve üretim boru hattı için [DATA_PIPELINE.md](DATA_PIPELINE.md)

## Faz durumu

| Faz | Konu | Durum |
|---|---|---|
| 0 | Kurulum (Flutter 3.44.9, JDK 17, Android SDK 36) | ✅ |
| 0.5 | Hareket prototipi, elle yazılan kaydırıcı | ✅ |
| 1 | Veri boru hattı, `content.db` üretimi | ✅ |
| 2 | Veri katmanı, SQLite, kalıcı ilerleme | ✅ |
| 3 | Onboarding, seviye seçimi, yerleştirme testi | ✅ |
| 4 | Kelime kaydırma oturumu, SRS | ✅ |
| 5 | Quiz motoru, 4 soru tipi | ✅ |
| 6 | Fiil çekimi, 8 zaman | ✅ |
| 7 | Dilbilgisi, 19 ders (A1'den C2'ye) | ✅ |
| 8 | İlerleme, seri, günlük hedef, 30 günlük ızgara | ✅ |
| 9 | Ses (TTS), kaynaklar ekranı, ayarlar | ✅ kısmi (bildirim yok) |
| 10 | APK üretimi, sözlük araması, hata bildirme | ✅ |
| 11 | İçerik gözden geçirme | ⏳ sürekli |
| 12 | Uçtan uca duman testi, hata avı | ✅ |
| 13 | İçerik elle denetimi (A1 ilk 1.180) | ⏳ sürüyor |
| 14 | Görsel dil: seviye renkleri | ✅ |
| 15 | Kelime aileleri, çekim tabloları, üst seviye dersler | ✅ |
| 16 | Dönüşlü fiiller (verbes pronominaux) | ✅ |
| 17 | Yolculuk haritası: duraklar, yıldızlar, seviye sınavları | ✅ |
| 18 | Harita animasyonları, kutlama, titreme, sekme geçişi | ✅ |
| 19 | Gezgin, kombo sayacı, dokunsal geri bildirim | ✅ |
| 20 | Yedekleme (dışa/içe aktarma), 30 günlük ızgara | ✅ |

Üretilen içerik: **15.423 kelime** (128 deyim), **17.832 örnek cümle**,
**2.698 fiil** (132 dönüşlü), **121.354 çekim**, **19 dilbilgisi dersi**, **7.560 kelime
ailesi bağı**. Veritabanı 23,0 MB.
Ayrıntılı sayılar ve ölçümler [content/reports/](content/reports/) altında.
Telefonda kurma ve test adımları: [TEST.md](TEST.md).

---

## 1. Kilit Kararlar

| Konu | Karar | Gerekçe |
|---|---|---|
| Teknoloji | Flutter (Dart) | Tek kod tabanı, akıcı kart animasyonu, hazır swipe paketleri, kolay APK üretimi |
| İçerik kaynağı | Açık lisanslı veri kümelerinin birleştirilmesi | 6 seviyelik içerik elle yazılamaz. Kaynaklar doğrulandı, hepsi ücretsiz ve indirilebilir |
| Veri dağıtımı | Uygulamayla gelen offline SQLite paketi | İnternet gerekmez, gecikme yok, maliyet yok |
| İlerleme verisi | Cihazda SQLite, hesap yok | Gizlilik tam, sunucu maliyeti sıfır, yedekleme dosya dışa aktarma ile |
| Seviye | Altı seviye de uygulamada, kullanıcı seçer | Uygulama kullanıcıyla birlikte ilerler, ikinci bir uygulamaya gerek kalmaz |
| Kart ön yüzü | Kelime + okunuş + Fransızca örnek cümle | Anlamı bağlamdan tahmin etmek en iyi öğrenme yolu |
| Diller | Ön yüz Fransızca, arka yüz İngilizce + Türkçe | İki dilli karşılık kalıcılığı artırır |
| **Animasyon** | **Birinci öncelik. Kaydırıcı hazır paketle değil elle yazılır** | **Bölüm 6'ya bakınız. Hazır paketler tam da önemli olan ayrıntılarda sınır koyar** |

Veri katmanı baştan senkrona hazır tasarlanır (her satırda `uuid` ve `updated_at`), ama v1'de bulut yazılmaz.

---

## 2. Ürün Fikrinin Geliştirilmiş Hali

### 2.1 Orijinal fikirdeki üç modül

1. **Kelime Tinder'ı** — seviyeye göre kelime ve deyim kartları, tıklayınca çevrilir, sağa kaydırma öğrendim, sola kaydırma öğrenmedim
2. **Fiil Çekimi Tinder'ı** — aynı mantık, çekim odaklı
3. **Dilbilgisi bölümü** — zaman kullanımları

### 2.2 Eklenen parçalar ve nedenleri

**a) İkili yerine aralıklı tekrar (SRS)**
Sadece "biliyorum / bilmiyorum" ayrımı yetersiz kalır. Bir kelimeyi bir kez bilmek onu öğrenmiş olmak değildir. Her kartın bir kutusu olur. Sağa kaydırma kartı bir üst kutuya taşır ve tekrar aralığını uzatır. Sola kaydırma kartı en alt kutuya düşürür. Böylece uygulama neyi ne zaman göstereceğini kendisi bilir.

**b) İki yerine dört kaydırma yönü**
İki seçenek "bunu zaten biliyorum, hiç görmek istemiyorum" ve "bu kelime beni çok zorluyor" durumlarını ayırt edemiyor.

| Yön | Renk | Anlam | Etki |
|---|---|---|---|
| Sağa | Yeşil | Biliyorum | Bir üst kutuya çıkar, quiz havuzuna girer |
| Sola | Sarı | Henüz bilmiyorum | Kutu 0'a düşer, aynı oturumda tekrar gelir |
| Yukarı | Mavi | Zor, yıldızla | Yıldızlı listeye girer, normalden iki kat sık gelir |
| Aşağı | Gri | Zaten biliyorum, bir daha gösterme | Arşive gider, quizde çıkmaz |
| Tek dokunuş | — | Kartı çevir | Arka yüz açılır |

**c) Ses**
Fransızcada yazım ve okunuş arasındaki fark çok büyüktür. Sesi olmayan bir kelime kartı yarım kalır. Cihazın kendi Fransızca konuşma motoru kullanılır. Ek dosya yok, ek maliyet yok.

**d) Quizde akıllı çeldirici**
Rastgele üretilen yanlış şıklar quizi kolaylaştırır ve öğretmez. Çeldiriciler kurala göre seçilir.
- Anlam quizinde çeldirici önce aynı seviye ve kelime türünden, sonra aynı seviyeden gelir
- Fiil çekimi quizinde çeldiriciler aynı fiilin diğer şahıs çekimleri ve diğer zamanlardaki halleri olur

**e) Dört quiz tipi**
Tek tip soru ezbere yol açar. Aynı kelime farklı yönlerden sorulur.
1. Fransızca kelime verilir, Türkçe veya İngilizce anlamı seçilir
2. Türkçe anlam verilir, Fransızca kelime seçilir
3. Cümlede boşluk verilir, doğru kelime seçilir
4. Fiil ve şahıs verilir, doğru çekim seçilir

**f) Günlük hedef, seri ve hatırlatma**
Uygulamanın açılma sebebi olması gerekir. Günlük kart hedefi, üst üste gün sayacı ve akşam bildirimi bunu sağlar.

**g) Zorlandıklarım listesi**
Altı kez sola kaydırılan kart "takıldığım kelimeler" listesine düşer. Bu liste ayrı bir deste olarak çalışılabilir. Öğrenmede en çok işe yarayan ekran budur.

**h) Tema desteleri**
Sadece seviye ile filtrelemek monotondur. Her kelimeye tema etiketi konur (yemek, seyahat, ev, iş, duygular, günlük konuşma, sayı ve zaman, sağlık, eğitim, doğa). Kullanıcı hem seviye hem tema seçebilir.

**i) İlerleme ekranı**
Kaç kelime hangi kutuda, her seviyenin yüzde kaçı bitti, son 30 günün grafiği, doğru cevap oranı.

**j) Sıklık sırasına göre gösterim**
Kartlar rastgele değil, kullanım sıklığına göre gelir. Bir seviyenin ilk 200 kelimesi o seviyede en çok işine yarayacak kelimelerdir. Bu aynı zamanda içerik kalite kontrolünü de kolaylaştırır, çünkü ilk göreceğin kelimeler ilk gözden geçirilen kelimeler olur.

**k) Hareketin kendisi bir özellik olarak ele alınır**
Kaydırmalı bir uygulamada içerik ne kadar iyi olursa olsun, hareket kötüyse uygulama açılmaz. Bu yüzden animasyon ayrı bir tasarım alanı olarak ele alınır ve kendi bölümü vardır. Bakınız bölüm 6.

---

## 3. Seviye Sistemi

Altı seviye de uygulamanın içindedir. Kullanıcı seviyesini kendisi seçer ve istediği zaman değiştirir.

### 3.1 İlk açılış akışı

```
1. Karşılama ekranı
2. "Seviyeni seç"
   ├── A1  Hiç bilmiyorum, sıfırdan başlıyorum
   ├── A2  Temel kalıpları biliyorum, basit cümle kurabiliyorum
   ├── B1  Günlük konuları anlıyorum, kendimi ifade edebiliyorum
   ├── B2  Karmaşık metinleri takip edebiliyorum
   ├── C1  Akıcıyım, nüansları öğrenmek istiyorum
   ├── C2  Neredeyse anadil düzeyi
   └── "Seviyemi bilmiyorum" → yerleştirme testi
3. Günlük hedef seçimi (10 / 20 / 40 kart)
4. Bildirim saati
```

### 3.2 Yerleştirme testi

20 soruluk uyarlanabilir test. A2'den başlar. Üst üste üç doğru bir üst seviyeye çıkarır, iki yanlış bir alt seviyeye indirir. Sonuçta doğru oranı yüzde 60'ın üzerinde olan en yüksek seviye atanır. Sorular anlam eşleştirme tipindedir ve her seviyenin sıklık listesinin ortalarından seçilir.

### 3.3 Seviye filtresi mantığı

Deste seçim ekranında iki ayar bulunur.

- **Seviye:** varsayılan olarak profil seviyesi gelir, tek tek değiştirilebilir
- **Alt seviyeleri karıştır:** açık olduğunda seçili seviyenin altındaki bilinmeyen kelimeler de desteye girer

İkinci ayar önemlidir. B1 seçen biri A1 ve A2 kelimelerinin hepsini bilmek zorunda değildir. Bu ayar açıkken uygulama önce alt seviyedeki eksikleri kapatır, sonra üst seviyeye geçer.

### 3.4 Seviye ilerlemesi

Bir seviyenin kelimelerinin yüzde 80'i kutu 3 ve üzerine çıktığında uygulama "bir üst seviyeye geçmeye hazırsın" bildirimi gösterir. Geçiş zorunlu değildir, öneri olarak kalır.

---

## 4. Ekran Haritası

```
İlk açılış → Seviye seçimi / Yerleştirme testi → Ana ekran

Ana Ekran (alt sekme çubuğu)
│
├── 1. Kelimeler
│   ├── Deste seçimi (seviye + tema + alt seviye karıştırma
│   │                 + "zorlandıklarım" + "yıldızlılar")
│   └── Kaydırma ekranı
│       ├── Kart ön yüzü
│       └── Kart arka yüzü
│
├── 2. Fiiller
│   ├── Deste seçimi (zaman + fiil grubu + düzensizler + seviye)
│   └── Çekim kaydırma ekranı
│
├── 3. Dilbilgisi
│   ├── Ders listesi (seviyeye göre gruplu, kilitsiz)
│   └── Ders ekranı
│       ├── Açıklama
│       ├── Kuruluş tablosu
│       ├── Örnek cümleler
│       ├── Sık yapılan hatalar
│       ├── Ders sonu mini quiz
│       └── İlgili çekim destesine geçiş
│
├── 4. Quiz
│   ├── Quiz tipi seçimi (kelime / fiil çekimi / karışık)
│   ├── Soru ekranı
│   └── Sonuç ekranı (yanlışları tek tek gözden geçirme)
│
└── 5. İlerleme
    ├── Özet kartları (seri, bugünkü hedef, toplam bilinen)
    ├── Altı seviyenin ilerleme çubukları
    ├── 30 günlük grafik
    ├── Zorlandıklarım listesi
    └── Ayarlar (seviye, günlük hedef, bildirim, ses hızı, yedekleme)
```

---

## 5. Kart Tasarımı

### 5.1 Kelime kartı

**Ön yüz (sadece Fransızca)**
```
┌─────────────────────────────┐
│  A1 · isim · dişil          │  ← seviye, tür, cinsiyet rozeti
│                             │
│                             │
│       la voiture            │  ← büyük punto
│       /la vwa.tyʁ/          │  ← okunuş
│          🔊                 │  ← sese dokun
│                             │
│  ─────────────────────      │
│  Je gare la voiture         │  ← örnek cümle, sadece Fransızca
│  devant la maison.          │
│                        🔊   │
│                             │
│  Çevirmek için dokun        │
└─────────────────────────────┘
```

**Arka yüz (İngilizce + Türkçe)**
```
┌─────────────────────────────┐
│       la voiture            │
│                             │
│  🇬🇧  the car               │
│  🇹🇷  araba                 │
│                             │
│  ─────────────────────      │
│  Je gare la voiture         │
│  devant la maison.          │
│                             │
│  🇬🇧 I park the car in      │
│      front of the house.    │
│  🇹🇷 Arabayı evin önüne     │
│      park ediyorum.         │
│                             │
│  Not: "voiture" dişildir,   │
│  hep "la" ile kullanılır.   │
│                    ⚑ hata   │
└─────────────────────────────┘
```

Sağ alttaki bayrak düğmesi kartta hata bildirmek içindir. Otomatik üretilen içerikte hata kaçınılmazdır ve bu düğme temizliği zamana yayar.

Deyim kartlarında ek olarak "birebir çevirisi" satırı bulunur. Örnek: *avoir le cafard* birebir "hamamböceğine sahip olmak", gerçek anlamı "moralinin bozuk olması". Bu satır deyimlerin akılda kalmasını çok kolaylaştırır.

### 5.2 Fiil çekim kartı

**Ön yüz**
```
┌─────────────────────────────┐
│  Présent · 1. grup · A1     │
│                             │
│       parler                │
│      (konuşmak)             │
│                             │
│         nous                │  ← sorulan şahıs
│         ?                   │
│                             │
│  Çevirmek için dokun        │
└─────────────────────────────┘
```

**Arka yüz**
```
┌─────────────────────────────┐
│    nous parlons             │
│    /nu paʁ.lɔ̃/       🔊     │
│                             │
│  Nous parlons français.     │
│  🇬🇧 We speak French.       │
│  🇹🇷 Fransızca konuşuyoruz. │
│                             │
│  Tam çekim                  │
│  je parle    nous parlons   │
│  tu parles   vous parlez    │
│  il parle    ils parlent    │
└─────────────────────────────┘
```

Arka yüzde tam çekim tablosunun gösterilmesi tek şahıs ezberlemek yerine kalıbı görmeyi sağlar.

---

## 6. Hareket ve Animasyon Tasarımı

**Bu bölüm uygulamanın birinci önceliğidir.**

Kaydırmalı bir uygulamanın rakiplerinden tek gerçek farkı hareketin kalitesidir. Aynı kelime listesi kötü animasyonla sıkıcı bir tablo, iyi animasyonla insanın elinden bırakamadığı bir şey olur. Bu yüzden animasyon en sona bırakılan bir cila işi değildir. En başta prototiplenir, ayrı bir bütçesi vardır ve bütün fazlar boyunca korunur.

Bunun iki somut sonucu var.

1. **Kaydırıcı hazır paketle yazılmaz, elle yazılır.** `appinio_swiper` ve benzerleri iyi paketlerdir ama tam da önem verdiğin ayrıntılarda sınır koyarlar: arkadaki kartların sürükleme sırasındaki davranışı, dört yönlü eşikler, eşik geçişinde titreşim, yarıda kesilebilen animasyonlar. Kendi kart destesi bileşenini yazmak yaklaşık 400 satırdır ve her şeyi kontrol etmeni sağlar.
2. **Faz 0.5 diye bir hareket prototipi fazı eklenir.** Veritabanı yok, içerik yok, sahte üç kelimeyle sadece hareket. Telefonda elde denenir, his doğru olana kadar üzerinde oynanır. Doğru his bulunmadan diğer fazlara geçilmez.

### 6.1 Genel ilkeler

1. Hiçbir şey aniden belirmez veya kaybolmaz
2. Her hareketin fiziksel bir sebebi olur. Kart parmağı takip eder, bırakılınca yay gibi yerine döner, fırlatılınca momentumla gider
3. Giriş animasyonları yavaşlayarak biter (`easeOut`), çıkış animasyonları hızlanarak gider (`easeIn`), yer değiştirmeler `easeInOut`
4. Kullanıcı eylemine tepki 100 ms içinde **başlar**, animasyonun bitmesi beklenmez
5. **Her animasyon yarıda kesilebilir.** Kartı hızlı hızlı kaydırırken bir öncekinin animasyonu bitmeden yenisine geçilebilmelidir. Kontrolcü sıfırlanmaz, mevcut hız yeni animasyona devredilir
6. Hedef 120 Hz. Kare bütçesi 8,3 ms

Beşinci madde en çok gözden kaçan ve en çok fark yaratan maddedir. Çoğu kart uygulaması hızlı kaydırınca takılır, çünkü animasyon bitmeden yeni girdi kabul edilmez.

### 6.2 Kart destesi

Ekranda üç kart görünür. Arkadakiler ölçek ve dikey kayma ile derinlik hissi verir.

```
        ┌───────────────┐        3. kart: ölçek 0.90, y +24, opaklık 0.55
       ┌┴──────────────┬┘
      ┌┴───────────────┴┐        2. kart: ölçek 0.95, y +12, opaklık 0.80
     ┌┴─────────────────┴┐
     │                   │
     │   üstteki kart    │       1. kart: ölçek 1.00, y 0, opaklık 1.00
     │   ölçek 1.00      │
     │                   │
     └───────────────────┘
```

Üstteki kart sürüklendikçe arkadakiler **eş zamanlı olarak** öne doğru ilerler. Sürükleme yüzde 40'a geldiğinde ikinci kart neredeyse tam boyutuna ulaşmış olur. Bu detay destenin canlı hissettirmesini sağlar. Arkadaki kartların hareketi ayrı bir animasyon değildir, üstteki kartın sürükleme oranına bağlı bir türevdir.

### 6.3 Sürükleme fiziği

| Davranış | Değer |
|---|---|
| Kart parmağı takip eder | Birebir, gecikme yok |
| Dönme açısı | Sürükleme mesafesine bağlı, en fazla 16 derece |
| Dönme merkezi | Tutuş noktasına bağlı. Kartın üstünden tutarsan alt taraf savrulur, altından tutarsan üst taraf |
| Eşik | Ekran genişliğinin yüzde 28'i veya 800 px/s hız |
| Eşik altında bırakma | Yay simülasyonu ile yerine döner |
| Eşik üstünde bırakma | Sürükleme hızından türetilen momentumla ekran dışına uçar |

Dönme merkezinin tutuş noktasına bağlı olması küçük bir ayrıntıdır ama kartın gerçek bir kâğıt gibi hissedilmesini sağlayan şey tam olarak budur.

Geri dönüş için `Curves` yerine gerçek yay simülasyonu kullanılır.

```dart
SpringDescription(mass: 1.0, stiffness: 500.0, damping: 30.0)
```

Bu değerler hafif bir aşma (overshoot) verir. Yay sertliği düşürülürse kart yumuşak ama gecikmeli, yükseltilirse keskin ama sert hisseder. Prototip fazında telefonda elle ayarlanacak asıl sayılar bunlardır.

### 6.4 Yön geri bildirimi

Sürükleme başladığı anda yönü belli olur ve kart üzerinde iki şey birlikte belirir.

1. **Renk katmanı.** Kartın üzerine yönün rengi bindirilir, opaklığı sürükleme oranıyla artar, en fazla 0.35'e çıkar
2. **Rozet.** "BİLİYORUM", "BİLMİYORUM", "ZOR", "ATLA" yazısı ölçek ve opaklıkla belirir. Ölçek 0.7'den 1.0'a `easeOutBack` eğrisiyle çıkar, yani hafif zıplayarak oturur

Eşik geçildiği anda üç şey olur.
- Hafif titreşim (`HapticFeedback.selectionClick`)
- Rozet bir anlık yüzde 8 büyüyüp normale döner
- Renk katmanı doygunlaşır

Titreşim önemlidir. Kullanıcı ekrana bakmadan da kartın gideceğini parmağıyla anlar. Bu geri bildirim olmadan eşik hissi kaybolur.

### 6.5 Kart çevirme

Kartın en dikkat isteyen animasyonu budur, çünkü uygulamanın en sık tekrarlanan hareketidir.

- Y ekseni etrafında üç boyutlu dönme
- Gerçek perspektif matrisi, düz bir ölçek animasyonu değil

```dart
Matrix4.identity()
  ..setEntry(3, 2, 0.0012)   // perspektif derinliği
  ..rotateY(angle)
```

- Süre 450 ms, eğri `easeOutCubic`
- Dönme 90 dereceyi geçtiğinde içerik ön yüzden arka yüze değişir
- Dönme sırasında kart hafifçe büyür (1.0 → 1.04 → 1.0). Kart öne gelip geri gidiyormuş hissi verir
- Gölge dönmeyle birlikte genişler ve yumuşar
- Dönme sırasında kart kaydırılabilir. Animasyon kesilir, kaydırma devralır

Perspektif değeri 0.0012 civarındadır. Daha büyük değerler abartılı bir balıkgözü etkisi verir, daha küçük değerler dönmeyi düz bir yassılaşmaya çevirir.

### 6.6 Animasyon kataloğu

Uygulamadaki bütün hareketler, süreleri ve eğrileriyle.

| Yer | Hareket | Süre | Eğri |
|---|---|---|---|
| Kart destesi | Arka kartların öne ilerlemesi | Sürüklemeye bağlı | Doğrusal türev |
| Kart | Yerine dönme | Yay | `SpringDescription(500, 30)` |
| Kart | Ekran dışına uçma | 280 ms | `easeInQuad` + momentum |
| Kart | Yeni kartın yerine oturması | 350 ms | `easeOutCubic` |
| Kart | Çevirme | 450 ms | `easeOutCubic` |
| Rozet | Belirme | 150 ms | `easeOutBack` |
| Renk katmanı | Opaklık | Sürüklemeye bağlı | Doğrusal |
| Üst çubuk | Oturum ilerleme dolumu | 400 ms | `easeOutCubic` |
| Ses ikonu | Konuşurken dalga | Döngü 1200 ms | `easeInOut` gidip gelme |
| Quiz | Doğru cevap dolumu | 300 ms | `easeOutCubic` |
| Quiz | Yanlış cevapta sarsılma | 400 ms | Sönümlenen salınım, 3 çevrim |
| Quiz | Sonraki soruya geçiş | 250 ms | Kayma + solma |
| Oturum sonu | Sayıların artması | 800 ms | `easeOutExpo` |
| Oturum sonu | Günlük hedef tamamlandı | 1500 ms | Parçacık efekti |
| Sekme geçişi | Sayfa değişimi | 300 ms | `easeInOutCubic`, kayma + solma |
| Sekme çubuğu | Seçili ikon | 200 ms | `easeOutBack`, ölçek 1.0 → 1.15 → 1.0 |
| Deste seçimi | Kaydırma ekranına geçiş | 400 ms | `Hero` geçişi |
| Listeler | Öğelerin sırayla belirmesi | 40 ms gecikmeli | `easeOut`, kayma + solma |
| Dilbilgisi | Zaman çizelgesi çizimi | 1200 ms | `easeInOutCubic` |
| Seviye ilerleme | Çubuk dolumu | 700 ms | `easeOutCubic` |

Genel süre kuralı: küçük öğeler 150-200 ms, orta boy öğeler 250-350 ms, tam ekran geçişler 350-500 ms. Bu aralıkların dışına çıkan her animasyon ya fark edilmez ya da yavaş hisseder.

### 6.7 Ekstra dokunuşlar

Bunlar zorunlu değildir ama uygulamayı "yapılmış" değil "tasarlanmış" hissettiren şeylerdir.

**Jiroskop parallaksı.** Telefon eğildiğinde kartın üzerindeki ışık parlaması ve gölge yönü hafifçe kayar. `sensors_plus` ile jiroskop okunur, kart içeriği 4-6 piksellik bir aralıkta ters yönde kaydırılır. Efekt fark edilmeyecek kadar hafif olmalıdır, abartıldığında rahatsız eder.

**Deste derinliği.** Kalan kart sayısı azaldıkça arkadaki kart sayısı da azalır. Son karta gelindiğinde arkada hiç kart görünmez. Küçük bir detaydır ama oturumun bittiğini hissettirir.

**Ağırlıklı gölge.** Kart sürüklendikçe gölgesi büyür ve yumuşar, kart yükseliyormuş gibi olur. Bırakıldığında gölge geri oturur.

**Zaman çizelgesi animasyonu.** Dilbilgisi derslerinde passé composé ile imparfait farkı anlatılırken imparfait bir çizgi olarak soldan sağa uzar, passé composé o çizginin üzerine noktalar olarak düşer. Bu ayrımı bir paragraf metinden çok daha iyi anlatır.

**Seri alevi.** Üst üste gün sayacı arttıkça yanındaki alev ikonu daha canlı yanar. Rive ile yapılır.

### 6.8 Performans bütçesi

Animasyon ne kadar güzel olursa olsun takılırsa değersizdir. 120 Hz ekranda kare başına 8,3 ms vardır.

**Kurallar.**

- Impeller renderer kullanılır (Flutter'da Android tarafında varsayılan). Shader derleme takılmaları böyle ortadan kalkar
- Sürükleme sırasında **widget ağacı yeniden kurulmaz**. `setState` çağrılmaz, sadece `AnimatedBuilder` içindeki `Transform` güncellenir. Bu tek kural tek başına performansın yarısıdır
- Her kart bir `RepaintBoundary` içine alınır. Üstteki kart hareket ederken arkadakiler yeniden boyanmaz
- Sürükleme sırasında gölgenin bulanıklık yarıçapı sabit tutulur. Değişen `BoxShadow` bulanıklığı her karede yeniden hesaplanır ve pahalıdır. Gölge büyüklüğü ölçek ve konumla verilir
- `BackdropFilter` ve buzlu cam efekti kullanılmaz. Çok pahalıdır ve burada bir şey kazandırmaz
- `Opacity` yerine `AnimatedOpacity` veya `FadeTransition` kullanılır, `Opacity` widget'ı ayrı katman açar
- Metin ölçümü sürükleme sırasında tekrarlanmaz. Kart içeriği sürükleme başlamadan önce yerleşmiş olur
- Özel çizim yapan yerlerde `shouldRepaint` doğru yazılır

**Ölçüm.** Her animasyon işi bittiğinde DevTools performans katmanı açılarak gerçek telefonda test edilir. Emülatörde ölçüm yapılmaz, emülatör yanıltır. Takılma varsa kaynak bulunmadan sonraki işe geçilmez.

### 6.9 Paketler

| Amaç | Paket | Not |
|---|---|---|
| Kart destesi ve kaydırma | **elle yazılır** | `GestureDetector` + `AnimationController` + `Transform`. Hazır paket kullanılmaz |
| Bildirimsel animasyon zincirleri | `flutter_animate` | Liste girişleri, sarsılma, solma gibi tekrar eden işler için çok kısaltır |
| Vektör animasyon | `rive` | Seri alevi, sekme ikonları, boş ekran çizimleri. Çalışma zamanı hafiftir |
| Parçacık efekti | `confetti` | Günlük hedef tamamlanınca |
| Jiroskop | `sensors_plus` | Kart parallaksı |
| Yay fiziği | Flutter içinde | `SpringSimulation`, ek paket gerekmez |

`rive` yerine `lottie` de kullanılabilir ama Rive dosyaları daha küçüktür ve çalışma zamanı daha ucuzdur.

### 6.10 Ayarlar

Animasyon hızı ayarı konur: 0.75x, 1x, 1.25x. Bazı insanlar zamanla animasyonların hızlanmasını ister, özellikle günde yüzlerce kart kaydırıyorsan.

Animasyonları tamamen kapatan bir seçenek konmaz. Sistem düzeyinde "hareketi azalt" ayarı açıksa süreler yarıya iner ama animasyonlar yok olmaz, çünkü kart çevirme gibi hareketler bilgi taşır.

---

## 7. Aralıklı Tekrar Sistemi

Basit ve öngörülebilir bir kutu sistemi kullanılır. Karmaşık algoritmalara ilk sürümde gerek yok.

| Kutu | Durum | Sonraki tekrar |
|---|---|---|
| 0 | Yeni veya unutulmuş | Aynı oturumda, 10 kart sonra |
| 1 | Öğreniliyor | 1 gün sonra |
| 2 | Öğreniliyor | 3 gün sonra |
| 3 | Biliniyor | 7 gün sonra |
| 4 | Biliniyor | 16 gün sonra |
| 5 | Pekişmiş | 35 gün sonra |
| — | Arşiv | Bir daha gösterilmez |

Kurallar:
- Sağa kaydırma bir üst kutuya çıkarır
- Sola kaydırma doğrudan kutu 0'a düşürür ve `lapses` sayacını bir artırır
- `lapses` 6'ya ulaşınca kart "zorlandıklarım" listesine eklenir
- Yıldızlı kartların tekrar aralığı yarıya iner
- Quiz sorusu sadece kutu 1 ve üzeri kartlardan gelir, çünkü hiç görülmemiş kelimeyi sormak öğretmez

**Oturum kompozisyonu:** 20 kartlık bir oturumda 14 kart zamanı gelmiş tekrar, 6 kart yeni kelimedir. Yeni kartlar seçili seviye içinde sıklık sırasına göre gelir. Zamanı gelmiş kart kalmadıysa boşluk yeni kartla doldurulur.

---

## 8. Veri Modeli

SQLite üzerinde `drift` paketi ile. İçerik ve ilerleme **ayrı veritabanı dosyalarında** tutulur. Böylece içerik güncellendiğinde ilerleme kaybolmaz.

### 8.1 İçerik tabloları (`assets/db/content.db`, salt okunur)

```sql
words (
  id            TEXT PRIMARY KEY,
  lemma_fr      TEXT NOT NULL,      -- voiture
  article       TEXT,               -- la / le / les / null
  pos           TEXT NOT NULL,      -- noun|verb|adj|adv|prep|conj|pron|phrase|idiom
  gender        TEXT,               -- m|f|null
  plural_fr     TEXT,
  ipa           TEXT,
  level         TEXT NOT NULL,      -- A1|A2|B1|B2|C1|C2
  level_source  TEXT,               -- flelex|frequency|manual
  theme         TEXT,
  meaning_en    TEXT NOT NULL,
  meaning_tr    TEXT NOT NULL,
  meaning_en_2  TEXT,               -- ikincil anlam
  meaning_tr_2  TEXT,
  literal_tr    TEXT,               -- sadece deyimlerde birebir çeviri
  note_tr       TEXT,
  register      TEXT,               -- neutre|familier|soutenu|vulgaire
  freq_rank     INTEGER NOT NULL,   -- seviye içi sıralama için
  confidence    REAL,               -- 0-1, otomatik üretim güveni
  reviewed      INTEGER DEFAULT 0,  -- elle gözden geçirildi mi
  is_idiom      INTEGER DEFAULT 0,
  sources       TEXT                -- JSON, hangi veri kümelerinden geldi
)

examples (
  id            TEXT PRIMARY KEY,
  word_id       TEXT REFERENCES words(id),
  sentence_fr   TEXT NOT NULL,
  sentence_en   TEXT NOT NULL,
  sentence_tr   TEXT NOT NULL,
  max_level     TEXT,               -- cümledeki en zor kelimenin seviyesi
  source_id     TEXT,               -- kaynak cümle kimliği ve atıf
  ordinal       INTEGER DEFAULT 0
)

verbs (
  id            TEXT PRIMARY KEY,
  infinitive    TEXT NOT NULL,
  group_no      INTEGER,            -- 1|2|3
  auxiliary     TEXT,               -- avoir|etre|both
  is_irregular  INTEGER DEFAULT 0,
  level         TEXT NOT NULL,
  meaning_en    TEXT NOT NULL,
  meaning_tr    TEXT NOT NULL,
  freq_rank     INTEGER
)

conjugations (
  id            TEXT PRIMARY KEY,
  verb_id       TEXT REFERENCES verbs(id),
  tense         TEXT NOT NULL,
  person        TEXT NOT NULL,      -- je|tu|il|nous|vous|ils
  form          TEXT NOT NULL,
  ipa           TEXT,
  level         TEXT NOT NULL,      -- zamanın seviyesi
  example_fr    TEXT,
  example_en    TEXT,
  example_tr    TEXT
)

grammar_lessons (
  id            TEXT PRIMARY KEY,
  slug          TEXT UNIQUE,
  title_tr      TEXT NOT NULL,
  title_en      TEXT NOT NULL,
  level         TEXT NOT NULL,
  tense_key     TEXT,               -- ilgili çekim destesine bağlar
  sort_order    INTEGER,
  body_md       TEXT NOT NULL
)

grammar_questions (
  id            TEXT PRIMARY KEY,
  lesson_id     TEXT REFERENCES grammar_lessons(id),
  prompt_tr     TEXT NOT NULL,
  sentence_fr   TEXT,
  correct       TEXT NOT NULL,
  distractors   TEXT NOT NULL,      -- JSON dizi
  explain_tr    TEXT
)
```

### 8.2 İlerleme tabloları (`progress.db`, cihazda yazılır)

```sql
card_state (
  id            TEXT PRIMARY KEY,
  card_type     TEXT NOT NULL,      -- word|conjugation|grammar
  ref_id        TEXT NOT NULL,
  box           INTEGER DEFAULT 0,
  status        TEXT DEFAULT 'new', -- new|learning|known|mastered|archived
  starred       INTEGER DEFAULT 0,
  due_at        INTEGER,
  last_seen_at  INTEGER,
  times_seen    INTEGER DEFAULT 0,
  times_right   INTEGER DEFAULT 0,
  lapses        INTEGER DEFAULT 0,
  updated_at    INTEGER NOT NULL,
  UNIQUE(card_type, ref_id)
)

quiz_attempts (
  id, card_type, ref_id, quiz_type, is_correct, answer_ms, created_at
)

daily_stats (
  day TEXT PRIMARY KEY, cards_swiped, new_learned,
  quiz_total, quiz_correct, seconds_spent
)

flagged_cards (
  id, card_type, ref_id, reason, created_at
)

app_settings (key TEXT PRIMARY KEY, value TEXT)
```

`card_state` satırları peşin oluşturulmaz. Bir kart ilk kez kaydırıldığında satırı yazılır. On bin kelime için baştan on bin satır yazmak gereksizdir.

---

## 9. İçerik Hacmi

Altı seviye için hedef. Ayrıntılı üretim yöntemi [DATA_PIPELINE.md](DATA_PIPELINE.md) belgesindedir.

| Seviye | Kelime | Deyim | Fiil | Gramer dersi |
|---|---|---|---|---|
| A1 | 800 | 60 | 60 | 6 |
| A2 | 1.200 | 100 | 100 | 5 |
| B1 | 2.000 | 150 | 150 | 5 |
| B2 | 2.500 | 150 | 150 | 4 |
| C1 | 2.500 | 100 | 100 | 2 |
| C2 | 1.000 | 40 | 40 | 2 |
| **Toplam** | **10.000** | **600** | **600** | **24** |

Buna ek olarak yaklaşık 12.000 örnek cümle (üç dilde) ve 600 fiil × 8 zaman × 6 şahıs = 28.800 çekim satırı.

Tahmini veritabanı boyutu 10-12 MB. APK içine gömülmesi sorun değildir.

### 9.1 Dilbilgisi dersleri

| Seviye | Dersler |
|---|---|
| A1 | Présent düzenli fiiller · Présent être/avoir/aller/faire · Futur proche · Passé composé · Imparfait · Impératif |
| A2 | Futur simple · Conditionnel présent · Plus-que-parfait · COD ve COI zamirleri · Karşılaştırma ve üstünlük |
| B1 | Subjonctif présent · Conditionnel passé · Si cümleleri (üç tip) · Dolaylı anlatım · İlgi zamirleri (qui, que, dont, où) |
| B2 | Subjonctif passé · Edilgen çatı · Participe présent ve gérondif · Zaman uyumu |
| C1 | Passé simple · Subjonctif imparfait |
| C2 | Soutenu ve littéraire kayıt farkları · İnce anlam ayrımları |

Passé composé ile imparfait farkını gösteren zaman çizelgesi görseli A1 derslerinde bulunur. Türkçe konuşan biri için en zorlayıcı nokta budur ve iki zamanı yan yana göstermek en etkili anlatım yoludur.

---

## 10. Teknik Mimari

### 10.1 Paketler

| Amaç | Paket |
|---|---|
| Kart destesi, kaydırma, çevirme | **elle yazılır**, bölüm 6.9'a bakınız |
| Animasyon ve kart fiziği | Flutter SDK ile elle yazılmış bileşenler |
| Veritabanı | `sqflite` |
| Durum yönetimi | `ChangeNotifier` + `InheritedNotifier` |
| Yönlendirme | Flutter `Navigator` |
| Seslendirme | `flutter_tts` |
| Markdown | `flutter_markdown` |
| Yedekleme | JSON dışa/içe aktarma |

### 10.2 Klasör yapısı

```
lib/
├── main.dart
├── app/            router, theme, constants
├── data/
│   ├── db/         content_database.dart, progress_database.dart, seed_loader.dart
│   ├── models/
│   └── repositories/  word, verb, grammar, srs, stats, settings
├── domain/
│   ├── srs/        box_scheduler.dart, session_builder.dart
│   ├── quiz/       question_generator.dart, distractor_picker.dart
│   └── placement/  placement_test.dart
├── motion/         ← animasyonun ortak dili, bölüm 6
│   ├── motion_tokens.dart     süreler, eğriler, yay tanımları tek yerde
│   ├── card_stack.dart        kart destesi, elle yazılan kaydırıcı
│   ├── swipe_controller.dart  sürükleme fiziği ve eşikler
│   ├── flip_card.dart         perspektifli çevirme
│   ├── swipe_badge.dart       yön rozeti ve renk katmanı
│   ├── tilt_parallax.dart     jiroskop efekti
│   └── transitions.dart       sayfa geçişleri, liste girişleri
├── features/
│   ├── onboarding/ level_select_screen.dart, placement_screen.dart
│   ├── vocab/      deck_select_screen.dart, swipe_screen.dart, widgets/
│   ├── verbs/
│   ├── grammar/
│   ├── quiz/
│   └── progress/
└── services/       tts_service.dart, notification_service.dart, backup_service.dart

content/            veri boru hattı, DATA_PIPELINE.md içinde ayrıntılı
assets/db/content.db
```

### 10.3 Önemli mimari kararlar

- İçerik ve ilerleme veritabanları ayrıdır. İçerik güncellemesi ilerlemeyi silmez.
- Kutu ilerletme mantığı (`box_scheduler.dart`) saf fonksiyon olarak yazılır. Veritabanına bağlı olmadığı için birim testi kolaydır ve bu mantık uygulamanın en kritik parçasıdır.
- Tüm sorgular repository katmanından geçer. Ekranlar doğrudan SQL çalıştırmaz.
- `words` tablosunda `(level, freq_rank)` ve `(theme, level)` üzerinde indeks bulunur. On bin satırda deste sorgusu böyle hızlı kalır.
- İçerik veritabanı sürümlüdür. Asset içeriği byte olarak değiştiğinde yerel kopya yenilenir; `progress.db` ayrı kalır. Sıra bağımsız içerik kimlikleri ve `content_aliases` eski ilerlemeyi yeni kimliklere taşır.
- **Bütün süreler, eğriler ve yay tanımları `motion/motion_tokens.dart` içinde tek yerde durur.** Hiçbir widget kendi içinde `Duration(milliseconds: 300)` yazmaz. Animasyon hissini ayarlamak tek dosyada sayı değiştirmek olmalıdır, otuz dosyayı taramak değil. Animasyon hızı ayarı da bu katmandan geçer.
- `motion/` klasörü hiçbir özelliğe bağlı değildir. İçindeki bileşenler kelime kartını da fiil kartını da bilmez, sadece kendilerine verilen widget'ı hareket ettirirler.

---

## 11. Yol Haritası

Tahminler günde iki üç saat çalışma varsayımıyla verilmiştir. Veri boru hattı ile uygulama geliştirme paralel yürütülebilir.

### Faz 0 — Kurulum (1 gün)
Flutter SDK ve Android Studio kurulumu, proje iskeleti, tema, alt sekme çubuğu, telefonda boş uygulamanın çalıştığının doğrulanması.

### Faz 0.5 — Hareket prototipi (3-4 gün) ⭐

**Bu faz atlanamaz ve ertelenemez.** Animasyon birinci öncelik olduğu için diğer her şeyden önce gelir.

Veritabanı yok, içerik yok, mimari yok. Tek bir dosyada sahte üç kelimeyle sadece hareket.

- `motion_tokens.dart` ve `card_stack.dart` yazılır
- Sürükleme fiziği, dönme merkezi, eşikler, yay geri dönüşü
- Dört yönlü rozet ve renk katmanı, eşikte titreşim
- Perspektifli kart çevirme
- Yarıda kesilebilirlik testi: kartlar hızlı hızlı kaydırılır, takılma olmamalı
- Gerçek telefonda DevTools performans katmanı ile ölçüm

Çıktı atılacak bir prototip değildir, `motion/` klasörünün ilk hali olur ve projeye taşınır.

**Bitiş ölçütü:** telefonda on kart üst üste hızlıca kaydırıldığında tek bir kare düşmemesi ve hissin doğru olması. His doğru değilse yay değerleri, süreler ve eğriler üzerinde oynanır. Bu faz gerekirse uzar, sonraki fazlara geçmek için acele edilmez.

### Faz 1 — Veri boru hattı, birinci geçiş (6-8 gün)
Kaynak veri kümelerinin indirilmesi, birleştirme scriptlerinin yazılması, seviye atama, örnek cümle eşleştirme, doğrulama ve `content.db` üretimi. Ayrıntı [DATA_PIPELINE.md](DATA_PIPELINE.md) belgesinde.

*Bu fazın çıktısı altı seviyeyi de kapsayan ilk veri paketidir. Kalite henüz kusursuz değildir, gözden geçirme Faz 8'de sürer.*

### Faz 2 — Veri katmanı (2-3 gün)
Drift şemaları, iki veritabanı, `seed_loader`, repository katmanı, veriyi gösteren basit bir liste ekranı.

### Faz 3 — Onboarding ve seviye sistemi (2-3 gün)
Seviye seçim ekranı, yerleştirme testi, ayarlarda seviye değiştirme, deste seçim ekranının seviye ve tema filtreleri.

### Faz 4 — Kelime kaydırma (4-5 gün)
Faz 0.5'ten gelen `motion/` bileşenlerinin gerçek veriye bağlanması. Kart ön ve arka yüz içeriği, `box_scheduler`, `session_builder`, üst ilerleme çubuğu, oturum sonu özeti ve sayı artma animasyonu, hata bildirme düğmesi.

Hareket işi Faz 0.5'te bittiği için bu faz beklenenden hızlı geçer.

*İlk kullanılabilir sürüm burada çıkar.*

### Faz 5 — Quiz motoru (3-4 gün)
Dört quiz tipi, akıllı çeldirici seçici, soru ekranı, sonuç ekranı, quiz sonucunun kart kutusunu etkilemesi.

### Faz 6 — Fiil çekimi (4-5 gün)
Çekim kartı, tam çekim tablosu, zaman ve grup filtreleri, çekim quizi ve şahıs bazlı çeldiriciler.

### Faz 7 — Dilbilgisi (5-6 gün)
Markdown ders görüntüleyici, kuruluş tabloları, zaman çizelgesi görseli, 24 dersin yazılması, ders sonu mini quizler, dersten ilgili çekim destesine geçiş.

*Dersler elle yazılır. Otomatik üretilemeyecek tek içerik budur ve zaten hacmi küçüktür.*

### Faz 8 — İlerleme ve alışkanlık (3 gün)
İstatistik ekranı, altı seviyenin ilerleme çubukları, seri sayacı, günlük hedef, akşam bildirimi, zorlandıklarım ve yıldızlılar listeleri.

### Faz 9 — Cila ve ikinci animasyon geçişi (4-5 gün)
Seslendirme entegrasyonu ve hız ayarı, koyu tema, ayarlar ekranı, JSON dışa ve içe aktarma ile yedekleme, boş durum ekranları.

Buna ek olarak bölüm 6.7'deki ekstra dokunuşlar bu fazda yapılır: jiroskop parallaksı, ağırlıklı gölge, seri alevi, zaman çizelgesi animasyonu, hedef tamamlama parçacıkları. Sekme geçişleri, liste girişleri ve quiz geri bildirim animasyonları baştan sona gözden geçirilir.

Uygulamanın tamamı bir kez daha telefonda performans katmanı açık gezilir. Kare düşüren her ekran düzeltilir.

### Faz 10 — Dağıtım (1 gün)
İmzalı APK üretimi, telefona kurulum, uygulama simgesi ve açılış ekranı.

### Faz 11 — İçerik gözden geçirme (sürekli)
Sıklık sırasına göre gözden geçirme. Önce A1'in ilk 300 kelimesi, sonra A2, böyle devam. Uygulama içinden bayraklanan kartlar öncelikli listeye girer. Bu iş hiç bitmez ama uygulamanın kullanımını da engellemez.

**Kullanılabilir ilk sürüme kadar tahmini süre: 4 hafta. Tüm modüllerle bitmiş ürün: 7-8 hafta.**

Hareket prototipi ve ikinci animasyon geçişi toplam süreye yaklaşık bir hafta ekler. Bu hafta uygulamanın en çok hissedilen kısmına gider.

---

## 12. Riskler ve Önlemler

| Risk | Etki | Önlem |
|---|---|---|
| Otomatik üretilen Türkçe karşılıkların bir kısmı yanlış olur | Yüksek | Sıklık sırasına göre gözden geçirme, uygulama içi hata bildirme düğmesi, her satırda güven skoru. Düşük güvenli satırlar öncelikli incelenir |
| Örnek cümleler seviyeye göre çok zor olur | Orta | Cümle seçiminde "tüm kelimeleri hedef seviyede veya altında" filtresi uygulanır. Bu filtre boru hattının en önemli parçasıdır |
| Bazı kelimelerde Türkçe karşılık hiç bulunamaz | Orta | İngilizce üzerinden ikinci geçiş, hâlâ boşsa kelime veri paketine alınmaz. Eksik karşılıklı kart göstermek hatalı kart göstermekten iyidir ama boş kart hiç iyi değildir |
| Kaynak veri kümelerinin lisans uyumu | Orta | Kullanılan kaynakların hepsi açık lisanslı. Uygulama içinde bir "kaynaklar" ekranı ile atıf verilir. Ayrıntılar boru hattı belgesinde |
| Cihazda Fransızca konuşma motoru kurulu değil | Düşük | Açılışta kontrol, kurulu değilse ayarlara yönlendiren uyarı. Ses olmadan da uygulama tam çalışır |
| SRS mantığında hata, kartların yanlış zamanda gelmesi | Orta | `box_scheduler` saf fonksiyon olarak yazılır, birim testleri ilk gün yazılır |
| Uygulamanın kullanılmaması | Orta | Günlük hedefi düşük tut (20 kart, üç dakika). Seri sayacı ve akşam bildirimi |
| Animasyonlar telefonda takılır | Yüksek | Bölüm 6.8'deki performans bütçesi. Ölçüm hep gerçek telefonda yapılır, emülatörde asla. Takılma bulunmadan sonraki işe geçilmez |
| Hareket hissi bir türlü doğru olmaz | Orta | Faz 0.5 bunun için var. Bütün ayar sayıları `motion_tokens.dart` içinde tek yerde durur, denemek dakikalar sürer |
| Animasyon işi projeyi geciktirir | Düşük | Faz 0.5 sabit bütçelidir ve çıktısı atılmaz, doğrudan projeye girer. Faz 4 bu sayede kısalır |

---

## 13. İlk Sürümün Dışında Bırakılanlar

- Bulut senkronizasyonu ve hesap sistemi
- Dinleme ve konuşma alıştırmaları
- Yazma quizi (klavyeden Fransızca yazma, aksan girişi sorun çıkarır)
- Widget ve kilit ekranı kartı
- Kendi kelimeni ekleme
- Cümle kurma oyunu (kelimeleri sıraya dizme)
- Kaydedilmiş insan sesi (cihaz konuşma motoru yeterli)

---

## 14. Tartışılacak Açık Konular

1. **Aşağı kaydırma gerçekten gerekli mi?** Dört yön yerine üç yönle başlanıp dördüncüsü sonra eklenebilir.

2. **Deyimler kelimelerle aynı destede mi olsun?** Ayrı deste odaklanmayı artırır, karışık deste çeşitlilik sağlar. Ayrı deste olarak başlayıp isteğe bağlı karıştırma eklenebilir.

3. **Bir kelimeye kaç örnek cümle konsun?** Bir cümle yeterli görünüyor ama iki cümle farklı kullanımları gösterir. Veri boru hattı iki cümle çıkarabiliyorsa ikisi de saklanır, kartta biri gösterilir, diğeri quizde boşluk doldurma sorusunda kullanılır.

4. **Kelime sayısı hedefleri doğru mu?** C1 ve C2 için 3.500 kelime iyimser olabilir. Boru hattı ne çıkarırsa ona göre ayarlanır.
