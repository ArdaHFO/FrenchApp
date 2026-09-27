# Step 02 — Persistence before cache publication (D1)

Date: 2026-09-27. Repository: `FrenchApp`. Scope authority: the Step 02 request and `01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md`, read before editing. The previous reports were not modified.

## A. Scope

This repair addresses only the confirmed D1 / Pattern-B defect in `lib/data/repositories.dart`: failed SQLite persistence previously left authoritative flag, journey, or practice caches reflecting an operation that had not persisted.

The five affected methods now prepare their intended state without mutating the cache, await the existing SQL operation, then publish the prepared state. `FlagStore.toggle` has separate INSERT and DELETE branches, both protected. SQLite exceptions continue to propagate. No optimistic mutation/rollback mechanism was added.

No AppState caller adjustment was necessary. Coordinator admission, serialization, transaction boundaries, SQL schema and row fields, backup format, SRS, scoring, rewards, content, editorial state, and UI behavior were not redesigned. This is a store-publication guarantee, not action-level atomicity across subsequent daily/game writes.

## B. Pre-edit checkpoint

Before modifying either source or tests, exact original bytes were copied beneath `.checkpoints/chatgpt/step02_before/`:

| Original repository path | Checkpoint copy relative to `step02_before/` | Bytes | Pre-edit SHA-256 |
|---|---|---:|---|
| `lib/data/repositories.dart` | `lib/data/repositories.dart` | 45416 | `403963ee73ca5f20e2d0588babec66d0a7b189fc93d5a27d7ecf2855edad4af5` |
| `test/progress_consistency_test.dart` | `test/progress_consistency_test.dart` | 76381 | `0bf0d61f1812d3c376e9ae00bad0ecafd2b0de6966ddd65667615562d30fa6b5` |

`SHA256SUMS.txt` records each original path, SHA-256 and byte size. `initial_state.json` records the initial Git command outputs, index hash and a 664-file SHA-256 inventory. The inventory excludes `.git`, `build`, `.dart_tool`, `.gradle` and `__pycache__` path components; generated build/cache files were not checkpointed. Existing authored files, bundled data, previous reports and earlier checkpoint/delivery files were included in the inventory. Originals were copied, not moved.

Pre-edit Git observations:

- `git status --short`: exit 0; existing 12 `AM`, 3 `A ` and 2 `AD` entries, plus numerous untracked paths. Exact short and full-untracked status outputs are retained in `initial_state.json`.
- `git branch --show-current`: exit 0, `master`.
- `git rev-parse --verify HEAD`: exit 128, `fatal: Needed a single revision`. This remains an unborn branch, not a normal committed baseline.
- Git index SHA-256: `6a21249c9265d474b15a4e37ac924abac5bd443f7b781832f434b38059018bee`.
- Git status emitted an existing environment warning that the user-level `.config/git/ignore` could not be accessed (`Permission denied`). Repository status still completed successfully.

The modified source/test files were already untracked. Consequently Git status alone cannot show their byte changes. The checkpoint comparison is the authoritative repair diff. No staging, reset, cleanup or commit was performed.

## C. Pre-fix regression evidence

Six tests were added before changing production code. The production SHA-256 was rechecked against its checkpoint before running:

```text
flutter test test/progress_consistency_test.dart --no-pub --plain-name 'D1 '
```

Result: **exit 1; 0 passed, 6 failed; 31.423 seconds elapsed**. All six reached the expected cache assertion after confirming the SQLite exception and unchanged durable state. These were assertion failures, not harness/compilation failures. The old implementation was not temporarily reconstructed after the fix: this run occurred against the original production file.

All tests invoke the real production `AppState` operation and bound stores/coordinator, with real SQLite `BEFORE INSERT`/`BEFORE DELETE` triggers using `RAISE(ABORT, ...)`. Each exception must be a `DatabaseException` containing its unique injected marker. `INSERT OR REPLACE` store operations are intercepted by the INSERT trigger. No mock substitutes the failing SQL statement.

| Exact test name | Assertion that failed against old code | Durable DB state after failure | Old cache state after failure | Why it establishes D1 |
|---|---|---|---|---|
| `D1 A flag INSERT failure preserves cache and retry flags once` | Expected `isFlagged(ref) == false`; actual `true` (line 344) | `flagged_cards` empty | Flag present, despite absent row | `_flagged.add` executed before failed INSERT |
| `D1 B flag DELETE failure preserves cache and retry unflags` | Expected `isFlagged(ref) == true`; actual `false` (line 375) | Original flag row retained, including original values/timestamp | Flag absent | `_flagged.remove` executed before failed DELETE; retry would choose the opposite branch |
| `D1 C journey INSERT failure preserves first-pass retry reward` | Expected `resultFor(station) == null`; actual `StationResult` (line 407) | `journey_progress` empty | Three-star result present | `_results` was published before failed persistence and could suppress retry rewards |
| `D1 D sentence INSERT failure preserves first solve and attempt count` | Expected sentence progress `null`; actual `SentenceProgress` (line 457) | `sentence_progress` empty | `attempts=1`, `solved=true`, `bestScore=100` | Attempt and first-solve state were consumed in RAM only |
| `D1 E story completion INSERT failure preserves first-completion retry` | Expected `completed == false`; actual `true` (line 519) | Node A, incomplete, best pair `0/0` | Node B, complete, best pair `1/1` | Completion and first-completion state were consumed in RAM only |
| `D1 F story node INSERT failure retains node A until retry persists B` | Expected node `A`; actual `B` (line 575) | Original node A row retained | Node B | Resume location changed in cache without a successful write |

Before these failed assertions, each test also confirmed that `snapshot(app)` matched the pre-attempt snapshot. That helper includes durable and cached conjugation cards, today's daily statistics, game profile, quests, achievements, and published reward/serial. The affected flag/journey/practice tables and caches are checked explicitly because they are not part of this existing snapshot helper.

Machine-readable `FA006B_RESULT` output recorded the six divergent states above under `D1_A_failed_insert`, `D1_B_failed_delete`, `D1_C_failed_journey`, `D1_D_failed_sentence`, `D1_E_failed_story_completion`, and `D1_F_failed_story_node`. The raw log is in the OS temporary directory as `frenchapp-step02-prefixed.log` (the filename is retained exactly). Retry assertions follow the failing cache assertions, so retries were first reached in the passing post-fix run.

## D. Exact implementation changes

All references below are post-fix line numbers in `lib/data/repositories.dart`.

| Method / lines | Old ordering | New ordering | Preserved success semantics |
|---|---|---|---|
| `FlagStore.toggle`, 799–822 | Test branch by removing from `_flagged`; await DELETE. Otherwise add to `_flagged`; await INSERT | Test membership with `contains`; await DELETE; then remove. Otherwise await INSERT; then add | Same branch based on prior published state, same ref/type/lemma/reason/timestamp values, same `Future<void>` success and exception propagation |
| `JourneyStore.record`, 891–923 | Canonicalize, compute `StationResult.bestOf`, publish `_results`, await INSERT, return result | Canonicalize and compute unchanged; await INSERT; publish `_results`; return result | Same station canonicalization/aliases, best-result comparison, stars and paired best score, replace mode, timestamp and returned `StationResult` |
| `PracticeStore.saveStoryNode`, 1297–1317 | Prepare `StoryProgress`, publish `_stories`, await `_writeStory` | Prepare; await `_writeStory`; publish `_stories` | Same node/resume behavior; preserves old completion and paired best score; same default state and `Future<void>` |
| `PracticeStore.completeStory`, 1320–1342 | Compute `first`, `better`, `next`; publish `_stories`; await `_writeStory`; return `first` | Same computations; await `_writeStory`; publish `_stories`; return `first` | Same first-completion boolean, completion flag, node, ratio comparison and paired best score; failed writes no longer consume first-completion state |
| `PracticeStore.recordSentence`, 1359–1385 | Compute `firstSolve` and `next`; publish `_sentences`; await INSERT; return boolean | Same computations; await INSERT; publish `_sentences`; return boolean | Same attempt increment, solved OR, maximum best score and first-solve boolean; failure changes none of them |

Each method remains inside its existing `coordinate(() async { ... })` scope. No new coordinator layer, transaction or await in a caller was introduced. `_writeStory` itself is unchanged. Persist-first means successful completion of these existing database statements before map/set mutation; it does not merge later AppState operations into the same SQL transaction.

The production textual diff is seven additions and six deletions, principally moved assignments plus the flag membership check. No algorithm or constant changed.

## E. Added tests and preserved success contracts

All six tests reside in `test/progress_consistency_test.dart:324–584` (262 added lines, no existing lines deleted). They reuse existing fixture initialization, temporary databases, `snapshot`, `aligned`, and diagnostic output. `test/helpers/progress_probe.dart` is unchanged.

| Test | Production entry point / location | Failure and retry guarantees |
|---|---|---|
| A, lines 324–352 | `AppState.toggleFlag`, `lib/app/app_state.dart:564` → `FlagStore.toggle` | INSERT exception propagates; absent DB/cache remain absent; successful retry creates one flag row and cache entry; no unrelated progress changes |
| B, lines 354–383 | Same entry point | DELETE exception retains original row and cached flag; successful retry deletes it instead of inserting again; no retry-direction inversion |
| C, lines 385–429 | `AppState.recordStation`, `app_state.dart:371` → `JourneyStore.record` → existing game operation | Failed journey statement leaves no result and leaves game/daily/reward snapshot unchanged. Retry persists one `3-star, 8/8` result matching cache, grants `60 XP`, `24 coins`, one passed station and one reward publication. Repeating the successful result retains one row and grants no duplicate reward |
| D, lines 432–489 | `AppState.recordSentenceAttempt`, `app_state.dart:430` → `PracticeStore.recordSentence` → existing daily/game operations | Failed sentence statement creates no phantom attempt, solve or score and changes no later state. First successful retry records `attempts=1`, solved, score 100; receives `27 XP / 4 coins` and one correct quiz activity. A wrong attempt followed by another correct solution ends at attempts 3, still solved, best 100, `41 XP / 5 coins`, daily `3 total / 2 correct`: first-solve bonus occurs once |
| E, lines 491–552 | `AppState.completeStory`, `app_state.dart:407` → `PracticeStore.completeStory` → existing daily/game operations | Failed completion retains original node A/incomplete/best pair, with no later changes. Retry completes at B with best `1/1`, `52 XP / 9 coins`, daily `1/1`. Replaying at `1/2` preserves paired best `1/1`, ends at `66 XP / 10 coins`, daily `3/2`; no repeated first-completion bonus |
| F, lines 554–584 | `AppState.saveStoryNode`, `app_state.dart:402` → `PracticeStore.saveStoryNode` | Failed save retains node A in DB/cache; retry puts both at B while remaining incomplete, and does not alter reward/daily/card state |

The reward totals are assertions of existing behavior, not changed reward definitions. `aligned` checks game/profile, quest, achievement, card and nonempty daily DB/cache agreement after successful reward-bearing operations.

Existing tests also exercise direct store first-completion/first-solve return values and reloading (`practice_engine_test.dart`), journey canonical/legacy IDs and persisted best-result behavior (`journey_alias_test.dart`), legacy reward suppression and new-star rewards (`journey_revision_compatibility_test.dart`), and paired journey best-score selection (`critical_regressions_test.dart`). No normal-behavior test expectation was changed.

These six tests establish failure at the affected SQL statement and successful retry through production AppState paths. They do not inject failure into subsequent daily/game commits, exercise operating-system crash durability, or add widget error-recovery behavior. Those distinctions are intentional.

## F. Current validation results

Commands ran in the requested order, with the pre-fix run preceding production edits. Flutter used existing dependencies with `--no-pub`; no `pub get`, package upgrade or corpus rebuild was run. Existing external Flutter SDK cache access used the same approved execution approach as Step 01.

| Exact command | Exit | Result / tests | Elapsed wall time |
|---|---:|---|---:|
| `flutter test test/progress_consistency_test.dart --no-pub --plain-name 'D1 '` (pre-fix) | 1 | Expected red: 6 failures at cache assertions, 0 passes | 31.423 s |
| `flutter test test/progress_consistency_test.dart --no-pub` (post-fix) | 0 | 54 passed, including all 6 new tests | 31.584 s |
| `flutter test test/practice_engine_test.dart --no-pub` | 0 | 6 passed | 3.751 s |
| `flutter test test/journey_alias_test.dart --no-pub` | 0 | 5 passed | 4.091 s |
| `flutter test test/journey_revision_compatibility_test.dart --no-pub` | 0 | 5 passed | 16.302 s |
| `flutter analyze --fatal-infos --no-pub` | 0 | No issues found; analyzer reported 60.0 s | 62.187 s |
| `flutter test --no-pub` | 0 | 183 passed | 329.401 s |
| `python -B content/tools/14_validate_db.py` | 0 | Structural and learning-safety checks passed | 0.374 s |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0 | All 6 levels match their recorded revisions | 0.128 s |

No skipped tests were reported by any test run. All post-fix commands passed on their first execution; no failing post-fix run was omitted. Test counts are runner-reported totals, not counts inferred from source. Repeated execution of the six new tests inside the full suite is included in the 183 total, not an additional six tests.

The pre-fix, targeted and full-suite logs emit the existing sqflite warning about changing the default database factory during fixture cleanup. This is the single warning block bracketed by two `*** sqflite warning ***` lines in each log. Other focused logs and analysis reported no warnings. It was not treated as a test failure or suppressed.

The database validator reported 15,423 words, 17,858 examples, 2,698 verbs, 121,354 conjugations, 19 lessons, 10,259 `needs_review` entries and 18,075 aliases. `needs_review` is a reported content count, not a validation failure. The revision audit reported A1 `baae3aab002a`, A2 `2f642eb6a31b`, B1 `edb71326d5a4`, B2 `34914142868b`, C1 `c282dfc81ced`, C2 `af2f9bd1240a`, each with matching computed and recorded values; JSON `exit_code` was 0. Neither command rebuilt content.

Raw command logs are temporary OS files under `%TEMP%`, named `frenchapp-step02-prefixed.log`, `frenchapp-step02-targeted.log`, `frenchapp-step02-practice_engine_test.log`, `frenchapp-step02-journey_alias_test.log`, `frenchapp-step02-journey_revision_compatibility_test.log`, `frenchapp-step02-analyze.log`, `frenchapp-step02-full-test.log`, `frenchapp-step02-validate-db.log`, and `frenchapp-step02-journey-audit.log`. They are supporting transient evidence; the permanent results are recorded in this report.

## G. Before/after integrity

### Protected files

| Path | Bytes | SHA-256 before and after (identical) |
|---|---:|---|
| `assets/db/content.db` | 24387584 | `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417` |
| `assets/db/content.version` | 74 | `3fc22e0ffec33e0a297546256fa7d2eed4815afd39da4e80f888cb57ecfaad9a` |
| `lib/data/content_version.dart` | 213 | `97caaaa95d35e3c3f8484451347d12fe68bf46bd4083bd8aa6aff6c6e8a3d8d6` |
| `pubspec.lock` | 20279 | `b3819b55fa193d12665d185e6b00f5bc717b81e4e5fd7ac9ca9f7044a0c90fbf` |
| `codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md` | 127410 | `7132f9501d6e1a1ab87cde206c3a89e28df1fac9fc27b8720648a0f3355b9b7b` |
| `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md` | 83268 | `fd0767a078866173ad64d63928dda6610249c7c3879994915828dfd1e8a1019f` |

Git index SHA-256 before and after: `6a21249c9265d474b15a4e37ac924abac5bd443f7b781832f434b38059018bee` (identical).

### Intended byte changes

| Path | Before SHA-256 | After SHA-256 | After bytes |
|---|---|---|---:|
| `lib/data/repositories.dart` | `403963ee73ca5f20e2d0588babec66d0a7b189fc93d5a27d7ecf2855edad4af5` | `83d387b241a10cadc4c9d144a85c52f3442e28432e7ebcaafae8c4e4677a6261` | 45448 |
| `test/progress_consistency_test.dart` | `0bf0d61f1812d3c376e9ae00bad0ecafd2b0de6966ddd65667615562d30fa6b5` | `da77dbb6ede2d60298b91fbaedc8e63266b364245413c811e92d13a39f481c11` | 87908 |

The checkpoint copies were rehashed and match the pre-edit manifest and baseline. `test/helpers/progress_probe.dart`, `lib/app/app_state.dart`, and `lib/data/progress_coordinator.dart` remain byte-identical.

Final comparison after all validation commands:

| Check | Result |
|---|---|
| Baseline file inventory | Of 664 original files, only `lib/data/repositories.dart` and `test/progress_consistency_test.dart` changed; the other 662 match their original SHA-256 |
| Missing original files | None |
| Added files outside excluded build/cache directories | Exactly the four Step 02 checkpoint files plus this report, listed in section I |
| Unexpected authored/source/content changes | None |
| `git status --short` | Exit 0; stdout byte-for-byte equivalent as captured text to initial output. Existing directory-level untracked entries already conceal the new nested files |
| Full-untracked porcelain comparison | Exactly five added `??` entries: the four checkpoint files and this report. No removed or otherwise changed status entries |
| Git index | Byte-identical SHA-256; staging state preserved |
| Branch / HEAD | `master`, branch query exit 0; HEAD verification still exit 128, `fatal: Needed a single revision` |
| Protected content, lockfile, earlier reports | All byte-identical, hashes above |

The 17 pre-existing tracked status entries, all prior untracked work, earlier checkpoints, content/editorial artifacts and deliveries were preserved. The only new permanent files are the authorized checkpoint and report. Flutter test/analyzer runtime outputs may occupy their existing generated `build`/`.dart_tool` caches; those caches were deliberately excluded from authored-file hashing and were neither cleaned nor checkpointed. Diagnostic logs and SQLite fixture databases use OS temporary storage. No new package resolution, dependency installation, APK replacement or intentional generated-content modification was performed.

## H. Remaining known findings

The following findings remain unresolved and outside this repair:

- **D2 — multi-commit completion/reward atomicity:** station/story/sentence actions still span separate store commits. A successful completion followed by a later game/daily failure is not repaired here.
- **D3 — free quiz detached persistence:** card save and activity submission remain independent and are not awaited before advancement.
- **D4 — failure UI latching:** the audited screen-local failure states are unchanged. Propagating a store exception does not itself reset those screens.
- **Caller-prepared full-card stale-write risk:** quiz/song full-row writes and stale snapshots are unchanged.
- **No normal authoritative HEAD:** the repository remains on unborn `master` unless separately changed by the user. This task created no commit and relies on the exact pre-edit checkpoint for its comparison.

The passing tests support only the repaired store-publication invariant and the existing tested success behavior. They do not establish that the entire application is free of persistence or UI defects.

## I. Intentional file changes

| Repository path | Change / purpose |
|---|---|
| `lib/data/repositories.dart` | Minimal D1 publication-order repair in the five named methods |
| `test/progress_consistency_test.dart` | Six SQLite failure/retry regression tests |
| `.checkpoints/chatgpt/step02_before/lib/data/repositories.dart` | Exact original production file |
| `.checkpoints/chatgpt/step02_before/test/progress_consistency_test.dart` | Exact original test file |
| `.checkpoints/chatgpt/step02_before/SHA256SUMS.txt` | Original paths, byte sizes and SHA-256 manifest |
| `.checkpoints/chatgpt/step02_before/initial_state.json` | Initial Git/index observations and broad file-hash baseline |
| `codex_reports/02_PERSISTENCE_CACHE_COMMIT_FIX.md` | This repair report and evidence |

Previous reports remain at `codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md` and `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md`. Neither was moved or edited. No other authored source/test/content file is intentionally changed.
