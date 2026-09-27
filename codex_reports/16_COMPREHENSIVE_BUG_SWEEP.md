# 16 — Comprehensive software bug sweep

Date: 2026-09-27. Branch: `master-completion-hybrid-enrichment`. This is a software review, not a linguistic audit or a claim that the application is bug free. Historical reports 00–09 remain evidence snapshots.

## Scope and method

The sweep began after Phase 15, independently of the earlier green tests. Searches covered every production `unawaited`, timer, delayed callback, stream subscription, full-card save, progress write and cache publication. Actual call paths were traced through AppState, ProgressCoordinator, stores and UI callbacks. Real SQLite trigger failures, malformed imports, controlled provider transports, stale routes after restore and widget layout constraints supplied execution evidence. No corpus rebuild or external editorial operation was performed.

## Confirmed defect ledger

| ID / severity | Reproduction and old result | Small repair / regression | Commit |
|---|---|---|---|
| BUG-001 / P2 | Story node INSERT or late completion game write throws SQLite 1811; atomic durable state stays old but callback error escapes and no usable feedback appears. | `StoryAdventureScreen` guards node persistence, catches node/completion errors, retains selection and exposes the existing continuation button as persistence retry. Two real-widget/SQLite cases. | `6cf2247` |
| BUG-002 / P2 | Flag INSERT failure through the production WordCard callback is detached; no error UI. Multiple pending toggles can invert the requested retry. | `SwipeSessionScreen._toggleFlag` awaits, guards each pending ref, reports failure; cache remains governed by Step 02. Real SQLite regression checks retry toggles once. | `6cf2247` |
| BUG-003 / P2 | SongPlayer vocabulary sheet star INSERT failure escapes without retry feedback. | Both song sheets retain semantic `cards.star`, generation checks and local saved state; pending guard plus inline failure/retry. Actual SongPlayer widget test and both production-path assertions. | `6dfa4c3` |
| BUG-004 / P1/P2 | Level confirmation saves A2, then daily-goal INSERT fails: level durable/cache changes while goal remains old. Other preference futures fail without UI handling. | `confirmLearningSettings` writes level/goal/onboarding in one transaction, then publishes. Small context-scoped `runPreferenceAction` guards/catches companion, speed, motion and practice-level actions. Real settings widget/SQLite failure and retry tests. | `7fa5ad3` |
| BUG-005 / P2 | `SongQuizScreen` with a valid empty lyric collection indexes question 0 and throws RangeError. | Explicit empty state, no completion/reward. Current built-in song catalog is nonempty. | `6cf2247` |
| BUG-006 / P2 | `no-cache,max-age=86400` incorrectly becomes fresh; malformed HTTP-date Retry-After turns 429 into transient failure; no-store refresh leaves previous persistent entry. | Honor no-cache/must-revalidate, preserve rateLimited with conservative fallback, remove superseded no-store entry. Three deterministic protocol/cache tests. | `46630cd` |
| BUG-007 / P1 | Import accepts null TEXT primary key, duplicate primary key, boolean 9, or right > seen. SQLite can commit rows that later fail cache reload or silently replace an earlier row. | Validate required/null keys, duplicate identities, booleans and paired counters before deleting anything. Four real-SQLite import regressions; valid legacy backups remain supported. | `ef492d1` |
| BUG-008 / P2 | Injected AudioPlayer pause failure through actual song play button escapes as StateError without feedback. | Owned injectable player seam; guarded/caught pause/seek, caught asynchronous play, mounted callbacks and reported disposal errors. Retry succeeds without detached exception. | `e8f8875` |
| BUG-009 / P2 | Full phone smoke detects About attribution Row overflow by 237 pixels after Phase 15's longer license label. | Wrap source name/license; width and text-scale matrix. This was a new integration regression, not pre-existing baseline debt. | `45998ab` |
| BUG-010 / P2 | Real QuizEngine fixture lemma `an`, example `Il mange.` produces a cloze inside another word. | Unicode whole-word match for both eligibility and replacement; otherwise use existing translation question kinds. No invented example/form. | `fcfee81` |
| BUG-011 / P2 | Distinct local rows with lemma `tour` and different Turkish meanings yield four options but only three distinct French options. | Retain distractor tier order while requiring distinct meanings, lemmas and displays. Sparse pools keep existing skip behavior. | `fcfee81` |
| BUG-012 / P2 | Actual 320 px / 2.0 text-scale sentence layout overflows two horizontal rows by 64 and 154 px. | Wrap status pills and constrain the task heading with Expanded. Narrow sentence/song/story and nine actual About width/scale cases pass. | `4b9d529` |

P1 denotes material partial persistence/import integrity; P2 denotes recoverable incorrect UX or questions. IDs group coherent defects rather than count every assertion as a separate bug. Earlier Phase 10/11 repairs are recorded in their reports, not counted again here.

## Mutation and transaction inventory

| Surface | Production ownership and integrity boundary | Evidence |
|---|---|---|
| SRS swipe / free quiz | `AppState.recordAnswer`, `recordQuizAnswer`: transaction-time card read, card/daily/game writes on one executor; post-commit cache publication then reward. | Existing card/daily/game fault injection, same-card queue ordering, archived-card behavior and reopen tests. |
| Song star | `SqliteCardStateStore.star`: transaction-time current card, starred-only semantics, commit before publish. | Step 05 race/SQL/reopen tests; BUG-003 caller failure handling. No production generic card `.save` caller found. |
| Flags | `FlagStore.toggle`: persist then cache; AppState notification after store success. | INSERT/DELETE rollback and retry-direction tests; BUG-002 UI test. |
| Station | `completeStationQuiz`: journey, daily, two sequential game updates in one transaction; publish final caches before both reward events. `recordStation` retains its narrower safe standalone contract. | Step 09 failure/parity/close/restore/retry tests; Phase 11 attempt replay reset. |
| Story / sentence | AppState completion/attempt transaction includes practice, daily and game. Single captured event time shared internally. Node save is its own semantic action. | Step 03/D1 failures, Phase 10 retry, Phase 11 midnight tests, BUG-001 story recovery. |
| Song quiz / arena | One `recordActivity` transaction per intended action; no separate SRS update. | Phase 10 real widgets and failure/retry tests. Song combo remains total correct, intentionally. |
| Settings / companion | Individual `SettingsStore.set` commits before publish; compound onboarding/level confirmation now one transaction. | BUG-004 real failure/retry. Current explicit preferences are not old learning-session writes. |
| Restore | Coordinator barrier rejects new admission, drains accepted work, imports transactionally, prepares all replacement stores and publishes one generation; failed post-import reload blocks writes until recovery. | Existing before/during/after-import tests, nested admission/close tests and eight stale-route cases. |
| Lexical cache | Independent support-directory SQLite, atomic upsert/eviction; no progress table or backup membership. | Corruption, offline reopen, TTL, eviction, no-store, single-flight and close tests. |

No production direct `progress.insert/update/delete/execute/raw*` bypass was found by the focused search. Internal initialization/migration/backup SQL is distinct from screen mutations. Generic full-row `save` remains for fixtures and is documented against stale caller snapshots.

## Async, lifecycle and state-machine review

- `ProgressSession` captures generation once. Eight actual stale route interactions after restore cover sentence, song quiz, arena, station, story, free quiz, flags and song starring; earlier tests cover word/verb swipe callbacks and retained store handles. Full exported progress and cache/reward snapshots must remain unchanged.
- Quiz and placement reveal timers are canceled on disposal and check mounted state. Placement returns a suggested level, not SRS progress. Search/verb-table debounce timers are canceled/replaced and disposed; Phase 11 fixes search-clear resubmission.
- Persistence retries reuse prepared answer/evaluation rather than replay local scoring/haptics. Duplicate pending retries are gated. Story, flag and song-sheet recovery now follow the same failure principle without a broad UI abstraction.
- Song position/state/error subscriptions are canceled; callbacks check mounted. Audio commands now catch asynchronous failures. Physical Android audio focus/codec/voice behavior remains a platform validation limitation.
- Lexical view request identity rejects older/disposed results. Service single-flight and background refresh never retain widget callbacks; provider/cache failures become explicit outcomes or stale data. Close waits for accepted fetches. Cache-open failure degrades to nonpersistent enrichment for that service lifetime.
- Settings callbacks represent explicit current preference actions, even from a retained settings page. That is a documented semantic asymmetry, not an established stale-learning defect.

## Domain, search, data and backup boundaries

Scheduler invariant test executes 1,200 transitions across all six boxes and both starred states, checking box bounds, counters, lapses, due dates and archived quiz immutability. Existing queue tests cover cumulative persisted state. No scheduling constants changed.

Game tests cover quest/achievement rollback and one-time retry claims, first-completion/first-solve rewards, station pass replay and level thresholds. Station still publishes its two historical nonempty rewards in order after final cache publication. Song combo-as-correct-count and swipe-focused metrics are intentional asymmetries, not automatically bugs.

Journey alias/revision, best paired results, sparse verb pools, empty quiz pools and safety filtering retain existing tests. BUG-010/011 intentionally change only malformed question construction. A read-only Python screen of 3,419 non-review word/example rows found 453 whose first substring match differs from a whole-word match. This is **not** 453 proven bad questions: plural/inflection stem completions account for many. The confirmed `an`/`mange` test establishes the defect; the repair conservatively avoids partial-token clozes.

Local search still owns accent/Turkish-I/ligature normalization and deterministic ranking. One-character queries intentionally return no results. Existing word-search tests cover language direction and exact-vs-prefix ranking. Online keys bound input to 120 runes, encode path segments, reject URL/path/control input, and retain accents/apostrophes; provider requests never become SQL or arbitrary URL navigation.

Import validation covers JSON/version/required tables/unknown columns/types/box/status and the newly rejected inconsistent rows. Missing optional tables represent empty imported state, preserving the existing snapshot semantics. Alias-collision and post-import recovery tests remain in place. Power loss or an actual SQLite COMMIT I/O fault is not simulated by statement-trigger injection.

## Provider, cache and privacy

Deterministic tests cover 403/404/429/500/502/503, numeric/date/bad Retry-After, malformed JSON/UTF-8/schema, empty/ambiguous senses, optional pronunciation failure, accents/apostrophes/percent encoding, bounded body and timeout, loopback transport headers, cache corruption/schema mismatch, stale/expired/negative caching, ten concurrent same-key requests, eviction and disposal/out-of-order UI results.

No live provider is required by CI. Only the explicit French lemma goes to fixed WiktApi en/fr endpoints. No progress, user ID, Turkish answer, backup or game state is sent. Redirects are disabled; transport has an 8-second connection limit, 15-second total request limit and 256 KiB response bound. Raw payloads are discarded after normalization. No telemetry or API secret was added.

Tagged unsafe senses are omitted from the default enrichment panel. Untagged content cannot be linguistically certified by a parser; online results remain additional, view-only dictionary information. Local approved meanings never change. Remote audio remains deferred because per-file license provenance is insufficient; device TTS is retained.

## Tooling, resources and security review

Local word search uses a reusable normalized index and scans the local corpus; no measured performance regression was established. Provider work is lazy and never runs at startup or per keystroke. Cache retention is 500 entries, with bounded per-request bodies and no eager full-curriculum fetch. This is a resource-bound review, not a mobile latency benchmark.

Python validators open content read-only. `review_queue.py` output protection resolves paths and checks existing same-file/hardlink collisions before writes. Existing unit tests exercise publication/collision boundaries; Windows symlink privilege skips are recorded separately. No review job, corpus output or bundled DB was changed.

Tracked-text scan checks private-key headers, GitHub-token and AWS-access-ID signatures without logging values. No matching path was found. Tracked-file inspection excludes APKs, signing keys, local.properties, checkpoints, staging and build/cache files. This focused scan is not a guarantee that every conceivable secret format is detectable.

## Validation log and limitations

All earlier failing runs remain evidence, not hidden retries:

- Story/flag/empty-song red: four expected failures, then four green.
- Song-star red: one real player failure; attempted PopularSong widget also hit missing WebViewPlatform before persistence. That platform harness error is **not** bug evidence. Green player test plus both source paths cover the repair; actual YouTube/WebView behavior remains unvalidated here.
- Settings red: two real failures, then two green including retry.
- Backup/cache red: seven expected failures. First affected green run had 139 passes and one stale Step 05 source-shape assertion; updated assertion preserves generation/semantic checks around the new try block. Rerun: 140 passes.
- Stale-route run: seven passes plus story `pumpAndSettle` animation timeout. Bounded animation pumping fixes the harness, not production behavior. First replacement hit another identical line; second targeted correction fixes the intended stale case.
- Initial coverage: 285 passes, two failures (story harness and real About overflow). The latter became BUG-009.
- A concurrent Flutter media launch failed to replace the in-use generated sqlite3.dll. No source defect inferred; subsequent Flutter runs are sequential.
- Media/quiz red: three intended failures. Affected suites after repairs: 143 passed. Additional real-content provider-outage smoke: one passed. Media retry assertion rerun passed.
- Analyzer found one new missing-brace info in the distractor loop; fixed explicitly. `dart fix --dry-run` suggested that same one change, not blindly applied.
- `dart format --output=none --set-exit-if-changed lib test` exited 1: 42 of 102 files differ from formatter output. This non-mutating check reports repository style debt; unrelated mass formatting is deliberately excluded.

No final global-correctness claim is made. Device voice/media engines, WebView, process/power-loss COMMIT behavior, unscreened upstream linguistic content and future public-host changes remain validation/operational limits.

## Sweep acceptance results

| Exact command | Exit / result | Duration |
|---|---|---|
| `flutter analyze --fatal-infos --no-pub` | 0, no issues | 7.28 s |
| `flutter test --coverage --no-pub` | 0, 301 passed, no runner-reported skips | 317.05 s |
| `python -B -m unittest discover -s content/tools/tests -p "test_*.py"` | 0, 86 run, 10 environment skips | 52.25 s |
| `python -B content/tools/14_validate_db.py` | 0, passes | 0.36 s |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0, six revisions match | 0.16 s |
| `flutter test test/progress_consistency_test.dart --no-pub --name 'BUG-009\|Sweep narrow\|Step10 sentence'` | 0, 13 passed after BUG-012 | about 5 s |

The 301-test coverage run precedes the last three narrow-layout cases/BUG-012. The last repair has focused green evidence; Phase 17 reruns the full suite on the final source. The initial actual-width layout run was 11 passes/1 failure, then the expanded rerun was 13 passes. An initial About helper silently supplied its default phone width; the cases now explicitly apply real view constraints after that helper. No incorrect width coverage claim is carried forward.

Coverage from the successful sweep run: AppState 316/334 executable lines; repositories 652/671; ProgressCoordinator 42/43; backup 119/132; WiktApi provider 87/89; lexical service 42/47; lexical cache 56/56. These are line-execution counts, not branch completeness or proof of all fault modes. Review of uncovered paths did not establish another defect. Provider, cache and progress failure tests remain more important than the percentages.

Known benign logs include the test-only sqflite factory warning, unavailable platform TTS plugin, and expected Python negative-path collision diagnostics. Ten Python skips require Windows symlink privileges (`WinError 1314`); they are not silently counted as passing checks. Existing asset/content/progress test fixtures are used without dependency upgrades.

**Result: 12 confirmed bug IDs, 12 repaired.** No confirmed unresolved P0/P1/P2 software defect remains in the inspected scope. This conclusion is bounded by the listed platform, crash, linguistic and coverage limitations, not a guarantee against undiscovered defects. Core-source/content integrity and final merge eligibility are verified again in report 17 and the master handoff.
