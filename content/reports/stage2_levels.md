# Aşama 2 — Seviye Ataması

Tarih: 2026-08-09 22:16 · Süre: 1 saniye

## Kural

```
seviye = sıklığın eşiği ilk aştığı seviye
eşik   = max(0.5, 0.10 × kelimenin en yüksek seviye sıklığı)
```

Mutlak taban gürültüyü eler, göreli ölçüt kelimeye göre uyarlanır.

## Kaynak dağılımı

| Kaynak | Sayı | Oran |
|---|---|---|
| FLELex (kelime + tür eşleşti) | 12.262 | 28.5% |
| FLELex (sadece kelime eşleşti) | 540 | 1.3% |
| Sıklık bandı yedeği | 30.274 | 70.3% |

**FLELex kapsaması: 29.7%** (12.802 / 43.076)

## Seviye dağılımı

| Seviye | Toplam | FLELex'ten | Sıklık bandından |
|---|---|---|---|
| A1 | 2.531 | 2.522 | 9 |
| A2 | 1.824 | 1.804 | 20 |
| B1 | 2.900 | 2.783 | 117 |
| B2 | 2.292 | 1.583 | 709 |
| C1 | 4.656 | 2.318 | 2.338 |
| C2 | 28.873 | 1.792 | 27.081 |

## Ayrışan atamalar: 5.037

İki yöntem iki seviyeden fazla ayrıştığında satır gözden geçirme
kuyruğuna girer. Genelde iki sebepten olur: kelime öğretim
kitaplarında geçmiyordur ama günlük dilde çok kullanılır, ya da tersi.

| Lemma | Tür | FLELex | Sıklık bandı | Sıra |
|---|---|---|---|---|
| deux | ADJ:num | B1 | A1 | 46 |
| trois | ADJ:num | B1 | A1 | 123 |
| dont | PRO:rel | B1 | A1 | 151 |
| accord | NOM | B1 | A1 | 208 |
| foutre | VER | B1 | A1 | 285 |
| cinq | ADJ:num | B2 | A1 | 306 |
| truc | NOM | B2 | A1 | 343 |
| propos | NOM | B2 | A1 | 386 |
| six | ADJ:num | C1 | A1 | 398 |
| rapport | NOM | B1 | A1 | 402 |
| second | ADJ | B1 | A1 | 415 |
| docteur | NOM | B1 | A1 | 429 |