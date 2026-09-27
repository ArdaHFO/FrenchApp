# Yerel içerik inceleme kuyruğu — FA-012

Bu araç çalışma durumunu yönetir; sözlük okumaz, LLM çağırmaz ve içerik yayımlamaz. Kaynak metinleri ve geçmiş kararları hash'li kopyalarda saklar. Gerçek anlam incelemesi aktif Codex oturumunda yapılır; oturum kapandığında otomatik sürmez. `content.db` salt okunur; kullanıcı `progress.db` dosyası hiçbir komutta kullanılmaz.

## Konumlar ve başlangıç

Repository kökünde Python 3.12.10 ile çalıştırıldı. Yeni bağımlılık yok.

- Araç: `content/tools/review_queue.py`.
- Kalıcı inceleme alanı: `content/review_work/fa012/`.
- Sidecar: `registry.sqlite`; uygulama veya kullanıcı ilerleme DB'si değildir.
- İçerik yolu bağlamı: `workspace.json`.
- Değişmez kaynak kopyaları: `sources/<sha256>.<uzantı>`; gerçek adları sidecar `sources` tablosunda ve FA-012-summary.json içinde.
- Devir paketi: `.staging/FA-012-handoff-20260912/`. Özgün dosyaların hiçbirinin üzerine açılmadı; hash listesi doğrulandı.
- `pubspec.yaml:38-40` yalnız `assets/db/content.db` ve `.version` dosyasını paketler; bu çalışma alanı APK varlığı değildir.

Komutlar repository kökünde:

```powershell
$env:PYTHONIOENCODING='utf-8'
python -B content/tools/review_queue.py --work content/review_work/fa012 init --db assets/db/content.db
python -B content/tools/review_queue.py --work content/review_work/fa012 sync
python -B content/tools/review_queue.py --work content/review_work/fa012 import-history --package .staging/FA-012-handoff-20260912 --manifest content/overrides/editorial_fa010b.json --manifest-sha256 aa3dbb537825c1aae78c3514fffb8e53bc60fda0d5f1685e625737874d219bc8
python -B content/tools/review_queue.py --work content/review_work/fa012 status
```

`init` mevcut doğru çalışma alanını yeniden açabilir. Başka içerik yoluna bağlı veya yeni fakat dolu bir çalışma alanına körlemesine yazmaz. `sync` bütün words envanterini ve yapısal bulguları yeniler; inceleme geçmişini silmez. Aynı arşivi tekrar import etmek no-op'tur; eski kararlar sonraki yeni kararların üzerine tekrar yazılmaz. Geçmiş FA-010A dosyaları eski metni temsil eder; güncel metin olarak kullanılmaz.

## Devam etme ve sonuç kabulü

```powershell
python -B content/tools/review_queue.py --work content/review_work/fa012 next
python -B content/tools/review_queue.py --work content/review_work/fa012 resume --job 1
python -B content/tools/review_queue.py --work content/review_work/fa012 status
```

İlk gerçek iş #1, 25 kayıtla hazırdır; henüz hiçbirine yeni anlamsal sonuç yazılmadı. İlk kimlik `w_b0d293d24079bda68612`. `next` açık iş varsa yeni iş üretmez; `resume` sadece eksik kayıtları, sabit kimlik/sıra/fingerprint ve incelenecek başlangıç metniyle döndürür. Önce A1–A2 grubu, bu grup içinde yapısal tarama hatası olmayanlar ve normal öğrenmeye uygunlar öncelik alır; ardından seviye, `freq_rank ASC, id` kullanılır. Sonra diğer seviyeler gelir. Uygun olmayan veya örneği eksik kayıtlar silinmez ve sonsuza kadar dışlanmaz; daha sonra aynı inceleme kuyruğuna girebilir. Öğrenmeye uygunluk bir öncelik sinyalidir, anlamsal doğruluk veya editoryal erişim yasağı değildir. Bu, uygulamanın kullanıcı seviyesi veya SRS sırası değildir.

`next --size 25` yalnız yeni işin boyutunu belirler. Onaylı-bekleyen, uygulanmış, korunması onaylı ve açık yapısal/kaynak engelli kayıtlar yeniden incelenmemiş havuzuna girmez. Kullanıcıya her 25 kayıt için yeni büyük prompt veya geçmiş dosyalarını taşıma zorunluluğu getirmez. Yeni aktif oturuma kısa talimat yeterlidir: “FA-012 kuyruğunun açık işini resume ile al, kaynakları gerçekten incele, kayıt bazlı sonuçları complete ile kaydet ve kısa durumu bildir.”

`complete` gerçek sonuç dosyasının yolunu alır:

```text
python -B content/tools/review_queue.py --work content/review_work/fa012 complete --job 1 --results <bu-işin-sonuç-dosyası.json>
```

Bu son komut gerçek içerikte bu tur çalıştırılmadı. Sonuç dosyası henüz yoktur; buradaki yol bir sonraki aktif incelemenin çıktısıdır. Sentetik CLI demosunda komut gerçek dosyayla çalıştırıldı; tam yolu ve sonucu FA-012-summary.json'da bulunur.

Sonuç zarfı:

```json
{
  "results": [
    {
      "id": "resume çıktısındaki gerçek ID",
      "fingerprint": "resume çıktısındaki fingerprint",
      "algorithm": "word-review-v1",
      "scope": ["target_meaning_alignment", "example_and_translation_alignment", "visible_usage_information"],
      "reviewer": "Codex — model destekli inceleme",
      "date": "gerçek inceleme tarihi",
      "status": "proposed_keep",
      "review": {
        "id": "aynı ID",
        "current": {},
        "current_example": {},
        "target_sense": "seçilen tek anlam",
        "reason": "bu kayda özgü gerçek gerekçe",
        "proposed_fields": {},
        "human_review_performed": false,
        "french_source_status": "source_supported",
        "sources": [],
        "example_origin": "mevcut"
      }
    }
  ]
}
```

Bu yalnız biçim açıklamasıdır, kabul edilebilir bir sonuç değildir: `current/current_example` gerçek başlangıç alanlarının tam kopyası olmalı; sources boşken source_supported reddedilir. Kaynak kaydı `url`, `access_date`, `access_status=body_inspected` ve desteklediği iddiayı içermeli. Bunlar worker'ın raporladığı ziyaretlerdir; CLI web sayfasının gerçekten açıldığını bağımsız kanıtlayamaz. URL varlığı tek başına yeterli değildir; `title_only`, eksik kaynak ve insan uzman iddiası reddedilir. Erişim yoksa `status=blocked_source`, `french_source_status=not_externally_verified` kullanılmalı; bu onay değildir.

Diğer kabul durumları `proposal` ve `blocked_structure`. `proposed_keep` henüz editoryal koruma onayı değildir. `complete`, `retained_current`, `approved_pending_application` veya `applied` statüsü veremez. Onay ve üretim yayını ayrı kalır. Yeni sonucun değişen örnek dilleri için gerçek metin farkına uyan `language_attribution_plan` gerekir; editorial_pilot.validate_review gevşetilmedi.

Her geçerli sonuç kısa ayrı transaction ile commit olur. Sonraki kayıt hata verirse önceki sonuç korunur; reddedilenler ID/gerekçeyle döner ve eksik kalır. Aynı sonuç tekrar verilirse çoğalmaz, farklı sonuç aynı tamamlanmış kaydı ezemez. Bozuk JSON hiçbir yeni sonucu tamamlamaz. Exit 0 başarılı/idempotent, exit 1 kısmi kayıt reddi, exit 2 işlem/dosya/sözleşme hatasıdır.

## Metin sürümü ve yerel eşzamanlılık

Fingerprint `word-review-v1` ve açık kapsam sabittir. Dahil edilenler: lemma, POS, article/gender, plural, IPA, TR/EN anlamları (yardımcı EN dahil), note/literal/register, gösterimi etkileyen is_idiom; bütün ordinal=0 FR/EN/TR metinleri, dil kaynak ID/yazarları, tr_direct ve max_level. Örneklerin fiziksel id, word_id ve sorgu satır sırası hash'e girmez; yinelenen ordinal=0 satırların çokluğu korunur. Word ID ayrıca kaydın anahtarıdır.

Seviye/frekans/tema, reviewed/needs_review/confidence/tr_path ve global DB meta/hash'i semantik fingerprint'e girmez. Envanter bu alanları ayrıca saklar. Dolayısıyla bu fingerprint bir öğrenme uygunluğu ya da v1 journey revizyonu değildir. Kaynak DB SHA-256 her envanter ve inceleme/uygulama kaynağıyla ayrıca tutulur. Hedef metin/POS/atıf değişince eski inceleme `stale` olur; başka kart veya global meta değişince aynı kart gereksiz yere eskimez.

Content baytları son sync'ten sonra değişirse next/resume/complete/import kabulü durur ve sync istenir. Sync sonrası sabit işte değişmiş kayıt açıkça işaretlenir; eski fingerprint'li sonuç kabul edilmez. Bilerek yeni sürümü incelemek için yalnız değişmiş/çıkarılmış, tamamlanmamış öğe serbest bırakılabilir:

```text
python -B content/tools/review_queue.py --work content/review_work/fa012 supersede --job 1 --id <değişmiş-ID>
```

Bu işlem anlamsal tamamlanma değildir; geçmiş snapshot durur. İşin diğer eksikleri bittiğinde next yeni metin için yeni iş oluşturabilir. Kaynak engelleri otomatik başarıya çevrilmez veya otomatik yeniden denenmez; raporda ayrı karar/erişim işi olarak kalır.

`BEGIN IMMEDIATE`, tek açık iş için unique index ve kayıt bazlı sonuç anahtarı iki yerel CLI çağrısını seri hâle getirir. İki `next` aynı mantıksal işe döner; ayrı bir kopyayı sahiplenmez. Varsayılan owner `local-codex`; farklı owner açık işi alamaz. Açık `--owner` ile aynı yerel işi devralmak güvenlik yetkisi veya dağıtık lease değildir. İki aynı-owner işlem aynı sonucu gönderirse ikincisi idempotent, çelişirse görünür hata olur. Rastgele sleep, arka plan worker veya sonsuz retry yok.

Bu araç, eşzamanlı kötü niyetli dosya değiştirmesine karşı genel dosya sistemi güvenlik sistemi değildir. Path.resolve/samefile ile başlangıçtaki girdi/çıktı ve hardlink çakışmaları reddedilir. Mevcut çıktı farklıysa üzerine yazılmaz. Yeni bir ad kullanın veya stdout alın; mevcut geçmişi temizlemek gerekmez.

## Kısa ve ayrıntılı rapor

```powershell
python -B content/tools/review_queue.py --work content/review_work/fa012 status
python -B content/tools/review_queue.py --work content/review_work/fa012 report
python -B content/tools/review_queue.py --work content/review_work/fa012 exceptions
python -B content/tools/review_queue.py --work content/review_work/fa012 spot-check --size 5 --seed 12012
```

`status` kısa sayılar, son complete sonucu, açık işin kalanları ve karar gereken ID'leri verir. `report` tüm kaynak hash/path ve seviye dağılımlarını ekler. `--output` isteğe bağlıdır; mevcut farklı dosyayı ezmez. Ayrıntılı envanter/findings sidecar'da kalır. Rastgele kontrol, ID sıralı güncel `proposed_keep` sonuçlarından sabit seed ile `Random.sample` kullanır; sürüm `spot-check-v1`, doğrulanan Python 3.12.10. Önceden onaylı 64 kaydı yeniden yeni-worker örneklemi gibi göstermez; gerçek yeni sonuç olmadığı için bu tur gerçek örneklem boştur. Sentetik test, yeni korunmalı önerilerden kontrol seçiminin kararlı olduğunu doğrular. Seçilmemiş kayıtlar onaylanmaz.

## Bu turun gerçek kapsamı

15.423 word kaydı hafif yapısal taramadan geçti. Bu sadece boş anlam, ordinal=0 sayısı, kopuk example bağlantısı, eksik çeviri/kaynak-yazar bilgisi ve aynı TR metni kurallarını kapsar. Aynı TR anlamını paylaşan 9.205 kayıt bir review_hint alır; yanlış çeviri olarak sayılmaz. 5.628 kayıtta ordinal=0 örnek yok, 1.668 satırda TR örnek yok; bunlar otomatik dil yargısı değildir. Lemma alt dizisi eşleşmesi kuralı kullanılmadı. Ayrı verbs/conjugations tablolarının anlamsal incelemesi yapılmadı.

Normal uygunluk 5.149, uygun olmayan 10.274; uygun A1–A2 1.341 ve bu havuzda henüz inceleme geçmişi olmayan 1.191 kayıt var. 150 geçmiş kaydın güncel içerik eşleşmesi 36 uygulanmış / 64 koruma / 49 onaylı-bekleyen / 1 blocked_structure olarak doğrulandı. `quoi` sorunsuz sayılmadı. `travers` için onaylı TR örnek “Küçük bir kusuru var: çok konuşuyor.” olarak karar olayında korunuyor; DB'ye yazılmadı. `gens.article=les` sonraki uygulayıcı izin listesi için açık ihtiyaç olarak exceptions'ta duruyor.

Eski inceleme ziyareti, ChatGPT'nin ayrıca bildirdiği bağımsız kontrol, ürün onayı ve mevcut DB'de uygulama eşleşmesi ayrı kaynaklardır. Import hiçbir sözlük sayfasını yeniden açmadı. FA-010A adapter'ı yalnız gerçek metin farkından atıf planı türetti; olmayan ziyaret/insan onayı üretmedi. Kaynak tarihlerinin ve inceleyen bilgilerinin özgün halleri hash'li sample/review/decision/evidence kopyalarında bulunur. Uygulama olayı eski ve yeni fingerprint'i bağlar; eski içerik üretim sürecinin geçmişte çalışmasını yeniden oynattığımız anlamına gelmez.

`content/overrides/editorial_fa010b.json`, editoryal yayın motoru, Python içerik üreticileri, Flutter ve bağımlılıklar değişmedi. Yeni araç hiçbir 49-kart UPDATE işlemi veya POS/kimlik taşıması yapmaz. Yeni onay/uygulama paketi ve kaynak engelinin kaldırılması için ayrı açık kararlar gerekir.

## Testler

```powershell
python -B -m unittest discover -s content/tools/tests -p "test_review_queue.py" -v
python -B -m unittest discover -s content/tools/tests -p "test_*.py" -v
```

Yeni testler sentetik gerçek SQLite şeması, trigger hatası, iki bağlantı bariyeri ve yeni CLI süreçleri kullanır. DB/source çıktısı hardlink çakışmaları bu ortamda sınandı. Mevcut çıktı yolu testlerindeki Windows symlink ayrıcalık atlamaları korunur; izin değiştirilmez. Güncel gerçek sayılar ve komut sonuçları FA-012-summary.json'dadır. Flutter/APK bu tur çalıştırılmadı; geçmiş 177 test bu turun sonucu değildir.
