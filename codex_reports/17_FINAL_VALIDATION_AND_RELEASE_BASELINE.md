# 17 — Final validation and release baseline

Date: 2026-09-27. Architecture: **HYBRID ENRICHMENT**. Final software candidate before documentation: `00672444d409f091d8cb9cf4d4d446620d44f731` on `master-completion-hybrid-enrichment`.

## Acceptance scope

Phase 16 completed with 12 confirmed bug IDs repaired. Its final narrow-layout repair and added tests are included in this fresh complete validation. The branch was clean at entry. No content rebuild, dependency upgrade, pub get, release-signing operation or APK replacement was requested/performed.

## Final validation matrix

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


## Offline acceptance

`offline enrichment failure leaves real-content core navigation and progress intact` uses the actual bundled content database and AppState, an explicit unavailable provider, and an actual enrichment route. It verifies unavailable feedback, unchanged exported progress, and subsequent vocabulary/verb/grammar/Journey navigation without another provider call. It passed independently and is included in the final full suite.

The existing real-content smoke tests additionally exercise startup, word swipes, verb sessions, local accent/Turkish search, grammar lessons, free quiz, completed station quizzes, Journey map, sentence/story practice and backup/progress persistence. Flutter widget tests deny ordinary external HTTP by default; deterministic provider/cache tests use injected transport or loopback only. These prove repository-level offline behavior, not physical Android airplane-mode acceptance.

## Small live-provider smoke

Five sequential requests ran through the **production** `WiktApiProvider` and `IoLexicalTransport` from an OS-temporary Dart script. No raw response was persisted or committed; no credentials supplied. The normal production User-Agent was accepted.

| Lookup / endpoint | HTTP | Elapsed | Encoded body |
|---|---:|---:|---:|
| chat / definitions | 200 | 661 ms | 2,491 B |
| chat / pronunciations | 200 | 65 ms | 428 B |
| école / definitions | 200 | 102 ms | 148 B |
| école / pronunciations | 200 | 76 ms | 526 B |
| zzfrenchappmissingqzx / definitions | 404 | 81 ms | 188 B |

Normalized results: chat found (4 senses, 5 pronunciation records), école found (1 sense, 6 pronunciation records), missing word notFound. Both found results retain pronunciation metadata. This is compatibility evidence, not a reliability SLA or another corpus benchmark. Cache/service behavior is exercised deterministically, separately from this live transport/parser smoke.

## Debug build

`flutter build apk --debug --no-pub` passed (exit 0, 253.75 s). Output: `build/app/outputs/flutter-apk/app-debug.apk`, **204,408,004 bytes (194.94 MiB)**. APK SHA-256: `600864e4718e08888a9dd6a52b114399b9b631638b4f13a4c78396eea5fbf7be`. Generated output is ignored and not published to Git; the root handoff APK was not replaced.

Embedded `assets/flutter_assets/assets/db/content.db` hashes to `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417`, exactly matching the protected input. No progress or lexical-cache runtime database is bundled. This is a debug build, not release-signing or physical-device validation.

Build warnings: `flutter_tts` applies Kotlin Gradle Plugin, which a future Flutter release will no longer support; installed SDK tools understand XML through v3 but encountered v4. Neither prevented this build. Dependencies/toolchain were not upgraded to suppress warnings.


## Protected integrity

All 14 protected files match the pre-master inventory: reports 00–09, `content.db`, both content markers and `pubspec.lock`. The database remains **24,387,584 bytes**.

| Artifact | SHA-256 before and after |
|---|---|
| assets/db/content.db | `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417` |
| assets/db/content.version | `3fc22e0ffec33e0a297546256fa7d2eed4815afd39da4e80f888cb57ecfaad9a` |
| lib/data/content_version.dart | `97caaaa95d35e3c3f8484451347d12fe68bf46bd4083bd8aa6aff6c6e8a3d8d6` |
| pubspec.lock | `b3819b55fa193d12665d185e6b00f5bc717b81e4e5fd7ac9ca9f7044a0c90fbf` |

The old rollback tag object remains `edb0da305152f116e67e99314f18bd1efed9acf1`, peeling to `583bb7631e7dacd994b874c3224eb518dd7a391c`. Fetch confirmed main/origin-main still at approved Step 09 `86b3b21f02c016990b0734431716bb8a84919cac` before final publication. No force push or approved-history rewrite is used.

Generated coverage, build output and lexical cache DB are ignored. Tracked-path and credential-signature checks found no APK, private signing key, local SDK properties, checkpoint, raw provider response or runtime cache staged. Existing ignored operational material remains local.

Historical report byte-identity manifest (same hash before/after):

| Report | SHA-256 |
|---|---|
| codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md | `7132f9501d6e1a1ab87cde206c3a89e28df1fac9fc27b8720648a0f3355b9b7b` |
| codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md | `fd0767a078866173ad64d63928dda6610249c7c3879994915828dfd1e8a1019f` |
| codex_reports/02_PERSISTENCE_CACHE_COMMIT_FIX.md | `04f9e38141648a6e13f48071c444c76bcedd03aa9001a6ca80c0e7fa5ef5f8b8` |
| codex_reports/03_COMPLETION_ATOMICITY_FIX.md | `9856713e19a4063368ca096ca8c3c19a7d36b50460c8b68dfce0c8557f05b27c` |
| codex_reports/04_FREE_QUIZ_ATOMICITY_FIX.md | `e5c8a5c93d5fbd2e1fc0304e9f446655fd79d4e511a71f7992cea96a6ad88afc` |
| codex_reports/05_SONG_STAR_STALE_WRITE_AUDIT_FIX.md | `d90ed3c0058def66ccb5845d5c9e29de2be9f8a7e6c23472d551d366f3f96a6f` |
| codex_reports/06_GIT_BASELINE_PUBLICATION.md | `8735e4c90f04e20981733ec3798e18abd317f2926347904ecdff4cc8ab0afebd` |
| codex_reports/07_API_FEASIBILITY_BENCHMARK.md | `316a7c84a90694f727c3bbd88284376ab106fe633878dc22ed134268ff42c02e` |
| codex_reports/08_CONTENT_ARCHITECTURE_DECISION.md | `4562be83f71eef5cda2327b8a009a88493f4d968dd4e95f99bd402aa656dca96` |
| codex_reports/09_STATION_FINALIZATION_ATOMICITY.md | `4bfc4e12f027f8e549d89d7dbef559a5c74abf68a0b4f9da248a34522356d674` |

## Limits and non-gating diagnostics

- Ten Python tests require Windows symbolic-link privilege unavailable here; exact runner skips are preserved in the validation output. Normal collision/hardlink/output-path tests execute.
- Physical Android TTS/voice availability, audio focus, WebView/YouTube and process power loss are not validated by desktop widget/SQLite tests. No release-signed build claim is made.
- Public provider availability/schema and untagged dictionary sense suitability remain external risks. Core learning has no dependency on them. Remote audio is intentionally deferred pending per-file license provenance.
- `dart format --output=none --set-exit-if-changed lib test` reports formatting differences (42/102 files at sweep time); no blind repository-wide formatting is applied. `dart fix --dry-run` identified one brace diagnostic, repaired explicitly; analyzer acceptance is independently required.
- Line coverage is a review aid, not exhaustive state-space proof. No claim of being bug free is made.

Individual skip verification reran `python -B -m unittest discover -s content/tools/tests -p 'test_output_paths.py' -v`: exit 0, 35 tests, 10 skips, 15.895 s. All ten are `test_output_paths.OutputPathTest.test_{cli,writer}_{dart_db,dart_marker,dart_source,marker_db,marker_source}_symlink` (the Cartesian product of the two modes and five cases). Every reason is `OSError, errno=22, winerror=1314: A required privilege is not held by the client`. No application failure is reclassified as an environmental skip.

Final `dart fix --dry-run` exited 0 with **Nothing to fix!** No automatic fixes were applied.

Default `git diff --check` flags preserved CRLF lines in report 10 and two song files as trailing whitespace. `git -c core.whitespace=cr-at-eol diff --check 86b3b21..HEAD` passes; no unrelated line-ending rewrite is introduced.

## Merge decision

**All specified merge gates pass; safe to fast-forward the validated completion branch under the approved workflow.** Analyzer, full tests, coverage, Python (documented environment-only skips), both content audits, debug build and offline validation pass. Twelve confirmed sweep defects are repaired. No secret/runtime artifact is staged; master handoff is included in the final documentation state.

Publication must use a normal branch push and main fast-forward, followed by annotated `stable-hybrid-enrichment-v1`; preserve the old rollback tag. Final local/remote/tag equality is checked after those operations and recorded in the final handoff. No remote CI success or physical-device acceptance is inferred from local validation.

