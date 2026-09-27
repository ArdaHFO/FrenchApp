# Phase 11 — Runtime edge cases

## Result and scope

Two actual widget regressions were reproduced and repaired: station full replay leaked the prior attempt's combo, and clearing dictionary search did not cancel a pending query. Practice actions now capture one local event time before coordinator admission and use it for practice timestamps, daily statistics and game/quest state. No global clock, reward changes or coordinator redesign.

## Evidence

`flutter test test/progress_consistency_test.dart --no-pub --plain-name Step11` initially exited 1, two failures:

- `Step11 full station replay starts a new combo`: two one-question attempts produced durable bestCombo=2; expected 1. Each attempt was individually correct. Full replay reset score/index but not combo/bestCombo.
- `Step11 clearing search cancels pending query`: clearing within the 140 ms debounce still displayed `essai` after 200 ms with an empty query. The timer retained the old query.

After fixes, the command exited 0 with four passing tests, including story/sentence event-time tests. These inject explicit local times 2026-09-26 23:59:59.999 and 2026-09-27 00:00:00, gate transaction execution, and verify daily/quest day, profile timestamp, practice timestamp and cumulative activity. Midnight disagreement in the old implementation is a source-established risk (independent clock reads), not a reproduced physical midnight race. The new optional `now` APIs enable deterministic validation.

## Exact changes

- `AppState.completeStory` / `recordSentenceAttempt`: optional event time captured before admission; all transaction writes use it. Existing commit then publish order unchanged.
- `PracticeStore.writeStory` / `writeSentence`: optional timestamp, standalone defaults unchanged.
- `StationQuizScreen`: full replay resets combo, best combo and wrong-feedback tick. Persistence-only retry does not reset any attempt data.
- `SearchScreen`: clear action cancels pending timer before empty search.
- `SqliteCardStateStore.save`: documentation warns against stale full-row UI snapshots. Production search found no card-store `.save` calls; remaining `.save` calls in lib are Canvas operations. Semantic star and quiz paths remain intact.

## Mutation and callback audit

| Surface | Current ownership / disposition |
|---|---|
| Word/verb answers and flags | Captured ProgressSession gate before mutation; flags' detached failure presentation remains a final-sweep target |
| Free quiz | Captured session gate before atomic answer; timer disposed/mounted guarded; no timer writes progress |
| Station | Captured session, one admission, retry payload; delayed continuation rechecks generation |
| Sentence / arena / song quiz | Captured session, Phase10 pending/retry guard and post-await generation check |
| Story | Captured session before node/completion writes; missing explicit persistence-error presentation and node duplicate guard remain final-sweep targets |
| Both song vocabulary sheets | Capture generation when sheet opens; allowProgress before semantic star; failure UI remains final-sweep target |
| Settings / companion | Current explicit preference actions through serialized AppState setters; old route is not inherently stale learning activity. No speculative generation binding added |
| Dictionary / verb-table debounce | Cancel on dispose and filter changes, mounted callback; dictionary clear defect fixed |
| Placement / animation timers | Mounted/dispose guarded; no durable writes in callback |
| Media | Player subscriptions/controllers disposed; playback failure and post-await interactions require final sweep, not assumed safe from source alone |

No confirmed stale-origin durable write bypass was found in this focused inspection. This is not exhaustive widget restore coverage; Phase16 must test retained routes and failure branches. Search included recordActivity, recordSentenceAttempt, completeStory, saveStoryNode, toggleFlag, star, Timer, Future.delayed, unawaited and generic save calls. Settings intent is an explicit asymmetry rather than a demonstrated defect.

## Validation

- Focused Step11: 4 passed, exit 0. Red run above retained as evidence.
- `flutter test test/progress_consistency_test.dart test/practice_engine_test.dart test/journey_alias_test.dart test/journey_revision_compatibility_test.dart test/game_progression_test.dart test/word_search_test.dart --no-pub`: exit 0, **108 passed**, 25.56 s; no skips reported. Existing sqflite test-factory warning.
- `flutter analyze --fatal-infos --no-pub`: exit 0, no issues, 6.11 s.

No failed post-fix attempt. Phase10 full suite (210) is historical relative to these edits; final full validation will include these four new tests. No corpus/dependency/build operation.

## Integrity and remaining boundaries

Only the five named source/test files changed in implementation; this report is separate. Reports 00–10 and bundled content/markers/lock are unchanged. Main remains the approved Step09 commit. No checkpoint or temporary artifact added. Process-crash/COMMIT-time injection, physical media/TTS and unresolved error-presentation cases remain for the final evidence-qualified sweep.

Implementation commit is the parent of this report commit (`git log --format='%H %s' --all --grep='fix: harden remaining runtime edge cases'`). The report does not attempt to embed its own self-referential hash.
