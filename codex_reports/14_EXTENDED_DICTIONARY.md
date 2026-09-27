# Phase 14 — Extended dictionary

## User capability and authority

Local SearchScreen still uses the existing synchronous local WordRepository search and ranking. No HTTP on typing, debounce or local result selection. Two explicit actions open `LexicalDetailScreen`:

- `Daha fazla sözlük bilgisi` in local word detail attaches the local lemma/POS, shows approved Turkish/English/IPA first, then clearly separate extra dictionary information.
- `Fransızca kelimeyi çevrimiçi ara` submits the explicit entered French query. Online-only results are view-only with no star, SRS, CEFR or Journey controls.

The screen displays safe additional English senses, provider POS/tags, IPA variants and selectable source URL. It prefers the local POS (including NOM/VER normalization); unmatched POS is explicitly labeled. It omits tagged inappropriate senses and does not replace any Word field. It does not display upstream quotations or play remote audio.

## Lifecycle

AppState owns one lazy LexicalService getter only for optional feature lifetime; service code remains independent of AppState/progress. No cache/network initialization at startup. Close drains progress and optional lexical work independently, then closes their databases. Content/progress schema unchanged.

The detail view has pending/result/error states. Duplicate retry taps are ignored while pending. A monotonically increasing request identity plus mounted check rejects older results and disposed-widget callbacks. Reusing the widget with another lemma/provider/local attachment starts a new request. Failure gives concise Turkish retry text; rate-limit/missing/schema/permanent outcomes are distinct. Cache/stale/partial-pronunciation/unavailable-cache status is visible. Refresh retries only lexical lookup. Local meaning stays visible while optional lookup fails or loads.

## Tests

`test/lexical_detail_test.dart`: **11 new widget tests**. Two control completers exercise old/new response order, disposal, outage, duplicate retry and view-only/safety behavior. Nine layout cases cover 320×640, 390×844, 430×932 at text scale 1.0/1.5/2.0; local meaning remains, matching safe noun senses display, other POS/unsafe senses do not, refresh is scroll-accessible and no Flutter exception occurs.

## Validation, including unsuccessful attempts

1. Initial widget run: exit 1, 3 passed/8 failed. Test helper ambiguously selected both the ListView and SelectableText's Scrollable. This was a harness error, not overflow evidence.
2. Combined lexical/search run: exit 1, 54 passed/1 failed. At narrow scale 2.0, the test expected lazy-list text before scrolling it into the build viewport. Corrected the test to scroll to the target first; production UI unchanged.
3. `flutter test test/lexical_detail_test.dart test/lexical_cache_test.dart test/lexical_provider_test.dart test/word_search_test.dart --no-pub`: exit 0, **55 passed**.
4. `flutter analyze --fatal-infos --no-pub`: exit 0, no issues.
5. `flutter test --no-pub`: exit 0, **265 passed**, no reported skips, 295.01 s. Includes all previous persistence/restore and actual local learning/search/Journey/grammar/song/backup smoke tests; no live provider dependency.

Only new detail source/test were formatted in this phase. Full-suite success is automated evidence, not physical-device/voice-engine certification. Final explicit provider-outage/core-flow tests and red-team review remain required.

## Files and integrity

AppState adds lazy optional service ownership; SearchScreen adds explicit navigation; new lexical detail screen/test. Separate report follows `feat: add optional online dictionary enrichment`. No dependency, curriculum, content marker, backup or SRS modification; reports 00–13 unchanged. Runtime cache/raw HTTP/build outputs are not staged. Main and old stable tag remain unchanged during branch work.
