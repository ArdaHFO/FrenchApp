import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'content_version.dart';

/// İki veritabanını açar.
///
/// `content.db` uygulamayla gelir, salt okunurdur ve içerik güncellemesinde
/// değiştirilir. `progress.db` cihazda oluşur ve kullanıcının ilerlemesini
/// tutar. Ayrı olmalarının sebebi: içerik güncellenince ilerleme silinmesin.
class AppDatabase {
  AppDatabase._(this.content, this.progress);

  final Database content;
  final Database progress;

  static const String _assetPath = 'assets/db/content.db';
  static const int progressSchemaVersion = 1;

  static Future<AppDatabase> open() async {
    final Directory dir = await getApplicationSupportDirectory();
    final String contentPath = p.join(dir.path, 'content.db');
    await _ensureContentCopied(contentPath);

    Database? content;
    Database? progress;
    try {
      content = await openDatabase(contentPath, readOnly: true);
      progress = await openDatabase(
        p.join(dir.path, 'progress.db'),
        version: progressSchemaVersion,
        onCreate: _createProgress,
      );
      await _ensureExtraTables(progress);
      await _migrateContentIds(content, progress);
      return AppDatabase._(content, progress);
    } catch (_) {
      if (progress != null) await progress.close();
      if (content != null) await content.close();
      rethrow;
    }
  }

  /// Eski içerik kimlikleri taşıyan bir yedek geri yüklendiğinde ilerlemeyi
  /// uygulamayı yeniden başlatmadan güncel kimliklere taşır.
  Future<void> migrateContentIds() => _migrateContentIds(content, progress);

  /// Varlık içindeki veritabanını cihaza kopyalar.
  ///
  /// Zaten kopyalanmışsa ve sürümü aynıysa dokunmaz. Sürüm farklıysa
  /// üzerine yazar; `progress.db` ayrı dosya olduğu için etkilenmez.
  static Future<void> _ensureContentCopied(String target) async {
    final File file = File(target);
    final File marker = File('$target.version');
    const String packagedVersion = kContentVersion;

    if (await file.exists() && await marker.exists()) {
      final bool sameVersion =
          (await marker.readAsString()).trim() == packagedVersion;
      final bool sameLength = await file.length() == kContentLength;
      if (sameVersion && sameLength) return;
    }

    final ByteData asset = await rootBundle.load(_assetPath);
    final Uint8List assetBytes =
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    await file.parent.create(recursive: true);
    final File staged = File('$target.tmp');
    final File backup = File('$target.old');
    if (await staged.exists()) await staged.delete();
    if (await backup.exists()) await backup.delete();
    await staged.writeAsBytes(assetBytes, flush: true);

    if (await file.exists()) await file.rename(backup.path);
    try {
      await staged.rename(target);
      await marker.writeAsString(packagedVersion, flush: true);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await backup.exists()) await backup.rename(target);
      if (await staged.exists()) await staged.delete();
      rethrow;
    }
  }

  /// Sonradan eklenen tablolar. Sürüm yükseltmesi yerine IF NOT EXISTS
  /// kullanılıyor: hem yeni kurulumda hem mevcut veritabanında çalışır,
  /// göç kodu yazmaya gerek kalmaz.
  static Future<void> _ensureExtraTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flagged_cards (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        card_type  TEXT NOT NULL,
        ref_id     TEXT NOT NULL,
        lemma      TEXT,
        reason     TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_flag_ref ON flagged_cards(ref_id)',
    );

    // Harita ilerlemesi. Duraklar icerikten uretildigi icin burada
    // yalnizca SONUC saklanir; durak tanimi degisse bile kimlik ayni
    // kaldigi surece ilerleme korunur.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS journey_progress (
        station_id   TEXT PRIMARY KEY,
        stars        INTEGER NOT NULL DEFAULT 0,
        best_correct INTEGER NOT NULL DEFAULT 0,
        best_total   INTEGER NOT NULL DEFAULT 0,
        updated_at   INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS game_profile (
        id              INTEGER PRIMARY KEY CHECK (id = 1),
        xp              INTEGER NOT NULL DEFAULT 0,
        coins           INTEGER NOT NULL DEFAULT 0,
        best_combo      INTEGER NOT NULL DEFAULT 0,
        total_cards     INTEGER NOT NULL DEFAULT 0,
        total_verbs     INTEGER NOT NULL DEFAULT 0,
        total_correct   INTEGER NOT NULL DEFAULT 0,
        total_answers   INTEGER NOT NULL DEFAULT 0,
        stations_passed INTEGER NOT NULL DEFAULT 0,
        updated_at      INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS daily_quests (
        day          TEXT NOT NULL,
        quest_id     TEXT NOT NULL,
        kind         TEXT NOT NULL,
        target       INTEGER NOT NULL,
        progress     INTEGER NOT NULL DEFAULT 0,
        reward_xp    INTEGER NOT NULL,
        reward_coins INTEGER NOT NULL,
        claimed      INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (day, quest_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS achievements (
        achievement_id TEXT PRIMARY KEY,
        unlocked_at    INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS story_progress (
        story_id    TEXT PRIMARY KEY,
        node_id     TEXT NOT NULL,
        completed   INTEGER NOT NULL DEFAULT 0,
        best_correct INTEGER NOT NULL DEFAULT 0,
        best_total  INTEGER NOT NULL DEFAULT 0,
        updated_at  INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sentence_progress (
        prompt_id   TEXT PRIMARY KEY,
        attempts    INTEGER NOT NULL DEFAULT 0,
        solved      INTEGER NOT NULL DEFAULT 0,
        best_score  INTEGER NOT NULL DEFAULT 0,
        updated_at  INTEGER NOT NULL
      )
    ''');
  }

  /// Content v1 used order-dependent ids. Content v2 carries aliases from
  /// those ids to deterministic ids, so an update cannot attach progress to
  /// a different word or verb. This is intentionally idempotent: an old
  /// backup imported later is migrated at the next launch as well.
  static Future<void> _migrateContentIds(
    Database content,
    Database progress,
  ) async {
    final List<Map<String, Object?>> tables = await content.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='content_aliases'",
    );
    if (tables.isEmpty) return;

    final List<Map<String, Object?>> rows = await content.query(
      'content_aliases',
      columns: <String>['alias_id', 'canonical_id', 'kind'],
    );
    if (rows.isEmpty) return;
    final Map<String, String> wordAliases = <String, String>{};
    final Map<String, String> verbAliases = <String, String>{};
    for (final Map<String, Object?> row in rows) {
      final String alias = row['alias_id']! as String;
      final String canonical = row['canonical_id']! as String;
      if (row['kind'] == 'verb') {
        verbAliases[alias] = canonical;
      } else {
        wordAliases[alias] = canonical;
      }
    }

    String migrateRef(String refId, String cardType) {
      if (cardType == 'word') return wordAliases[refId] ?? refId;
      final int colon = refId.indexOf(':');
      final String verbId = colon < 0 ? refId : refId.substring(0, colon);
      final String? replacement = verbAliases[verbId];
      if (replacement == null) return refId;
      return colon < 0 ? replacement : '$replacement${refId.substring(colon)}';
    }

    await progress.transaction((Transaction txn) async {
      final List<Map<String, Object?>> cards = await txn.query('card_state');
      final Map<String, Map<String, Object?>> winners =
          <String, Map<String, Object?>>{};
      final Set<String> affected = <String>{};
      for (final Map<String, Object?> card in cards) {
        final String type = card['card_type']! as String;
        final String oldRef = card['ref_id']! as String;
        final String newRef = migrateRef(oldRef, type);
        final String key = '$type\u0000$newRef';
        final Map<String, Object?>? current = winners[key];
        if (current == null ||
            (card['updated_at']! as int) > (current['updated_at']! as int)) {
          winners[key] = <String, Object?>{...card, 'ref_id': newRef};
        }
        if (newRef == oldRef) continue;
        affected.add(key);
        await txn.delete(
          'card_state',
          where: 'card_type = ? AND ref_id = ?',
          whereArgs: <Object?>[type, oldRef],
        );
      }
      for (final String key in affected) {
        await txn.insert(
          'card_state',
          winners[key]!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final List<Map<String, Object?>> flags = await txn.query('flagged_cards');
      for (final Map<String, Object?> flag in flags) {
        final String type = flag['card_type']! as String;
        final String oldRef = flag['ref_id']! as String;
        final String newRef = migrateRef(oldRef, type);
        if (newRef == oldRef) continue;
        await txn.update(
          'flagged_cards',
          <String, Object?>{'ref_id': newRef},
          where: 'id = ?',
          whereArgs: <Object?>[flag['id']],
        );
      }
    });
  }

  static Future<void> _createProgress(Database db, int version) async {
    await db.execute('''
      CREATE TABLE card_state (
        card_type    TEXT NOT NULL,
        ref_id       TEXT NOT NULL,
        box          INTEGER NOT NULL DEFAULT 0,
        status       TEXT NOT NULL DEFAULT 'fresh',
        starred      INTEGER NOT NULL DEFAULT 0,
        due_at       INTEGER,
        last_seen_at INTEGER,
        times_seen   INTEGER NOT NULL DEFAULT 0,
        times_right  INTEGER NOT NULL DEFAULT 0,
        lapses       INTEGER NOT NULL DEFAULT 0,
        updated_at   INTEGER NOT NULL,
        PRIMARY KEY (card_type, ref_id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_card_due ON card_state(card_type, due_at)',
    );
    await db.execute('''
      CREATE TABLE daily_stats (
        day           TEXT PRIMARY KEY,
        cards_swiped  INTEGER NOT NULL DEFAULT 0,
        new_learned   INTEGER NOT NULL DEFAULT 0,
        quiz_total    INTEGER NOT NULL DEFAULT 0,
        quiz_correct  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
  }

  Future<Map<String, String>> meta() async {
    final List<Map<String, Object?>> rows =
        await content.query('meta', columns: <String>['key', 'value']);
    return <String, String>{
      for (final Map<String, Object?> r in rows)
        r['key']! as String: r['value']! as String,
    };
  }

  Future<void> close() async {
    await content.close();
    await progress.close();
  }
}
