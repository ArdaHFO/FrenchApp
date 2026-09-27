# Aşama 9 — Dönüşlü Fiiller

Tarih: 2026-08-15 21:59

**132 dönüşlü fiil**, 5.902 çekim satırı.

## Neden elle yazıldı

Dönüşlü fiil, temel fiilin `se` almış hâli değildir; çoğu zaman
başka bir fiildir. Otomatik üretim burada anlam kayması yapar:

| Temel | Dönüşlü |
|---|---|
| rendre — geri vermek | se rendre — gitmek, teslim olmak |
| rappeler — geri çağırmak | se rappeler — hatırlamak |
| passer — geçmek | se passer — olmak, yaşanmak |
| attendre — beklemek | s'attendre à — ummak |
| tromper — aldatmak | se tromper — yanılmak |
| entendre — duymak | s'entendre — anlaşmak |

Türkçe karşılıklar ve tür bilgisi elle yazıldı. Otomatik olan tek
şey çekim: o tamamen kurala bağlı olduğu için üretmek elle
yazmaktan daha güvenli.

## Tür dağılımı

| Tür | Sayı | Anlamı |
|---|---|---|
| `reflechi` | 48 | Özneye dönüyor (se laver) |
| `reciproque` | 14 | Karşılıklı (se parler) |
| `essentiel` | 20 | Sadece dönüşlü var (se souvenir) |
| `sens` | 50 | Anlamı değişiyor (se rendre) |

## Örnek çıktı — se laver

- **present**: je me lave · tu te laves · il se lave · nous nous lavons · vous vous lavez · ils se lavent
- **passe_compose**: je me suis lavé(e) · tu t'es lavé(e) · il s'est lavé · nous nous sommes lavé(e)s · vous vous êtes lavé(e)(s) · ils se sont lavés
- **imperatif**: lave-toi · lavons-nous · lavez-vous