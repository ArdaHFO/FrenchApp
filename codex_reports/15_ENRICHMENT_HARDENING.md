# Phase 15 — Enrichment hardening and attribution

## Attribution and audio decision

`THIRD_PARTY_NOTICES.md`, About source list and lexical detail now distinguish service software from dictionary content, attribute Wiktionary contributors, retain source entry/retrieval time and state normalization/filtering. Detail shows CC BY-SA license URL. Corrected the obsolete notice saying the project lacked a source license: existing LICENSE is MIT, unchanged; this does not license external datasets.

Current primary sources inspected:

- [WiktApi project license](https://github.com/TheAlexLichter/wiktapi.dev/blob/main/LICENSE): MIT software.
- [WiktApi About](https://wiktapi.dev/about): Wiktionary → Kaikki provenance.
- [Kaikki license section](https://kaikki.org/dictionary/): Wiktionary-derived data, CC BY-SA/GFDL, upstream dump dates do not establish the service's loaded snapshot.
- [Wiktionary copyrights](https://en.wiktionary.org/wiki/Wiktionary:Copyrights) and [Wikimedia terms](https://foundation.wikimedia.org/wiki/Policy:Terms_of_Use): attribution/share-alike and separately credited material matter. Current CC BY-SA 4.0 link retained; exact snapshot/third-party rights are not assumed from software MIT.

**Remote pronunciation playback deferred.** Inspected pronunciation projection exposes IPA/audio filenames/tags without sufficient per-file author/license provenance. No media is downloaded/played by lexical enrichment. Existing TTS retained. Upstream quotation examples are normalized internally but not displayed; their separate rights and source metadata would need explicit treatment before enabling that UI. This is engineering attribution, not legal clearance. Existing bundled-data distribution caveats remain.

## Privacy / security review

Only an explicit lemma, fixed edition en/language fr and projection are sent to the fixed HTTPS provider host. User-Agent identifies application, not user. No progress, backup, identity, Turkish answer, game state, credentials or API key. URI path-segment tests cover accents/apostrophes/spaces/percent; URL/path syntax and long/control queries rejected. Redirects disabled, body/time bounded, no HTML execution, no telemetry. Source URL is a selectable string, not an automatically followed provider-controlled link. Local search typing causes no request. Online-only entries remain view-only.

## CI and validation

`.github/workflows/quality.yml` now runs `python -B -m unittest discover -s content/tools/tests -p "test_*.py"` in addition to existing validators/tests. No live-provider CI tests.

- Python exact command above: exit 0, **86 tests, 10 skipped**, 37.293 s. Skips are symlink creation unavailable on this Windows environment (test_output_paths link helper); expected output-plan collision diagnostics are negative-test evidence, not suite failure. Final validation will capture individual skip reasons explicitly.
- `flutter test test/lexical_detail_test.dart test/lexical_provider_test.dart test/lexical_cache_test.dart --no-pub`: exit 0, **51 passed**, no skips.
- `flutter analyze --fatal-infos --no-pub`: exit 0, no issues.
- `git diff --check`: clean. No failed Phase15 validation attempt.

## Files / limits

Four implementation files: quality workflow, third-party notices, About screen, lexical detail screen. Separate report follows `chore: harden lexical enrichment and attribution`. Historical reports/content/markers/lock/old rollback tag unchanged. No dependency upgrade, API-first learning, remote audio or corpus change. Comprehensive red-team sweep and final build/offline/live gates remain next; this phase does not declare release acceptance.
