import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/journey.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('FA-003B: legacy B2 result is available under the canonical ID',
      () async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE journey_progress (station_id TEXT PRIMARY KEY, '
        'stars INTEGER, best_correct INTEGER, best_total INTEGER, updated_at INTEGER)');
    await db.insert('journey_progress', <String, Object?>{
      'station_id': 'B2-w0-4e9395bf7fb2',
      'stars': 2,
      'best_correct': 7,
      'best_total': 8,
      'updated_at': 123,
    });
    final JourneyStore store = await JourneyStore.load(db);
    expect(store.resultFor('B2-w0-34914142868b'), isNotNull,
        reason:
            'Earned legacy progress must be visible through the new station ID');
    expect(
        store.resultFor('B2-w0-34914142868b')!.stationId, 'B2-w0-34914142868b');
  });

  Future<Database> open() async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute(
        'CREATE TABLE journey_progress (station_id TEXT PRIMARY KEY, '
        'stars INTEGER, best_correct INTEGER, best_total INTEGER, updated_at INTEGER)');
    return db;
  }

  Future<void> seed(Database db, String id, List<int> score) =>
      db.insert('journey_progress', <String, Object?>{
        'station_id': id,
        'stars': score[0],
        'best_correct': score[1],
        'best_total': score[2],
        'updated_at': 123,
      }).then((_) {});

  List<int> score(StationResult result) =>
      <int>[result.stars, result.bestCorrect, result.bestTotal];

  const List<String> keys = <String>[
    'w0',
    'w1',
    'w2',
    'w3',
    'w4',
    'w5',
    'w6',
    'w7',
    'v0',
    'i0',
    'boss',
  ];
  String legacy(String key) => 'B2-$key-4e9395bf7fb2';
  String canonical(String key) => 'B2-$key-34914142868b';

  test(
      'FA-003B: all 11 aliases handle absent, legacy, canonical and paired rows',
      () async {
    final Database db = await open();
    for (final String key in keys) {
      for (final int mask in <int>[0, 1, 2, 3]) {
        await db.delete('journey_progress');
        if (mask & 1 != 0) await seed(db, legacy(key), <int>[2, 7, 8]);
        if (mask & 2 != 0) await seed(db, canonical(key), <int>[2, 7, 8]);
        final List<Map<String, Object?>> before =
            await db.query('journey_progress');
        final JourneyStore store = await JourneyStore.load(db);
        if (mask == 0) {
          expect(store.resultFor(legacy(key)), isNull);
          expect(store.resultFor(canonical(key)), isNull);
        } else {
          expect(store.resultFor(legacy(key)),
              same(store.resultFor(canonical(key))));
          expect(store.resultFor(legacy(key))!.stationId, canonical(key));
          expect(score(store.resultFor(canonical(key))!), <int>[2, 7, 8]);
        }
        expect(store.passedCount, mask == 0 ? 0 : 1);
        expect(store.totalStars, mask == 0 ? 0 : 2);
        expect(await db.query('journey_progress'), before,
            reason: 'Loading must not write normalized rows or updated_at');
      }
    }
  });

  test(
      'FA-003B: merge preserves best attempt and canonical exact tie in either row order',
      () async {
    final Database db = await open();
    // [legacy, canonical, expected]; equal ratios use different score pairs.
    final List<List<List<int>>> cases = <List<List<int>>>[
      <List<int>>[
        <int>[3, 8, 8],
        <int>[2, 7, 8],
        <int>[3, 8, 8]
      ],
      <List<int>>[
        <int>[2, 7, 8],
        <int>[3, 8, 8],
        <int>[3, 8, 8]
      ],
      <List<int>>[
        <int>[2, 9, 10],
        <int>[2, 7, 8],
        <int>[2, 9, 10]
      ],
      <List<int>>[
        <int>[2, 7, 8],
        <int>[2, 9, 10],
        <int>[2, 9, 10]
      ],
      <List<int>>[
        <int>[2, 7, 8],
        <int>[2, 14, 16],
        <int>[2, 14, 16]
      ],
      <List<int>>[
        <int>[0, 0, 0],
        <int>[0, 0, 0],
        <int>[0, 0, 0]
      ],
    ];
    for (final List<List<int>> entry in cases) {
      for (final bool reverse in <bool>[false, true]) {
        await db.delete('journey_progress');
        final List<int> order = reverse ? <int>[1, 0] : <int>[0, 1];
        for (final int i in order) {
          await seed(db, i == 0 ? legacy('w0') : canonical('w0'), entry[i]);
        }
        final JourneyStore store = await JourneyStore.load(db);
        expect(score(store.resultFor(legacy('w0'))!), entry[2]);
        expect(store.resultFor(legacy('w0'))!.stationId, canonical('w0'));
        final Map<String, StationResult> supplied = <String, StationResult>{
          for (final int i in order)
            (i == 0 ? legacy('w0') : canonical('w0')): StationResult(
              stationId: i == 0 ? legacy('w0') : canonical('w0'),
              stars: entry[i][0],
              bestCorrect: entry[i][1],
              bestTotal: entry[i][2],
            ),
        };
        expect(score(JourneyStore(db, supplied).resultFor(canonical('w0'))!),
            entry[2]);
      }
    }
  });

  test(
      'FA-003B: record through either ID writes canonical and retains legacy row',
      () async {
    final Database db = await open();
    for (final String key in keys) {
      await seed(db, legacy(key), <int>[2, 7, 8]);
    }
    final List<Map<String, Object?>> legacyRows =
        await db.query('journey_progress');
    final JourneyStore store = await JourneyStore.load(db);
    for (final String key in keys) {
      for (final String id in <String>[legacy(key), canonical(key)]) {
        final StationResult result =
            await store.record(stationId: id, stars: 1, correct: 6, total: 8);
        expect(result.stationId, canonical(key));
        expect(score(result), <int>[2, 7, 8]);
      }
    }
    expect(store.passedCount, 11);
    expect(store.totalStars, 22);
    final List<Map<String, Object?>> after = await db.query('journey_progress');
    expect(after, hasLength(22));
    for (final Map<String, Object?> row in legacyRows) {
      expect(
          after.singleWhere((r) => r['station_id'] == row['station_id']), row);
    }
    final JourneyStore reloaded = await JourneyStore.load(db);
    expect(reloaded.passedCount, 11);
    expect(reloaded.totalStars, 22);
  });

  test('FA-003B: unknown revision, level and station keys remain unchanged',
      () async {
    final Database db = await open();
    const List<String> unknown = <String>[
      'B2-w0-aaaaaaaaaaaa',
      'A2-w0-4e9395bf7fb2',
      'B2-w8-4e9395bf7fb2',
      'B2-v1-4e9395bf7fb2',
      'B2-unknown-4e9395bf7fb2',
    ];
    final JourneyStore store = await JourneyStore.load(db);
    for (final String id in unknown) {
      expect(
          (await store.record(stationId: id, stars: 2, correct: 7, total: 8))
              .stationId,
          id);
    }
    final JourneyStore reloaded = await JourneyStore.load(db);
    for (final String id in unknown) {
      expect(reloaded.resultFor(id)!.stationId, id);
    }
    expect(reloaded.passedCount, unknown.length);
  });
}
