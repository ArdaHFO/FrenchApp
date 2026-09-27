# Phase 12 — Optional lexical provider foundation

## Boundary

New `lib/services/lexical/{lexical_models,lexical_transport,wiktapi_provider}.dart` has no dependency on curriculum repositories, AppState, progress, SRS, rewards or Journey. No existing feature uses the provider yet. Local learning authority is unchanged. No package dependency added.

## Contract and endpoint evidence

`LexicalLookupKey` fixes provider WiktApi, edition en, lexical language fr and normalization version 1. Trimmed/collapsed/lowercase lemma is the cache identity; expected POS is a presentation hint, not a separate identity. Accents are retained; no claim of Unicode NFC normalization. Queries over 120 runes, control/path/URL syntax or empty text are rejected before HTTP.

Official documentation consulted: https://wiktapi.dev/quickstart. Two responsible actual requests for `chat` verified `/v1/en/word/chat/definitions?lang=fr` and `/v1/en/word/chat/pronunciations?lang=fr`, both HTTP 200 without authentication. Observed cache header: `public, max-age=86400, stale-while-revalidate=604800`. Definitions carry POS/language/senses; pronunciation projection carries POS/language/sounds. This avoids the full route's missing POS metadata and does not join arrays by position. These inspection requests are not final live validation of the implemented client.

`WiktApiProvider.lookup` validates root edition/word identity, filters French rows, retains POS-grouped senses, tags, optional examples, IPA and audio metadata. Provenance records source/response URL, requested lemma, retrieval UTC, schema version and source label. Unknown upstream generation stays null. Unsafe tags are retained but `safeForDefaultDisplay` excludes vulgar/offensive/slur/sexual/obscene/derogatory/pejorative/racist senses from default presentation. Dictionary data is not promoted into approved learning content.

Explicit outcomes: found, notFound, selectionRequired, transientFailure, rateLimited, schemaFailure, permanentFailure. Missing French senses is selectionRequired, not a successful empty definition. Pronunciation failure preserves usable definitions with `pronunciationUnavailable=true`. No remote playback is implemented; audio filenames alone do not establish media licensing.

## Transport

Injectable dart:io HttpClient, no new dependency. User-Agent identifies FrenchApp/project URL; Accept application/json. URI path segments encode the explicit query exactly once. Connection timeout 8 s, total request timeout 15 s, decoded response bound 262,144 bytes checked both while streaming and before parsing. Client force-closes in finally; redirects disabled. No credentials or learner information. Two sequential projections per lookup, no automatic retries. HTTP 429 honors numeric/date Retry-After through provider-wide cooldown (60 s fallback). 404 is separately negative-cacheable; 403 is permanent; 5xx/408 and transport failures are transient.

## Tests and validation history

`test/lexical_provider_test.dart` adds **27 deterministic tests**. Synthetic payloads cover multiple POS/senses, foreign-language noise, optional fields, unsafe tags, normalized JSON roundtrip/provenance, accented/apostrophe/multiword/percent queries, invalid inputs, 403/404/429/500/502/503, numeric/date Retry-After, malformed JSON/schema/identity, invalid UTF8, oversized body, timeout/socket/HTTP errors and partial pronunciation. Loopback-only HttpServer tests exercise real transport headers, streamed size rejection and timeout. No live HTTP in tests and no progress database involved.

Validation attempts retained:

1. `flutter test test/lexical_provider_test.dart --no-pub`: exit 1, 24 passed / 3 failed. First draft double-encoded accents/spaces/percent signs. Actual decoded pathSegments proved the error. Replaced pre-encoded Uri.https path with Uri pathSegments for endpoint and source link.
2. Same command: exit 0, **27 passed**.
3. `flutter analyze --fatal-infos --no-pub`: exit 1, two brace-style infos. Added braces; no logic changes.
4. Analyzer rerun: exit 0, no issues.

New files formatted with `dart format lib/services/lexical test/lexical_provider_test.dart`. An initial patch targeted the wrong neighboring size-check line and was rejected without modifying files; corrected patch addressed the actual diagnostics.

## Integrity / publication

Only three new production files and one new test file belong to implementation, followed by this separate report. Content, markers, lock and historical reports unchanged. Implementation commit precedes this report (`git log --grep='feat: add lexical enrichment provider foundation'`). Main/rollback tag unchanged. Persistent caching, UI and attribution remain subsequent phases; no API-first learning integration.
