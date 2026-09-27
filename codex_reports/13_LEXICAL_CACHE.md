# Phase 13 — Persistent lexical cache

## Design

`LexicalCache` opens an independent `lexical_cache.db` in application support storage through lazy `LexicalService.production()`. No progress tables, migrations, backup exports or content DB changes. Runtime cache filename/sidecars are ignored by Git. Loss of this file loses only optional dictionary enrichment.

Key: provider / edition / language / normalization version / normalized requested lemma. Expected POS is not a key component: all grouped POS are retained and presentation can select them. Records contain normalized JSON, found/notFound status, fetched/fresh/stale/access timestamps, schema version, provenance and partial-pronunciation flag. No raw HTTP payload retention.

Positive fallback: 24 h fresh plus 7 d usable stale. Negative fallback: 4 h, no stale negative serving. Provider Cache-Control max-age/stale-while-revalidate values override defaults; no-store is not written. Errors are not negative-cached. Retention defaults to **500 entries**, last-access eviction after successful upsert within the same cache transaction, preserving current request. This is an entry bound, not an exact byte-size claim; normalized payload size varies.

Fresh lookup returns without HTTP. Usable stale lookup returns immediately and initiates shared background refresh; failed refresh retains existing data. Explicit refresh also falls back to still-usable stale data on transient/rate/schema failures. Expired data does not masquerade as fresh/offline guaranteed data. 404 replaces prior positive data only after a successful provider notFound result. Concurrent identical fetches share one future, including differing POS hints. Background operations never reference widgets or mutate curriculum.

Malformed cached JSON, unknown status/schema or identity mismatch is removed and treated as miss. Cache-open/read/write failure cannot prevent a usable online result; `cacheUnavailable` marks unavailable persistence. Close rejects new lookup and drains accepted fetches before closing DB. No eager whole-curriculum population.

## Tests

`test/lexical_cache_test.dart` adds **13 tests**, actual SQLite files in OS temporary storage:

- Fresh persistence across close/reopen while provider offline.
- Ten concurrent lookups use one provider request.
- Immediate stale return, shared background refresh and retained data after failure.
- Explicit refresh failure fallback; expired data failure.
- Negative cache expiry.
- Capacity/LRU behavior preserving recent/current entries.
- Corrupt JSON, schema and status replacement (three cases).
- No-store/failure not persisted.
- Unavailable cache preserves online result.
- Close drains pending request and rejects later work.

## Validation history

`flutter test test/lexical_cache_test.dart test/lexical_provider_test.dart --no-pub`: exit 0, **40 passed**, no skips, first run. `dart format` applied only lexical source/new test. Analyzer first exited 1 with four missing-brace infos; braces added without logic change. `flutter analyze --fatal-infos --no-pub` rerun exited 0, no issues. No production feature integration yet; no claim of tested dictionary UI in this phase.

## Changes and integrity

Implementation adds `lexical_cache.dart`, `lexical_service.dart`, `lexical_cache_test.dart` and narrow `.gitignore` runtime-cache rule. Separate report follows implementation commit (`git log --grep='feat: add persistent lexical enrichment cache'`). Existing dependencies, content/markers, progress behavior and historical reports unchanged. No live network in cache tests, no raw cache/test DB committed. Main and rollback tag unchanged.
