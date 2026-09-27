# 07 - WiktApi feasibility benchmark

Date: 2026-09-27. Repository: `ArdaHFO/FrenchApp`. Report-only decision benchmark; no API migration.

## A. Executive decision

**CONDITIONAL GO for a dual-source/provider-abstraction prototype only.** Ordinary lexical enrichment passes the sample thresholds. This does not authorize replacing or deleting `content.db`.

- Core French lookup **360/360 (100%)**; English gloss **360/360 (100%)**; expected POS **359/360 (99.72%)**, using definitions to recover metadata missing from the full response.
- Conjugations **NO-GO for replacement**: 1,572/2,700 cells (58.22%) have concrete candidates; 1,188/2,700 (44%) have a unique normalized candidate. Compound tense cells are missing; all 12 sampled reflexive lookup strings fail.
- Prefix search **NO-GO as sole dictionary search**: target top-50 15/40 (37.50%), top-10 10/40 (25%).
- Idioms **keep local**: 32/40 exact lookup/gloss (80%).
- Turkish **optional enrichment**: 0/500 in the primary English edition; a separate French-edition diagnostic yields 16/40 (40%). Do not pool those denominators.
- Public host **acceptable only with persistent caching and local fallback**: full-word p95 0.166 s, but a short desktop observation is not an SLA.

The DB is a product baseline and sampling frame, not linguistic ground truth. Shared upstream provenance means high gloss agreement is not independent linguistic validation.

## B. Benchmark methodology

### Starting point and population

Clean `main` at `583bb7631e7dacd994b874c3224eb518dd7a391c`, matching live `origin/main` and the peeled tag `baseline-pre-api-migration-2026-09-27`. Reports 00, 05 and 06 informed the architecture/integrity boundary. SQLite opened with `mode=ro`.

DB population: 15,423 words; 2,698 dedicated verbs, of which 1,057 have `needs_review=0`. `SqliteWordRepository.candidateIds`, `lib/data/repositories.dart:187-225`, excludes needs-review/function words by default; `idiomsOnly=false` does not exclude idioms. Across all levels, 5,149 default eligible targets comprise 5,067 ordinary words and 82 idioms.

| CEFR | Default eligible | Idioms within default | Core sample |
|---|---|---|---|
| A1 | 926 | 30 | 60 |
| A2 | 415 | 22 | 60 |
| B1 | 476 | 18 | 60 |
| B2 | 447 | 9 | 60 |
| C1 | 858 | 3 | 60 |
| C2 | 2027 | 0 | 60 |

### Deterministic selection

Python 3.12 `random.Random(20260927)`, NFC/case-folded lemma uniqueness across groups. Exactly **500 unique targets**: 360 core, 40 edges, 40 idioms, 60 dedicated verbs. Stable DB IDs and original fields remain in temporary `sample.json`; every lemma is listed in the appendix.

1. Read words ordered by `(freq_rank,id)`, with ordinal-0 example join, and safe verbs ordered likewise. Reserve nine mandatory irregulars first. `avoir` and `faire` currently have `needs_review=1`; they were deliberately included as explicitly required critical verbs.
2. Seed-shuffle remaining safe non-reflexive group-1 verbs and take 15; group-2 take 12; group-3 take 12; reflexives take 12. These are DB group labels, not independent grammatical adjudication. Auxiliary assignments in the sample: avoir 44, etre 16, including reflexives.
3. Reserve named safe edge candidates (homographs/elision); the qualifying selections were homme, livre, son, vol, aujourd'hui. Then shuffle remaining safe non-idiom pools for apostrophes (up to 6), hyphens (6), accents (6), multi-sense (`meaning_en_2`, comma or semicolon; 6), and length <=3 until total 40. Actual buckets: 5 named, 2 additional apostrophe, 6 hyphen, 6 accent, 6 multi-sense, 15 short. This diagnostic permits function words, unlike core.
4. For each level, exclude reserved lemmas and idioms. Divide frequency-sorted ordinary pool into thirds using `min(2,3*i//N)`. Bucket by `(POS,third,gender-or-empty,has-ordinal-0-example)`; sort and shuffle keys, shuffle members, round-robin pop to 60.
5. Shuffle safe idioms within levels, then round-robin to 40. Final distribution A1 10, A2 9, B1 9, B2 9, C1 3, C2 0 (no eligible C2 idioms).
6. Sort requests by group core/edge/idiom/verb, then `(level,freq_rank,id)`. Continue the same RNG for 40 unique prefixes: ten lower-level 2-character, ten higher-level up-to-3-character, ten accented up-to-3-character, ten 5-character. `ci` is a two-character target in the upper group.

Core POS: nouns 131, adjectives 108, word-table verbs 54, adverbs 51, numeric adjectives 16. Diversity/CEFR balancing is intentional, not population proportional. No unbiased population estimate or confidence interval is claimed.

| Level | Sample frequency-rank range | Frequency thirds |
|---|---|---|
| A1 | 86-29,849 | 18/16/26 |
| A2 | 144-3,380 | 21/20/19 |
| B1 | 1,069-6,601 | 18/21/21 |
| B2 | 1,731-11,160 | 18/19/23 |
| C1 | 4,050-40,074 | 18/22/20 |
| C2 | 7,252-42,979 | 17/22/21 |

### Network policy

Sequential requests, 0.5-second pause after each uncached response, URL-keyed temporary cache, 30-second timeout. At most one retry after five seconds for network/500/502/503/504 errors. A 429 would record Retry-After and stop further traffic; none occurred. A 403 stops collection for inspection. No audio downloads. Explicit benchmark User-Agent and `Accept: application/json`, no credentials.

An initial exploratory default-header Python request returned **403**. Its elapsed time/body/headers were not retained; it is reported separately rather than omitted or assigned fabricated latency. Subsequent explicit-header requests succeeded. The initial rejection's cause is unknown; it is not classified as a retry-recovered lexical answer.

Instrumented collection approximately 17:11-17:26 UTC: **1,127 unique requests**. Extra definitions calls were necessary because the full route omitted metadata, and 40 alternate-edition translation calls explored Turkish. No repeated load testing. Fresh urllib connections include connection/read time; geography and provider cache warmth are uncontrolled.

Scripts, sample IDs/fields, responses and request logs remain in OS temp `frenchapp-step07-x2nxkefl`, not the repository. They may expire with OS cleanup. The appendix fixes the population; hashes identify temporary reproducibility artifacts.

| Temporary artifact | SHA-256 |
|---|---|
| sample.json | 40f38416827f35a8ff025c3a1dc760d6de7a576b1c506bacc75468ce0f9af79a |
| prefixes.json | b2ddad284ed3c0000525da9db40113fe6f932989736b84757fb2492a9b120497 |
| sample.py | 5ac8d0a7c988328dd97e3dfda74effd1630741f85731bbb2adfb502f69ba643a |
| net.py | c29fc8bb83ca89771cc8673f3a94609ff88f6bd68cf2b67c3301740a6b8a0a48 |
| analyze.py | 726e192876b5b66f6d9f076ac7f73d2c76d4f463f18d81c0a24fe2b7f206f623 |
| requests.jsonl | f118be78f0b0474491ee4d501f8abb2cdcb1c557583ba08266176a3fc8ff686d |

## C. API surface verification

Syntax follows the [official quickstart](https://wiktapi.dev/quickstart); each route below was exercised. Edition `en` means English Wiktionary, while `lang=fr` filters lexical language. Words are percent-encoded.

| Route on https://api.wiktapi.dev | Status | Actual schema |
|---|---|---|
| /v1/editions | 200 | editions array, 21 codes |
| /v1/languages | 200 | languages: lang_code, lang, entry_count; display names not consistently English |
| /v1/en/word/chat?lang=fr | 200 | word, edition, entries containing senses/sounds/translations/forms |
| /v1/en/word/chat/definitions?lang=fr | 200 | definitions: pos, lang_code, senses |
| /v1/en/word/chat/translations?lang=fr | 200 | translations: pos, lang_code, nested rows |
| /v1/en/word/chat/pronunciations?lang=fr | 200 | pronunciations: pos, lang_code, sounds with IPA/audio filename/tags |
| /v1/en/word/%C3%AAtre/forms?lang=fr | 200 | forms: pos, lang_code; form/tags/source/optional IPA |
| /v1/en/search?q=cha&lang=fr&limit=50 | 200 | results: word, lang_code, lang, pos |
| /v1/en/word/frenchappzznotaword2026?lang=fr | 404 | error=true, url, status=404, missing-word message |
| /v1/fr/word/{word}/translations?lang=fr | 40/40 200 | Alternate-edition diagnostic |

**Observed schema mismatch:** none of 480 successful sampled full responses includes `pos` or `lang_code` on its entries. Full-only explicit POS coverage is therefore 0%. Definitions provide metadata for successful non-verb lookups; forms provide it for dedicated verbs. Do not assume the documented rich entry schema exists on this public route or join parallel response arrays by position without identity tests.

Operational exact lookup = HTTP 200 + nonempty entries + NFC/case-folded root word matching the requested lemma + French confirmed through definitions/forms. Root word may echo the query; this is not independent canonical-headword proof for every nested sense. Variant references such as `coeur` require resolution.

Successful responses advertise JSON UTF-8, CORS `*`, `Cache-Control: public, max-age=86400, stale-while-revalidate=604800` (including observed search), `Vary: Accept-Encoding`, Cloudflare HIT/MISS and Via Caddy. Missing-word probe: `max-age=14400`. Headers are not an uptime/client-persistence guarantee. Pronunciations projection exposes audio filenames whereas full sounds also expose ogg/mp3 URLs. No authentication or Retry-After was observed.

## D. Core lexical coverage

Denominators include missing entries. Field presence does not prove the first returned sense is suitable.

| Group | N | French lookup | English gloss | Expected POS | Multiple POS |
|---|---|---|---|---|---|
| core | 360 | 360/360 (100.00%) | 360/360 (100.00%) | 359/360 (99.72%) | 86/360 (23.89%) |
| edge | 40 | 40/40 (100.00%) | 40/40 (100.00%) | 40/40 (100.00%) | 12/40 (30.00%) |
| idiom | 40 | 32/40 (80.00%) | 32/40 (80.00%) | 27/40 (67.50%) | 4/40 (10.00%) |
| verb | 60 | 48/60 (80.00%) | 48/60 (80.00%) | 48/60 (80.00%) | 6/60 (10.00%) |

| Core level n=60 | Lookup | Gloss | POS | IPA | Audio URL | Example | Translated example |
|---|---|---|---|---|---|---|---|
| A1 | 60/60 (100.00%) | 60/60 (100.00%) | 59/60 (98.33%) | 58/60 (96.67%) | 58/60 (96.67%) | 23/60 (38.33%) | 19/60 (31.67%) |
| A2 | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 59/60 (98.33%) | 34/60 (56.67%) | 32/60 (53.33%) |
| B1 | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 57/60 (95.00%) | 56/60 (93.33%) | 19/60 (31.67%) | 16/60 (26.67%) |
| B2 | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 58/60 (96.67%) | 54/60 (90.00%) | 18/60 (30.00%) | 14/60 (23.33%) |
| C1 | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 58/60 (96.67%) | 52/60 (86.67%) | 18/60 (30.00%) | 14/60 (23.33%) |
| C2 | 60/60 (100.00%) | 60/60 (100.00%) | 60/60 (100.00%) | 55/60 (91.67%) | 54/60 (90.00%) | 11/60 (18.33%) | 8/60 (13.33%) |

Core passes 98% lookup, 97% gloss and 95% POS guidance in this sample, not a guarantee of all-curriculum coverage.

## E. POS/gender analysis

Map: `NOM -> noun`, `VER -> verb`, `ADJ -> adj`, `ADV -> adv`, `ADJ:num -> num OR adj`, `PRO:per -> pron`, `CON -> conj`. Numeric adjectives allow numeral classification. Idiom descriptive map only: `PHR -> phrase/idiom/prep_phrase/proverb/adv/verb`; other labels are not automatically linguistically wrong. Expected POS need only occur among French entries.

Only core discrepancy: **quelque**, DB ADV versus API det. This is a taxonomy/sense-selection mismatch, not a demonstrated linguistic error. Core multi-POS 86/360 (23.89%); edge 12/40 (30%). First-entry selection is unsafe; avoir lists a noun before its verb.

All 131 core nouns with current m/f gender expose compatible noun sense tags (100%); all 24 corresponding edge nouns also match. Two of these core nouns and three edge nouns expose both genders. Tags do not provide a unique article decision. Livre (book/pound) needs sense alignment. Preserve local gender/article/elision/aspirated-h decisions until parity is tested.

## F. English gloss analysis

359/360 core `meaning_en` strings exactly equal one raw API gloss (99.72%). The remaining crepuscule entry (accented in actual data) differs in dusk/evening/morning-twilight wording, not an established semantic conflict.

Token overlap = distinct DB meaning tokens also present in the union of all API gloss tokens / distinct DB tokens. NFKD ASCII-fold, lowercase `[a-z]+`, discard one-letter tokens and stopwords `a an the to of and or in on for with from as by be is are at that this one someone something person who which it its his her not any very more most make do having used relating`. This is lexical recall, not semantic accuracy; all-sense union can hide a wrong first sense.

All 359 nonempty-token core cases score 1.0. Dessus / 'on (it)' has an empty comparison set and is undefined. No successful ordinary/edge case has zero overlap. `content/tools/06_english.py:157-237` already imports Kaikki French POS-filtered cleaned glosses, explaining shared-source agreement. It is not independent validation.

Successful low-overlap idioms: tout a fait has zero recall but compatible absolutely/entirely wording; metro, boulot, dodo has zero recall but descriptive routine/rat-race wording; du coup scores 0.5 with result/discourse uses; poser un lapin scores 0.667 with somebody/someone and idiomatic/compositional differences. Accents are preserved in actual requests/appendix. Eight missing idioms also score zero and are not conflicting definitions.

Core senses: median 2, mean 2.34, max 13 raw objects, not deduplicated curriculum concepts. No clearly incompatible ordinary definition was established by the limited qualitative inspection; this does not certify correctness or age appropriateness.

## G. IPA/pronunciation/audio coverage

Core IPA 346/360 (96.11%), equal to DB field availability; audio URL metadata 333/360 (92.50%); multiple distinct IPA strings 47/360 (13.06%). Edge IPA/audio 40/40 and 33/40; idiom 32/40 and 30/40; dedicated verb 47/60 and 48/60.

French specificity comes from filtered entry metadata, not independent phonetic classification. Dialect variants are not errors. Audio URL reachability/playback/format and per-file licenses were not tested; no audio downloaded. Pronunciation/sense selection still needs normalization.

## H. Example coverage

Core sense-nested example presence 123/360 (34.17%); examples under the expected POS in definitions 118/360 (32.78%); nonempty `english`/`translation` 103/360 (28.61%). Linkage is detectable but does not prove relevance to the curriculum-selected sense. French example language is inferred from the entry, not independently classified.

Current ordinal-0 DB examples 257/360 (71.39%): API-only examples would materially reduce availability. Keep curated/local examples. This matches the app's loaded first example rather than counting all possible example rows.

## I. Turkish translation coverage

Primary English-edition French entries: **0/500**, equivalently 0/480 successful lookups. Dedicated translation-route probes corroborate absent Turkish in this primary track; that is not a claim that every edition lacks Turkish.

Separate French-edition diagnostic: every ninth core row in the sorted sample, 40 requests, all HTTP 200. **16/40 (40%)** contain nonempty Turkish strings; seven sense-linked via text/index, nine unscoped. Examples include adresser, epoux, numeric entries and succes; some duplicate strings occur. This measures structural availability, not independently verified translation quality.

Current DB Turkish is populated for all core/edge/idiom samples. Preserve local Turkish in the prototype; optional French-edition enrichment or later removal is a product decision. Turkish does not veto ordinary English lexical feasibility; no machine translation was added.

## J. Prefix-search quality

40 prefixes, limit 50: all HTTP 200, zero empty sets, wrong-language rows or prefix violations. Target top-10 **10/40 (25%)**, top-50 **15/40 (37.50%)**. Returned rows include 41 proper names, inflections and repeated headwords/POS, legitimate dictionary material but curriculum search noise.

By ten-prefix group, top-10/top-50: lower short 0/1; upper short 2/4; accented 2/3; longer 6/7. Cap exclusion does not mean a word is absent: all targets resolve by exact lookup. No semantic relevance or curriculum frequency ranking is established. Keep local multilingual curriculum search.

| Prefix | Target | Rank in 50 | Rows |
|---|---|---|---|
| oe | oeuvre | 41 | 50 |
| oc | océanique | absent | 50 |
| di | dingue | absent | 50 |
| fo | foudre | absent | 50 |
| so | sourcil | absent | 50 |
| fa | faiblement | absent | 50 |
| ma | malade | absent | 50 |
| qu | quatre | absent | 50 |
| co | coupable | absent | 50 |
| gr | grave | absent | 50 |
| cir | circoncision | absent | 50 |
| din | dingo | 50 | 50 |
| esp | espace-temps | 14 | 50 |
| ci | ci | 1 | 50 |
| pét | pétasse | absent | 50 |
| éle | élevé | absent | 50 |
| sau | sauvegarder | absent | 50 |
| bav | baveux | absent | 50 |
| shé | shérif | 5 | 6 |
| fou | fourmilier | absent | 50 |
| lég | législature | absent | 50 |
| dém | démarcher | absent | 50 |
| mél | mélatonine | absent | 50 |
| pré | précautionneux | absent | 50 |
| dét | détachement | 16 | 50 |
| émi | éminent | absent | 50 |
| bée | béer | 6 | 19 |
| rév | révolte | absent | 50 |
| gés | gésir | 6 | 6 |
| dép | déposition | absent | 50 |
| condi | condition | 7 | 50 |
| nombr | nombriliste | absent | 50 |
| pourp | pourpre | 8 | 10 |
| faibl | faiblement | 9 | 48 |
| ouver | ouvertement | 6 | 13 |
| trent | trente-deux | 16 | 50 |
| craqu | craquer | absent | 50 |
| vague | vaguement | 10 | 31 |
| criqu | criquet | 3 | 4 |
| appar | apparemment | absent | 50 |

## K. Verb/forms matrix

**Independent NO-GO for replacing local conjugations.** All 48 non-reflexive samples resolve with French verb forms; all 12 reflexive strings return 404. No stripping se/s', synthetic pronoun insertion or compound-form generation was attempted. Those would be new algorithms requiring validation.

Expected product grid: seven six-person tenses + three imperative persons = 45 per verb, **2,700 cells**. Local sample actually has 2,694 cells; dechoir lacks six imparfait cells. This grid is not a linguistic claim that every verb has every form (e.g. pouvoir imperative).

Filter `lang_code=fr,pos=verb`. Exclude template/table metadata, blank/dash rows, multiword-construction tags and '+ past participle' instructions. Exclude IPA-tagged, slash-delimited phonetic and phonetic-character strings: 38 form rows. Distinct NFC/case-folded surfaces per cell: one = conservative unique candidate; multiple = selection required. Legitimate variants are not necessarily wrong; singleton presence is not independently proven correctness.

Person tags first/second/third + singular/plural map to je/tu/il/nous/vous/ils. Il/ils stand for the app's combined subject labels; imperative expects tu/nous/vous.

| API tags | App tense | Condition |
|---|---|---|
| indicative + present | present | Not perfect |
| indicative + present + perfect | passe_compose | Concrete person-tagged surface required |
| indicative + imperfect | imparfait | Six persons |
| indicative + future | futur_simple | Not perfect |
| conditional | conditionnel | Neither perfect nor past |
| indicative + pluperfect | plus_que_parfait | Concrete person-tagged surface required |
| subjunctive + present | subjonctif | Not perfect |
| imperative | imperatif | Three persons |

| Tense | Required | Concrete candidate | Unique | Multiple |
|---|---|---|---|---|
| present | 360 | 288/360 (80.00%) | 220 | 68 |
| passe_compose | 360 | 0/360 (0.00%) | 0 | 0 |
| imparfait | 360 | 282/360 (78.33%) | 215 | 67 |
| futur_simple | 360 | 288/360 (80.00%) | 215 | 73 |
| conditionnel | 360 | 288/360 (80.00%) | 215 | 73 |
| plus_que_parfait | 360 | 0/360 (0.00%) | 0 | 0 |
| subjonctif | 360 | 288/360 (80.00%) | 221 | 67 |
| imperatif | 180 | 138/180 (76.67%) | 102 | 36 |

| Class | N | Concrete / required | Unique / required |
|---|---|---|---|
| common-irregular | 9 | 294/405 (72.59%) | 187/405 (46.17%) |
| regular-er | 15 | 495/675 (73.33%) | 462/675 (68.44%) |
| regular-ir | 12 | 396/540 (73.33%) | 330/540 (61.11%) |
| other-irregular | 12 | 387/540 (71.67%) | 209/540 (38.70%) |
| reflexive | 12 | 0/540 (0.00%) | 0/540 (0.00%) |

| Critical verb | Concrete cells / 45 | Unique cells / 45 |
|---|---|---|
| avoir | 33 | 33 |
| être | 33 | 0 |
| faire | 33 | 0 |
| aller | 33 | 33 |
| pouvoir | 30 | 25 |
| vouloir | 33 | 30 |
| devoir | 33 | 0 |
| venir | 33 | 33 |
| prendre | 33 | 33 |

No complete 45-cell paradigms: 48 partial, 12 absent. Even non-reflexives alone reach only 1,572/2,160 (72.78%) concrete coverage, below the 80% NO-GO boundary. Restricting to their 33 simple-tense cells gives 1,572/1,584 (99.24%) presence, but only 1,188/1,584 (75%) unique surfaces. High simple-form presence must not be presented as complete conjugation feasibility.

There are 756 compound-construction instructions, e.g. present indicative of an auxiliary plus past participle, not completed person forms. They contribute zero to compound cells. Another 770 person-tagged rows lie outside recognized product mapping, often historical past or other subjunctive tenses; these are not all provider errors.

- Etre includes suis, me suis, m'en suis in one present first-person cell. All 33 simple cells have multiple candidates; faire/devoir similarly flatten different paradigms.
- Ressortir exposes alternative class/sense paradigms; tags alone do not select one.
- Vouloir imperative variants can be legitimate and are counted as selection-required, not incorrect.
- Pouvoir exposes phonetic strings `pø` and `pɥis` in `form` with tense/person tags; dechoir has slash-delimited phonetics. Naive ingestion would treat pronunciation as spelling.
- Dechoir has missing imperfect/imperative cells and multiple future candidates; its local grid is also incomplete, as acknowledged above.

Verb metadata is CONDITIONAL for lexical enrichment only. Auxiliary, reflexive/base-infinitive, group, aspirated-h and conjugation contracts must remain local. No future generator was implemented or validated.

Missing reflexive lookup strings:

`se demander`, `se retrouver`, `se quitter`, `se promener`, `s'exposer`, `se situer`, `se blesser`, `s'accrocher`, `s'adresser`, `se soucier`, `se peigner`, `se conformer`.

## L. Idiom coverage

Exact lookup/gloss 32/40 (80%); examples/translated examples 12/40 (30%); IPA 32/40 (80%); audio 30/40 (75%); Turkish 0. Descriptive POS mapping matches 27/40 but phrase taxonomy is not an ordinary-word veto.

DB English/Turkish 40/40, ordinal-0 examples 34/40, IPA 6/40. API pronunciation enriches idioms, but eight whole targets and many examples would be lost. Keep local idioms with optional API enrichment. Exact misses:

`faire la cuisine`, `ça dépend`, `être en retard`, `se rendre compte`, `être au courant`, `ce n'est pas la mer à boire`, `revenons à nos moutons`, `en faire tout un fromage`.

## M. Latency/reliability

Nearest-rank percentiles `sorted[ceil(p*N)-1]` across instrumented attempts, including 404s. Endpoint latency is not paired full+definitions UI latency. Full includes one extra chat probe beyond the 500 sample; definitions/search/translations also include surface probes. Cached reuse is not counted as a request.

| Category | Requests | 200 | 404 | p50 s | p90 s | p95 s | Max s |
|---|---|---|---|---|---|---|---|
| definitions | 441 | 433 | 8 | 0.060 | 0.087 | 0.116 | 3.110 |
| editions | 1 | 1 | 0 | 0.138 | 0.138 | 0.138 | 0.138 |
| forms | 60 | 48 | 12 | 0.061 | 0.078 | 0.095 | 0.261 |
| full | 501 | 481 | 20 | 0.064 | 0.100 | 0.166 | 2.974 |
| languages | 1 | 1 | 0 | 0.205 | 0.205 | 0.205 | 0.205 |
| missing | 1 | 0 | 1 | 0.069 | 0.069 | 0.069 | 0.069 |
| pronunciations | 1 | 1 | 0 | 0.042 | 0.042 | 0.042 | 0.042 |
| search | 41 | 41 | 0 | 0.059 | 0.107 | 0.153 | 0.218 |
| translations | 40 | 39 | 1 | 0.056 | 0.072 | 0.082 | 0.088 |
| translations-fr | 40 | 40 | 0 | 0.061 | 0.089 | 0.099 | 0.104 |

Instrumented first-attempt HTTP 200: **1,085/1,127 (96.27%)**. Forty-two 404s represent missing lexical entries or the deliberate missing control, not host outages. Retry-recovered success 0; retries 0; transport errors 0; 429 0; 5xx 0. Including the separately uninstrumented exploratory 403, 1,128 known API attempts occurred. No latency is fabricated for that 403.

500-target full pass: 480 successful, 20 missing; core all successful. Combined instrumented p95 0.139 s; full p95 0.166 s is within the <=0.5 s excellent planning band. Maxima of 2.974 s full and 3.110 s definitions still matter. No repeat-day/mobile/cold-offline/outage/longitudinal SLA testing. Persistent cache is required for control and availability, not because this run showed generally slow service.

## N. Payload/cache-size projection

UTF-8 JSON body bytes, no headers/storage overhead/audio; error bodies excluded from successful distributions.

| Population | Successful N | Median bytes | p90 | p95 | Max | Mean |
|---|---|---|---|---|---|---|
| Core | 360 | 2517.5 | 9808 | 10964 | 33755 | 3954.51 |
| All groups | 480 | 2791.5 | 10998 | 15752 | 38075 | 5073.25 |

Largest core payload: arreter 33,755 bytes; overall etre 38,075 bytes (accented actual lemmas). Estimated 5,149-entry cache at core mean: **19.42 MiB** full JSON, approximately 12.36 MiB at the median. Full+definitions mean 4,447.14 bytes, median 2,865, projected **21.84 MiB**. Mixed sample full mean projects 24.91 MiB, illustrating distribution sensitivity.

These are projections, not a full-curriculum cache measurement. Balanced sampling is not population weighted; selected-field storage could shrink it, indexes/provenance/versions could enlarge it. Audio is excluded. This does not authorize DB removal.

## O. Current DB versus API field coverage

| Core field | Current DB | API | Implication |
|---|---|---|---|
| English | 360/360 (100.00%) | 360/360 (100.00%) | Shared upstream; sense selection required |
| POS | 360/360 (100.00%) | 359/360 (99.72%) expected match | Definitions route needed |
| IPA | 346/360 (96.11%) | 346/360 (96.11%) | Equal availability; extra variants |
| Gendered nouns | 131/131 (100.00%) | 131/131 (100.00%) compatible | May be multiple genders/senses |
| French example | 257/360 (71.39%) | 123/360 (34.17%) | Local fallback needed |
| Expected-POS example | Not independently reassigned | 118/360 (32.78%) | Sense/POS narrowing matters |
| Translated example | 257/360 (71.39%) | 103/360 (28.61%) | Availability, not alignment proof |
| Turkish | 360/360 (100.00%) | 0/360 (0.00%) primary | Alternate edition 16/40 separate |
| Audio URL | No comparable word-table field | 333/360 (92.50%) | Metadata only, no playback test |
| IDs/CEFR/order/safety/Journey | Local product-owned | No matching contract established | Must remain local |

Verb-table example absence was not interpreted as application-wide absence; it has no equivalent example column. Word/idiom comparison uses loaded ordinal-0 fields. Extra senses may enrich a dictionary but be inappropriate as unfiltered flashcard content.

## P. 50-entry qualitative audit

Deterministic purposive selection: ten highest-frequency A1/A2 core; fifteen lowest-overlap successful non-verb entries not already selected; ten highest-sense-count core/edge not already selected; nine mandatory irregulars; six earliest remaining idioms. Few successful cases have low overlap, so tied full-overlap cases fill that stratum. Missing faire la cuisine enters through the idiom stratum. Definitions metadata was inspected after the full payloads.

Classes: clear = usable lexical information; normalize = spelling/POS/wording processing needed; select = ambiguous or requires sense/register selection; unsuitable = no exact result. These are not a population accuracy estimate. Uncertain interpretation stays selection-required, not declared linguistically wrong.

Counts: 32 select, 12 clear, 5 normalize, 1 unsuitable.

| # | Lemma | Class | Reason |
|---|---|---|---|
| 1 | arrêter | select | Stop/arrest/cease senses |
| 2 | assez | clear | Enough/quite usable |
| 3 | tant | select | So much/many and other uses |
| 4 | façon | clear | Way/manner usable |
| 5 | quelque | normalize | ADV versus determiner taxonomy |
| 6 | ainsi | clear | Thus/in this way usable |
| 7 | depuis | select | Preposition/adverb |
| 8 | ordre | select | Order has multiple senses |
| 9 | rue | select | Street/plant/inflected forms |
| 10 | coeur | normalize | Spelling-reference coeur needs ligature resolution |
| 11 | tout à fait | clear | Zero overlap but synonymous absolutely/entirely |
| 12 | métro, boulot, dodo | normalize | Zero overlap; verbose daily-routine description |
| 13 | du coup | select | Result/discourse filler |
| 14 | poser un lapin | normalize | Idiomatic/compositional and somebody/someone |
| 15 | le | select | Article/pronoun and chosen DB meaning |
| 16 | bon | select | Good plus register-sensitive senses |
| 17 | homme | select | Man/human/husband/employee |
| 18 | an | clear | Year usable |
| 19 | car | select | Conjunction/coach |
| 20 | ni | clear | Nor/neither usable |
| 21 | aujourd'hui | clear | Today/nowadays usable |
| 22 | livre | select | Book/pound; gender matters |
| 23 | expliquer | clear | Explain usable |
| 24 | quatre | normalize | Numeral/numeric adjective |
| 25 | plaisir | clear | Pleasure usable |
| 26 | pot | select | Container/beverage/kitty/slang |
| 27 | raie | select | Line/furrow/fish/form entries |
| 28 | dessus | select | Adverb/noun |
| 29 | grave | select | Serious/low-pitched and other senses |
| 30 | chiffre | select | Number/digit and other senses |
| 31 | devant | select | Preposition/adverb/noun/form |
| 32 | lancer | select | Noun throw may precede verb |
| 33 | sol | select | Soil/music/currency |
| 34 | témoin | select | Witness/best man/baton/control |
| 35 | jaune | select | Color/yolk/register-sensitive senses |
| 36 | avoir | select | Asset noun before have verb |
| 37 | être | select | Being noun and be verb |
| 38 | faire | select | Do/make; form paradigms ambiguous |
| 39 | aller | select | Journey noun and go verb |
| 40 | pouvoir | select | Power noun/can verb; phonetics in forms |
| 41 | vouloir | select | Will noun/want verb |
| 42 | devoir | select | Duty noun/must-owe verb |
| 43 | venir | select | Neutral/vulgar come senses |
| 44 | prendre | select | Take has many senses |
| 45 | avoir sommeil | clear | Be sleepy usable |
| 46 | bonne nuit | clear | Good night usable |
| 47 | de rien | select | Welcome/unimportant |
| 48 | de temps en temps | clear | From time to time usable |
| 49 | faire la cuisine | unsuitable | Exact 404 |
| 50 | il y a | select | Ago versus there is/are |

## Q. Provider/license/operational risks

The public host is outside app control. This run does not establish uptime, stable schema, quota guarantees or update cadence. Missing full-route metadata and the unexplained initial 403 are concrete integration concerns. A safe curriculum headword can return vulgar/adult/technical senses; local headword eligibility does not approve every API sense.

Future options, not implemented: persistent cache keyed by provider/edition/language/lemma/schema version, stale serving, bounded prefetch, negative-cache expiry, typed provider boundary and local fallback. Avoid repeated full-curriculum downloads. [Self-hosting documentation](https://wiktapi.dev/guides/self-hosting) describes a Node/SQLite deployment; [update guidance](https://wiktapi.dev/guides/updating-data) covers imports/staging. Self-hosting transfers uptime, disk and validation responsibility to this project. A controlled Kaikki/Wiktextract service is another future option, not work performed here.

Engineering attribution review, not legal advice: [WiktApi software is MIT](https://github.com/TheAlexLichter/wiktapi.dev/blob/main/LICENSE); the dictionary data is not thereby MIT. The [provider pipeline](https://wiktapi.dev/concepts/data-pipeline) uses structured Wiktionary-derived data. [Kaikki](https://kaikki.org/dictionary/) identifies Wiktionary source licensing under CC BY-SA and GFDL. Its published dump/extraction dates do not prove the public API's loaded generation.

[Wikimedia Terms of Use section 7](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use) describes text attribution, license notice and share-alike requirements including CC BY-SA 4.0/GFDL where applicable. Retain source-entry links, edition/language, retrieval/version and modification provenance. Review About/third-party notices and cached/exported data attribution before release; adaptation/distribution questions need separate assessment. Audio/media require per-file license/credit checks. No current license file was altered.

## R. Decision matrix

| Component | Decision | Evidence | Recommended future source |
|---|---|---|---|
| Core French lexical data | GO for prototype | 100% lookup, 99.72% POS with metadata | API behind local curriculum/fallback |
| English meanings | GO with selection | 100% gloss, shared upstream | API + local selected-sense fallback |
| IPA/pronunciation | CONDITIONAL GO | 96.11% IPA, 92.50% audio URL | API/cache + fallback; playback/license tests |
| Examples | CONDITIONAL, no replacement parity | 34.17% versus DB 71.39% | Hybrid, curated local examples |
| Prefix dictionary search | NO-GO as sole search | 37.50% target top-50 | Local curriculum search + exact API |
| Turkish | CONDITIONAL optional enrichment | 0/500 primary; alternate 16/40 | Local now; optional/remove only by product decision |
| Idioms | NO-GO replacement | 80% lookup/gloss | Local + optional API |
| Verb metadata | CONDITIONAL enrichment | 48/60 lookup, reflexive misses | Local aux/group/reflexive; optional lexical API |
| Conjugations | NO-GO | 58.22% candidate cells, 44% unique | Local |
| Public WiktApi host | Acceptable only with persistent cache/fallback | Full p95 0.166s, no longitudinal SLA | Cache-backed provider; self-host if later justified |

## S. Exact conditions for the next step

Proceed only to a dual-source design/prototype retaining the complete current DB fallback. No API migration has begun.

1. Local curriculum owns stable IDs, CEFR, frequency/order, themes, safe-learning eligibility, Journey membership/revision mappings and progress references. Provider spelling/sense order must not change learner identity. `progress.db` and SRS remain local and unchanged.
2. Typed provider results must distinguish missing/error/ambiguous states, preserve provenance, and handle actual metadata routes. Test response identity/schema rather than joining arrays by assumed order. Resolve spelling references and select senses explicitly.
3. Keep conjugations, auxiliary/reflexive metadata, idioms, curated examples and multilingual curriculum search local. No compound/reflexive generator in this prototype.
4. Persistent cache, stale serving and fallback must cover offline, timeout, 403/429/5xx, missing entries and schema drift. Measure paired-request and cache-hit mobile UX before making learning network-dependent.
5. Local Turkish remains during the prototype. French-edition enrichment needs sense/quality checks; removal is a later product decision.
6. Preserve register/attribution information; do not automatically expose every gloss as approved learning content. Parity checks compare product requirements, not presumed DB linguistic truth.
7. Later curriculum extraction and feature migrations require separate review/tests. This benchmark does not authorize content.db deletion, schema/reward/SRS changes or replacement of tests/content markers.

## T. Repository integrity

Initial main had valid HEAD, live remote equality, stable tag and clean tracked/untracked porcelain. **All 207 pre-existing tracked files** were SHA-256 inventoried and rechecked before report creation: present and byte-identical. No source/tests/curriculum/dependencies/previous reports changed. No corpus rebuild or application build/test suite was run; historical validation is not represented as current test execution.

Protected hashes below are both the starting and rechecked values:

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

Only intentional repository addition: `codex_reports/07_API_FEASIBILITY_BENCHMARK.md`. Raw responses/scripts/logs remain in OS temp, not staged. Ignored checkpoints/builds/editorial material were not removed or reset. Authorized Git index changes stage only this report.

Local tooling failures were not API/application failures: one CP1252 inspection failed reading UTF-8 and was rerun with explicit encoding; an unquoted PowerShell tag `^{}` argument failed and was corrected; an oversized report-generator shell command exceeded Windows command-line length and was split before execution. Form normalization was refined from cached evidence to exclude 38 phonetic rows; final metrics use that rule. No extra API calls were needed for these corrections.

## U. Git publication

Starting local/live remote main: `583bb7631e7dacd994b874c3224eb518dd7a391c`.

Publication procedure: stage only this report, commit `docs: benchmark lexical API feasibility`, push normally to `https://github.com/ArdaHFO/FrenchApp.git` main. Verify local HEAD against `git ls-remote origin refs/heads/main`, clean porcelain and unchanged baseline tag. No tag movement or history rewrite.

A Git commit cannot contain its own SHA literally without changing that SHA. The exact report commit and completed remote verification are therefore supplied in the final task handoff. Recover the immutable report commit using `git log -1 --format=%H -- codex_reports/07_API_FEASIBILITY_BENCHMARK.md`. This section records the publication procedure, not a fabricated post-commit result in a pre-commit document. No second receipt/amendment is necessary.

## Appendix - Exact sampled targets

Every target below is unique after NFC/case folding. Accents/apostrophes are preserved. The immutable DB hash, sample-manifest hash, method and seed fix the tested population without publishing raw payloads.

### core / A1 (60)

arrêter; assez; façon; quelque; ordre; rue; coeur; expliquer; quatre; plaisir; près; clair; reconnaître; soeur; devant; grave; malade; prochain; régler; au-dessus; lune; évidemment; allemand; certainement; mademoiselle; mince; taxi; succès; jaune; supérieur; total; oeuf; inspirer; royaume; remarque; raide; tranquillement; quelquefois; intimider; spécialité; moulin; polonais; affoler; tunique; lamenter; faiblement; spacieux; écuyer; sanitaire; agrément; aventurier; biscotte; muguet; vermeil; vivable; océanique; voiturer; antillais; moyenner; nuitée.

### core / A2 (60)

tant; ainsi; depuis; ouvert; secret; mener; travers; lancer; supposer; dessus; sol; inquiet; voie; mille; ferme; tas; deuxième; cent; condition; sombre; valise; attente; là-haut; apparemment; courant; patte; coupable; vague; aveugle; figure; oeuvre; sergent; moral; miroir; pot; totalement; bel; franchir; venger; adresser; vitre; dingue; soulager; craquer; annonce; boue; dessous; particulièrement; époux; coude; moche; sujet; ouvrier; normalement; brutal; hanter; sourcil; régiment; foudre; soi-disant.

### core / B1 (60)

désormais; laisse; parvenir; chiffre; malin; gouverneur; distraire; poudre; tentative; minuscule; ruiner; carrément; cap; pratiquement; saloperie; tragique; anonyme; amical; fatal; gré; brigade; agressif; visiblement; caporal; paisible; pourrir; boy; bénéfice; quarante; égoïste; assistance; infiniment; brut; révolte; embaucher; marais; évaluer; glorieux; cube; avide; notamment; hisser; strictement; gouffre; hiérarchie; vermine; illustre; éduquer; contester; pochette; impératrice; brioche; mondain; fabricant; incessant; séparément; pourpre; subit; rudement; fondement.

### core / B2 (60)

empreinte; ronger; désagréable; hypothèse; chauve; navrer; vaguement; crépuscule; salopard; dix-huit; vicieux; escroc; sitôt; vingt-cinq; détachement; superficiel; pleinement; explosif; bougre; déposition; dot; dôme; immonde; rayure; charrier; roulement; ouvertement; hautement; raie; terne; délirant; outrage; shérif; gésir; rappliquer; partisan; dix-neuf; caca; vil; cambrioleur; éminent; prospère; indécent; druide; engourdi; empocher; précipitamment; traction; euphorie; idem; justification; sauvegarder; accaparer; titi; oblique; iode; assourdir; frise; foncé; rigoureusement.

### core / C1 (60)

crête; viril; ci; impact; propice; vingt-deux; escadrille; bassine; fictif; éloignement; plumer; éther; funeste; nounours; maussade; pétasse; agoniser; bossu; hyper; palpiter; mangue; existant; bath; roulotte; dégommer; rhubarbe; vitrail; trente-six; nuisible; criquet; élevé; nécessité; dingo; baveux; roupiller; rejeton; impétueux; pincement; lessiver; trente-deux; fourmilier; intégralement; trépied; affaisser; circoncision; béer; quarante-huit; précieusement; désolant; thérapeutique; pertinemment; équivalent; stipuler; buis; précautionneux; contingence; revisiter; inabordable; migratoire; neurobiologie.

### core / C2 (60)

fréquemment; pareillement; ombrelle; accouder; linguistique; rusé; quatre-vingt-dix; blindage; trépas; placide; pâmer; matrone; nativité; oublieux; skieur; toiser; quarante-trois; pépée; revêche; espace-temps; bigrement; trente-quatre; inadéquat; gnouf; salubre; quarante-sept; délectation; isolément; lourdingue; blanchissage; neuneu; nonante; cocufier; cagnard; derechef; ultraviolet; démarcher; fâcheusement; législature; encoignure; superfétatoire; abricotier; carier; hambourgeois; nombriliste; bobineau; microbiologie; mélatonine; monocycle; déclive; mensuellement; eider; aléser; précairement; agglutinatif; sumérien; plutonique; soixante-dixième; électrophorèse; vitement.

### edge / edge (40)

le; bon; homme; an; ni; aujourd'hui; livre; son; cri; vol; bol; dévorer; blé; psy; car; nu; pénétrer; toile; témoin; mat; tâcher; maîtrise; gin; duper; gui; rigidité; bio; lis; entre-deux; ingénierie; quarante-deux; véniel; presqu'île; pince-nez; quarante-quatre; qu'en-dira-t-on; balalaïka; dame-jeanne; pistolet-mitrailleur; coutumièrement.

### idiom / idiom (40)

avoir sommeil; bonne nuit; de rien; de temps en temps; faire la cuisine; il y a; s'il vous plaît; à bientôt; ça dépend; être en retard; faire la queue; faire semblant; prendre son temps; se rendre compte; tout à fait; à la fois; à la vôtre; à votre santé; être au courant; casser les pieds; du coup; en effet; faire la tête; mettre au monde; métro, boulot, dodo; nez à nez; tenir au courant; être dans la lune; appeler un chat un chat; au fur et à mesure; avoir un chat dans la gorge; ce n'est pas la mer à boire; mettre les pieds dans le plat; poser un lapin; revenons à nos moutons; tomber dans les pommes; ça marche; avoir d'autres chats à fouetter; en faire tout un fromage; être à l'ouest.

### verb / common-irregular (9)

avoir; être; faire; aller; pouvoir; vouloir; devoir; venir; prendre.

### verb / regular-er (15)

oublier; occuper; ignorer; regretter; organiser; transporter; masquer; escroquer; congeler; grelotter; gamberger; recroqueviller; concerter; calomnier; buriner.

### verb / regular-ir (12)

réunir; grandir; saisir; guérir; réagir; jouir; gémir; gravir; vieillir; rugir; raffermir; vagir.

### verb / other-irregular (12)

taire; courir; intervenir; suffire; valoir; haïr; ressortir; parfaire; déchoir; soustraire; assaillir; morfondre.

### verb / reflexive (12)

se demander; se retrouver; se quitter; se promener; s'exposer; se situer; se blesser; s'accrocher; s'adresser; se soucier; se peigner; se conformer.
