# Step 05 - Song-star stale-write audit and repair

Date: 2026-09-27. Reports 01-04 supplied the scoped context and were inspected before production edits. Source, real-SQLite execution and widget evidence are distinguished below.

## A. Scope and conclusion

**Reproduced, at API level, before production edits.** Both song vocabulary callbacks prepared a full replacement card from a sheet-build cache snapshot. A canonical same-word `recordAnswer(dontKnow)` accepted first could commit, then be overwritten by that older song row while its daily/game effects remained committed.

A narrow production repair was made: `SqliteCardStateStore.star(refId)` reads the current committed row inside its own SQLite transaction, changes only `starred`, writes through that transaction, awaits the outer transaction future, then publishes the cache. Both song callbacks now pass only the word ID. No AppState, coordinator, scheduler, schema, reward, content or quiz implementation changed.

The guarantee is scoped to these song vocabulary saves: they preserve newer accepted SRS answers rather than writing caller-prepared full rows. This is not a claim of global persistence correctness.

## B. Production full-card save inventory

The audit searched all `lib/` for `.save(`, `cards.save`, `SrsCard(`, `copyWith(starred:`, `writeState`, `BoxScheduler.apply`, `applyQuizResult` and `card_state`. Exact production sites before and after:

| Classification | File/symbol and line region | Before | After |
|---|---|---|---|
| Song vocabulary starring | `lib/features/songs/popular_song_screen.dart`, `_showFocusWord`, 389-475; old save 456-457 | `app.cards.save(card!.copyWith(starred: true))` from the sheet builder snapshot | Line 456: `await app.cards.star(matchedWord.id)` |
| Song vocabulary starring | `lib/features/songs/song_player_screen.dart`, `_showWordSheet`, 546-660; old save 633-634 | Same full-row pattern | Line 633: same semantic star call |
| Free quiz; former legacy full-row caller | `lib/features/quiz/quiz_screen.dart`, `_answer`; `lib/app/app_state.dart`, `recordQuizAnswer`, 337-365 | Step 04 already removed full-row save from the widget | Unchanged; transaction-time `readState` and `applyQuizResult`, then `writeState(txn, ...)` at 351 |
| Canonical SRS | `lib/app/app_state.dart`, `recordAnswer`, 297-335 | Reads current state inside transaction, computes scheduler result and writes with the same executor, line 313 | Unchanged; no caller-prepared full-card save |
| Store API/implementation, not a production caller | `lib/data/repositories.dart`, `CardStateStore.save`, line 485; `SqliteCardStateStore.save`, 547-550 | Generic full-row API persists then publishes | Retained byte-for-byte; now has no production call sites |
| New semantic store mutation | `lib/data/repositories.dart`, `SqliteCardStateStore.star`, 552-562 | Absent | Current-row read and starred copy occur inside one transaction; internal `writeState(txn, ...)` at 557 |
| Other raw DB lifecycle writes | `lib/data/app_database.dart`, word/conjugation alias migration around 217-244; `lib/data/backup.dart`, table import loop | Migration/import operates on raw rows, not widget-prepared `SrsCard` snapshots | Unchanged; not a song-save caller or an additional discovered instance of this race |
| Unrelated `.save()` calls | `lib/ui/game_companion.dart` and `lib/motion/celebration.dart` | `Canvas.save()` drawing operations | Unchanged; not persistence |

There is no production conjugation-store `.save(...)` caller. `SrsCard` constructors elsewhere in `lib/` are model copying, row decoding or fresh-state synthesis; schedulers return immutable cards but do not persist them. The two AppState scheduler paths own transaction-time reads. Generic save remains used by test fixtures and is deliberately not removed.

## C. Pre-edit checkpoint

Checkpoint: `.checkpoints/chatgpt/step05_before/`. Exact originals, preserved before their first edit:

- `lib/data/repositories.dart`
- `lib/features/songs/popular_song_screen.dart`
- `lib/features/songs/song_player_screen.dart`
- `test/progress_consistency_test.dart`
- `test/learning_filter_test.dart`

`SHA256SUMS.txt` records original repository path, SHA-256 and byte size for all five. `initial_state.json` records a 681-file inventory (hash and byte size), initial short Git status, full untracked porcelain, branch, HEAD verification, Git stderr/exit codes and index hash. Inventory exclusions: `.git`, `build`, `.dart_tool`, `.gradle`, `__pycache__`; existing checkpoints/reports and other authored/assets files are included. The snapshot was collected before creating this checkpoint.

Branch was `master`; `git rev-parse --verify HEAD` exited 128 with `fatal: Needed a single revision`. The index is protected independently of the unborn HEAD. Existing status contains 17 tracked entries (12 AM, 3 A, 2 AD), plus pre-existing untracked work. Git status reports a permissions warning reading the user's external `.config/git/ignore`; output and warning are retained in the initial JSON. No index, stage or history operation was performed.

Hashes and final comparison are in section K.

## D. Existing song-star semantics

Both callbacks affect **word** cards via `app.cards`; neither affects conjugation cards. A token's folded French lemma is searched in the dictionary (limit 12), then matched by exact folded lemma. A missing dictionary match offers no save action. A matched word with no `card_state` row receives the synthesized default `SrsCard(refId: ...)` from `stateFor`.

Each modal captures `app.progressGeneration` at opening. Its StatefulBuilder reads a cached card and uses `card.starred` to disable the save button when already saved. On tap, `allowProgress(context, app, generation)` must pass before persistence admission. Previously the callback copied the captured card with `starred: true` and awaited `save`; it never toggled back to false.

On success, the old store wrote every card field using INSERT OR REPLACE, updated SQL `updated_at` with execution-time `DateTime.now()`, then published the cache. The widget called `app.notifyProgressChanged()`, then refreshed its mounted sheet. The saved label is `Kelime destene eklendi`; the unsaved action is `Kelime desteme ekle`.

The intended mutation does not recalculate `dueAt`, `lastSeenAt`, box, status, timesSeen, timesRight or lapses. Missing-row behavior is fresh, box 0, zero counters, null due/last-seen dates, starred true. No daily statistics, XP, coins, quests, achievements or reward publication belong to a star action. SQL updated-at is not an `SrsCard` cache field.

Neither callback adds a pending guard or catches persistence errors. The awaited exception prevents the subsequent notification/refresh. That existing error UX remains unchanged; this task does not repair song-quiz D4 or introduce a new starring policy. A repeated accepted star is still an idempotent true assignment, with the existing updated-at write behavior.

## E. Pre-fix stale schedule evidence

### Real production API sequence, not a song widget race

Test: `Step05 song star preserves the preceding committed same-word answer` (`test/progress_consistency_test.dart:260`). Before production edits it used the exact old persistence sequence shared by both callbacks:

```dart
final prepared = app.cards.stateFor(ref).copyWith(starred: true);
final saving = app.cards.save(prepared);
```

The test seeds `word-probe`, a real word in the synthetic content fixture, through the production card store. It accepts `AppState.recordAnswer(cardType: word, action: dontKnow)` first, uses the existing `ProbeDatabase.transactionGate` to pause before real SQLite transaction submission, prepares the song row from S0, and admits its bound-store save behind that answer. It releases the gate and awaits both futures. Neither the coordinator queue nor SQLite writes are mocked. The probe's gate does not hold a SQLite transaction or bypass its executor.

Definitive pre-fix command:

```text
flutter test test/progress_consistency_test.dart --plain-name 'Step05' --no-pub
```

Exit **1**, **0 passed / 1 failed**, **5.595 seconds**. The test reached real persistence and failed `expect(cardFields(actual), cardFields(expected))`: `Which: at location ['box'] is <3> instead of <0>`. There was no persistence exception; both writes succeeded. This is an assertion demonstrating lost progress, not a compilation/harness failure.

Observed exact fields (dates are epoch milliseconds):

| Field | Initial S0 | Canonical committed S1 | Prepared song row | Final DB and cache | Required final |
|---|---|---|---|---|---|
| box | 3 | 0 | 3 | 3 | 0 |
| status | known | fresh | known | known | fresh |
| starred | false | false | true | true | true |
| timesSeen | 9 | 10 | 9 | 9 | 10 |
| timesRight | 7 | 7 | 7 | 7 | 7 |
| lapses | 2 | 3 | 2 | 2 | 3 |
| dueAt | 1790985600000 | 1790526065938 | 1790985600000 | 1790985600000 | 1790526065938 |
| lastSeenAt | 1789862400000 | 1790526065938 | 1789862400000 | 1789862400000 | 1790526065938 |

The canonical action's other state survived: DB/cache daily `{cards_swiped:1,new_learned:0,quiz_total:0,quiz_correct:0}`; profile XP 4, coins 0, total_cards 1, other tested profile counters zero; cards quest progress 1, quiz/verbs quest progress 0, all unclaimed; achievement `first_card`; reward `{xp:4,coins:0,serial:1}`. Thus card and activity no longer described the same accepted answer.

Raw JSON: `%TEMP%/frenchapp-step05-red.log`, `FA006B_RESULT` scenario `Step05 song same-card ordering`. The old test sequence is recorded above; the final regression replaces its save with the semantic API. The retained diagnostic `prepared` value in the green test is only the stale comparison row and is never persisted.

Both callbacks had the same word-store, cache-copy, awaited-save and generation-check sequence. One real-API race establishes the shared store hazard; source inspection and the new path test establish that both callbacks have been migrated. No plugin/media-dependent save-button race was driven, and this report does not claim widget-level race evidence.

## F. Repair design

`SqliteCardStateStore.star(String refId)` is the minimum ownership change: both existing callbacks already use the bound concrete card store. Adding another AppState layer or a second transaction framework is unnecessary.

```text
sheet checks captured generation
  -> bound cardStore.star(wordId)
  -> existing coordinate admission / FIFO execution
  -> _db.transaction
       readState(txn, wordId)   [latest committed row, or fresh default]
       current.copyWith(starred: true)
       writeState(txn, starred, now: DateTime.now())
       return prepared card
     outer transaction completes successfully
  -> publish(card)
  -> return card
  -> existing AppState notification
  -> existing mounted sheet refresh
```

The transaction callback performs no cache publication. A SQL/transaction exception propagates before `publish`. The read and write receive the same actual transaction executor. All unrelated SRS fields come from the execution-time row, even if the modal captured an older card. Timestamp remains write-execution time; starring still does not reschedule anything.

The existing coordinator binding is used unchanged. A stale store reference rejects after generation rotation. The modal's separate generation check remains necessary because a stale sheet otherwise could access the new AppState store; that check is retained byte-for-byte.

## G. Exact implementation changes

| File/symbol | Change | Preserved behavior |
|---|---|---|
| `lib/data/repositories.dart:552-562`, `SqliteCardStateStore.star` | Add 12 lines: coordinated current-row read, starred copy and write in one transaction, post-commit publish, return card | Generic `save`, existing transaction helpers, row serialization, updated-at, generation admission and all D1/D2 code unchanged |
| `lib/features/songs/popular_song_screen.dart:456`, `_showFocusWord` | Replace two-line full-row save with `await app.cards.star(matchedWord.id)` | Dictionary matching, saved state, stale-sheet guard, await, AppState notification and mounted sheet refresh |
| `lib/features/songs/song_player_screen.dart:633`, `_showWordSheet` | Identical replacement | Same behavior; no media/player/quiz changes |
| `test/learning_filter_test.dart:338` | Existing song-save API coverage uses `star('blocked')` | The separate arbitrary missing-card seed still deliberately uses generic save; existing learning safety assertions retained |
| `test/progress_consistency_test.dart:260-390` | Add five focused tests | All preceding tests/helpers and existing D1/D2/D3 assertions retained |

No interface cleanup, optimistic cache mutation, broad notification change, dependency, schema or content modification is included.

## H. Regression tests

All five new tests live in the existing real-SQLite consistency harness; `test/helpers/progress_probe.dart` is unchanged.

1. **`Step05 song star preserves the preceding committed same-word answer`** - red-first test converted to the new semantic operation. Gates canonical `dontKnow`, admits star behind it, compares every SRS field in returned committed expectation, DB and cache, asserts one swipe/no quiz/no newLearned, XP 4/coins 0/totalCards 1/reward serial 1, then closes/reopens and verifies card and persisted activity reconstruction. All date/counter/status fields are compared, not only `starred`.
2. **`Step05 song star SQL failure preserves cache and retries after commit`** - first records a canonical answer; then a real trigger `BEFORE INSERT ON card_state WHEN NEW.starred = 1` raises `SONG_STAR_FAIL`. Verifies exception marker, unchanged full SQL rows (including updated-at), card cache, daily/game/quests/achievements and reward publication. Drops trigger and retries; exactly one successful transaction, one row and starred=true. The probe's after-real-commit/before-outer-future-return hook asserts the cache still holds the old state. After completion, cache matches DB and all activity is byte/value-equivalent to its prior snapshot.
3. **`Step05 song star creates a fresh unstarted word without activity`** - missing row becomes exactly `SrsCard(refId, starred:true)`, with box 0/fresh/null dates/zero counters; updated-at lies within the call interval. No activity/reward changes; close/reopen preserves it.
4. **`Step05 song star rejects a store from the previous progress generation`** - exports/restores the app's current progress, attempts star through the old bound store, expects `ProgressUnavailable` and unchanged DB/cache/activity, then demonstrates the current store can star successfully. This protects the new public mutation's admission behavior.
5. **`Step05 both song callbacks use guarded semantic starring`** - source-path test for both production files: semantic ID-only call, no `.save(` or starred full-row copy, generation guard before awaited call, notification afterward. This is explicitly source coverage, not widget interaction.

The existing learning-filter song API test is updated rather than duplicated. Existing song-feature tests exercise catalogs and screen rendering, not a real media-backed save race. The unchanged full-suite widget test `test/app_smoke_test.dart:1538`, `şarkı sahnesi açılır ve söz kelimesini desteye ekler`, also navigates to SongPlayerScreen, opens a lyric word, taps `save_song_word` and checks `Kelime destene eklendi`. It passed in this run. That provides actual normal-success callback coverage for SongPlayerScreen, but not a widget race/SQL-failure test or an equivalent PopularSongScreen save interaction. No network/media dependencies were added. Existing stale-store/restore tests remain intact; the new generation test supplements them for `star` specifically.

## I. Before/after semantic table

| Scenario | Old behavior | Required/new behavior |
|---|---|---|
| Earlier accepted same-card SRS answer | Song row derived from S0 can overwrite S1 while daily/game preserve the answer | Transaction reads S1 and persists S1 with starred=true; all other fields preserved, including through reopen |
| Normal existing-card star | Full cached row written, starred=true, updated-at refreshed | Latest committed row written, starred=true, same timestamp policy |
| SQL INSERT failure | Existing generic save already avoids publishing on its own failed statement | New transaction also leaves DB/cache/activity unchanged and propagates failure; retry succeeds |
| Missing card-state row | Default fresh starred card, zero exposures/activity | Same logical result, checked after reopen |
| Already starred | Saved button disabled; another already-admitted true assignment can still write updated-at | Same policy; operation never toggles or creates activity |
| Restore invalidates old store/sheet | Bound old store and explicit sheet-generation guard reject stale work | Preserved; new store API tested after generation rotation |
| UI success | Await, notify AppState, refresh mounted sheet | Same sequence after successful post-commit cache publication |
| UI persistence error | Propagated future, no success notification/refresh | Unchanged; no new generic error UX claimed |

## J. Validation results

All Flutter commands used the existing dependencies and `--no-pub`; SDK-cache access used the established external-cache execution permission. No pub get, upgrade, corpus/APK build or dependency-lock change was performed. Durations below are measured wall seconds.

| Exact command / attempt | Exit | Result | Seconds | Notes |
|---|---:|---|---:|---|
| `flutter test test/progress_consistency_test.dart --plain-name 'Step05' --no-pub` - definitive pre-fix | 1 | 0 passed, 1 expected assertion failure | 5.595 | Real stale overwrite; evidence in E |
| Same command - intermediate partial-edit attempt (`focused.log`) | 1 | 0 passed, 1 assertion failure | 5.795 | Test still called generic save because edit script stopped before converting tests; not evidence that the new star API failed |
| Same command - first completed new-test attempt (`focused2.log`) | 1 | Loader compilation failure; no tests executed | 46.556 | New generation test referenced local `backupB` before its declaration; changed only that new test to export/restore its own app state |
| Same command - corrected focused rerun (`focused3.log`) | 0 | 5 passed | 5.488 | Ordering, SQL failure/retry, fresh word, stale generation, both callback paths |
| `flutter test test/learning_filter_test.dart --no-pub` | 0 | 10 passed | 7.807 | Existing handled TTS plugin diagnostic |
| `flutter test test/song_feature_test.dart --no-pub` | 0 | 5 passed | 6.073 | First attempt passed |
| `flutter test test/progress_consistency_test.dart --no-pub` | 0 | 69 passed | 23.922 | First full-file attempt passed |
| `flutter analyze --fatal-infos --no-pub` | 0 | No issues found | 109.414 | Analyzer reports 106.4 seconds |
| `flutter test --no-pub` | 0 | 198 passed | 314.333 | First full-suite attempt passed; includes existing song-save widget smoke test |
| `python -B content/tools/14_validate_db.py` | 0 | Structural and learning-safety checks passed | 0.353 | First attempt; no warnings |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0 | All six levels match | 0.133 | First attempt; JSON exit_code=0 |

Skipped tests: zero reported in completed runs. The compilation failure is a loader failure, not an executed regression case. No test assertion was weakened to obtain green results.

The editing attempts are disclosed for completeness: an initial literal replacement expected CRLF where a song callback used LF and stopped after adding the store method; no validation command ran in that edit call. The next script changed both callbacks but stopped at the differently wrapped learning-filter call, so the following intermediate validation still ran the old generic-save regression and failed as before. The completed test edit then exposed the local-helper declaration error above. These are implementation/harness attempts, not extra pre-fix defect reproductions.

Warnings: the existing consistency-fixture cleanup emits one sqflite default-factory warning block bracketed by two `*** sqflite warning ***` markers in red/focused/consistency runs. The learning-filter suite logs a handled `MissingPluginException` for `getLanguages` on `flutter_tts` (`TTS hazirlanamadi` diagnostic); its ten tests still pass. No network/media setup was added to hide it. The full-suite log contains the same sqflite warning block and two handled flutter_tts missing-plugin diagnostics; no tests were skipped or failed. Content validation reports 15,423 words, 17,858 examples, 2,698 verbs, 121,354 conjugations, 19 lessons, 10,259 needs_review entries and 18,075 aliases (counts, not failures). Journey hashes match for A1 `baae3aab002a`, A2 `2f642eb6a31b`, B1 `edb71326d5a4`, B2 `34914142868b`, C1 `c282dfc81ced`, C2 `af2f9bd1240a`.

Raw logs are temporary OS files `%TEMP%/frenchapp-step05-{red,focused,focused2,focused3,learning,songs,consistency,analyze,full,validate-db,journey-audit}.log`. This report retains the permanent evidence and command outcomes. No failed test attempt or required rerun is omitted. A final evidence-summary script initially failed while printing Turkish diagnostic text through the Windows console encoding; it was rerun successfully with UTF-8 stdout before the final integrity comparison/report update. This was not a Flutter test or protected-file failure.

## K. Integrity preservation

### Protected artifacts

| Path | Bytes | SHA-256 before = after |
|---|---:|---|
| `assets/db/content.db` | 24387584 | `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417` |
| `assets/db/content.version` | 74 | `3fc22e0ffec33e0a297546256fa7d2eed4815afd39da4e80f888cb57ecfaad9a` |
| `lib/data/content_version.dart` | 213 | `97caaaa95d35e3c3f8484451347d12fe68bf46bd4083bd8aa6aff6c6e8a3d8d6` |
| `pubspec.lock` | 20279 | `b3819b55fa193d12665d185e6b00f5bc717b81e4e5fd7ac9ca9f7044a0c90fbf` |
| `codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md` | 127410 | `7132f9501d6e1a1ab87cde206c3a89e28df1fac9fc27b8720648a0f3355b9b7b` |
| `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md` | 83268 | `fd0767a078866173ad64d63928dda6610249c7c3879994915828dfd1e8a1019f` |
| `codex_reports/02_PERSISTENCE_CACHE_COMMIT_FIX.md` | 21232 | `04f9e38141648a6e13f48071c444c76bcedd03aa9001a6ca80c0e7fa5ef5f8b8` |
| `codex_reports/03_COMPLETION_ATOMICITY_FIX.md` | 30488 | `9856713e19a4063368ca096ca8c3c19a7d36b50460c8b68dfce0c8557f05b27c` |
| `codex_reports/04_FREE_QUIZ_ATOMICITY_FIX.md` | 28709 | `e5c8a5c93d5fbd2e1fc0304e9f446655fd79d4e511a71f7992cea96a6ad88afc` |

Git index before = after: `6a21249c9265d474b15a4e37ac924abac5bd443f7b781832f434b38059018bee`.

### Checkpointed files

| Path | Before SHA-256 (bytes) | After SHA-256 (bytes) |
|---|---|---|
| `lib/data/repositories.dart` | `6906193df69aaea8b4a22694d80010aa5b008f646508877c23ff27b247ad91ff` (48118) | `3c59dc621ae2e0606db248c03bd819a94f5b16848b3a780e1c0844c6624670d6` (48559) |
| `lib/features/songs/popular_song_screen.dart` | `4d1748357ec5a921dbda8b67808336d22075927ddb4fd466eb61b17f312b507b` (18381) | `4567a1b83fe153c08ac3ccd03269968c9523f8c5e1b974ea62fbc96a896692ed` (18331) |
| `lib/features/songs/song_player_screen.dart` | `aec0f200717be7de2a0d513929c2f64f326e9712645cc1412c8c71fc483d0b0d` (25197) | `4eb1dce2ef6a96fec79fcced0c59b4dbab102be8258ae021df6affc69e6ef123` (25147) |
| `test/progress_consistency_test.dart` | `c08912f31e295d76c6d1ffd88246f1442be33495049299330776381fe03e4781` (105553) | `70ee9627fea265ac5a21933810dc23cf916315b2147b107277c57e014c1d063d` (112234) |
| `test/learning_filter_test.dart` | `94f0b27278610381effbd75f45ffe3d56034db93291e6976c24875fd376a9e75` (17859) | `7bea74811924e93e87def35b9c676174d6c1b76b077eb72b36c9248adf19a63c` (17804) |

### Final repository comparison

Final 689-file inventory versus initial 681: exactly five existing files changed (the checkpointed files above), no removed/missing files, and exactly eight additions (seven checkpoint files plus this report, enumerated in N). The other 676 pre-existing files are byte-identical within the stated inventory scope. Every checkpoint copy matches its initial hash/size. AppState, QuizScreen, ProgressCoordinator, BoxScheduler, probe helper and previous reports remain byte-identical.

`git status --short` is identical before/after, because these edited/new paths are already under previously untracked directories. This is not used alone to claim integrity: full untracked porcelain differs only by the eight authorized additions, with no removed status entries; broad hashing detects exactly the intended five edits. Initial complete status is preserved in `initial_state.json`; final additions are exactly:

```text
?? .checkpoints/chatgpt/step05_before/SHA256SUMS.txt
?? .checkpoints/chatgpt/step05_before/initial_state.json
?? .checkpoints/chatgpt/step05_before/lib/data/repositories.dart
?? .checkpoints/chatgpt/step05_before/lib/features/songs/popular_song_screen.dart
?? .checkpoints/chatgpt/step05_before/lib/features/songs/song_player_screen.dart
?? .checkpoints/chatgpt/step05_before/test/learning_filter_test.dart
?? .checkpoints/chatgpt/step05_before/test/progress_consistency_test.dart
?? codex_reports/05_SONG_STAR_STALE_WRITE_AUDIT_FIX.md
```

Branch remains `master`; HEAD verification remains exit 128/unborn. Index hash is unchanged. No unexpected authored/content changes occurred. Flutter's ignored build/cache artifacts and OS temporary logs are outside the authored inventory; no generated artifact was intentionally promoted into source, content, reports 00-04 or a deliverable APK.

## L. Remaining production full-row callers

**No production caller-prepared full-card `.save(...)` path remains under `lib/` after this change.** Free quiz uses `recordQuizAnswer`; swipe uses `recordAnswer`; song callbacks use `star`. The full-row `save` API remains available for fixtures/legitimate callers and is not globally hardened against stale inputs. A future caller could recreate the hazard; this repair does not remove that API or claim it is safe for stale snapshots.

Production full-row SQL serialization remains in `writeState`, as required to persist complete rows, but each active runtime mutation prepares the row after a transaction-time read. Backup/import and database migration are separate raw-row lifecycle operations, outside this song repair.

## M. Remaining known findings

Unchanged and unresolved in this step:

- Station completion's later separate `recordActivity` sequencing question.
- D4 persistence-error UI latching in sentence/song-quiz/arena/station screens.
- Practice midnight timing.
- Non-swipe stale-widget/settings questions beyond the retained song guard and tested bound-store admission.
- Step 03 optional COMMIT-time fault-injection limitation: its experiment was inconclusive; this step proves statement-failure rollback and post-outer-commit publication, not injected COMMIT failure or process-crash durability.
- Unborn `master` Git HEAD; checkpoint remains the exact pre-edit reference.

Song stale-full-row overwrite is now reproduced and repaired at the scoped callbacks. No other production caller-prepared save was discovered in this audit. D1, D2 and Step 04 methods are not rewritten or weakened.

## N. Intentional file changes

Modified production: `lib/data/repositories.dart`, `lib/features/songs/popular_song_screen.dart`, `lib/features/songs/song_player_screen.dart`.

Modified tests: `test/progress_consistency_test.dart` (five new cases), `test/learning_filter_test.dart` (existing song semantic API call).

New checkpoint files: `.checkpoints/chatgpt/step05_before/SHA256SUMS.txt`, `initial_state.json`, and exact original copies at `lib/data/repositories.dart`, `lib/features/songs/popular_song_screen.dart`, `lib/features/songs/song_player_screen.dart`, `test/progress_consistency_test.dart`, `test/learning_filter_test.dart` beneath that checkpoint root.

New workflow report: `codex_reports/05_SONG_STAR_STALE_WRITE_AUDIT_FIX.md`. Reports 00-04 are untouched. Validation logs are temporary OS files, and Flutter may refresh ignored build/cache artifacts. No source outside the listed five files was intentionally modified. Text diff: repositories +12/-0; each song screen +1/-2; learning-filter test +1/-2; consistency tests +130/-0. Removing only the new Step05 block reconstructs the exact checkpoint bytes of the existing consistency suite.
