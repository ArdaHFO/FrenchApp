# FrenchApp master completion handoff

Date: 2026-09-27. Approved architecture: **HYBRID ENRICHMENT**.

## A. Executive summary

Approved Step 09 was verified, fast-forwarded to main and pushed before implementation. Phases 10–15 add persistence recovery, event-time/replay hardening, a bounded lexical provider, independent persistent cache, explicit online dictionary detail and attribution/CI updates. Phase 16 independently found and repaired 12 confirmed defect IDs. Phase 17 supplies fresh final validation and build evidence. This is not a linguistic re-curation or API-first migration.

## B. Final architecture

`content.db` remains the authoritative offline source of curriculum, local definitions, Turkish meanings, examples, conjugations, grammar, relations, safety, CEFR/order, aliases and stable IDs. `progress.db` remains local. No API response changes learning pools, answers, SRS, Journey or identity.

Optional `LexicalService` sits outside WordRepository. It combines an exact WiktApi adapter with a separate `lexical_cache.db`. AppState creates it lazily only when explicit enrichment is requested. Provider outcomes never write progress. Online-only dictionary entries are view-only.

## C. Git history

Approved Step 09 implementation `2bb997c7ab36b95d098e88d131165d22b42903b9` and report `86b3b21f02c016990b0734431716bb8a84919cac` were already reviewed. Main was fast-forwarded from `16949a3dd067bfb84083c51e5a97a2e7b8294410` to that report commit, then the completion branch was created. The chronological completion ledger appears at the end of this report.

No approved history or old rollback tag is rewritten. This document cannot embed its own future commit hash; resolve the final documentation state through `stable-hybrid-enrichment-v1` and normal Git history. Final remote/tag equality is checked after publication, not inferred from a successful local commit.

## D. Runtime repairs

- Steps 02–05 established persist-before-publish, atomic station/story/sentence actions, atomic free-quiz answers with transaction-time card reads, and semantic song starring without stale full-row overwrite.
- Step 09 combines station result, station reward and ordinary quiz activity into one admission/transaction, preserving reward-event order and persistence-only retry.
- Phase 10 repairs sentence/song/arena pending/error/retry state. Failed persistence consumes no local score/combo twice; duplicate retries are blocked.
- Phase 11 captures one practice event timestamp, resets station attempt-scoped replay combo, cancels stale cleared-search debounce and documents generic full-row save constraints.
- Phase 16 extends recovery to story/flags/song sheets/preferences/media, makes compound settings confirmation atomic, validates unsafe backup rows and fixes proven quiz/layout boundaries.

## E. User-facing enrichment

Local dictionary search and ranking are unchanged. A local word sheet offers **Daha fazla sözlük bilgisi**. Search offers an explicit exact online lookup action; typing does not send requests. The detail screen keeps approved local meaning first, separates additional English senses/IPA, shows attribution and cache status, and offers concise lexical-only retry. Online-only results have no save/star/deck/CEFR/SRS action.

## F. Provider behavior

Fixed host `api.wiktapi.dev`, English edition `en`, lexical language `fr`. Exact definitions supply POS-grouped senses; pronunciations supply IPA/audio metadata. There is no positional array join, prefix-search replacement, translation API or progress-aware provider model. Found/notFound/selectionRequired/transientFailure/rateLimited/schemaFailure/permanentFailure remain distinguishable.

Keys normalize surrounding/repeated whitespace and case, preserve accents/apostrophes, bound input to 120 runes and reject control/path/URL input. Transport has identifying User-Agent, JSON Accept, percent-encoded path segments, redirects disabled, 8 s connection/15 s total timeout and 256 KiB body bound. A five-request production-adapter live smoke passed; it is not an SLA.

## G. Cache behavior

Independent support-directory SQLite stores normalized selected data/provenance, not raw payloads. Key includes provider/edition/language/lemma/schema; expected POS is presentation filtering, not a colliding cache identity. Default positive freshness 24 h plus 7 d stale window, shorter negative caching, useful response headers honored. no-cache/must-revalidate/no-store behavior has explicit regressions.

Fresh reads avoid network. Usable stale results return immediately and trigger single-flight revalidation; failure keeps usable stale data. Negative cache avoids repeated immediate 404 calls. Expired/no-cache failures remain explicit. Malformed/unsupported cached records are discarded safely. Last-access eviction caps retention at 500 entries; there is no eager curriculum fetch. Cache loss cannot remove progress or enter a progress backup. Physical size varies with normalized senses; 500 is a retention bound, not a promised byte size.

## H. Offline guarantees

Core startup, vocabulary, verbs, local search, grammar, quizzes, Journey and progress continue through local repositories. The real-content outage smoke checks unchanged progress and core navigation after provider failure. Existing real-content smoke and atomicity suites exercise actual offline learning actions. Device airplane-mode/physical voice-engine behavior is a separate validation limit, not claimed here.

## I. Bug sweep methodology

Report 16 inventories transaction/cache publication, async futures/timers/streams, state-machine recovery, restore generations, SRS/game/Journey invariants, search/quiz sparse and duplicate data, backup validation, provider/cache failure states, layout/text scaling, media lifecycle, resource bounds, privacy and Python publication/path safety. Evidence includes real SQLite triggers, synthetic provider payloads, real widgets, read-only current-content analysis and coverage-guided inspection.

## J. Bug ledger

See report 16 for exact reproduction, expected/observed states and regression names. Summary:

| ID | Severity | Repair / test evidence | Commit |
|---|---|---|---|
| BUG-001 | P2 | Story node/completion failure feedback and persistence retry; two SQLite/widget tests | `6cf2247` |
| BUG-002 | P2 | Await/guard flag callback, unchanged state on failure, retry toggles once | `6cf2247` |
| BUG-003 | P2 | Both song-star sheets recover; actual player widget + source path tests | `6dfa4c3` |
| BUG-004 | P1/P2 | Atomic compound settings confirmation, preference failure/duplicate handling | `7fa5ad3` |
| BUG-005 | P2 | Empty song quiz has an empty state and no reward | `6cf2247` |
| BUG-006 | P2 | Cache directives, malformed Retry-After, no-store eviction | `46630cd` |
| BUG-007 | P1 | Reject null/duplicate identities, invalid booleans and inconsistent backup counters before writes | `ef492d1` |
| BUG-008 | P2 | Media command error surfaced; retry works, play/seek/disposal futures handled | `e8f8875` |
| BUG-009 | P2 | Long attribution wraps; nine actual width/text-scale cases | `45998ab` |
| BUG-010 | P2 | Cloze whole-word boundaries, red `an` inside `mange` fixture | `fcfee81` |
| BUG-011 | P2 | Distinct French distractors despite same-lemma different-sense rows | `fcfee81` |
| BUG-012 | P2 | Narrow 2× sentence text wraps without overflow | `4b9d529` |

Twelve IDs found, twelve fixed; no confirmed unresolved scoped P0/P1/P2 software defect is knowingly left. This does not establish absence of undiscovered defects.

Exact regression locations (line numbers in the final source candidate):

- `test/progress_consistency_test.dart:713–851`: BUG-001 story node/completion; BUG-002 flag; BUG-003 player song star; BUG-004 atomic level/goal and preference retry. Test names start with those IDs.
- Same file `:852–906`: BUG-005 empty song quiz, BUG-009 nine attribution layouts, and `Sweep narrow large-text sentence remains usable` (BUG-012), with song/story control cases.
- Same file `:907`: eight `Sweep stale <feature> route cannot mutate restored progress` cases.
- `test/backup_validation_test.dart:56`: four `BUG-007 backup rejects <corruption> before durable replacement` cases.
- `test/lexical_provider_test.dart:87,96` and `test/lexical_cache_test.dart:72`: BUG-006 no-cache, malformed Retry-After and no-store refresh.
- `test/song_media_failure_test.dart:28`: BUG-008 media command failure and successful retry.
- `test/learning_filter_test.dart:471,483`: BUG-010 complete-word cloze and BUG-011 unique homograph options.
- `test/box_scheduler_test.dart:11`: 1,200-transition scheduler invariant test; `test/app_smoke_test.dart:237`: real-content offline enrichment failure/core navigation.

Phase 16 adds 39 tests beyond the 265-test post-feature suite. The complete master adds 97 tests beyond the 207-test Step 09 baseline, for 304 final tests.

## K. Unfixed items and legitimate limits

Remote pronunciation playback is deferred because WiktApi's audio filename alone lacks adequate per-file license provenance. Existing TTS remains. Physical Android voice/media focus, WebView/YouTube, power-loss/COMMIT I/O failure and privileged Windows symlink cases are not fully validated here. Dictionary tags cannot guarantee all untagged senses are suitable; local approved content remains authoritative. Retained settings pages are treated as explicit current preference actions, not stale learning sessions. Formatting differences remain non-functional style debt.

## L. Final validation

| Exact command | Exit / result | Wall duration |
|---|---|---|
| `flutter analyze --fatal-infos --no-pub` | 0 / No analyzer issues | 7.53 s |
| `flutter test --no-pub` | 0 / 304 passed; no reported skips | 319.89 s |
| `flutter test --coverage --no-pub` | 0 / 304 passed; no reported skips | 330.20 s |
| `python -B -m unittest discover -s content/tools/tests -p "test_*.py"` | 0 / 86 run; 10 environment skips | 53.02 s |
| `python -B content/tools/14_validate_db.py` | 0 / Structural/learning-safety PASS | 0.45 s |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0 / Six Journey revisions match | 0.17 s |
| `flutter build apk --debug --no-pub` | 0 / Debug APK built | 253.75 s |

All seven final commands passed on their first Phase 17 attempt. Phase 16 red runs, harness failures and repair reruns are retained in report 16. Final recorded LCOV line coverage is 8,920/10,174 (87.67%); generated coverage is not committed. This is recorded-line execution, not exhaustive branch/state coverage.

Warnings: test-only sqflite factory replacement, missing desktop TTS plugin, and expected Python negative output-collision diagnostics. No Flutter test skip was reported.


## M. Build result

`flutter build apk --debug --no-pub` passed (exit 0, 253.75 s). Output: `build/app/outputs/flutter-apk/app-debug.apk`, **204,408,004 bytes (194.94 MiB)**. APK SHA-256: `600864e4718e08888a9dd6a52b114399b9b631638b4f13a4c78396eea5fbf7be`. Generated output is ignored and not published to Git; the root handoff APK was not replaced.

Embedded `assets/flutter_assets/assets/db/content.db` hashes to `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417`, exactly matching the protected input. No progress or lexical-cache runtime database is bundled. This is a debug build, not release-signing or physical-device validation.

Build warnings: `flutter_tts` applies Kotlin Gradle Plugin, which a future Flutter release will no longer support; installed SDK tools understand XML through v3 but encountered v4. Neither prevented this build. Dependencies/toolchain were not upgraded to suppress warnings.


## N. Security and privacy

Only an explicitly queried French lemma is sent to the fixed provider. No telemetry, API key, progress, profile, identifier, Turkish response or backup leaves the app. Responses are size/time bounded and never interpreted as executable markup. Focused tracked-file/signature scans found no credentials/private keys or generated/runtime artifacts to publish. This is evidence-qualified scanning, not an absolute security guarantee.

## O. License and attribution

`THIRD_PARTY_NOTICES.md`, About and enrichment detail distinguish WiktApi software MIT from Wiktionary-derived dictionary data and CC BY-SA/GFDL source obligations. Normalized/filtered online definitions identify contributors, source and retrieval time. No dictionary data is relabeled MIT. Existing bundled-source notices and FLELex distribution checks remain; this engineering handoff is not legal clearance for every distribution context.

## P. Files changed

Scoped runtime/AppState/store/backup/UI repairs; new `lib/services/lexical/` provider/models/transport/cache/service; `LexicalDetailScreen`; small preference callback helper; focused deterministic tests; CI Python unittest step; attribution and ignore rules; numbered reports 10–17 and this handoff. No content/pipeline/dependency/marker changes. No APK, raw provider response or runtime cache is committed.

## Q. Remaining risks

Public-host outages/schema drift, unscreened lexical data and media licensing remain external concerns. Persistent cache reduces network dependence but does not promise always-current enrichment. Statement-trigger rollback tests do not simulate process/power-loss at COMMIT. Line coverage does not enumerate every state combination. Core learning remains local regardless.

## R. Merge recommendation

**All specified merge gates pass; safe to fast-forward the validated completion branch under the approved workflow.** Analyzer, full tests, coverage, Python (documented environment-only skips), both content audits, debug build and offline validation pass. Twelve confirmed sweep defects are repaired. No secret/runtime artifact is staged; master handoff is included in the final documentation state.

Publication must use a normal branch push and main fast-forward, followed by annotated `stable-hybrid-enrichment-v1`; preserve the old rollback tag. Final local/remote/tag equality is checked after those operations and recorded in the final handoff. No remote CI success or physical-device acceptance is inferred from local validation.


## Chronological completion commit ledger

| Commit | Purpose |
|---|---|
| `db8d23dd8fc9e26e1c825db25a5b7950416f7055` | fix: recover practice UI from persistence failures |
| `2e0d78bbe8eda7098005b1ed0be457338e391922` | docs: record persistence recovery repair |
| `551db44498feca107b2e4093a0e950f94a25c661` | fix: harden remaining runtime edge cases |
| `2facd0e2bb8065121bbcc2682953e7e1a9d46ca4` | docs: record runtime edge-case hardening |
| `fa9d0df72d52e0a887ca5fbfaaa89d2012b8d171` | feat: add lexical enrichment provider foundation |
| `57285613f9cdee99fcb4f729f1016f94fb94b8ff` | docs: record lexical provider foundation |
| `03e44a77bcd33f251f72ca69ffa5f62376085e99` | feat: add persistent lexical enrichment cache |
| `81fdb685bbd448fe6694ef2e3c0c477d50f67c80` | docs: record lexical cache design |
| `a65802bfd2b363a7b570e07b6c3bfbb283983083` | feat: add optional online dictionary enrichment |
| `2489c080b581e9a1f5562b14ab85f46848fc7b14` | docs: record extended dictionary feature |
| `c35caef883959f1bb14d7459cdbcc311696749e9` | chore: harden lexical enrichment and attribution |
| `30a216f8db29a6c658005e6e57e118e8326881a8` | docs: record lexical enrichment hardening |
| `6cf22476b03fc8acc17946a11691e959b6f82139` | fix: resolve BUG-001 BUG-002 BUG-005 recovery and empty quiz |
| `6dfa4c33fcc72dbea96ff9f97b8cca9b625bc7d7` | fix: resolve BUG-003 song vocabulary save recovery |
| `ef492d1a64dbe9c4baed842831418ebaf5ce327c` | fix: resolve BUG-007 reject inconsistent backup rows |
| `46630cd00e51d908b2c879170f6f723351f986e8` | fix: resolve BUG-006 honor lexical cache directives |
| `7fa5ad376902375982f0ca8918cfe2d698849952` | fix: resolve BUG-004 atomic preference confirmation and error UX |
| `e8f88751ab4f0d3dea2fd0c6418ba210f9172fe3` | fix: resolve BUG-008 recover media command failures |
| `fcfee8159fa2de983d8119bdd312fb5472e41cf3` | fix: resolve BUG-010 BUG-011 quiz word boundaries and options |
| `45998ab436dde169706c2310371c6f24e68b2ace` | fix: resolve BUG-009 wrap attribution and verify stale routes |
| `cabf0e48330b840aedb328fb289cd10fa59dc876` | test: verify offline core flows and scheduler invariants |
| `4b9d5293677169a4df7b52f63c92009e1ac29ffa` | fix: resolve BUG-012 narrow large-text sentence layout |
| `00672444d409f091d8cb9cf4d4d446620d44f731` | docs: record comprehensive bug sweep |
| `d9d0a639a10e0f02a5562113211ffc0f9bc73faf` | docs: record final validation and release baseline |
| `stable-hybrid-enrichment-v1^{commit}` (this final handoff commit) | docs: complete hybrid enrichment handoff |
