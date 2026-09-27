import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// İlerlemenin dışa/içe aktarımı.
///
/// Yedeklenen `progress.db`'dir; içerik veritabanı yedeklenmez çünkü
/// uygulamayla birlikte geliyor ve her kurulumda aynı. Yedek düz JSON:
/// bir dosya paylaşma paketi eklemeden panoya kopyalanabiliyor ve
/// gerektiğinde gözle okunabiliyor.
///
/// Kimlikler (`ref_id`, `station_id`) içerikten türediği için sürümler
/// arasında sabit; içerik güncellense de yedek tutmaya devam eder.
class ProgressBackup {
  ProgressBackup._();

  static const int formatVersion = 1;

  /// Yedeklenen tablolar. `app_settings` de dahil: seviye, günlük hedef
  /// ve animasyon hızı da geri gelsin.
  static const List<String> _tables = <String>[
    'card_state',
    'daily_stats',
    'app_settings',
    'journey_progress',
    'flagged_cards',
    'game_profile',
    'daily_quests',
    'achievements',
    'story_progress',
    'sentence_progress',
  ];

  /// İlk yedek biçiminden beri bulunan tablolar. Bunlardan biri yoksa dosya
  /// tam bir FrenchApp yedeği değildir; kısmi JSON'un mevcut ilerlemeyi
  /// sessizce silmesine izin verilmez.
  static const List<String> _requiredTables = <String>[
    'card_state',
    'daily_stats',
    'app_settings',
  ];

  static Future<String> export(Database db) async {
    final Map<String, Object?> out = <String, Object?>{
      'format': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
    };
    await db.transaction((txn) async {
      final existing = (await txn.query('sqlite_master',
              columns: ['name'], where: 'type = ?', whereArgs: ['table']))
          .map((row) => row['name']).toSet();
      for (final table in _tables) {
        if (!existing.contains(table) && !_requiredTables.contains(table)) {
          out[table] = const <Map<String, Object?>>[];
        } else {
          // Real read failures propagate; only absent optional tables are empty.
          out[table] = await txn.query(table);
        }
      }
    });
    return const JsonEncoder.withIndent('  ').convert(out);
  }

  /// Yedeği geri yükler.
  ///
  /// Mevcut ilerlemenin **üzerine yazar**: her tablo temizlenip yedekteki
  /// satırlar konur. Birleştirme yapılmıyor çünkü iki cihazın SRS
  /// durumunu harmanlamanın doğru bir yolu yok; yanlış birleştirme
  /// tekrar aralıklarını sessizce bozardı.
  static Future<ImportReport> import(Database db, String json) async {
    final Object? decoded = jsonDecode(json);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Yedek dosyası tanınmadı.');
    }
    final Object? version = decoded['format'];
    if (version is! int || version < 1) {
      throw const FormatException('Yedek sürümü geçersiz.');
    }
    if (version > formatVersion) {
      throw FormatException(
        'Bu yedek daha yeni bir sürümden ($version). Uygulamayı güncelle.',
      );
    }

    for (final String table in _requiredTables) {
      if (decoded[table] is! List) {
        throw FormatException('Yedek eksik veya bozuk: $table bulunamadı.');
      }
    }

    // Bütün satırları herhangi bir tablo silinmeden önce doğrula. SQLite'ın
    // esnek tür sistemi "metin" değerini INTEGER sütununa kabul edebilir;
    // bu da geri yüklemeden sonra uygulamanın `as int` dönüşümünde çökmesine
    // yol açardı.
    final Map<String, List<Map<String, Object?>>> normalized =
        <String, List<Map<String, Object?>>>{};
    for (final String table in _tables) {
      final Object? rawRows = decoded[table];
      if (rawRows != null && rawRows is! List) {
        throw FormatException('Yedek tablosu bozuk: $table.');
      }
      final List<Map<String, Object?>> columns =
          await db.rawQuery('PRAGMA table_info($table)');
      if (columns.isEmpty) continue;
      final Map<String, String> types = <String, String>{
        for (final Map<String, Object?> column in columns)
          column['name']! as String:
              (column['type'] as String? ?? '').toUpperCase(),
      };
      final List<Map<String, Object?>> rows = <Map<String, Object?>>[];
      final primaryKeys = columns.where((c) => (c['pk'] as int) > 0)
          .map((c) => c['name'] as String).toList();
      final identities = <String>{};
      for (final Object? rawRow in (rawRows as List? ?? const <Object?>[])) {
        if (rawRow is! Map) {
          throw FormatException('Yedekte $table satırı bozuk.');
        }
        final Map<String, Object?> row = <String, Object?>{};
        for (final MapEntry<Object?, Object?> entry in rawRow.entries) {
          final String key = entry.key.toString();
          final String? type = types[key];
          if (type == null) {
            throw FormatException('Yedekte bilinmeyen alan: $table.$key.');
          }
          final Object? value = entry.value;
          if (value != null &&
              ((type.contains('INT') && value is! int) ||
                  (type.contains('TEXT') && value is! String))) {
            throw FormatException('Yedekte alan türü bozuk: $table.$key.');
          }
          row[key] = value;
        }
        for (final column in columns) {
          final name = column['name'] as String;
          final required = (column['pk'] as int) > 0 ||
              ((column['notnull'] as int) != 0 && column['dflt_value'] == null);
          if ((required && row[name] == null) ||
              (row.containsKey(name) && row[name] == null && (column['notnull'] as int) != 0)) {
            throw FormatException('Yedekte zorunlu alan eksik: $table.$name.');
          }
        }
        if (primaryKeys.isNotEmpty && !identities.add(jsonEncode(primaryKeys.map((k) => row[k]).toList()))) {
          throw FormatException('Yedekte yinelenen kayıt var: $table.');
        }
        _validateValues(table, row);
        rows.add(row);
      }
      normalized[table] = rows;
    }

    final Map<String, int> counts = <String, int>{};
    await db.transaction((Transaction txn) async {
      for (final String table in _tables) {
        final List<Map<String, Object?>>? rows = normalized[table];
        if (rows == null) continue;
        await txn.delete(table);
        int n = 0;
        for (final Map<String, Object?> row in rows) {
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          n++;
        }
        counts[table] = n;
      }
    });
    return ImportReport(counts);
  }

  static void _validateValues(String table, Map<String, Object?> row) {
    int? integer(String key) => row[key] as int?;
    void nonNegative(String key) {
      final int? value = integer(key);
      if (value != null && value < 0) {
        throw FormatException('Yedekte negatif değer var: $table.$key.');
      }
    }

    void boolean(String key) {
      final value = integer(key);
      if (value != null && value != 0 && value != 1) {
        throw FormatException('Yedekte geçersiz işaret var: $table.$key.');
      }
    }
    void paired(String correct, String total) {
      if ((integer(correct) ?? 0) > (integer(total) ?? 0)) {
        throw FormatException('Yedekte tutarsız sayaç var: $table.$correct.');
      }
    }

    switch (table) {
      case 'card_state':
        boolean('starred');
        paired('times_right', 'times_seen');
        final int? box = integer('box');
        if (box != null && (box < 0 || box > 5)) {
          throw const FormatException('Yedekte geçersiz SRS kutusu var.');
        }
        final Object? status = row['status'];
        if (status != null &&
            !const <String>{
              'fresh',
              'learning',
              'known',
              'mastered',
              'archived'
            }.contains(status)) {
          throw const FormatException('Yedekte geçersiz kart durumu var.');
        }
        for (final String key in <String>[
          'times_seen',
          'times_right',
          'lapses',
          'updated_at',
        ]) {
          nonNegative(key);
        }
      case 'daily_stats':
        paired('quiz_correct', 'quiz_total');
        for (final String key in <String>[
          'cards_swiped',
          'new_learned',
          'quiz_total',
          'quiz_correct',
        ]) {
          nonNegative(key);
        }
      case 'journey_progress':
        paired('best_correct', 'best_total');
        final int? stars = integer('stars');
        if (stars != null && (stars < 0 || stars > 3)) {
          throw const FormatException('Yedekte geçersiz durak yıldızı var.');
        }
        nonNegative('best_correct');
        nonNegative('best_total');
      case 'game_profile':
        paired('total_correct', 'total_answers');
        for (final String key in <String>[
          'xp',
          'coins',
          'best_combo',
          'total_cards',
          'total_verbs',
          'total_correct',
          'total_answers',
          'stations_passed',
        ]) {
          nonNegative(key);
        }
      case 'daily_quests':
        boolean('claimed');
        for (final String key in <String>[
          'target',
          'progress',
          'reward_xp',
          'reward_coins',
        ]) {
          nonNegative(key);
        }
      case 'story_progress':
        boolean('completed');
        paired('best_correct', 'best_total');
        nonNegative('best_correct');
        nonNegative('best_total');
      case 'sentence_progress':
        boolean('solved');
        nonNegative('attempts');
        nonNegative('best_score');
    }
  }
}

class ImportReport {
  const ImportReport(this.counts);

  final Map<String, int> counts;

  int get cards => counts['card_state'] ?? 0;
  int get days => counts['daily_stats'] ?? 0;
  int get stations => counts['journey_progress'] ?? 0;

  @override
  String toString() =>
      '$cards kart · $days gün · $stations durak geri yüklendi';
}
