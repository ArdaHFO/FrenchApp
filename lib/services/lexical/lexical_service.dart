import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'lexical_cache.dart';
import 'lexical_models.dart';
import 'wiktapi_provider.dart';

/// Lazy optional service: no provider/cache work is required at app startup.
class LexicalService implements LexicalProvider {
  LexicalService(
      {required LexicalProvider provider,
      required Future<LexicalCache> Function() openCache,
      DateTime Function()? clock})
      : _provider = provider,
        _openCache = openCache,
        _clock = clock ?? DateTime.now;
  factory LexicalService.production() => LexicalService(
      provider: WiktApiProvider(),
      openCache: () async {
        final directory = await getApplicationSupportDirectory();
        return LexicalCache.open(p.join(directory.path, 'lexical_cache.db'));
      });
  final LexicalProvider _provider;
  final Future<LexicalCache> Function() _openCache;
  final DateTime Function() _clock;
  Future<LexicalCache?>? _cache;
  final _flights = <String, Future<LexicalOutcome>>{};
  bool _closed = false;

  Future<LexicalCache?> _getCache() => _cache ??= (() async {
        try {
          return await _openCache();
        } catch (_) {
          return null;
        }
      })();

  @override
  Future<LexicalOutcome> lookup(LexicalLookupKey key) => lookupWithPolicy(key);

  Future<LexicalOutcome> lookupWithPolicy(LexicalLookupKey key,
      {bool refresh = false}) async {
    if (_closed || !key.valid) {
      return const LexicalOutcome(LexicalStatus.permanentFailure);
    }
    final cache = await _getCache();
    LexicalCacheEntry? entry;
    try {
      entry = await cache?.read(key, _clock());
    } catch (_) {/* optional cache unavailable */}
    if (_closed) return const LexicalOutcome(LexicalStatus.permanentFailure);
    final now = _clock();
    if (!refresh && entry != null && now.isBefore(entry.freshUntil)) {
      return entry.outcome.cached(isStale: false);
    }
    final usable = entry != null &&
        entry.outcome.status == LexicalStatus.found &&
        now.isBefore(entry.staleUntil);
    if (!refresh && usable) {
      unawaited(_fetch(key, cache)); // self-contained; never calls a widget.
      return entry.outcome.cached(isStale: true);
    }
    final result = await _fetch(key, cache);
    if (usable &&
        result.status != LexicalStatus.found &&
        result.status != LexicalStatus.notFound) {
      return entry.outcome.cached(isStale: true);
    }
    return result;
  }

  Future<LexicalOutcome> _fetch(LexicalLookupKey key, LexicalCache? cache) {
    final existing = _flights[key.cacheKey];
    if (existing != null) return existing;
    final future = (() async {
      LexicalOutcome result;
      try {
        result = await _provider.lookup(key);
      } catch (_) {
        result = const LexicalOutcome(LexicalStatus.transientFailure);
      }
      var unavailable = cache == null;
      try {
        await cache?.write(key, result, _clock());
      } catch (_) {
        unavailable = true;
      }
      if (!unavailable) return result;
      return LexicalOutcome(result.status,
          data: result.data,
          retryAt: result.retryAt,
          maxAge: result.maxAge,
          staleAge: result.staleAge,
          cacheable: result.cacheable,
          cacheUnavailable: true,
          pronunciationUnavailable: result.pronunciationUnavailable);
    })();
    _flights[key.cacheKey] = future;
    unawaited(future.then((_) => _flights.remove(key.cacheKey)));
    return future;
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_flights.values.toList());
    final cache = await _cache;
    await cache?.close();
  }
}
