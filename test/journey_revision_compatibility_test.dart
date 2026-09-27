import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/data/backup.dart';
import 'package:french_app/data/content_version.dart';
import 'package:french_app/domain/journey.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/features/journey/journey_map_screen.dart';
import 'package:french_app/features/journey/station_builder.dart';
import 'package:french_app/features/quiz/quiz_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Known B2 compatibility policy and current packaged-content regression tests.
// Python is already required by the content checks. Calling the read-only audit
// avoids introducing a second hash implementation or a new Dart dependency.
void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String oldRevision;
  late String newRevision;
  AppState? currentApp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('frenchapp_fa003a_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    final ProcessResult audit = await Process.run(
      Platform.isWindows ? 'python' : 'python3',
      <String>[
        '-B',
        'content/tools/journey_revision_audit.py',
        '--db',
        'assets/db/content.db',
        '--json'
      ],
    );
    expect(audit.exitCode, 0,
        reason: 'The current package must pass the revision audit.');
    final Map<String, dynamic> report =
        jsonDecode(audit.stdout as String) as Map<String, dynamic>;
    final List<dynamic> levels = report['levels'] as List<dynamic>;
    final Map<String, dynamic> b2 = levels
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['level'] == 'B2');
    expect(levels.where((row) => row['status'] != 'match'), isEmpty);
    oldRevision = '4e9395bf7fb2';
    expect(b2['recorded'], b2['computed']);
    newRevision = b2['computed'] as String;
    expect(oldRevision, '4e9395bf7fb2');
    expect(newRevision, '34914142868b');
  });
  tearDown(() async {
    await currentApp?.close();
    currentApp = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    await temp.delete(recursive: true);
  });

  Future<AppState> openOriginal() async {
    final AppState bootstrap = await AppState.create();
    await bootstrap.close();
    final Database legacy =
        await databaseFactoryFfi.openDatabase('${temp.path}/content.db');
    await legacy.update('meta', <String, Object?>{'value': oldRevision},
        where: 'key=?', whereArgs: <Object?>['journey_revision_B2']);
    await legacy.close();
    // Controlled legacy-content comparison only. The real marker/update path
    // has its own test below and does not use this shortcut.
    final AppState app = await AppState.create();
    currentApp = app;
    await app.setLevel(CefrLevel.b2);
    await app.setReducedMotion(true);
    expect(app.contentMeta['journey_revision_B2'], oldRevision);
    return app;
  }

  Future<AppState> reopenWithOnlyB2RevisionChanged() async {
    await currentApp!.close();
    currentApp = null;
    final String contentPath = '${temp.path}/content.db';
    final String previousPath = '${temp.path}/previous.db';
    await File(contentPath).copy(previousPath);
    final int oldLength = await File(contentPath).length();
    final Database content = await databaseFactoryFfi.openDatabase(contentPath);
    try {
      expect(
          await content.update(
            'meta',
            <String, Object?>{'value': newRevision},
            where: 'key=?',
            whereArgs: <Object?>['journey_revision_B2'],
          ),
          1);
      await content
          .execute('ATTACH DATABASE ? AS previous', <Object?>[previousPath]);
      final List<Map<String, Object?>> tables = await content.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      for (final Map<String, Object?> row in tables) {
        final String table = row['name']! as String;
        final String filter =
            table == 'meta' ? " WHERE key != 'journey_revision_B2'" : '';
        for (final List<String> pair in <List<String>>[
          <String>['main', 'previous'],
          <String>['previous', 'main'],
        ]) {
          final String left = pair[0];
          final String right = pair[1];
          final List<Map<String, Object?>> difference = await content.rawQuery(
            'SELECT * FROM $left."$table"$filter '
            'EXCEPT SELECT * FROM $right."$table"$filter',
          );
          expect(difference, isEmpty,
              reason: 'Unexpected content difference: $table');
        }
        final List<Map<String, Object?>> counts = await content.rawQuery(
          'SELECT (SELECT count(*) FROM main."$table") AS a, '
          '(SELECT count(*) FROM previous."$table") AS b',
        );
        expect(counts.single['a'], counts.single['b']);
      }
      await content.execute('DETACH DATABASE previous');
    } finally {
      await content.close();
    }
    // The production copy check accepts the unchanged temporary marker/length.
    // Repository content and its markers are never written.
    expect(await File(contentPath).length(), oldLength);
    final AppState app = await AppState.create();
    currentApp = app;
    expect(app.contentMeta['journey_revision_B2'], newRevision);
    return app;
  }

  Future<List<Map<String, Object?>>> stationDescriptions(AppState app) async {
    final List<JourneyStation> stations = StationBuilder.build(app);
    final List<Map<String, Object?>> descriptions = <Map<String, Object?>>[];
    for (int index = 0; index < stations.length; index++) {
      final JourneyStation station = stations[index];
      final List<String> resolvedVerbs =
          await StationBuilder.verbRefIdsFor(app, station);
      // Same shuffle sequence as StationQuizScreen, with a controlled RNG.
      final Random rng = Random(1000 + index);
      final List<String> verbs = List<String>.of(resolvedVerbs)..shuffle(rng);
      final List<String> words = List<String>.of(station.wordIds)..shuffle(rng);
      final List<QuizQuestion> questions = await QuizEngine.build(
        app: app,
        wordIds: words,
        verbRefIds: verbs,
        count: station.questionCount,
        rng: rng,
      );
      descriptions.add(<String, Object?>{
        'id': station.id,
        'position': index,
        'level': station.level.code,
        'indexInLevel': station.indexInLevel,
        'kind': station.kind.name,
        'title': station.title,
        'wordIds': station.wordIds,
        'declaredVerbRefIds': station.verbRefIds,
        'resolvedVerbRefIds': resolvedVerbs,
        'questionCount': station.questionCount,
        'passRatio': station.passRatio,
        'isBoss': station.isBoss,
        'starsByCorrect': <int>[
          for (int correct = 0; correct <= questions.length; correct++)
            JourneyStation.starsFor(
                correct, questions.length, station.passRatio),
        ],
        'questions': <Map<String, Object?>>[
          for (final QuizQuestion question in questions)
            <String, Object?>{
              'kind': question.kind.name,
              'refId': question.refId,
              'isVerbCard': question.isVerbCard,
              'prompt': question.prompt,
              'subPrompt': question.subPrompt,
              'correct': question.correct,
              'options': question.options,
              'speakText': question.speakText,
            },
        ],
      });
    }
    return descriptions;
  }

  test(
      'FA-003B: isolated legacy revision preserves ordered station and quiz content',
      () async {
    final AppState original = await openOriginal();
    final List<Map<String, Object?>> before =
        await stationDescriptions(original);
    final AppState revised = await reopenWithOnlyB2RevisionChanged();
    final List<Map<String, Object?>> after = await stationDescriptions(revised);
    expect(after, hasLength(before.length));
    final Map<String, String> mapping = <String, String>{};
    final List<Map<String, Object?>> b2Evidence = <Map<String, Object?>>[];
    for (int i = 0; i < before.length; i++) {
      final Map<String, Object?> a = Map<String, Object?>.of(before[i]);
      final Map<String, Object?> b = Map<String, Object?>.of(after[i]);
      final String oldId = a.remove('id')! as String;
      final String newId = b.remove('id')! as String;
      expect(b, a,
          reason: 'Ordered station/content contract changed at $oldId');
      if (a['level'] == 'B2') {
        expect(oldId, isNot(newId));
        expect(newId, oldId.replaceFirst(oldRevision, newRevision));
        mapping[oldId] = newId;
        b2Evidence.add(<String, Object?>{
          'old': oldId,
          'new': newId,
          'kind': a['kind'],
          'words': (a['wordIds']! as List).length,
          'verbRefs': (a['resolvedVerbRefIds']! as List).length,
          'requestedQuestions': a['questionCount'],
          'actualQuestions': (a['questions']! as List).length,
          'passRatio': a['passRatio'],
        });
      } else {
        expect(newId, oldId);
      }
    }
    final List<String> oldIds =
        before.map((row) => row['id']! as String).toList();
    final List<String> newIds =
        after.map((row) => row['id']! as String).toList();
    expect(oldIds.toSet(), hasLength(oldIds.length));
    expect(newIds.toSet(), hasLength(newIds.length));
    expect(mapping.values.toSet(), hasLength(mapping.length));
    expect(mapping.values.toSet().intersection(oldIds.toSet()), isEmpty);
    expect(mapping, isNotEmpty);
    debugPrint(
        'FA-003A station_count=${before.length} B2_mapping=${jsonEncode(b2Evidence)}');
  });

  Future<Map<String, List<Map<String, Object?>>>> rawProgress(
      AppState app) async {
    final Map<String, List<Map<String, Object?>>> result =
        <String, List<Map<String, Object?>>>{};
    for (final String table in <String>[
      'journey_progress',
      'card_state',
      'flagged_cards',
      'daily_stats',
      'app_settings',
      'game_profile',
      'daily_quests',
      'achievements',
      'story_progress',
      'sentence_progress',
    ]) {
      result[table] = await app.db.progress.query(table);
    }
    return result;
  }

  test(
      'FA-003B: real content update replaces a correctly marked legacy DB and preserves progress',
      () async {
    AppState app = await AppState.create();
    currentApp = app;
    await app.db.progress.insert('journey_progress', <String, Object?>{
      'station_id': 'B2-w0-4e9395bf7fb2',
      'stars': 2,
      'best_correct': 7,
      'best_total': 8,
      'updated_at': 123,
    });
    // Seed unrelated real-schema SRS state, using a current public-content ID.
    final String word = app.words.all().first.id;
    await app.db.progress.insert('card_state', <String, Object?>{
      'card_type': 'word',
      'ref_id': word,
      'box': 2,
      'starred': 1,
      'status': 'archived',
      'updated_at': 123,
    });
    await app.db.progress.update(
        'game_profile',
        <String, Object?>{
          'xp': 40,
          'coins': 16,
          'stations_passed': 1,
        },
        where: 'id=1');
    final Map<String, List<Map<String, Object?>>> saved =
        await rawProgress(app);
    await app.close();
    currentApp = null;
    final String path = '${temp.path}/content.db';
    final Database legacy = await databaseFactoryFfi.openDatabase(path);
    await legacy.update('meta', <String, Object?>{'value': oldRevision},
        where: 'key=?', whereArgs: <Object?>['journey_revision_B2']);
    await legacy.close();
    // Compute the actual legacy bytes' marker; never impersonate the new marker.
    final ProcessResult hash = await Process.run(
      Platform.isWindows ? 'python' : 'python3',
      <String>[
        '-B',
        '-c',
        'import hashlib,pathlib,sys; b=pathlib.Path(sys.argv[1]).read_bytes(); '
            'print(hashlib.sha256(b).hexdigest().upper()+":"+str(len(b)))',
        path,
      ],
    );
    expect(hash.exitCode, 0);
    final String oldMarker = (hash.stdout as String).trim();
    expect(oldMarker, isNot(kContentVersion));
    await File('$path.version').writeAsString(oldMarker);
    app =
        await AppState.create(); // Real AppDatabase._ensureContentCopied path.
    currentApp = app;
    expect(app.contentMeta['journey_revision_B2'], newRevision);
    expect(await File(path).readAsBytes(),
        await File('assets/db/content.db').readAsBytes());
    expect(
        (await File('$path.version').readAsString()).trim(), kContentVersion);
    expect(await rawProgress(app), saved);
    expect(app.journey.resultFor('B2-w0-34914142868b')!.stars, 2);
    expect(app.rewardSerial, 0);
    await app.close();
    currentApp = null;
    app = await AppState.create();
    currentApp = app;
    await app.reloadProgress();
    expect(await rawProgress(app), saved);
    expect(app.journey.passedCount, 1);
    expect(app.rewardSerial, 0);
  });

  test(
      'FA-003B: paired backup rows deduplicate without reconciling historical profile counters',
      () async {
    final AppState app = await AppState.create();
    currentApp = app;
    for (final String id in <String>[
      'B2-w0-4e9395bf7fb2',
      'B2-w0-34914142868b'
    ]) {
      await app.db.progress.insert('journey_progress', <String, Object?>{
        'station_id': id,
        'stars': 2,
        'best_correct': 7,
        'best_total': 8,
        'updated_at': 123,
      });
    }
    await app.db.progress.update(
        'game_profile',
        <String, Object?>{
          'xp': 80,
          'coins': 32,
          'stations_passed': 2,
        },
        where: 'id=1');
    final Map<String, List<Map<String, Object?>>> saved =
        await rawProgress(app);
    final String backup = await ProgressBackup.export(app.db.progress);
    expect(jsonDecode(backup)['format'], 1);
    expect(jsonDecode(backup)['journey_progress'], hasLength(2));
    await ProgressBackup.import(app.db.progress, backup);
    await app.reloadProgress();
    await app.reloadProgress();
    expect(await rawProgress(app), saved);
    expect(app.journey.passedCount, 1);
    expect(app.journey.totalStars, 2);
    expect(<int>[
      app.game.profile.xp,
      app.game.profile.coins,
      app.game.profile.stationsPassed
    ], <int>[
      80,
      32,
      2
    ]);
    expect(app.rewardSerial, 0);
  });

  test('FA-003B: new user receives normal first station bonus', () async {
    final AppState app = await AppState.create();
    currentApp = app;
    await app.recordStation(
        stationId: 'B2-w0-34914142868b', stars: 2, correct: 7, total: 8);
    expect(<int>[
      app.game.profile.xp,
      app.game.profile.coins,
      app.game.profile.stationsPassed
    ], <int>[
      40,
      16,
      1
    ]);
    expect(app.journey.passedCount, 1);
  });

  // Inspect the real map's rendered node, not a copied unlock algorithm.
  // The private widget name is a test coupling; no production API was added.
  Finder nodeFor(String id) => find.byWidgetPredicate((Widget widget) {
        if (widget.runtimeType.toString() != '_StationNode') return false;
        return ((widget as dynamic).station as JourneyStation).id == id;
      });

  Future<void> showMap(WidgetTester tester, AppState app) async {
    await tester.pumpWidget(AppScope(
      state: app,
      child: const MaterialApp(home: JourneyMapScreen()),
    ));
    // The map has looping decoration; finite pumps avoid waiting for an
    // animation to finish forever. No timers or test timeouts are disabled.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets(
      'FA-003B: legacy progress keeps map match and earns only a real star improvement',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final AppState original = (await tester.runAsync(openOriginal))!;
    final List<JourneyStation> oldB2 = StationBuilder.build(original)
        .where((JourneyStation station) => station.level == CefrLevel.b2)
        .toList();
    final JourneyStation oldFirst = oldB2[0];
    final JourneyStation oldNext = oldB2[1];
    final int stars = JourneyStation.starsFor(7, 8, oldFirst.passRatio);
    expect(stars, 2);
    // Raw legacy rows model an older app; the new record API canonicalizes IDs.
    await tester.runAsync(() async {
      await original.db.progress.insert('journey_progress', <String, Object?>{
        'station_id': oldFirst.id,
        'stars': 2,
        'best_correct': 7,
        'best_total': 8,
        'updated_at': 123,
      });
      await original.db.progress.update(
          'game_profile',
          <String, Object?>{
            'xp': 40,
            'coins': 16,
            'stations_passed': 1,
          },
          where: 'id=1');
      await original.reloadProgress();
    });
    expect(original.journey.resultFor(oldFirst.id)!.bestCorrect, 7);
    expect(original.journey.resultFor(oldFirst.id)!.bestTotal, 8);
    expect(original.journey.resultFor(oldNext.id), isNull);
    final int xp = original.game.profile.xp;
    final int coins = original.game.profile.coins;
    final int passed = original.game.profile.stationsPassed;
    expect(<int>[xp, coins, passed], <int>[40, 16, 1]);
    final String backup = (await tester
        .runAsync(() => ProgressBackup.export(original.db.progress)))!;
    final List<Map<String, Object?>> saved = (await tester
        .runAsync(() => original.db.progress.query('journey_progress')))!;
    await showMap(tester, original);
    expect(
        find.descendant(
            of: nodeFor(oldFirst.id),
            matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(2));
    expect(
        find.descendant(
            of: nodeFor(oldNext.id), matching: find.byIcon(Icons.lock_rounded)),
        findsNothing);
    expect(nodeFor(oldNext.id), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    final AppState revised =
        (await tester.runAsync(reopenWithOnlyB2RevisionChanged))!;
    final List<JourneyStation> newB2 = StationBuilder.build(revised)
        .where((JourneyStation station) => station.level == CefrLevel.b2)
        .toList();
    final JourneyStation newFirst = newB2[0];
    final JourneyStation newNext = newB2[1];
    expect(revised.journey.resultFor(oldFirst.id)!.stars, 2);
    expect(revised.journey.resultFor(newFirst.id)!.stars, 2);
    expect(revised.journey.resultFor(oldFirst.id)!.stationId, newFirst.id);
    expect(
        await tester
            .runAsync(() => revised.db.progress.query('journey_progress')),
        saved);
    expect(revised.journey.totalStars, 2);
    expect(revised.journey.passedCount, 1);
    expect(newB2.where((s) => revised.journey.resultFor(s.id)?.passed ?? false),
        hasLength(1));
    await showMap(tester, revised);
    expect(
        find.descendant(
            of: nodeFor(newFirst.id),
            matching: find.byIcon(Icons.star_rounded)),
        findsNWidgets(2));
    expect(
        find.descendant(
            of: nodeFor(newNext.id), matching: find.byIcon(Icons.lock_rounded)),
        findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());

    // Restore preserves physical rows; every reload rebuilds the canonical view.
    await tester.runAsync(() async {
      await ProgressBackup.import(revised.db.progress, backup);
      await revised.reloadProgress();
      await revised.reloadProgress();
    });
    expect(
        await tester
            .runAsync(() => revised.db.progress.query('journey_progress')),
        saved);
    expect(revised.journey.resultFor(newFirst.id)!.stars, 2);
    expect(revised.journey.resultFor(oldFirst.id)!.stationId, newFirst.id);
    expect(revised.journey.resultFor(oldFirst.id)!.stars, 2);
    await tester.runAsync(() => revised.recordStation(
          stationId: newFirst.id,
          stars: stars,
          correct: 7,
          total: 8,
        ));
    expect(<int>[
      revised.game.profile.xp - xp,
      revised.game.profile.coins - coins,
      revised.game.profile.stationsPassed - passed
    ], <int>[
      0,
      0,
      0
    ]);
    expect(revised.journey.resultFor(oldFirst.id)!.stars, 2);
    expect(revised.journey.resultFor(newFirst.id)!.stars, 2);
    expect(revised.journey.totalStars, 2);
    expect(revised.journey.passedCount, 1);
    await tester.runAsync(() => revised.recordStation(
          stationId: oldFirst.id,
          stars: 2,
          correct: 7,
          total: 8,
        ));
    expect(<int>[
      revised.game.profile.xp,
      revised.game.profile.coins,
      revised.game.profile.stationsPassed
    ], <int>[
      xp,
      coins,
      passed
    ]);
    await tester.runAsync(() => revised.recordStation(
          stationId: newFirst.id,
          stars: 3,
          correct: 8,
          total: 8,
        ));
    expect(<int>[
      revised.game.profile.xp - xp,
      revised.game.profile.coins - coins,
      revised.game.profile.stationsPassed - passed
    ], <int>[
      20,
      8,
      0
    ]);
    expect(revised.journey.totalStars, 3);
    expect(revised.journey.passedCount, 1);
    final List<Map<String, Object?>> raw = (await tester
        .runAsync(() => revised.db.progress.query('journey_progress')))!;
    expect(raw, hasLength(2));
    expect(
        raw.singleWhere((r) => r['station_id'] == oldFirst.id), saved.single);
    await showMap(tester, revised);
    expect(
        find.descendant(
            of: nodeFor(newNext.id), matching: find.byIcon(Icons.lock_rounded)),
        findsNothing);
    expect(nodeFor(newNext.id), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugPrint('FA-003B progress: legacy stars/lock preserved; replay bonus=0; '
        '2->3 stars bonus=20 XP,8 coins,0 passed; raw legacy retained');
  });
}
