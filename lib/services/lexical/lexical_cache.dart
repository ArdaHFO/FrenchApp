import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'lexical_models.dart';

class LexicalCacheEntry {
  const LexicalCacheEntry(this.outcome, this.freshUntil, this.staleUntil);
  final LexicalOutcome outcome;
  final DateTime freshUntil, staleUntil;
}

/// Disposable provider data, never part of progress.db or progress backups.
class LexicalCache {
  LexicalCache._(this._db, this.capacity);
  static const defaultCapacity = 500;
  final Database _db;
  final int capacity;
  static Future<LexicalCache> open(String path,
      {DatabaseFactory? factory, int capacity = defaultCapacity}) async {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
    final db = await (factory ?? databaseFactory).openDatabase(path,
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('''CREATE TABLE lexical_entries (
        cache_key TEXT PRIMARY KEY, status TEXT NOT NULL, payload TEXT,
        fetched_at INTEGER NOT NULL, fresh_until INTEGER NOT NULL,
        stale_until INTEGER NOT NULL, last_accessed INTEGER NOT NULL,
        schema_version INTEGER NOT NULL, pronunciation_unavailable INTEGER NOT NULL
      )''');
              await db.execute(
                  'CREATE INDEX lexical_lru ON lexical_entries(last_accessed)');
            }));
    return LexicalCache._(db, capacity);
  }

  Future<LexicalCacheEntry?> read(LexicalLookupKey key, DateTime now) async {
    final rows = await _db.query('lexical_entries',
        where: 'cache_key = ?', whereArgs: [key.cacheKey]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    LexicalCacheEntry entry;
    try {
      if (row['schema_version'] != LexicalLookupKey.schemaVersion) {
        throw const FormatException('Cache schema');
      }
      final status = LexicalStatus.values.byName(row['status'] as String);
      if (status != LexicalStatus.found && status != LexicalStatus.notFound) {
        throw const FormatException('Cache status');
      }
      final data = status == LexicalStatus.found
          ? LexicalEnrichment.fromJson(
              jsonDecode(row['payload'] as String) as Map<String, dynamic>)
          : null;
      if (data != null &&
          LexicalLookupKey(data.provenance.requestedLemma).cacheKey !=
              key.cacheKey) {
        throw const FormatException('Cache identity');
      }
      entry = LexicalCacheEntry(
          LexicalOutcome(status,
              data: data,
              pronunciationUnavailable: row['pronunciation_unavailable'] == 1),
          DateTime.fromMillisecondsSinceEpoch(row['fresh_until'] as int),
          DateTime.fromMillisecondsSinceEpoch(row['stale_until'] as int));
    } catch (_) {
      await _db.delete('lexical_entries',
          where: 'cache_key = ?', whereArgs: [key.cacheKey]);
      return null;
    }
    await _db.update(
        'lexical_entries', {'last_accessed': now.millisecondsSinceEpoch},
        where: 'cache_key = ?', whereArgs: [key.cacheKey]);
    return entry;
  }

  Future<void> write(
      LexicalLookupKey key, LexicalOutcome outcome, DateTime now) async {
    if (!outcome.cacheable ||
        (outcome.status != LexicalStatus.found &&
            outcome.status != LexicalStatus.notFound)) {
      return;
    }
    final fresh = now.add(outcome.maxAge);
    final stale = outcome.status == LexicalStatus.notFound
        ? fresh
        : fresh.add(outcome.staleAge);
    await _db.transaction((txn) async {
      await txn.insert(
          'lexical_entries',
          {
            'cache_key': key.cacheKey,
            'status': outcome.status.name,
            'payload': outcome.data == null
                ? null
                : jsonEncode(outcome.data!.toJson()),
            'fetched_at': now.millisecondsSinceEpoch,
            'fresh_until': fresh.millisecondsSinceEpoch,
            'stale_until': stale.millisecondsSinceEpoch,
            'last_accessed': now.millisecondsSinceEpoch,
            'schema_version': LexicalLookupKey.schemaVersion,
            'pronunciation_unavailable':
                outcome.pronunciationUnavailable ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      // Keep current lookup, evict oldest others. Rows and LRU remain bounded.
      await txn.rawDelete('''DELETE FROM lexical_entries WHERE cache_key IN (
        SELECT cache_key FROM lexical_entries WHERE cache_key != ?
        ORDER BY last_accessed DESC, cache_key ASC LIMIT -1 OFFSET ?
      )''', [key.cacheKey, capacity - 1]);
    });
  }

  Future<void> close() => _db.close();
}
