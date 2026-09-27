# 08 - Content architecture decision

Date: 2026-09-27. Decision support for the technical lead; no provider code or product migration implemented.

## A. Executive architecture decision

**Recommend HYBRID ENRICHMENT, Option A. Classify `content.db` as KEEP.** Retain the approved local learning snapshot and add explicitly optional online dictionary/pronunciation enrichment. Do not make ordinary learning, search, Journey, conjugations or progress dependent on a lexical provider.

Measured reasons:

- Current DB is **24,387,584 bytes (23.258 MiB)**. Conjugations plus their indexes account for **14,143,488 bytes (57.99%)**. Step 07 rejected API replacement of conjugations. Words including indexes are only 14.86% of the DB.
- Removing English/IPA for the 5,067 eligible ordinary words saves only **245,760 bytes (0.234 MiB, 1.01%)**, including repacking, while losing current offline display/search behavior. Even removing those fields from every non-idiom word saves only 0.672 MiB.
- The smallest measured, current-runtime-consumption-preserving projection is **22,020,096 bytes (21 MiB)**. Most savings come from 8,063 additional examples never loaded by today's runtime, plus unused payload. It retains all visible examples, meanings, IPA, conjugations, aliases and curriculum identity. This is a conditional future packaging experiment, not a shippable replacement or proof of an absolute minimum.
- Step 07 projected 19.42 MiB raw full-entry cache or 21.84 MiB full+definitions for 5,149 entries. A new selected-field projection from those existing responses averages 626 bytes/entry, roughly 3.07 MiB for that population, before cache overhead/audio. Even that exceeds the English/IPA removal saving.

The principal API value is broader exact-word dictionary coverage, additional senses and pronunciation/audio metadata. Storage replacement is a weak justification. No source, test, dependency, content marker or existing report was changed.

## B. Current DB physical composition

### Measurement method

The bundled source was opened read-only throughout. Python's bundled SQLite lacks `dbstat`; the already-installed Android SDK `sqlite3.exe` (SQLite 3.50.6) supports it and was run with `-readonly -json`. No tool installation or DB extension was needed. Python read-only queries supplied schema/row/logical counts.

The page measurement was:

```sql
SELECT name, pagetype, count(*) AS pages,
       sum(pgsize) AS allocated, sum(payload) AS payload,
       sum(unused) AS unused, sum(ncell) AS cells
FROM dbstat GROUP BY name, pagetype;
```

Allocated bytes include the B-tree's pages; payload is SQLite record payload, not merely text. [SQLite's dbstat documentation](https://www.sqlite.org/dbstat.html) distinguishes payload/unused bytes and excludes freelist/pointer-map/lock pages. Here all reported allocation sums exactly to the file size: 5,954 pages of 4,096 bytes, zero freelist pages. Thus no unexplained residual allocation needs estimating. Schema and sequence are reported separately from domain tables.

### Table totals (indexes assigned to their owner)

| Table | Rows | Table payload bytes | Table allocated bytes | Index bytes | Combined % DB |
|---|---|---|---|---|---|
| words | 15,423 | 2,371,458 | 2,539,520 | 1,085,440 | 14.864% |
| examples | 17,858 | 3,145,305 | 3,371,008 | 548,864 | 16.073% |
| verbs | 2,698 | 302,863 | 327,680 | 155,648 | 1.982% |
| conjugations | 121,354 | 6,774,369 | 7,581,696 | 6,561,792 | 57.995% |
| grammar_lessons | 19 | 60,118 | 86,016 | 8,192 | 0.386% |
| word_relations | 7,560 | 363,978 | 409,600 | 643,072 | 4.316% |
| content_aliases | 18,075 | 665,995 | 770,048 | 274,432 | 4.283% |
| meta | 14 | 520 | 4,096 | 4,096 | 0.034% |
| sqlite_sequence | 2 | 31 | 4,096 | 0 | 0.017% |
| sqlite_schema | 25 | 4,110 | 12,288 | 0 | 0.050% |

### Every index

Primary-key/unique autoindexes are real disk allocations. Do not count them twice in addition to the owner totals above.

| Index | Owner | Payload bytes | Allocated bytes | % DB |
|---|---|---|---|---|
| idx_conj_tense | conjugations | 2,410,399 | 2,797,568 | 11.471% |
| idx_conj_verb | conjugations | 3,365,017 | 3,764,224 | 15.435% |
| idx_examples_word | examples | 482,194 | 548,864 | 2.251% |
| idx_relations_word | word_relations | 203,992 | 233,472 | 0.957% |
| idx_verbs_level_rank | verbs | 26,845 | 40,960 | 0.168% |
| idx_verbs_reflexive | verbs | 13,362 | 28,672 | 0.118% |
| idx_words_idiom | words | 76,987 | 131,072 | 0.537% |
| idx_words_level_rank | words | 155,039 | 208,896 | 0.857% |
| idx_words_theme_level | words | 226,877 | 278,528 | 1.142% |
| sqlite_autoindex_content_aliases_1 | content_aliases | 213,992 | 274,432 | 1.125% |
| sqlite_autoindex_grammar_lessons_1 | grammar_lessons | 151 | 4,096 | 0.017% |
| sqlite_autoindex_grammar_lessons_2 | grammar_lessons | 329 | 4,096 | 0.017% |
| sqlite_autoindex_meta_1 | meta | 260 | 4,096 | 0.017% |
| sqlite_autoindex_verbs_1 | verbs | 72,718 | 86,016 | 0.353% |
| sqlite_autoindex_word_relations_1 | word_relations | 377,872 | 409,600 | 1.680% |
| sqlite_autoindex_words_1 | words | 416,293 | 466,944 | 1.915% |

All indexes total **9,281,536 bytes (38.06% of the file)**. Total B-tree payload is 21,731,074 bytes; unused in-page capacity is 425,410 bytes. The remaining 2,231,100 bytes are page/cell/header structure, not removable lexical prose. There is no large freelist to reclaim. A VACUUM-only control saved only 24,576 bytes.

The two conjugation indexes alone consume 6,561,792 bytes. They support actual verb/tense queries; deleting them is not equivalent to lexical offloading. Query performance and alternative key/schema layout were not benchmarked, so no index removal is recommended here.

## C. Logical field/payload composition

For TEXT fields, `sum(length(column))` counts characters and `sum(length(CAST(column AS BLOB)))` counts UTF-8 bytes. NULL contributes zero. These sums exclude record headers, keys, indexes and page slack. For numeric fields the cast is **decimal text representation**, not SQLite's variable-size integer/REAL encoding; numeric figures below are labeled as such and must not be subtracted directly from physical size.

### Words - all 15,423 rows

| Column | Type | Non-NULL | Characters / numeric display length | UTF-8 / numeric display bytes |
|---|---|---|---|---|
| id | TEXT | 15,423 | 339,306 | 339,306 |
| lemma_fr | TEXT | 15,423 | 124,677 | 129,326 |
| article | TEXT | 9,457 | 18,914 | 18,914 |
| pos | TEXT | 15,423 | 46,693 | 46,693 |
| gender | TEXT | 11,280 | 11,280 | 11,280 |
| plural_fr | TEXT | 14,166 | 127,561 | 131,917 |
| ipa | TEXT | 14,504 | 147,119 | 179,297 |
| level | TEXT | 15,423 | 30,846 | 30,846 |
| level_source | TEXT | 15,423 | 115,724 | 115,724 |
| theme | TEXT | 15,423 | 103,621 | 103,621 |
| meaning_en | TEXT | 15,423 | 307,847 | 308,021 |
| meaning_en_2 | TEXT | 6,582 | 150,761 | 150,896 |
| meaning_tr | TEXT | 15,423 | 119,363 | 132,053 |
| literal_tr | TEXT | 46 | 768 | 836 |
| note_tr | TEXT | 44 | 3,258 | 3,531 |
| register | TEXT | 27 | 148 | 184 |
| freq_rank | INTEGER | 15,423 | 68,758 | 68,758 |
| confidence | REAL | 15,423 | 67,441 | 67,441 |
| tr_path | TEXT | 15,423 | 160,468 | 160,468 |
| reviewed | INTEGER | 15,423 | 15,423 | 15,423 |
| is_idiom | INTEGER | 15,423 | 15,423 | 15,423 |
| is_function | INTEGER | 15,423 | 15,423 | 15,423 |
| needs_review | INTEGER | 15,423 | 15,423 | 15,423 |

All word TEXT totals **1,862,913 bytes**, versus table-record payload 2,371,458 bytes and allocated 2,539,520 bytes. In particular all primary English is only 308,021 bytes, secondary English 150,896, and IPA 179,297. The English+secondary+IPA removable-text upper bound for all 15,295 non-idioms is 633,614 bytes; for the 5,067 eligible ordinary subset it is 210,615 bytes. Neither is a feature-preserving deletion.

French identity/display is lemma+article, not a preformatted display column. POS/gender, CEFR/theme/rank and needs-review/function/idiom flags influence current behavior. `reviewed` is not the runtime safety flag. Level-source/translation-route remain useful editorial provenance even though current Dart does not map them.

### Examples - all 17,858 rows

| Column | Type | Non-NULL | Characters / numeric display length | UTF-8 / numeric display bytes |
|---|---|---|---|---|
| id | INTEGER | 17,858 | 78,544 | 78,544 |
| word_id | TEXT | 17,858 | 392,876 | 392,876 |
| sentence_fr | TEXT | 17,858 | 751,205 | 775,963 |
| sentence_en | TEXT | 17,858 | 651,219 | 651,287 |
| sentence_tr | TEXT | 14,551 | 500,360 | 549,506 |
| tr_direct | INTEGER | 17,858 | 17,858 | 17,858 |
| max_level | TEXT | 17,858 | 35,561 | 35,561 |
| ordinal | INTEGER | 17,858 | 17,858 | 17,858 |
| sentence_fr_id | INTEGER | 17,858 | 113,551 | 113,551 |
| author_fr | TEXT | 17,858 | 143,780 | 143,827 |
| sentence_en_id | INTEGER | 17,858 | 112,100 | 112,100 |
| author_en | TEXT | 17,858 | 91,174 | 91,224 |
| sentence_tr_id | INTEGER | 14,551 | 102,149 | 102,149 |
| author_tr | TEXT | 14,551 | 80,058 | 80,115 |

Example text bytes: French 775,963; English 651,287; Turkish 549,506. Word-reference IDs add 392,876; author names add 315,166; max-level labels add 35,561. All example TEXT totals 2,720,359 bytes versus record payload 3,145,305. Sentence IDs are numeric and attribution-significant; their decimal display lengths are not their storage size.

Ordinal distribution: **9,795 ordinal-0**, 8,046 ordinal-1, 17 ordinal-2. The repository loads only ordinal-0. None of the 8,063 additional rows has negative/local sentence IDs or FrenchApp authors in any language; 91 belong to idioms. They remain valuable source/editorial material, but are not displayed by today's runtime. Omitting them from a future runtime projection must not delete them from the canonical content source.

### Conjugations and aliases

| conjugations field | Type | Characters / numeric display length | UTF-8 / numeric display bytes |
|---|---|---|---|
| id | INTEGER | 617,019 | 617,019 |
| verb_id | TEXT | 2,669,788 | 2,669,788 |
| tense | TEXT | 1,351,108 | 1,351,108 |
| person | TEXT | 347,876 | 347,876 |
| form | TEXT | 1,249,252 | 1,313,411 |
| level | TEXT | 242,708 | 242,708 |

| content_aliases field | Type | Characters / numeric display length | UTF-8 / numeric display bytes |
|---|---|---|---|
| alias_id | TEXT | 123,745 | 123,745 |
| canonical_id | TEXT | 397,650 | 397,650 |
| kind | TEXT | 72,300 | 72,300 |

Conjugation TEXT totals 5,924,891 bytes: forms **1,313,411**, repeated verb IDs **2,669,788**, tense names **1,351,108**, persons **347,876**, CEFR **242,708**. The gap to record payload is 849,478 bytes of record/numeric representation; allocation exceeds payload by another 807,327 bytes, including 64,526 unused. Indexes add 6,561,792. Thus much of this table's footprint is identity/query layout, not replaceable dictionary definitions. A compact encoding is a different future storage study, not evidence for API conjugations.

Alias text totals 593,695 bytes; record payload 665,995; table+index 1,044,480 (4.28% of DB). These 18,075 legacy mappings are progress/backup compatibility, not cache garbage.

Verbs contain 251,018 TEXT bytes in total: infinitives 22,457; English 63,648; Turkish 29,146; IPA 30,301; auxiliary 13,490; past participle 21,493; stable IDs 59,356, plus level/reflexive metadata/notes. Grammar Markdown is 58,759 bytes; the complete grammar table with both unique indexes is just 94,208 bytes. Word relations store two stable IDs per edge (332,640 TEXT bytes), with 1,052,672 allocated bytes including indexes. These small feature datasets are poor candidates for network dependence.

## D. Runtime feature dependency matrix

Offline requirement means preserving today's already-available behavior, not assuming every feature has equal product importance. Paths/symbols below were checked against current source; report 00 predates persistence repairs and is not used as authority for their old behavior.

| DB fields/table | Actual runtime consumers | Offline? | Identity/progress sensitive? | API replacement candidate? |
|---|---|---|---|---|
| words.id, lemma_fr, article, pos, gender, level, theme, freq_rank; safety/function/idiom flags | repositories.dart:83-151 load/_fromRow; :187-264 candidateIds/distractorsFor; domain/word.dart display/posTr; vocab/swipe_session_screen.dart:64,199-206 | Yes | ID direct; ordering/eligibility changes pools | No for authoritative curriculum |
| words.meaning_en, meaning_tr, ipa | vocab/word_card.dart:225-228,341-345; vocab/search_screen.dart:476-487; domain/word_search.dart:105-119 | Yes | Not SRS key, but existing content/search contract | Additional API detail only; preserve baseline |
| words.literal_tr, note_tr, register, is_idiom | vocab/word_card.dart:191-192,395-432,491-493 | Yes for existing idiom teaching | No key; pedagogy/safety | Keep local (Step07 idiom misses) |
| examples ordinal=0: FR/EN/TR text, sentence IDs/authors | repositories.dart:83-93,137-145; Word.sentenceAttribution domain/word.dart:65; word_card.dart:444-478 | Yes | No SRS key; attribution and cloze content | Keep local; optional extra API examples |
| words.meaning_tr, pos, level, display; examples.sentence_fr/tr/en | QuizEngine.build quiz_engine.dart:47-128; distractorsFor repositories.dart:239-264 | Yes | Questions refer to stable word IDs; answer semantics depend on text | No silent replacement with changing API gloss |
| words/verbs IDs, safe pools, rank, level; meta.journey_revision_*; actual conjugations | StationBuilder.build/:verbRefIdsFor station_builder.dart:24-166; domain/journey_aliases.dart | Yes | Direct station membership/revision compatibility | No |
| grammar_lessons id/slug/title/level/tense_key/sort_order/body_md | LessonRepository.all repositories.dart:451-477; grammar/grammar_screens.dart:30,184-205; Markdown and verb-practice launch | Yes | Lesson identity/linkage; no API curriculum ownership | No; already tiny |
| verbs all mapped columns; conjugations verb_id/tense/person/form | VerbRepository repositories.dart:286-449; verb_screens.dart:46-101,802-989; domain/verb.dart Conjugation.refId/display | Yes | verbId:tense:person is card identity | No form replacement; API lexical detail optional |
| verbs infinitive/EN/TR/rank/group/reflexive/aux; conjugation tables | verb_tables_screen.dart:93-121,303-340,451-550; calls all(), not only safe learning subset | Yes | Dictionary retains unsafe/missing-learning records too | Do not prune needs_review rows as dead data |
| verbs is_reflexive, level, meaning_tr, aspirated_h; conjugations forms/persons | reflexive_arena_screen.dart:47-71,227; byLevels/tablesFor/conjugationDisplay | Yes | Verb activity, not per-form SRS mutation in arena | No (all sampled reflexive exact API lookups missed) |
| words lemma/search, ID and needs_review for song save matching | popular_song_screen.dart:_showFocusWord :389-456; song_player_screen.dart:_showWordSheet :545-633; local search then cards.star(id) | Lexical matching/saving yes; media may already be online | Saved local word ID; generation guard preserved | Optional detail, never provider-index save identity |
| word_relations word_id/related_id/ordinal | repositories.dart:108-115,176-184 relativesOf; word_card.dart:354-369; search_screen.dart:444,527 | Yes to preserve related words | Stable endpoint IDs; no independent SRS key | Keep local; tiny graph and existing filtering |
| meta counts/sources/built_at; eligible word pools | AboutScreen about_screen.dart:63-75; progress_screen.dart:128,288; AppState.wordCount :206 | Yes | Journey keys separately identity-sensitive | No API substitution for local corpus facts |
| content_aliases alias_id/canonical_id/kind; content markers | AppDatabase._migrateContentIds app_database.dart:180-260; restoreProgress app_state.dart:511+; backup.dart export/import refs | Yes | Critical legacy word and verb-prefix remapping | Never provider-owned |
| words.meaning_en_2 and confidence; plural_fr/level_source/tr_path/reviewed | meaningEn2/confidence mapped but no feature getter reads found; other four fields not mapped into Word | Not a current visible dependency | Keep authoring provenance; needs_review is distinct | Secondary detail can be enriched; no reason to offload safety metadata |
| examples ordinal>0, tr_direct, max_level | No runtime consumer found; only ordinal-0 loaded, flags not mapped | Not required by current runtime | Retain canonical/editorial source material | Future packaging projection only |
| Authored songs/stories/sentences/placement (not DB) | domain/song.dart, adventure.dart/adventure_expansion.dart, sentence_practice.dart; onboarding placement screen | Their authored learning data stays local | Own stable story/prompt identifiers | No API replacement implied |

Search currently indexes **all 15,423 words**, including records excluded from normal learning; verb tables call all() for the 2,698-verb dictionary. Shrinking to the 5,149 default word pool would delete existing dictionary behavior and possibly content referenced by saved progress. None of the measured realistic scenarios does that.

## E. Irreducible local data

Classification applies to preserving the present product, not to every possible future redesign.

| Component | Classification | Reason / boundary |
|---|---|---|
| Stable word/idiom/verb IDs, lemma/POS keys, aliases | MUST LOCAL | SRS/flags/backups identify local records, not provider senses |
| CEFR/rank/theme/needs-review/function/idiom status | MUST LOCAL | Ordered safe pools, filters, quiz distractors, Journey membership |
| Journey generation inputs/revision keys/explicit aliases | MUST LOCAL | Provider changes must never reshuffle passed stations |
| Primary approved English and current IPA | MUST LOCAL for unchanged offline behavior | Core card/dictionary fields; English is also indexed; small removal saving |
| Turkish, idiom gloss/literal/note/register | MUST LOCAL | Quiz answers/distractors are Turkish; Step07 API cannot replace this |
| Displayed FR/EN/TR examples + author/ID provenance | MUST LOCAL | Cloze, cards, attribution; Step07 34.17% versus local 71.39% |
| Grammar Markdown/tense links | MUST LOCAL | Authored instruction, no tested provider substitute |
| Conjugations; auxiliary/group/reflexive/base/aspirated-h metadata | MUST LOCAL | Step07 forms 58.22% candidate/44% unique; existing sessions require exact cells |
| Related-word links | MUST LOCAL for feature parity | Existing visible related-word feature and safe filtering |
| Meta counts/source/version/marker contract | MUST LOCAL | Installation, About and revision consistency |
| Additional examples, translation routes/level sources/reviewed | SHOULD LOCAL in canonical source; optional runtime packaging | Source/editorial evidence must not be deleted; runtime reads only a subset |
| Secondary English/plural data unused by current features | SHOULD LOCAL in authoring source; CAN API for optional display | No current visible dependency; replacing primary meaning is a separate matter |
| Exact non-curriculum dictionary lookup, extra senses/IPA variants | CAN API | Only explicitly online detail; no guaranteed offline enrichment |
| Audio/pronunciation URLs, provider source links | OPTIONAL API ENRICHMENT | New value without changing approved learning answers |
| Progress/card/game/stat/settings data | MUST LOCAL (progress.db, not measured content.db) | Provider has no authority over learner state |

Step07 proved availability for a balanced 360-word ordinary sample, not reliable offline replacement for all ordinary records or suitability of every returned sense. Therefore the safe replacement set for primary visible lexical fields is empty under the current behavior constraint. That is why scenarios C/D retain primary English and IPA instead of manufacturing a tiny but incomplete offline product.

## F. Temporary DB footprint experiments

All derivative copies are under OS temp `frenchapp-step08-wr4c4wae`; none is inside the repository. Each starts from the same byte-identical source, executes only the listed SQL, commits, then VACUUMs the copy. No production schema is altered. [SQLite VACUUM](https://www.sqlite.org/lang_vacuum.html) repacks remaining content; it does not imply application compatibility. A no-deletion control separates layout savings from content removal.

Scenarios C/D are **conditional runtime projections**, not replacements for canonical pipeline/editorial data. There is no claim they pass the existing content publisher unchanged. A real projection would need its own version/size/hash and source-provenance contract.

| Scenario | Bytes | MiB | Saving vs A | Saving % | zlib-9 bytes (proxy) |
|---|---|---|---|---|---|
| A current | 24,387,584 | 23.258 | 0 | 0.00% | 6,986,859 |
| A0 VACUUM only | 24,363,008 | 23.234 | 24,576 | 0.10% | 6,982,588 |
| B eligible ordinary EN/IPA removal | 24,141,824 | 23.023 | 245,760 | 1.01% | 6,855,415 |
| B-wide optimistic all-non-idiom bound | 23,683,072 | 22.586 | 704,512 | 2.89% | 6,565,927 |
| C conservative local curriculum/content projection | 24,064,000 | 22.949 | 323,584 | 1.33% | 6,830,957 |
| D minimum measured current-runtime projection | 22,020,096 | 21.000 | 2,367,488 | 9.71% | 6,115,536 |

**B:** remove primary/secondary English and IPA only for eligible ordinary words. This is the benchmark-supported population, not proven safe removal. Rows/IDs/Turkish/examples/idioms/verbs remain. API cache misses would blank card English/IPA and remove English local search matches. It is deliberately classified **not feature-preserving**, even though SQL integrity passes. B-wide applies to all 15,295 non-idioms and is an optimistic storage bound beyond Step07's core coverage.

**C:** keep primary English/IPA as offline fallback, plus Turkish/examples/idioms/conjugations and every curriculum/identity row. Clear only ordinary secondary English (mapped, no current feature use) and plural_fr (not mapped). No mandatory field is outsourced. Its modest saving does not require an API.

**D:** extend C by omitting unused runtime-level-source/translation-route/reviewed payload, additional examples (`ordinal<>0`) and unused example selection metadata. Keep confidence, all safety flags, all word/verb rows, all first examples and attribution, every conjugation/alias/relation/lesson, and all indexes. Extra examples remain in the untouched canonical source. They include 91 extra idiom examples; all current idiom display examples remain. The derivative's `meta.example_count` is corrected from 17,858 to 9,795. That inventory display changes appropriately; no active example or quiz source is removed.

Exact changes (each copy separately; SQL is documentary, never run on the asset):

**A0 VACUUM only**

```sql
-- No payload change
VACUUM;
```

**B eligible ordinary EN/IPA removal**

```sql
UPDATE words SET meaning_en='',meaning_en_2=NULL,ipa=NULL WHERE is_idiom=0 AND needs_review=0 AND is_function=0;
VACUUM;
```

**B-wide optimistic all-non-idiom bound**

```sql
UPDATE words SET meaning_en='',meaning_en_2=NULL,ipa=NULL WHERE is_idiom=0;
VACUUM;
```

**C conservative local curriculum/content projection**

```sql
UPDATE words SET meaning_en_2=NULL,plural_fr=NULL WHERE is_idiom=0;
VACUUM;
```

**D minimum measured current-runtime projection**

```sql
UPDATE words SET meaning_en_2=NULL,plural_fr=NULL WHERE is_idiom=0;
UPDATE words SET level_source=NULL,tr_path=NULL,reviewed=0;
DELETE FROM examples WHERE ordinal<>0;
UPDATE examples SET tr_direct=0,max_level=NULL;
UPDATE meta SET value=(SELECT CAST(COUNT(*) AS TEXT) FROM examples)
WHERE key='example_count';
VACUUM;
```

### Checks and limits

All copies pass SQLite `integrity_check` and have zero `foreign_key_check` violations. For C and D, explicit SQL equality checks verify:

- All 15,423 frequency-ordered mapped-and-consumed Word records, including first-example text and per-language attribution, are identical. `meaning_en_2` is deliberately excluded because source search found no consumer; this is not equality of every model property.
- All verbs, conjugations, aliases, grammar lessons and relations match exactly; Journey meta keys remain identical.
- Same ordered consumed-row JSON SHA-256: `463805c752b1e276d7daa1d604ecdda95bffa7e5ec2a419545a3d4ad66d6ca36`.

This proves data-query parity for inspected paths, not a Flutter/widget/device regression run, future consumer compatibility or a shipping content-validation result. D is the smallest **tested reasonable projection**, not an information-theoretic minimum. No indexes/unsafe rows/legacy aliases were deleted to create an artificially small result.

Compression column is measured `zlib.compress(bytes,9)` only. Baseline compresses to 6,986,859 bytes; D to 6,115,536. This 871,323-byte difference is an illustrative compression proxy, **not a measured APK saving**. APK compression/alignment, duplicate installed asset and device storage differ. No APK was built or replaced. AppDatabase additionally installs a full writable-filesystem copy of the read-only asset; raw DB bytes are neither total APK nor total installed footprint.

## G. API cache comparison

Step07 existing temporary responses were still available; **zero new WiktApi requests** were made in this task. Raw-body means are 3,954.5056 bytes/core full entry and 4,447.1389 bytes/full+definitions. Step07's mixed-population full projection was 24.91 MiB versus core 19.42 MiB, demonstrating distribution sensitivity.

New measured compact projection: for each of the 360 core responses, keep at most two distinct English glosses under the expected POS, two distinct IPA strings, the first available audio metadata record (file/ogg/mp3/tags), provider/edition/language/lemma, source URL, fixed-length retrieval timestamp, provisional license/schema/selection descriptors. Serialize compact UTF-8 JSON. This is a size experiment, not a provider model implementation or approved sense/license selection. One entry (quelque taxonomy mismatch) has no expected-POS gloss; provenance/audio attribution completeness remains future work.

Measured selected-record sizes: mean **626.05 bytes**, median **602**, p90 **772**, p95 **791**, maximum **991**; expected-POS gloss present 359/360. No waveform/audio downloaded. Actual cache indexes/keys, HTTP metadata, expiration, per-file credits and storage slack would add bytes. A normalized app cache may differ; these are not exact future SQLite file sizes.

The following uses the global core means multiplied by real level counts or explicit seen-count assumptions, not a measured cache of every word. Level counts include idioms and are budget denominators, not claims that those idioms resolve.

| Cache scope | Entries | Raw full MiB | Full+definitions MiB | Selected record MiB |
|---|---|---|---|---|
| All default learning | 5149 | 19.418 | 21.838 | 3.074 |
| Active A1 | 926 | 3.492 | 3.927 | 0.553 |
| Active A2 | 415 | 1.565 | 1.760 | 0.248 |
| Active B1 | 476 | 1.795 | 2.019 | 0.284 |
| Active B2 | 447 | 1.686 | 1.896 | 0.267 |
| Active C1 | 858 | 3.236 | 3.639 | 0.512 |
| Active C2 | 2027 | 7.644 | 8.597 | 1.210 |
| Seen-only | 100 | 0.377 | 0.424 | 0.060 |
| Seen-only | 500 | 1.886 | 2.121 | 0.299 |
| Seen-only | 1000 | 3.771 | 4.241 | 0.597 |
| Seen-only | 2000 | 7.543 | 8.482 | 1.194 |

An eager raw cache approximately doubles the local content footprint rather than economically replacing a few hundred KiB of meanings. Even the 3.074 MiB selected full-curriculum estimate exceeds B's 0.234 MiB saving by about thirteen times, before cache overhead. Seen-only cache is a better enrichment budget: approximately 0.299 MiB at 500 entries or 0.597 MiB at 1,000.

Recommendation: cache explicitly requested enrichment, with bounded retention/stale serving; do not eagerly redownload the whole curriculum. Active-level prefetch is only a later measured option. Default mix-lower-level behavior can require several levels, so an active-level cache is not automatically a complete offline learning source. Local baseline data remains the offline guarantee, independent of cache eviction or provider freshness.

## H. Offline/network analysis

Current lexical lookup reads eager in-memory Word objects after local startup; conjugations/grammar load from local SQLite and cache. This is network-free and deterministic, not a measured claim of zero latency. Startup/RAM/device performance was not benchmarked here. Local snapshots are fixed until publication and already include approved overrides/safety decisions.

Moving primary English/IPA out would make current card detail and English search dependent on an unevicted cache or network. Turkish quizzes could still function, but that is reduced behavior, not parity. Provider failure must never shrink eligible sessions or change their answer keys. Step07's public-host p95 0.166 s is historical measured desktop evidence, not a new measurement or SLA; multi-route parsing, metadata omissions, offline misses, 403s and schema changes add failure states. API content may be richer or newer, but its exact freshness generation is not guaranteed.

Economically, no user download-size complaint, store limit, measured startup bottleneck or maintenance-cost figure justifies a storage migration. No invented dollar/hour ROI is supplied. Current dependency/tooling already uses SQLite; separate catalog files require new loaders, atomic version coordination, duplicate identity mappings and parity tests without evidence of lower total bytes. Enrichment offers visible new capability without paying that migration cost. If storage later becomes a demonstrated requirement, profile indexes/repeated conjugation keys before considering network replacement of a 0.2 MiB lexical payload.

## I. High-value API use cases

| Use case | Value | Complexity/offline behavior | Cache and content risk |
|---|---|---|---|
| Explicit exact lookup beyond curriculum | High: new dictionary reach | Medium; online view unavailable offline unless cached; local search unaffected | On-demand cache; spelling/POS ambiguity, no automatic learning save |
| Expandable additional English senses | High dictionary detail; medium for beginners | Medium; collapse/hide on failure, preserve local card meaning | Sense/register selection; never overwrite approved answer |
| Pronunciation/audio metadata | High potential beyond device TTS | Medium-high; TTS retained, streaming only when requested | Metadata cache; audio licensing/reachability/device tests still needed |
| IPA variants | Medium detailed pronunciation | Low-medium on provider boundary; baseline IPA retained | Dialect/POS labels, avoid arbitrary preferred variant |
| Provider-linked provenance | Medium trust/traceability; required supporting work | Low-medium; cached source links remain visible | Store provider/version/retrieval; license display reviewed separately |

## J. Search architecture

**Retain local normalized curriculum/dictionary search first; add an explicit 'Search online' exact-French-lemma action.** Offer it when no desired local result is found, but do not automatically send every keystroke or assume a Turkish query is a French lemma.

`WordSearchEngine.fold/buildIndex/searchIndex/_score` (`lib/domain/word_search.dart:79-212`) folds French/Turkish accents/ligatures/apostrophes, searches lemma/display/TR/EN, and ranks by match class, frequency then lemma, with default limit 80. Repository search covers all local words; safe-learning filtering remains separate. Step07 prefix target top-50 was only 37.50%, and prefix search does not replace multilingual local meaning search.

Keep online results in a clearly labeled separate detail view, not merged into an opaque ranking. For a local result, an explicit 'More dictionary detail' uses its lookup key and retains the local ID. An online-only result has no curriculum rank, CEFR, safety approval, station membership or progress affordance. Not-found/network failure leaves local results intact. Provider spellings/senses may be shown as alternatives, not automatically equated to a local record using accent folding alone.

## K. Stable identity/progress compatibility

Ownership boundary:

```text
local stable curriculum ID
  -> immutable local learning record and progress reference
  -> optional provider lookup key (provider, edition=en, language=fr, lemma)
  -> replaceable enrichment snapshot with provenance
```

The offline builder's `stable_id` (`content/tools/13_build_db.py:91-95`) hashes NFC/case-folded semantic key parts; word IDs use lemma+POS (:347), idioms their lemma (:494), verbs their lemma (:602), reflexives a distinct kind (:644). Keep the published IDs; do not regenerate them from API output. Current conjugation refs are `${verb.id}:${tense.key}:$person` (`lib/domain/verb.dart::Conjugation.refId`), not SQLite conjugation row IDs.

`AppDatabase._migrateContentIds` reads aliases and rewrites word refs or the verb prefix inside conjugation refs, resolving collisions by updated time; flags are migrated too. `ProgressBackup` exports/imports progress tables, not lexical content. Removing aliases would break old-backup compatibility even if a fresh installation appeared fine.

Journey uses local ordered eligible pools plus revision keys (`StationBuilder`) and explicit station aliases. `content/tools/journey_revisions.py::calculate_revisions` hashes sorted safe IDs; it intentionally excludes frequency, question rules and exact station order. Therefore preserving the revision string alone is insufficient if a redesign changes ordering/content selection. Both ordered query parity and identity compatibility matter. No revision contract is changed here.

For the first prototype, **non-curriculum online words are view-only**. Making them learnable introduces durable IDs, CEFR/safety/translation decisions, backup/migration ownership and missing-provider/offline handling. That is a separate product and persistence design. Current song-star callbacks continue matching and saving an existing safe local ID through `cards.star`, not a provider result position.

## L. Provider abstraction boundary

Minimum conceptual contract, not implemented Dart:

- `LexicalLookupKey`: provider, edition, language, requested lemma; optional expected POS hint used only for selection, never curriculum eligibility.
- `lookupExact(key) -> LexicalOutcome`: found grouped senses/pronunciations, notFound, ambiguous/selectionRequired, or failure with transient/rate-limit/schema category. Keep not-found distinct from service failure.
- `LexicalEnrichment`: returned spelling/variants, grouped POS/senses/glosses, optional IPA/audio metadata/examples, and explicit missing fields. No SrsCard, rewards or required Turkish promise.
- `Provenance`: provider/entry URL, edition/language, retrieval timestamp, schema version, upstream generation if actually supplied, source/license/attribution metadata. Unknown generation stays unknown.
- A future cache wrapper may return fresh/stale snapshots and delegate misses. It should have independent keys/lifecycle and must not become the source of truth for `Word` or `progress.db`.

The caller attaches enrichment to a local ID; the provider does not issue, migrate or own it. Do not wrap the entire existing `WordRepository` with a network-backed implementation: its synchronous all/byId/candidateIds/distractor semantics are curriculum contracts, not lexical fetch contracts. POS interpretation can use the current API definitions route; the full route lacked metadata in Step07, so joining parallel lists by result order is not acceptable.

CEFR, frequency, Journey, SRS, safety rules, Turkish quiz answers and stable IDs are explicitly outside provider responsibility. A thin HTTP/parser/cache boundary is justified by observed schema and network failure states; a second curriculum framework is not.

## M. Should content.db remain?

**KEEP. HYBRID ENRICHMENT is the primary recommendation.** 'Remove content.db' should cease to be a project goal unless new evidence changes the product/storage requirements.

| Architecture option | Measured benefit | Engineering/correctness cost | Decision |
|---|---|---|---|
| A Keep DB + optional enrichment | Preserves offline parity; adds new dictionary/audio capability | Bounded HTTP/parser/cache/detail UI work | Recommended |
| B Shrink DB via API replacement | Eligible EN/IPA: 0.234 MiB raw saving; all-ordinary bound 0.672 MiB | Network/cache dependence, changed search/meaning selection, parity tests | Reject as current primary plan; optional packaging study later |
| C Split into small assets/DBs + API | No measured total-byte or runtime advantage from splitting alone; realistic D still 21 MiB | New loaders/versioned multi-file publication, repeated identity/alias integration | Not justified now |
| D Eliminate content.db | No viable provider substitute for 58% conjugation footprint plus offline teaching/identity | Recreates substantial local storage under another name or loses features | Reject on current evidence |

The D footprint experiment is not architecture Option D: it is a smaller SQLite runtime projection retaining offline behavior, not DB elimination. At most it supports a later **packaging-only** optimization if a real distribution budget warrants ~2.26 MiB raw/~0.83 MiB compression-proxy saving. Canonical examples/provenance must remain intact, and a separate projection publisher would need tests. This is not required for enrichment and is not authorized by this report.

Splitting files is not inherently compression. Much of the measured footprint is repeated conjugation identities/indexes; a future compact representation might save space, but no alternate schema/query-speed prototype was measured, so it is not promoted as REPLACE LATER. Keep SQLite's existing query/transaction/read-only-content separation unless a later measured requirement outweighs migration cost.

## N. Complexity-benefit matrix

Qualitative estimates, not person-day or monetary claims. Network dependency describes the proposed feature, not a requirement to make the whole application online. 'Do now' means the next explicitly authorized implementation phase, not work performed in this report.

| Candidate | User value | Complexity | Correctness risk | Network dependency | Recommendation |
|---|---|---|---|---|---|
| API-backed existing card meaning | Low incremental | High | High | High if replacing baseline | Reject replacement |
| Online extra definitions | Medium-high | Medium | Medium (sense/register) | Medium, optional | Do now after provider/cache contract |
| Pronunciation/audio | High potential | Medium-high | Medium (variant/license/playback) | Medium; TTS fallback | Later, after metadata/device validation |
| Explicit online exact dictionary | High | Medium | Medium | Medium, optional | Do now, view-only |
| Turkish API enrichment | Low-medium incremental | Medium-high | High (sense mapping/coverage) | Medium | Later; local authoritative |
| API idioms | Low incremental | Medium | High replacement risk | Medium | Reject replacement; incidental detail later |
| API examples | Medium extra detail | Medium-high | High if replacing curated cloze | Medium | Later; no answer-key substitution |
| API conjugations | Low viable replacement benefit | High | High | High | Reject replacement |
| DB slimming | Low at measured savings | Medium-high with publisher/parity | Medium-high | Low packaging-only, high API-offload | Later only with storage target |

## O. Revised migration sequence

1. Accept/revise this decision and retain the stable rollback tag. Confirm enrichment-only product scope, current baseline fields and view-only external entries. No DB-removal workstream.
2. Select narrow remaining runtime-error/retry work with the lead (not a broad refactor), especially D4 patterns that must not be copied into new asynchronous views. Preserve Steps02-05 transaction/publication guarantees.
3. Define provider result/provenance and selection contracts, independent of curriculum repositories; document the observed full-versus-definitions schema issue. Establish offline and missing/ambiguous behavior before a widget calls HTTP.
4. Implement a bounded exact-lookup client/parser in a separately authorized step with recorded representative fixtures. Test encoding, missing entries, variant references, multiple POS, malformed schema, timeouts/403/429/5xx and source links. No progress writes.
5. Add a small persistent normalized cache with size/expiry policy, stale serving and single-flight behavior. Measure storage and cold/warm device latency; ensure cache loss never damages learning data. Do not prefetch 5,149 entries by default.
6. Add explicit view-only online dictionary detail and expandable extra senses. Keep local search/ranking/meaning unchanged. Test navigation/disposal/out-of-order responses and offline fallback.
7. Evaluate IPA/audio metadata and licensing, then device playback with TTS fallback. Do not make playback a prerequisite for a session.
8. Run parity/failure tests around local pool order, IDs, Journey, quizzes, song matching and backups, plus device/network tests. Verify API absence cannot change sessions/rewards.
9. Only if download/install/storage evidence demands it, evaluate a versioned runtime projection (C/D) or compact conjugation representation. Benchmark against the full DB and retain canonical source/provenance; no storage migration merely for architectural symmetry.

## P. Remaining runtime debt

Reports02-05 repaired store publication ordering, scoped completion atomicity, free-quiz atomic persistence/current-card reads and song-star stale writes. Current source uses those paths; the older report00 descriptions of split quiz writes/unborn Git are historical, not current defects.

Still unresolved by this task: station completion's later separate `recordActivity` admission; D4 persistence-error latching in sentence/song-quiz/arena/station; practice midnight timing; non-swipe stale-widget/settings coverage questions; Step03's inconclusive optional COMMIT-time fault-injection experiment (not proof of process-crash durability). `SqliteCardStateStore.save` remains a generic full-row API, but Step05 found no production caller-prepared save path; a future caller could reintroduce that pattern.

Git authority is no longer debt: main has a valid published HEAD and baseline tag. No current application tests were rerun in this report-only analysis; historical 198-test evidence is not called fresh validation. Scope is physical/data/query/source evidence, not Android visual/performance or linguistic acceptance.

## Q. Repository integrity

Initial main and live origin/main both `e2355ebd539c0fc615516cad3e82f95087b0cea7`; clean tracked and full-untracked porcelain. Stable annotated tag object remains `edb0da305152f116e67e99314f18bd1efed9acf1`, peeled target `583bb7631e7dacd994b874c3224eb518dd7a391c`. No reset/checkout/cleanup or tag movement.

All 208 pre-existing tracked files were SHA-256 inventoried before analysis. Source DB has been read-only; only temporary derivative copies received UPDATE/DELETE/VACUUM. Raw Step07 cache was read, not changed; no API network requests or permanent benchmark scripts were added. The only intentional repository addition is this report.

Protected starting/rechecked hashes:

| Path | SHA-256 unchanged |
|---|---|
| assets/db/content.db | 6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417 |
| assets/db/content.version | 3fc22e0ffec33e0a297546256fa7d2eed4815afd39da4e80f888cb57ecfaad9a |
| lib/data/content_version.dart | 97caaaa95d35e3c3f8484451347d12fe68bf46bd4083bd8aa6aff6c6e8a3d8d6 |
| pubspec.lock | b3819b55fa193d12665d185e6b00f5bc717b81e4e5fd7ac9ca9f7044a0c90fbf |
| lib/app/app_state.dart | e8f1be8ca503a50dd5ae392fc27d4fe58ca107aa779cd0be9dc283b8251346ef |
| lib/data/repositories.dart | 3c59dc621ae2e0606db248c03bd819a94f5b16848b3a780e1c0844c6624670d6 |
| test/progress_consistency_test.dart | 70ee9627fea265ac5a21933810dc23cf916315b2147b107277c57e014c1d063d |
| codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md | 7132f9501d6e1a1ab87cde206c3a89e28df1fac9fc27b8720648a0f3355b9b7b |
| codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md | fd0767a078866173ad64d63928dda6610249c7c3879994915828dfd1e8a1019f |
| codex_reports/02_PERSISTENCE_CACHE_COMMIT_FIX.md | 04f9e38141648a6e13f48071c444c76bcedd03aa9001a6ca80c0e7fa5ef5f8b8 |
| codex_reports/03_COMPLETION_ATOMICITY_FIX.md | 9856713e19a4063368ca096ca8c3c19a7d36b50460c8b68dfce0c8557f05b27c |
| codex_reports/04_FREE_QUIZ_ATOMICITY_FIX.md | e5c8a5c93d5fbd2e1fc0304e9f446655fd79d4e511a71f7992cea96a6ad88afc |
| codex_reports/05_SONG_STAR_STALE_WRITE_AUDIT_FIX.md | d90ed3c0058def66ccb5845d5c9e29de2be9f8a7e6c23472d551d366f3f96a6f |
| codex_reports/06_GIT_BASELINE_PUBLICATION.md | 8735e4c90f04e20981733ec3798e18abd317f2926347904ecdff4cc8ab0afebd |
| codex_reports/07_API_FEASIBILITY_BENCHMARK.md | 316a7c84a90694f727c3bbd88284376ab106fe633878dc22ed134268ff42c02e |

Temporary evidence under `frenchapp-step08-wr4c4wae`: initial inventory, schema, dbstat/logical measurements, derivative DBs, SQL/parity scripts, normalized-cache measurements and report-generation script. None belongs in Git. Some exploratory shell reads used historical singular filenames and returned not-found; correct paths were then discovered with rg. Python dbstat unavailability was resolved with the installed CLI, not by estimating table sizes from row counts. Initial inventory filtering was corrected for Git's trailing NUL entry; no project mutation resulted.

SQL integrity checks and parity comparisons are documented in F. Report/source hash verification, staged-file review and remote verification are publication gates. No Flutter dependency resolution, corpus rebuild, editorial application or APK build occurred.

## R. Git publication

Authorized commit message: `docs: decide hybrid content architecture`. Stage only `codex_reports/08_CONTENT_ARCHITECTURE_DECISION.md`, push normally to main, verify local HEAD equals live remote main and the baseline tag is unchanged. Initial parent is the Step07 report commit above.

A commit cannot embed its own literal SHA in its content without changing the SHA. The exact report SHA and completed remote verification are therefore supplied in the final task handoff; recover it with `git log -1 --format=%H -- codex_reports/08_CONTENT_ARCHITECTURE_DECISION.md`. This records the publication procedure, not an invented pre-commit verification result.

**Primary recommendation for the technical lead: HYBRID ENRICHMENT / KEEP.** Local SQLite remains authoritative for existing learning, identity, offline search and conjugations. WiktApi is optional, cached, provenance-bearing dictionary/pronunciation detail. API-first learning, conjugation replacement and content.db removal are explicitly rejected on the present evidence.
