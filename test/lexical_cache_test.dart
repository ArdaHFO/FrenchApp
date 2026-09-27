import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/services/lexical/lexical_cache.dart';
import 'package:french_app/services/lexical/lexical_models.dart';
import 'package:french_app/services/lexical/lexical_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeProvider implements LexicalProvider {
  int calls = 0;
  FutureOr<LexicalOutcome> Function(LexicalLookupKey) respond = found;
  @override
  Future<LexicalOutcome> lookup(LexicalLookupKey key) async {
    calls++;
    return respond(key);
  }
}

LexicalOutcome found(LexicalLookupKey key) =>
    LexicalOutcome(LexicalStatus.found,
        data: LexicalEnrichment(
            word: key.lemma,
            senses: [
              LexicalSense(pos: 'noun', glosses: ['test'])
            ],
            pronunciations: [],
            provenance: LexicalProvenance(
                requestedLemma: key.lemma,
                responseUrl: key.endpoint('definitions').toString(),
                sourceUrl: 'https://en.wiktionary.org',
                retrievedAt: DateTime.utc(2026))));

void main() {
  sqfliteFfiInit();
  late Directory directory;
  late String path;
  late LexicalCache cache;
  late LexicalService service;
  late FakeProvider provider;
  late DateTime now;
  final key = LexicalLookupKey('chat');
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lexical-test-');
    path = '${directory.path}/lexical_cache.db';
    cache =
        await LexicalCache.open(path, factory: databaseFactoryFfi, capacity: 3);
    now = DateTime.utc(2026);
    provider = FakeProvider();
    service = LexicalService(
        provider: provider, openCache: () async => cache, clock: () => now);
  });
  tearDown(() async {
    await service.close();
    await cache.close();
    await directory.delete(recursive: true);
  });

  test('fresh normalized cache survives reopening without network', () async {
    expect((await service.lookup(key)).status, LexicalStatus.found);
    await service.close();
    cache = await LexicalCache.open(path, factory: databaseFactoryFfi);
    provider.respond = (_) => throw const SocketException('offline');
    service = LexicalService(
        provider: provider, openCache: () async => cache, clock: () => now);
    final result =
        await service.lookup(LexicalLookupKey(' CHAT ', expectedPos: 'verb'));
    expect(result.fromCache, isTrue);
    expect(result.data!.senses.single.pos, 'noun');
    expect(provider.calls, 1);
  });
  test('identical concurrent lookups single flight across POS hints', () async {
    final gate = Completer<LexicalOutcome>();
    provider.respond = (_) => gate.future;
    final requests = List.generate(10, (_) => service.lookup(key));
    while (provider.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(provider.calls, 1);
    gate.complete(found(key));
    expect(
        (await Future.wait(requests))
            .every((r) => r.status == LexicalStatus.found),
        isTrue);
    expect(provider.calls, 1);
  });
  test('stale data returns immediately and background refresh is shared',
      () async {
    await service.lookup(key);
    now = now.add(const Duration(days: 2));
    final gate = Completer<LexicalOutcome>();
    provider.respond = (_) => gate.future;
    final stale = await service.lookup(key);
    expect(stale.stale, isTrue);
    expect((await service.lookup(key)).stale, isTrue);
    expect(provider.calls, 2);
    gate.complete(const LexicalOutcome(LexicalStatus.transientFailure));
    await service.close();
    cache = await LexicalCache.open(path, factory: databaseFactoryFfi);
    expect((await cache.read(key, now))!.outcome.data!.word, 'chat');
  });
  test('explicit refresh failure retains usable stale entry', () async {
    await service.lookup(key);
    now = now.add(const Duration(days: 2));
    provider.respond = (_) => const LexicalOutcome(LexicalStatus.rateLimited);
    expect((await service.lookupWithPolicy(key, refresh: true)).stale, isTrue);
  });
  test('expired cache does not masquerade as fresh on outage', () async {
    await service.lookup(key);
    now = now.add(const Duration(days: 9));
    provider.respond =
        (_) => const LexicalOutcome(LexicalStatus.transientFailure);
    expect((await service.lookup(key)).status, LexicalStatus.transientFailure);
  });
  test('negative cache prevents repeated 404 and expires', () async {
    provider.respond = (_) => const LexicalOutcome(LexicalStatus.notFound,
        maxAge: Duration(hours: 4));
    await service.lookup(key);
    expect((await service.lookup(key)).fromCache, isTrue);
    expect(provider.calls, 1);
    now = now.add(const Duration(hours: 5));
    await service.lookup(key);
    expect(provider.calls, 2);
  });
  test('LRU bounds retention and preserves recently accessed/current entries',
      () async {
    for (final word in ['a', 'b', 'c']) {
      await service.lookup(LexicalLookupKey(word));
      now = now.add(const Duration(seconds: 1));
    }
    await service.lookup(LexicalLookupKey('a'));
    now = now.add(const Duration(seconds: 1));
    await service.lookup(LexicalLookupKey('d'));
    expect(await cache.read(LexicalLookupKey('b'), now), isNull);
    for (final word in ['a', 'c', 'd']) {
      expect(await cache.read(LexicalLookupKey(word), now), isNotNull);
    }
  });
  for (final corruption in [
    "payload = '{'",
    'schema_version = 999',
    "status = 'unexpected'"
  ]) {
    test('corrupt row is miss and safely replaced: $corruption', () async {
      await service.lookup(key);
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.execute('UPDATE lexical_entries SET $corruption');
      expect((await service.lookup(key)).status, LexicalStatus.found);
      expect(provider.calls, 2);
      expect((await cache.read(key, now))!.outcome.data!.word, 'chat');
    });
  }
  test('no-store and provider failures are not persisted', () async {
    provider.respond =
        (_) => const LexicalOutcome(LexicalStatus.notFound, cacheable: false);
    await service.lookup(key);
    expect(await cache.read(key, now), isNull);
    provider.respond = (_) => throw const SocketException('offline');
    expect((await service.lookup(key)).status, LexicalStatus.transientFailure);
    expect(await cache.read(key, now), isNull);
  });
  test('cache unavailable does not prevent online dictionary result', () async {
    await service.close();
    service = LexicalService(
        provider: provider,
        openCache: () async => throw const FileSystemException('denied'));
    final result = await service.lookup(key);
    expect(result.status, LexicalStatus.found);
    expect(result.cacheUnavailable, isTrue);
  });
  test('close drains background work and rejects new lookups', () async {
    final gate = Completer<LexicalOutcome>();
    provider.respond = (_) => gate.future;
    final request = service.lookup(key);
    while (provider.calls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    var closed = false;
    final closing = service.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    gate.complete(found(key));
    await request;
    await closing;
    expect((await service.lookup(key)).status, LexicalStatus.permanentFailure);
  });
}
