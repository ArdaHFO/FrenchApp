# Phase 10 ? Persistence recovery UI

## Scope and result

SentencePracticeScreen, SongQuizScreen and ReflexiveArenaScreen now recover from persistence errors without replaying answer evaluation or consuming session counters twice. Existing atomic AppState actions and station behavior are unchanged. Implementation `db8d23dd8fc9e26e1c825db25a5b7950416f7055` on `master-completion-hybrid-enrichment`, based on approved Step09 `86b3b21f02c016990b0734431716bb8a84919cac`. Step09 was fast-forwarded to main and remotely verified before this branch was created.

## Red-first evidence

Three actual-widget, real-SQLite tests in `test/progress_consistency_test.dart`:

- `Step10 sentence persistence failure retains attempt and retries once`
- `Step10 song persistence failure retains attempt and retries once`
- `Step10 arena persistence failure retains attempt and retries once`

`flutter test test/progress_consistency_test.dart --no-pub --plain-name Step10` first exited 1 with all three failures. A BEFORE UPDATE trigger on game_profile raised SQLite 1811 (`Step10_sentence`, `Step10_song`, `Step10_arena`). All durable/cache/reward snapshots remained unchanged, but exceptions escaped the UI and persistence retry controls were absent. This reached the production transaction, not a mock/harness failure. After repair the identical focused command exited 0, 3 passed; no unhandled Flutter exception remained.

## Exact changes and state machine

- `lib/features/practice/sentence_practice_screen.dart`: `_check` prepares immutable evaluation/prospective counters; `_saveEvaluation` commits counters only after persistence. Failure retains evaluation and pending attempt. `sentence_save_retry` resubmits that attempt without evaluation/haptic. Pedagogical retry/next is disabled until saved.
- `lib/features/songs/song_quiz_screen.dart`: `_next` catches save failure, clears recording, preserves completed answers/selection, exposes `song_quiz_save_retry`. Historical combo equals correct count. No re-answering.
- `lib/features/verbs/reflexive_arena_screen.dart`: `_answer` prepares counters and haptic once; `_saveAnswer` persists, then publishes local counters and starts the existing reveal delay. Failure retains feedback and old counters; `arena_save_retry` persists only.

All three guard pending duplicate submission and mounted/progress generation before applying success. Failure message is `Sonu? kaydedilemedi. Tekrar deneyin.` No reward or scheduling constants changed.

## Regression assertions

Each test compares all progress tables, caches and published reward before/after injected failure, waits beyond reveal duration, then gates a double-tapped retry. Exactly one transaction commits, quiz activity/correct count/best combo are one, reward serial is one, sentence attempts is one where applicable. Arena advances once. Tests use the existing progress probe and SQLite factory, with no new persistence framework.

## Validation

| Command | Result | Duration |
|---|---|---|
| `flutter test test/practice_engine_test.dart test/song_feature_test.dart test/verb_pool_test.dart test/game_progression_test.dart --no-pub` | 0 / PASS | 9.83 s |
| `flutter test test/progress_consistency_test.dart --no-pub` | 0 / PASS | 20.98 s |
| `flutter analyze --fatal-infos --no-pub` | 0 / PASS | 54.8 s |
| `flutter test --no-pub` | 0 / PASS | 291.12 s |
| `python -B content/tools/14_validate_db.py` | 0 / PASS | 0.25 s |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0 / PASS | 0.11 s |

Affected suite: 23 passed. Progress consistency: 81 passed. Full Flutter: **210 passed**, no reported skips. Analyzer: no issues. Content validator: structural/learning-safety PASS; Journey: six levels match. Existing sqflite default-factory warning is test setup, not a failure. No post-fix rerun was needed. A restricted read of temporary logs was denied; reading the same logs with authorized filesystem access succeeded and did not rerun tests.

## Integrity and remaining work

Broad SHA-256 comparison against pre-master tracked inventory identifies only: `lib/features/practice/sentence_practice_screen.dart`, `lib/features/songs/song_quiz_screen.dart`, `lib/features/verbs/reflexive_arena_screen.dart`, `test/progress_consistency_test.dart`. Reports 00?09, content DB/markers and lock remain byte-identical. No new checkpoint, dependency resolution, APK or corpus rebuild. Git index changes only reflect authorized commits.

Phase11 still needs event-time and replay/callback review. Provider/cache/UI work and comprehensive final sweep remain pending. This report establishes three recovery contracts, not global correctness. Raw validation logs remain in OS temporary storage.
