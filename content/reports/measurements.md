# Faz 1 Ölçümleri

Ölçüm tarihi: 2026-08-09 21:57
Süre: 124 saniye

Bu üç sayı DATA_PIPELINE.md bölüm 9'da planın kalanını belirleyen ölçümler
olarak tanımlanmıştı.

## 1. Tatoeba — Fransızca/Türkçe cümle bağı

| Ölçüm | Sayı |
|---|---|
| Toplam cümle (tüm diller) | 13.537.806 |
| Fransızca cümle | 723.290 |
| İngilizce cümle | 2.033.133 |
| Türkçe cümle | 748.577 |
| Toplam çeviri bağı | 28.361.472 |
| **Türkçe çevirisi olan Fransızca cümle** | **12.245** (1.7%) |
| İngilizce çevirisi olan Fransızca cümle | 375.094 |
| **Hem İngilizce hem Türkçe çevirisi olan** | **8.284** (1.1%) |

## 2. FLELex — seviye kapsaması

| Ölçüm | Sayı |
|---|---|
| Lexique benzersiz lemma (islem=1) | 43.562 |
| FLELex lemma | 13.381 |
| **Kesişim** | **12.846** |
| **Kapsama oranı** | **29.5%** |

FLELex sütunları: `['word', 'tag', 'freq_A1', 'freq_A2', 'freq_B1', 'freq_B2', 'freq_C1', 'freq_C2', 'freq_total']`

Lexique kelime türü dağılımı (ilk 10): `{'NOM': 28886, 'ADJ': 10599, 'VER': 5289, 'ADV': 1822, 'ONO': 236, 'ADJ:num': 123, 'PRE': 80, 'PRO:per': 53, 'PRO:ind': 44, 'ADJ:ind': 36}`

## 3. DBnary — Fransızca'dan Türkçe'ye doğrudan çeviri

| Ölçüm | Sayı |
|---|---|
| Taranan satır | 21.679.597 |
| Toplam çeviri kaydı | 1.036.146 |
| **Türkçe hedefli çeviri** | **7.388** |
| İngilizce hedefli çeviri | 161.457 |

En çok çeviri olan diller: `{'eng': 161457, 'ita': 73340, 'deu': 63915, 'spa': 62028, 'hrv': 42040, 'nld': 41832, 'por': 29964, 'oci': 29556, 'cat': 27060, 'rus': 24478, 'epo': 21490, 'pol': 20683}`
