import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/data/backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE card_state (
      card_type TEXT NOT NULL,
      ref_id TEXT NOT NULL,
      box INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'fresh',
      starred INTEGER NOT NULL DEFAULT 0,
      due_at INTEGER,
      last_seen_at INTEGER,
      times_seen INTEGER NOT NULL DEFAULT 0,
      times_right INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (card_type, ref_id)
    )''');
    await db.execute('''CREATE TABLE daily_stats (
      day TEXT PRIMARY KEY,
      cards_swiped INTEGER NOT NULL DEFAULT 0,
      new_learned INTEGER NOT NULL DEFAULT 0,
      quiz_total INTEGER NOT NULL DEFAULT 0,
      quiz_correct INTEGER NOT NULL DEFAULT 0
    )''');
    await db.execute(
      'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.insert('card_state', <String, Object?>{
      'card_type': 'word',
      'ref_id': 'keep-me',
      'updated_at': 1,
    });
  });

  tearDown(() => db.close());

  Map<String, Object?> backup({Object? cards = const <Object?>[]}) =>
      <String, Object?>{
        'format': 1,
        'card_state': cards,
        'daily_stats': const <Object?>[],
        'app_settings': const <Object?>[],
      };

  test('kısmi yedeği hiçbir veriyi silmeden reddeder', () async {
    await expectLater(
      ProgressBackup.import(db, '{"format":1,"card_state":[]}'),
      throwsFormatException,
    );
    expect(await db.query('card_state'), hasLength(1));
  });

  test('SQLite tarafından kabul edilebilen yanlış türü önceden reddeder',
      () async {
    final String json = jsonEncode(backup(cards: <Object?>[
      <String, Object?>{
        'card_type': 'word',
        'ref_id': 'broken',
        'box': 'beş',
        'status': 'fresh',
        'starred': 0,
        'times_seen': 0,
        'times_right': 0,
        'lapses': 0,
        'updated_at': 1,
      },
    ]));

    await expectLater(
      ProgressBackup.import(db, json),
      throwsFormatException,
    );
    expect((await db.query('card_state')).single['ref_id'], 'keep-me');
  });

  test('geçerli tam yedek mevcut ilerlemenin üzerine yazar', () async {
    final String json = jsonEncode(backup(cards: <Object?>[
      <String, Object?>{
        'card_type': 'word',
        'ref_id': 'restored',
        'box': 2,
        'status': 'learning',
        'starred': 0,
        'due_at': null,
        'last_seen_at': null,
        'times_seen': 3,
        'times_right': 2,
        'lapses': 0,
        'updated_at': 2,
      },
    ]));

    final ImportReport report = await ProgressBackup.import(db, json);
    expect(report.cards, 1);
    expect((await db.query('card_state')).single['ref_id'], 'restored');
  });
}
