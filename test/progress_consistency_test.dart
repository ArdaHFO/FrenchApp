import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_shell.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/data/backup.dart';
import 'package:french_app/data/progress_coordinator.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/game.dart';
import 'package:french_app/domain/journey.dart';
import 'package:french_app/features/journey/station_quiz_screen.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/srs/box_scheduler.dart';
import 'package:french_app/domain/srs/srs_card.dart';
import 'package:french_app/features/progress/backup_screen.dart';
import 'package:french_app/features/quiz/quiz_screen.dart';
import 'package:french_app/features/verbs/verb_screens.dart';
import 'package:french_app/features/vocab/swipe_session_screen.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:french_app/motion/swipe_direction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/progress_probe.dart';

const String refA = 'probe:present:je';
const String refB = 'backup-b:present:je';
const Duration deadline = Duration(seconds: 15);

Map<String, Object?> cardFields(SrsCard card) => <String, Object?>{
      'box': card.box,
      'status': card.status.name,
      'starred': card.starred ? 1 : 0,
      'due_at': card.dueAt?.millisecondsSinceEpoch,
      'last_seen_at': card.lastSeenAt?.millisecondsSinceEpoch,
      'times_seen': card.timesSeen,
      'times_right': card.timesRight,
      'lapses': card.lapses,
    };

Map<String, Object?> profileFields(GameProfile p) => <String, Object?>{
      'xp': p.xp,
      'coins': p.coins,
      'best_combo': p.bestCombo,
      'total_cards': p.totalCards,
      'total_verbs': p.totalVerbs,
      'total_correct': p.totalCorrect,
      'total_answers': p.totalAnswers,
      'stations_passed': p.stationsPassed,
    };

Future<Map<String, Object?>> snapshot(AppState app) async {
  final List<Map<String, Object?>> cards = await app.db.progress.query(
      'card_state',
      where: 'card_type = ?',
      whereArgs: <Object?>['conjugation'],
      orderBy: 'ref_id');
  final List<Map<String, Object?>> days = await app.db.progress.query(
      'daily_stats',
      where: 'day = ?',
      whereArgs: <Object?>[DailyStatsStore.keyFor(DateTime.now())]);
  final Map<String, Object?> profile = Map<String, Object?>.of(
      (await app.db.progress.query('game_profile')).single)
    ..remove('id')
    ..remove('updated_at');
  final List<Map<String, Object?>> quests = await app.db.progress.query(
      'daily_quests',
      where: 'day = ?',
      whereArgs: <Object?>[DailyStatsStore.keyFor(DateTime.now())],
      orderBy: 'quest_id');
  final List<Map<String, Object?>> achievements =
      await app.db.progress.query('achievements', orderBy: 'achievement_id');
  return <String, Object?>{
    'cards_db': <String, Object?>{
      for (final Map<String, Object?> row in cards)
        row['ref_id']! as String: Map<String, Object?>.of(row)
          ..remove('ref_id')
          ..remove('card_type')
          ..remove('updated_at'),
    },
    'cards_cache': <String, Object?>{
      for (final MapEntry<String, SrsCard> e
          in app.verbCards.snapshot().entries)
        e.key: cardFields(e.value),
    },
    'daily_db': days.isEmpty
        ? <String, Object?>{}
        : (Map<String, Object?>.of(days.single)..remove('day')),
    'daily_cache': Map<String, int>.of(app.stats.today()),
    'profile_db': profile,
    'profile_cache': profileFields(app.game.profile),
    'quests_db': <String, Object?>{
      for (final Map<String, Object?> q in quests)
        q['quest_id']! as String: <String, Object?>{
          'progress': q['progress'],
          'claimed': q['claimed']
        },
    },
    'quests_cache': <String, Object?>{
      for (final DailyQuest q in app.game.quests)
        q.id: <String, Object?>{
          'progress': q.progress,
          'claimed': q.claimed ? 1 : 0
        },
    },
    'achievements_db': achievements
        .map((Map<String, Object?> r) => r['achievement_id'])
        .toList(),
    'achievements_cache': app.game.unlockedAchievements.toList()..sort(),
    'published_reward': <String, Object?>{
      'xp': app.lastReward.xp,
      'coins': app.lastReward.coins,
      'serial': app.rewardSerial
    },
  };
}

void aligned(Map<String, Object?> s) {
  for (final String key in <String>[
    'cards',
    'profile',
    'quests',
    'achievements'
  ]) {
    expect(s['${key}_cache'], s['${key}_db'],
        reason: '$key cache matches persisted data');
  }
  if ((s['daily_db']! as Map).isNotEmpty) {
    expect(s['daily_cache'], s['daily_db']);
  }
}

void report(String scenario, List<String> events, Map<String, Object?> data) {
  debugPrintSynchronously('FA006B_RESULT ${jsonEncode(<String, Object?>{
        'scenario': scenario,
        'events': events,
        ...data,
      })}');
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String devicePath;
  final List<AppState> apps = <AppState>[];
  final List<OperationGate> gates = <OperationGate>[];
  final Map<AppState, ProbeDatabase> probes = <AppState, ProbeDatabase>{};

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  tearDownAll(() {
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('frenchapp_fa006a_');
    devicePath = '${temp.path}/a';
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => devicePath);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('flutter_tts'), (_) async => <String>[]);
    final String path = '${temp.path}/synthetic-content.db';
    final Database db = await databaseFactoryFfi.openDatabase(path);
    await db.execute(
        'CREATE TABLE words (id TEXT, freq_rank INTEGER, lemma_fr TEXT, pos TEXT, level TEXT, theme TEXT)');
    await db.execute('''CREATE TABLE examples (word_id TEXT, ordinal INTEGER,
      sentence_fr TEXT, sentence_en TEXT, sentence_tr TEXT, sentence_fr_id INTEGER,
      author_fr TEXT, sentence_en_id INTEGER, author_en TEXT, sentence_tr_id INTEGER, author_tr TEXT)''');
    await db.execute(
        'CREATE TABLE word_relations (word_id TEXT, related_id TEXT, ordinal INTEGER)');
    await db.execute('CREATE TABLE meta (key TEXT, value TEXT)');
    await db.execute(
        '''CREATE TABLE verbs (id TEXT, infinitive TEXT, auxiliary TEXT,
      level TEXT, freq_rank INTEGER, needs_review INTEGER)''');
    await db.execute(
        'CREATE TABLE conjugations (verb_id TEXT, tense TEXT, person TEXT, form TEXT)');
    await db.insert('verbs', <String, Object?>{
      'id': 'probe',
      'infinitive': 'tester',
      'auxiliary': 'avoir',
      'level': 'A1',
      'freq_rank': 1,
      'needs_review': 0
    });
    await db.insert('conjugations', <String, Object?>{
      'verb_id': 'probe',
      'tense': 'present',
      'person': 'je',
      'form': 'teste'
    });
    await db.insert('words', <String, Object?>{
      'id': 'word-probe',
      'freq_rank': 1,
      'lemma_fr': 'essai',
      'pos': 'noun',
      'level': 'A1',
      'theme': 'daily'
    });
    await db.close();
    final Uint8List bytes = await File(path).readAsBytes();
    binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async =>
            const StringCodec().decodeMessage(message) == 'assets/db/content.db'
                ? ByteData.sublistView(bytes)
                : null);
  });
  tearDown(() async {
    await binding.runAsync(() async {
      for (final OperationGate gate in gates) {
        gate.release();
      }
      gates.clear();
      for (final AppState app in apps) {
        await app.close();
      }
      apps.clear();
      for (final String channel in <String>[
        'plugins.flutter.io/path_provider',
        'flutter_tts'
      ]) {
        binding.defaultBinaryMessenger
            .setMockMethodCallHandler(MethodChannel(channel), null);
      }
      binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
      await temp.delete(recursive: true);
    });
  });

  Future<AppState> boot([String device = 'a']) async {
    devicePath = '${temp.path}/$device';
    final AppState app = await AppState.create();
    apps.add(app);
    await app.setReducedMotion(true);
    // Existing mutable store fields are the only injection seam. AppDatabase,
    // schema creation, backup import/export and close retain the real DB.
    final ProbeDatabase probe = ProbeDatabase(app.db.progress);
    probes[app] = probe;
    app.verbCards =
        await SqliteCardStateStore.load(probe, cardType: 'conjugation');
    app.stats = await DailyStatsStore.load(probe);
    app.game = await GameStore.load(probe);
    probe.events.clear();
    return app;
  }

  OperationGate gate() {
    final OperationGate g = OperationGate();
    gates.add(g);
    return g;
  }

  test('Step05 song star preserves the preceding committed same-word answer', () async {
    final app = await boot();
    const ref = 'word-probe';
    final initial = SrsCard(refId: ref, box: 3, status: CardStatus.known,
        timesSeen: 9, timesRight: 7, lapses: 2,
        dueAt: DateTime.utc(2026, 10, 3),
        lastSeenAt: DateTime.utc(2026, 9, 20));
    await app.cards.save(initial);
    final boundary = gate();
    probes[app]!.transactionGate = boundary;
    final canonical = app.recordAnswer(cardType: AnswerCardType.word,
        refId: ref, action: SwipeAction.dontKnow, now: DateTime.now());
    await boundary.entered.future.timeout(deadline);
    // The semantic save is admitted while the earlier answer is pending.
    final prepared = app.cards.stateFor(ref).copyWith(starred: true);
    final saving = app.cards.star(ref);
    boundary.release();
    final committed = await canonical;
    await saving;
    final expected = committed.after.copyWith(starred: true);
    final actual = await app.cards.readState(app.db.progress, ref);
    final activity = await snapshot(app);
    report('Step05 song same-card ordering', probes[app]!.events, {
      'S0': cardFields(initial), 'S1': cardFields(committed.after),
      'prepared': cardFields(prepared), 'final_db': cardFields(actual),
      'final_cache': cardFields(app.cards.stateFor(ref)), 'activity': activity,
    });
    expect(cardFields(actual), cardFields(expected));
    expect(cardFields(app.cards.stateFor(ref)), cardFields(expected));
    expect(app.stats.today()['cards_swiped'], 1);
    expect(app.stats.today()['new_learned'], 0);
    expect(app.stats.today()['quiz_total'], 0);
    expect(app.game.profile.xp, 4);
    expect(app.game.profile.coins, 0);
    expect(app.game.profile.totalCards, 1);
    expect(app.rewardSerial, 1);
    aligned(activity);
    await app.close();
    final reopened = await boot();
    expect(cardFields(reopened.cards.stateFor(ref)), cardFields(expected));
    expect(cardFields(await reopened.cards.readState(reopened.db.progress, ref)), cardFields(expected));
    final reloaded = await snapshot(reopened);
    for (final key in activity.keys.where((key) => key != 'published_reward')) {
      expect(reloaded[key], activity[key], reason: '$key survives reopen');
    }
  });

  test('Step05 song star SQL failure preserves cache and retries after commit', () async {
    final app = await boot();
    const ref = 'word-probe';
    await app.recordAnswer(cardType: AnswerCardType.word, refId: ref,
        action: SwipeAction.dontKnow, now: DateTime.now());
    final probe = probes[app]!;
    app.cards = await SqliteCardStateStore.load(probe);
    final before = cardFields(app.cards.stateFor(ref));
    final rowsBefore = await app.db.progress.query('card_state');
    final activityBefore = await snapshot(app);
    await app.db.progress.execute(
        "CREATE TRIGGER song_star_fail BEFORE INSERT ON card_state WHEN NEW.starred = 1 BEGIN SELECT RAISE(ABORT,'SONG_STAR_FAIL'); END");
    await expectLater(app.cards.star(ref), throwsA(isA<DatabaseException>()
        .having((e) => e.toString(), 'SQL marker', contains('SONG_STAR_FAIL'))));
    expect(await app.db.progress.query('card_state'), rowsBefore);
    expect(cardFields(app.cards.stateFor(ref)), before);
    expect(await snapshot(app), activityBefore);
    await app.db.progress.execute('DROP TRIGGER song_star_fail');
    var commits = 0;
    probe.onTransactionCommitted = () {
      commits++;
      // SQLite has committed but the outer transaction future has not returned.
      expect(cardFields(app.cards.stateFor(ref)), before);
    };
    final result = await app.cards.star(ref);
    probe.onTransactionCommitted = null;
    expect(commits, 1);
    final expected = {...before, 'starred': 1};
    expect(cardFields(result), expected);
    expect(cardFields(app.cards.stateFor(ref)), expected);
    expect(cardFields(await app.cards.readState(app.db.progress, ref)), expected);
    expect(await app.db.progress.query('card_state'), hasLength(1));
    expect(await snapshot(app), activityBefore);
  });

  test('Step05 song star creates a fresh unstarted word without activity', () async {
    final app = await boot();
    const ref = 'word-probe';
    final activity = await snapshot(app);
    expect(app.cards.snapshot(), isEmpty);
    expect(await app.db.progress.query('card_state'), isEmpty);
    final before = DateTime.now().millisecondsSinceEpoch;
    final result = await app.cards.star(ref);
    final expected = cardFields(const SrsCard(refId: ref, starred: true));
    expect(cardFields(result), expected);
    expect(cardFields(app.cards.stateFor(ref)), expected);
    final row = (await app.db.progress.query('card_state')).single;
    expect(row['updated_at'], inInclusiveRange(before, DateTime.now().millisecondsSinceEpoch));
    expect(cardFields(await app.cards.readState(app.db.progress, ref)), expected);
    expect(await snapshot(app), activity);
    await app.close();
    final reopened = await boot();
    expect(cardFields(reopened.cards.stateFor(ref)), expected);
    expect(cardFields(await reopened.cards.readState(reopened.db.progress, ref)), expected);
    expect(await snapshot(reopened), activity);
  });

  test('Step05 song star rejects a store from the previous progress generation', () async {
    final app = await boot();
    final oldCards = app.cards;
    await app.restoreProgress(await app.exportProgress());
    final rows = await app.db.progress.query('card_state');
    final activity = await snapshot(app);
    await expectLater(oldCards.star('word-probe'), throwsA(isA<ProgressUnavailable>()));
    expect(await app.db.progress.query('card_state'), rows);
    expect(oldCards.snapshot(), isEmpty);
    expect(app.cards.snapshot(), isEmpty);
    expect(await snapshot(app), activity);
    await app.cards.star('word-probe');
    expect(app.cards.stateFor('word-probe').starred, isTrue);
  });

  test('Step05 both song callbacks use guarded semantic starring', () {
    for (final file in ['popular_song_screen.dart', 'song_player_screen.dart']) {
      final source = File('lib/features/songs/$file').readAsStringSync();
      expect(source, contains('await app.cards.star(matchedWord.id);'));
      expect(source, isNot(contains('.save(')));
      expect(source, isNot(contains('copyWith(starred:')));
      expect(source, matches(RegExp(
          r'if \(!allowProgress\(context, app, generation\)\) return;\s*await app.cards.star\(matchedWord.id\);\s*app.notifyProgressChanged\(\);')));
    }
  });

  SrsCard answerA() =>
      BoxScheduler.apply(const SrsCard(refId: refA), SwipeAction.know,
          now: DateTime.utc(2026, 9, 12, 12));

  Future<void> driveUntil(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 250 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(done(), isTrue, reason: 'named async/Flutter boundary completed');
  }

  Future<void> show(WidgetTester tester, AppState app, Widget screen) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      // Drive fake-zone continuations before leaving the widget test zone.
      bool closed = false;
      unawaited(app.close().then((_) {
        closed = true;
      }));
      await driveUntil(tester, () => closed);
      apps.remove(app);
    });
    await tester
        .pumpWidget(AppScope(state: app, child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  Future<void> startVerb(WidgetTester tester, AppState app) async {
    await show(tester, app, const VerbDeckScreen());
    await tester.tap(find.text('Oturumu başlat'));
    // UI/SQLite startup settling only. Race experiments below use explicit gates.
    for (int i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(CardStack).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.byType(CardStack), findsOneWidget);
  }

  Future<void> rewardPublished(AppState app) {
    final Completer<void> result = Completer<void>();
    final int before = app.rewardSerial;
    void listener() {
      if (app.rewardSerial > before && !result.isCompleted) {
        app.removeListener(listener);
        result.complete();
      }
    }

    app.addListener(listener);
    return result.future.timeout(deadline);
  }

  // Advances Flutter callbacks and real IO until a NAMED completion event.
  // This is not the delay injection: all experimental order is enforced by
  // OperationGate, and no gate is released on elapsed time.

  Future<AppState> bootFreeQuiz() async {
    final path = '${temp.path}/synthetic-content.db';
    final content = await databaseFactoryFfi.openDatabase(path);
    for (final entry in {'tu': 'testes', 'nous': 'testons', 'vous': 'testez'}.entries) {
      await content.insert('conjugations', {
        'verb_id': 'probe', 'tense': 'present', 'person': entry.key, 'form': entry.value,
      });
    }
    await content.close();
    final bytes = await File(path).readAsBytes();
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (ByteData? message) async =>
            const StringCodec().decodeMessage(message) == 'assets/db/content.db'
                ? ByteData.sublistView(bytes) : null);
    final app = await boot();
    await app.setReducedMotion(false);
    await app.verbCards.save(const SrsCard(refId: refA, box: 2,
        status: CardStatus.learning, timesSeen: 4, timesRight: 3, lapses: 1));
    return app;
  }

  for (final failure in ['card', 'game']) {
    testWidgets('D3 widget $failure failure preserves answer and permits one retry',
        (tester) async {
      final app = (await tester.runAsync(bootFreeQuiz))!;
      final before = (await tester.runAsync(() => snapshot(app)))!;
      await show(tester, app, const QuizScreen());
      await tester.tap(find.text('Başla'));
      await driveUntil(tester, () => find.text('teste').evaluate().isNotEmpty);
      expect(find.text('1 / 1'), findsOneWidget);
      final target = failure == 'card' ? 'INSERT ON card_state' : 'UPDATE ON game_profile';
      await tester.runAsync(() => app.db.progress.execute(
          "CREATE TRIGGER d3_fail BEFORE $target BEGIN SELECT RAISE(ABORT,'D3_$failure'); END"));
      await tester.tap(find.text('teste'));
      var drained = false;
      unawaited(app.progress.run(() async {}).then((_) => drained = true));
      await driveUntil(tester, () => drained);
      await tester.pump(const Duration(seconds: 2));
      final failed = (await tester.runAsync(() => snapshot(app)))!;
      report('D3_widget_$failure', [], {
        'before': before, 'after': failed,
        'finished': find.text('Quiz bitti').evaluate().isNotEmpty,
        'result_score': find.text('1 / 1 doğru').evaluate().isNotEmpty,
        'retry_error': find.textContaining('Cevap kaydedilemedi').evaluate().isNotEmpty,
        'framework_exception': tester.takeException()?.toString(),
      });
      expect(failed, before, reason: 'one quiz answer must roll back all stores');
      expect(find.text('Quiz bitti'), findsNothing);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.textContaining('Cevap kaydedilemedi'), findsOneWidget);
      await tester.runAsync(() => app.db.progress.execute('DROP TRIGGER d3_fail'));
      final boundary = gate();
      final probe = probes[app]!;
      probe.transactionGate = boundary;
      probe.events.clear();
      await tester.tap(find.text('teste'));
      await driveUntil(tester, () => boundary.entered.isCompleted);
      await tester.tap(find.text('testes'));
      await tester.tap(find.text('teste'));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Quiz bitti'), findsNothing);
      expect((await tester.runAsync(() => snapshot(app)))!, before);
      boundary.release();
      await driveUntil(tester, () => app.rewardSerial == 1);
      await tester.tap(find.text('teste'));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Quiz bitti'), findsOneWidget);
      expect(find.text('1 / 1 doğru'), findsOneWidget);
      expect(app.verbCards.stateFor(refA).timesSeen, 5);
      expect(app.verbCards.stateFor(refA).timesRight, 4);
      expect(app.verbCards.stateFor(refA).box, 3);
      expect(app.stats.today()['quiz_total'], 1);
      expect(app.stats.today()['quiz_correct'], 1);
      expect(app.stats.today()['cards_swiped'], 0);
      expect(app.stats.today()['new_learned'], 0);
      expect(app.game.profile.xp, 12);
      expect(app.game.profile.coins, 1);
      expect(app.game.profile.bestCombo, 1);
      expect(app.game.profile.totalVerbs, 0);
      expect(probe.events.where((e) => e == 'transaction.committed'), hasLength(1));
      aligned((await tester.runAsync(() => snapshot(app)))!);
      expect(tester.takeException(), isNull);
    });
  }

  for (final type in AnswerCardType.values) {
    test('D3 atomic ${type.name} quiz reads the preceding committed same-card answer', () async {
      final app = await boot();
      final store = type == AnswerCardType.word ? app.cards : app.verbCards;
      final ref = type == AnswerCardType.word ? 'word-probe' : refA;
      final initial = SrsCard(refId: ref, box: 2, status: CardStatus.learning,
          timesSeen: 4, timesRight: 3, lapses: 1);
      await store.save(initial);
      final at = DateTime.now();
      final boundary = gate();
      probes[app]!.transactionGate = boundary;
      final canonical = app.recordAnswer(cardType: type,
          refId: ref, action: SwipeAction.dontKnow, now: at);
      await boundary.entered.future.timeout(deadline);
      final quiz = app.recordQuizAnswer(cardType: type,
          refId: ref, correct: true, combo: 1, now: at);
      expect(cardFields(store.stateFor(ref)), cardFields(initial));
      boundary.release();
      final committed = await canonical;
      final result = await quiz;
      final expected = BoxScheduler.applyQuizResult(committed.after, correct: true, now: at);
      final stale = BoxScheduler.applyQuizResult(initial, correct: true, now: at);
      expect(cardFields(result), cardFields(expected));
      expect(cardFields(result), isNot(cardFields(stale)));
      expect(cardFields(store.stateFor(ref)), cardFields(expected));
      expect(cardFields(await store.readState(app.db.progress, ref)), cardFields(expected));
      expect([result.box, result.timesSeen, result.timesRight, result.lapses], [1, 6, 4, 2]);
      expect(app.stats.today()['cards_swiped'], 1);
      expect(app.stats.today()['new_learned'], 0);
      expect(app.stats.today()['quiz_total'], 1);
      expect(app.stats.today()['quiz_correct'], 1);
      expect(app.game.profile.xp, type == AnswerCardType.word ? 16 : 19);
      expect(app.game.profile.coins, 1);
      expect(app.game.profile.totalCards, 1);
      expect(app.game.profile.totalVerbs, type == AnswerCardType.word ? 0 : 1);
      expect(app.rewardSerial, 2);
      aligned(await snapshot(app));
      await app.close();
      final reopened = await boot();
      final reloaded = type == AnswerCardType.word ? reopened.cards : reopened.verbCards;
      expect(cardFields(reloaded.stateFor(ref)), cardFields(expected));
      expect(cardFields(await reloaded.readState(reopened.db.progress, ref)), cardFields(expected));
      expect(reopened.stats.today()['quiz_total'], 1);
      expect(reopened.game.profile.xp, type == AnswerCardType.word ? 16 : 19);
      aligned(await snapshot(reopened));
    });
  }

  test('D3 API preserves quiz rules and publishes every cache only after commit', () async {
    for (final type in AnswerCardType.values) {
      final app = await boot(type.name);
      final store = type == AnswerCardType.word ? app.cards : app.verbCards;
      final ref = type == AnswerCardType.word ? 'word-probe' : refA;
      var total = 0;
      for (final scenario in ['correct', 'wrong', 'archived']) {
        final at = DateTime.now().toLocal();
        final old = SrsCard(refId: ref, box: scenario == 'archived' ? 5 : 2,
            status: scenario == 'archived' ? CardStatus.archived : CardStatus.learning,
            starred: true, timesSeen: 4, timesRight: 3, lapses: 1);
        await store.save(old);
        final right = scenario != 'wrong';
        Map<String, Object?> view() => {
          'card': cardFields(store.stateFor(ref)),
          'daily': Map<String, int>.of(app.stats.today()),
          'profile': profileFields(app.game.profile),
          'quests': {for (final q in app.game.quests) q.id: [q.progress, q.claimed]},
          'achievements': app.game.unlockedAchievements.toList()..sort(),
          'reward': [app.rewardSerial, app.lastReward.xp, app.lastReward.coins],
        };
        final before = view();
        final observed = <Map<String, Object?>>[];
        void listener() => observed.add(view());
        app.addListener(listener);
        final probe = probes[app]!;
        probe.events.clear();
        probe.onTransactionCommitted = () {
          expect(view(), before);
          expect(observed, isEmpty);
          probe.rejectReads = true;
        };
        final result = await app.recordQuizAnswer(cardType: type, refId: ref,
            correct: right, combo: 10, now: at);
        probe.onTransactionCommitted = null;
        probe.rejectReads = false;
        app.removeListener(listener);
        total++;
        expect(observed, [view()]);
        expect(probe.events.where((e) => e == 'transaction.committed'), hasLength(1));
        final expected = BoxScheduler.applyQuizResult(old, correct: right, now: at);
        expect(cardFields(result), cardFields(expected));
        expect(cardFields(await store.readState(app.db.progress, ref)), cardFields(expected));
        expect(app.stats.today()['cards_swiped'], 0);
        expect(app.stats.today()['new_learned'], 0);
        expect(app.stats.today()['quiz_total'], total);
        expect(app.game.profile.totalCards, 0);
        expect(app.game.profile.totalVerbs, 0);
        expect(app.game.profile.bestCombo, 10);
        expect(app.game.unlockedAchievements, contains('combo_10'));
        final rows = await app.db.progress.query('daily_stats');
        expect(rows.single['day'], DailyStatsStore.keyFor(at));
        final quests = await app.db.progress.query('daily_quests');
        expect(quests.every((q) => q['day'] == DailyStatsStore.keyFor(at)), isTrue);
        aligned(await snapshot(app));
      }
      expect(app.stats.today()['quiz_correct'], 2);
      expect(app.game.profile.xp, 26);
      expect(app.game.profile.coins, 2);
    }
  });

  Map<String, Object?> completionCaches(AppState app) => {
        'journey_stars': app.journey.resultFor('d2-station')?.stars,
        'journey_correct': app.journey.resultFor('d2-station')?.bestCorrect,
        'journey_total': app.journey.resultFor('d2-station')?.bestTotal,
        'stories': {
          for (final e in app.practice.stories.entries)
            e.key: [e.value.nodeId, e.value.completed,
              e.value.bestCorrect, e.value.bestTotal],
        },
        'sentences': {
          for (final e in app.practice.sentences.entries)
            e.key: [e.value.attempts, e.value.solved, e.value.bestScore],
        },
        'daily': Map<String, int>.of(app.stats.today()),
        'game': profileFields(app.game.profile),
        'quests': {
          for (final q in app.game.quests) q.id: [q.progress, q.claimed],
        },
        'achievements': app.game.unlockedAchievements.toList()..sort(),
        'reward': [app.rewardSerial, app.lastReward.xp, app.lastReward.coins,
          app.lastReward.completedQuests, app.lastReward.unlockedAchievements,
          app.lastReward.levelUp],
      };

  Future<Map<String, Object?>> completionSnapshot(AppState app) async => {
        'caches': completionCaches(app),
        for (final table in ['journey_progress', 'story_progress',
          'sentence_progress', 'daily_stats', 'game_profile',
          'daily_quests', 'achievements'])
          table: await app.db.progress.query(table, orderBy: '1'),
      };


  Future<void> stationFinalization(AppState app) async {
    await app.completeStationQuiz(stationId: 'd2-station', stars: 3,
        correct: 8, total: 8, combo: 8);
  }

  test('Step09 normal success preserves station and quiz reward events', () async {
    final app = await boot();
    final events = <Map<String, Object?>>[];
    app.addListener(() => events.add(completionCaches(app)));
    await stationFinalization(app);
    final after = await completionSnapshot(app);
    report('Step09_success', [], {'after': after, 'notifications': events});
    expect(app.game.profile.xp, 256);
    expect(app.game.profile.coins, 42);
    expect(app.game.profile.stationsPassed, 1);
    expect(app.game.profile.totalAnswers, 8);
    expect(app.game.profile.totalCorrect, 8);
    expect(app.game.profile.bestCombo, 8);
    expect(app.stats.today()['quiz_total'], 8);
    expect(app.game.quests.singleWhere((q) => q.id == 'quiz').claimed, isTrue);
    expect(app.game.unlockedAchievements, isEmpty);
    expect(events.map((e) => (e['reward']! as List).take(3).toList()).toList(),
        [[1, 60, 24], [2, 196, 18]]);
    final finalCaches = completionCaches(app)..remove('reward');
    for (final event in events) {
      expect(Map.of(event)..remove('reward'), finalCaches,
          reason: 'every listener sees all committed caches');
    }
    aligned(await snapshot(app));
  });

  for (final failure in ['daily', 'late_game', 'journey', 'station_game']) {
    test('Step09 $failure failure rolls back entire station finalization', () async {
      final app = await boot();
      final before = await completionSnapshot(app);
      final target = switch (failure) {
        'daily' => 'INSERT ON daily_stats',
        'journey' => 'INSERT ON journey_progress',
        'station_game' => 'UPDATE ON game_profile WHEN NEW.stations_passed > OLD.stations_passed',
        _ => 'UPDATE ON game_profile WHEN NEW.total_answers > OLD.total_answers',
      };
      await app.db.progress.execute("CREATE TRIGGER step09_fail BEFORE $target "
          "BEGIN SELECT RAISE(ABORT,'Step09_$failure'); END");
      Object? caught;
      try { await stationFinalization(app); } catch (error) { caught = error; }
      expect(caught, isA<DatabaseException>());
      expect(caught.toString(), contains('Step09_$failure'));
      final after = await completionSnapshot(app);
      report('Step09_$failure', [], {'exception': caught.toString(),
          'before': before, 'after': after});
      expect(after, before, reason: 'whole station attempt must roll back');
      await app.db.progress.execute('DROP TRIGGER step09_fail');
      final probe = probes[app]!;
      var commits = 0;
      probe.onTransactionCommitted = () {
        commits++;
        expect(completionCaches(app), before['caches'],
            reason: 'no publication before the outer transaction returns');
        probe.rejectReads = true;
      };
      await stationFinalization(app);
      probe.onTransactionCommitted = null;
      probe.rejectReads = false;
      expect(commits, 1);
      expect(app.game.profile.xp, 256);
      expect(app.game.profile.coins, 42);
      expect(app.game.profile.stationsPassed, 1);
      expect(app.stats.today()['quiz_total'], 8);
      expect(app.rewardSerial, 2);
      final committed = await completionSnapshot(app);
      await app.close();
      final reopened = await boot();
      final reloaded = await completionSnapshot(reopened);
      for (final key in committed.keys.where((k) => k != 'caches')) {
        expect(reloaded[key], committed[key], reason: '$key survives reopen');
      }
      expect(completionCaches(reopened)..remove('reward'),
          (Map.of(committed['caches']! as Map)..remove('reward')));
      await stationFinalization(reopened);
      expect(reopened.game.profile.xp, 352); // Ordinary quiz reward only.
      expect(reopened.game.profile.coins, 50);
      expect(reopened.game.profile.stationsPassed, 1);
      expect(reopened.stats.today()['quiz_total'], 16);
      expect(reopened.rewardSerial, 1);
      expect(await reopened.db.progress.query('journey_progress'), hasLength(1));
      aligned(await snapshot(reopened));
    });
  }

  testWidgets('Step09 station final save failure offers persistence-only retry', (tester) async {
    final app = (await tester.runAsync(bootFreeQuiz))!;
    const station = JourneyStation(id: 'd2-station', level: CefrLevel.a1,
        indexInLevel: 0, kind: StationKind.verbs, title: 'Step09 station',
        wordIds: [], verbRefIds: [], questionCount: 1);
    final before = (await tester.runAsync(() => completionSnapshot(app)))!;
    await show(tester, app, const SizedBox.shrink());
    await tester.pumpWidget(AppScope(state: app, child: const MaterialApp(
        home: StationQuizScreen(station: station))));
    await driveUntil(tester, () => find.textContaining('tester ·').evaluate().isNotEmpty);
    final person = tester.widget<Text>(find.textContaining('tester ·')).data!.split(' · ').last;
    final answer = {'je': 'teste', 'tu': 'testes', 'nous': 'testons', 'vous': 'testez'}[person]!;
    await tester.runAsync(() => app.db.progress.execute(
        "CREATE TRIGGER step09_fail BEFORE INSERT ON daily_stats "
        "BEGIN SELECT RAISE(ABORT,'Step09_widget'); END"));
    await tester.tap(find.text(answer));
    await tester.pump(const Duration(seconds: 2));
    var drained = false;
    unawaited(app.progress.run(() async {}).then((_) => drained = true));
    await driveUntil(tester, () => drained);
    await tester.pump(const Duration(seconds: 2));
    final failed = (await tester.runAsync(() => completionSnapshot(app)))!;
    report('Step09_widget', [], {'before': before, 'after': failed,
      'result': find.text('Durak geçildi').evaluate().isNotEmpty,
      'retry': find.byKey(const ValueKey('station_save_retry')).evaluate().isNotEmpty,
      'exception': tester.takeException()?.toString()});
    expect(failed, before, reason: 'UI finalization must leave no partial station');
    expect(find.text('Durak geçildi'), findsNothing);
    expect(find.byKey(const ValueKey('station_save_retry')), findsOneWidget);
    expect(find.text('Sonuç kaydedilemedi. Tekrar deneyin.'), findsOneWidget);
    // The final answer is retained; option taps cannot consume it again.
    await tester.tap(find.text(answer));
    await tester.pump(const Duration(seconds: 2));
    expect(await tester.runAsync(() => completionSnapshot(app)), before);
    await tester.runAsync(() => app.db.progress.execute('DROP TRIGGER step09_fail'));
    final boundary = gate();
    probes[app]!.transactionGate = boundary;
    final retry = find.byKey(const ValueKey('station_save_retry'));
    await tester.tap(retry);
    await tester.tap(retry); // Same frame, before the retry button rebuilds.
    await driveUntil(tester, () => boundary.entered.isCompleted);
    expect(find.text('Durak geçildi'), findsNothing);
    expect(await tester.runAsync(() => completionSnapshot(app)), before);
    boundary.release();
    await driveUntil(tester, () => find.text('Durak geçildi').evaluate().isNotEmpty);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('1 / 1 doğru'), findsOneWidget);
    expect(app.game.profile.totalAnswers, 1);
    expect(app.game.profile.totalCorrect, 1);
    expect(app.game.profile.bestCombo, 1);
    expect(app.game.profile.stationsPassed, 1);
    expect(app.game.profile.xp, 72);
    expect(app.game.profile.coins, 25);
    expect(app.stats.today()['quiz_total'], 1);
    expect(app.rewardSerial, 2);
    expect(probes[app]!.events.where((e) => e == 'transaction.committed'), hasLength(1));
    expect(tester.takeException(), isNull);
    aligned((await tester.runAsync(() => snapshot(app)))!);
  });

  test('Step09 accepted finalization drains atomically before close', () async {
    final app = await boot();
    final before = await completionSnapshot(app);
    final boundary = gate();
    probes[app]!.transactionGate = boundary;
    final action = stationFinalization(app);
    await boundary.entered.future;
    var closed = false;
    final closing = app.close().then((_) => closed = true);
    await expectLater(stationFinalization(app), throwsA(isA<ProgressUnavailable>()));
    expect(closed, isFalse);
    expect(await completionSnapshot(app), before);
    boundary.release();
    await action;
    await closing;
    final reopened = await boot();
    expect(reopened.journey.resultFor('d2-station')!.stars, 3);
    expect(reopened.game.profile.xp, 256);
    expect(reopened.game.profile.coins, 42);
    expect(reopened.game.profile.stationsPassed, 1);
    expect(reopened.stats.today()['quiz_total'], 8);
    aligned(await snapshot(reopened));
  });

  test('Step09 success parity includes replays improvements and achievements', () async {
    final legacy = await boot('legacy');
    final atomic = await boot('atomic');
    final at = DateTime.now();
    final attempts = [
      (id: 'd2-station', stars: 0, correct: 2, total: 8, combo: 2),
      (id: 'd2-station', stars: 2, correct: 7, total: 8, combo: 7),
      (id: 'd2-station', stars: 3, correct: 8, total: 8, combo: 8),
      (id: 'd2-station', stars: 3, correct: 8, total: 8, combo: 8),
      for (var i = 0; i < 4; i++)
        (id: 'extra-$i', stars: 3, correct: 10, total: 10, combo: 10),
    ];
    for (final attempt in attempts) {
      final oldEvents = <List<Object?>>[];
      final newEvents = <List<Object?>>[];
      void oldListener() => oldEvents.add(List.of(completionCaches(legacy)['reward']! as List));
      void newListener() => newEvents.add(List.of(completionCaches(atomic)['reward']! as List));
      legacy.addListener(oldListener);
      atomic.addListener(newListener);
      await legacy.recordStation(stationId: attempt.id, stars: attempt.stars,
          correct: attempt.correct, total: attempt.total);
      await legacy.recordActivity(quizTotal: attempt.total,
          quizCorrect: attempt.correct, combo: attempt.combo, now: at);
      await atomic.completeStationQuiz(stationId: attempt.id, stars: attempt.stars,
          correct: attempt.correct, total: attempt.total, combo: attempt.combo, now: at);
      legacy.removeListener(oldListener);
      atomic.removeListener(newListener);
      expect(completionCaches(atomic), completionCaches(legacy));
      expect(newEvents, oldEvents);
      final oldDb = await completionSnapshot(legacy);
      final newDb = await completionSnapshot(atomic);
      for (final table in ['journey_progress', 'daily_stats', 'game_profile', 'daily_quests', 'achievements']) {
        List<Map> withoutTimes(Object? rows) => (rows! as List)
            .map((row) => Map.of(row as Map)..remove('updated_at')..remove('unlocked_at')).toList();
        expect(withoutTimes(newDb[table]), withoutTimes(oldDb[table]), reason: table);
      }
    }
    expect(atomic.game.unlockedAchievements, containsAll(['combo_10', 'station_5']));
    final row = (await atomic.db.progress.query('journey_progress',
        where: 'station_id = ?', whereArgs: ['d2-station'])).single;
    expect(row['updated_at'], at.millisecondsSinceEpoch);
  });

  test('Step09 late failure rolls back both game operations achievements and claims', () async {
    final app = await boot();
    for (var i = 0; i < 4; i++) {
      await app.recordStation(stationId: 'seed-$i', stars: 1, correct: 6, total: 8);
    }
    final before = await completionSnapshot(app);
    await app.db.progress.execute(
        'CREATE TRIGGER step09_fail BEFORE UPDATE ON game_profile '
        'WHEN NEW.total_answers > OLD.total_answers '
        "BEGIN SELECT RAISE(ABORT,'Step09_achievements'); END");
    Future<void> complete() => app.completeStationQuiz(stationId: 'd2-station',
        stars: 3, correct: 10, total: 10, combo: 10);
    await expectLater(complete(), throwsA(isA<DatabaseException>()));
    expect(await completionSnapshot(app), before);
    await app.db.progress.execute('DROP TRIGGER step09_fail');
    await complete();
    expect(app.game.unlockedAchievements, containsAll(['combo_10', 'station_5']));
    expect(app.game.profile.stationsPassed, 5);
    expect(app.game.profile.totalAnswers, 10);
    expect(app.stats.today()['quiz_total'], 10);
    expect(app.game.quests.singleWhere((q) => q.id == 'quiz').claimed, isTrue);
    expect(await app.db.progress.query('achievements'), hasLength(2));
    aligned(await snapshot(app));
  });

  Future<void> checkCompletionFailure(String kind, String failure) async {
    final app = await boot();
    if (kind == 'story') await app.saveStoryNode('d2-story', 'A');
    final before = await completionSnapshot(app);
    final notifications = <Map<String, Object?>>[];
    void listener() => notifications.add(completionCaches(app));
    app.addListener(listener);
    addTearDown(() => app.removeListener(listener));
    Future<void> action() => switch (kind) {
      'station' => app.recordStation(
          stationId: 'd2-station', stars: 3, correct: 8, total: 8),
      'story' => app.completeStory(
          storyId: 'd2-story', nodeId: 'B', correct: 8, total: 8),
      _ => app.recordSentenceAttempt(
          promptId: 'd2-sentence', correct: true, score: 100, combo: 10),
    };
    final String marker = 'D2_${kind}_$failure';
    final target = failure == 'daily' ? 'INSERT ON daily_stats' : 'UPDATE ON game_profile';
    await app.db.progress.execute(
        "CREATE TRIGGER d2_fail BEFORE $target BEGIN SELECT RAISE(ABORT,'$marker'); END");
    Object? caught;
    try {
      await action();
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<DatabaseException>());
    expect(caught.toString(), contains(marker));
    final afterFailure = await completionSnapshot(app);
    report('D2_${kind}_$failure', [], {
      'exception': caught.toString(), 'before': before, 'after': afterFailure,
      'notifications': notifications,
    });
    expect(afterFailure, before, reason: 'the entire completion action rolls back');
    expect(notifications, isEmpty);
    await app.db.progress.execute('DROP TRIGGER d2_fail');

    // This hook runs after SQLite COMMIT but BEFORE the outer transaction
    // future returns. Publishing inside its callback would fail this check.
    final probe = probes[app]!;
    probe.events.clear();
    var commitObservations = 0;
    probe.onTransactionCommitted = () {
      commitObservations++;
      expect(completionCaches(app), before['caches']);
      expect(notifications, isEmpty);
    };
    await action();
    probe.onTransactionCommitted = null;
    expect(commitObservations, 1);
    expect(probe.events.where((e) => e == 'transaction.committed'), hasLength(1));
    expect(notifications, [completionCaches(app)],
        reason: 'one notification observes every committed cache and reward');
    expect(app.rewardSerial, 1);
    if (kind == 'station') {
      expect(app.journey.resultFor('d2-station')!.stars, 3);
      expect(app.game.profile.stationsPassed, 1);
      expect(app.game.profile.xp, 60);
      expect(app.game.profile.coins, 24);
      expect(app.stats.today()['quiz_total'], 0);
    } else if (kind == 'story') {
      final story = app.practice.story('d2-story')!;
      expect([story.nodeId, story.completed, story.bestCorrect, story.bestTotal],
          ['B', true, 8, 8]);
      expect(app.stats.today()['quiz_total'], 8);
      expect(app.stats.today()['quiz_correct'], 8);
      expect(app.game.profile.xp, 236); // 96 normal + 40 first + 100 quest.
      expect(app.game.profile.coins, 26);
      expect(app.game.quests.singleWhere((q) => q.id == 'quiz').claimed, isTrue);
    } else {
      final sentence = app.practice.sentence('d2-sentence')!;
      expect([sentence.attempts, sentence.solved, sentence.bestScore], [1, true, 100]);
      expect(app.stats.today()['quiz_total'], 1);
      expect(app.stats.today()['quiz_correct'], 1);
      expect(app.game.profile.xp, 27);
      expect(app.game.profile.coins, 4);
      expect(app.game.unlockedAchievements, contains('combo_10'));
    }
    aligned(await snapshot(app));
    final committed = await completionSnapshot(app);
    await app.close();
    final reopened = await boot();
    final reloaded = await completionSnapshot(reopened);
    for (final key in committed.keys.where((key) => key != 'caches')) {
      expect(reloaded[key], committed[key], reason: '$key survives reopen');
    }
    final oldCaches = Map<String, Object?>.of(committed['caches']! as Map<String, Object?>)
      ..remove('reward');
    final newCaches = Map<String, Object?>.of(reloaded['caches']! as Map<String, Object?>)
      ..remove('reward');
    expect(newCaches, oldCaches); // Reward publication is intentionally transient.
    if (kind == 'station') {
      await reopened.recordStation(stationId: 'd2-station', stars: 3, correct: 8, total: 8);
      expect(reopened.game.profile.xp, 60);
      expect(reopened.game.profile.coins, 24);
      expect(reopened.game.profile.stationsPassed, 1);
      expect(reopened.rewardSerial, 0);
      expect(await reopened.db.progress.query('journey_progress'), hasLength(1));
    } else if (kind == 'story') {
      await reopened.completeStory(storyId: 'd2-story', nodeId: 'B', correct: 8, total: 8);
      expect(reopened.game.profile.xp, 332); // Only another normal 96 XP.
      expect(reopened.game.profile.coins, 34);
      expect(reopened.stats.today()['quiz_total'], 16);
    } else {
      await reopened.recordSentenceAttempt(promptId: 'd2-sentence', correct: true, score: 100, combo: 10);
      expect(reopened.practice.sentence('d2-sentence')!.attempts, 2);
      expect(reopened.game.profile.xp, 39);
      expect(reopened.game.profile.coins, 5);
      expect(reopened.stats.today()['quiz_total'], 2);
    }
    aligned(await snapshot(reopened));
  }

  test('D2 A station reward failure rolls back journey and preserves retry',
      () => checkCompletionFailure('station', 'game'));
  test('D2 B story daily failure rolls back completion and preserves retry',
      () => checkCompletionFailure('story', 'daily'));
  test('D2 C story game failure rolls back completion and daily activity',
      () => checkCompletionFailure('story', 'game'));
  test('D2 D sentence daily failure preserves first solve and attempt count',
      () => checkCompletionFailure('sentence', 'daily'));
  test('D2 E sentence game failure rolls back attempt and daily activity',
      () => checkCompletionFailure('sentence', 'game'));
  test('D1 A flag INSERT failure preserves cache and retry flags once',
      () async {
    final app = await boot();
    const ref = 'd1-flag';
    final before = await snapshot(app);
    expect(app.flags.isFlagged(ref), isFalse);
    expect(await app.flags.all(), isEmpty);
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE INSERT ON flagged_cards BEGIN SELECT RAISE(ABORT,'D1_FLAG_INSERT'); END");
    await expectLater(
        app.toggleFlag(refId: ref, cardType: 'word', lemma: 'essai'),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_FLAG_INSERT'))));
    final rows = await app.flags.all();
    report('D1_A_failed_insert', [], {
      'db': rows,
      'cache_flagged': app.flags.isFlagged(ref),
    });
    expect(rows, isEmpty);
    expect(await snapshot(app), before);
    expect(app.flags.isFlagged(ref), isFalse);
    expect(app.flags.count, 0);
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await app.toggleFlag(refId: ref, cardType: 'word', lemma: 'essai');
    expect((await app.flags.all()).single['ref_id'], ref);
    expect(app.flags.isFlagged(ref), isTrue);
    expect(app.flags.count, 1);
    expect(await snapshot(app), before);
  });

  test('D1 B flag DELETE failure preserves cache and retry unflags', () async {
    final app = await boot();
    const ref = 'd1-flag';
    await app.toggleFlag(refId: ref, cardType: 'word');
    final originalRows = await app.flags.all();
    final before = await snapshot(app);
    expect(originalRows, hasLength(1));
    expect(app.flags.isFlagged(ref), isTrue);
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE DELETE ON flagged_cards BEGIN SELECT RAISE(ABORT,'D1_FLAG_DELETE'); END");
    await expectLater(
        app.toggleFlag(refId: ref, cardType: 'word'),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_FLAG_DELETE'))));
    final rows = await app.flags.all();
    report('D1_B_failed_delete', [], {
      'db': rows,
      'cache_flagged': app.flags.isFlagged(ref),
    });
    expect(rows, originalRows);
    expect(await snapshot(app), before);
    expect(app.flags.isFlagged(ref), isTrue);
    expect(app.flags.count, 1);
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await app.toggleFlag(refId: ref, cardType: 'word');
    expect(await app.flags.all(), isEmpty);
    expect(app.flags.isFlagged(ref), isFalse);
    expect(app.flags.count, 0);
    expect(await snapshot(app), before);
  });

  test('D1 C journey INSERT failure preserves first-pass retry reward',
      () async {
    final app = await boot();
    const station = 'd1-station';
    final before = await snapshot(app);
    expect(app.journey.resultFor(station), isNull);
    expect(await app.db.progress.query('journey_progress'), isEmpty);
    Future<void> complete() => app.recordStation(
        stationId: station, stars: 3, correct: 8, total: 8);
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE INSERT ON journey_progress BEGIN SELECT RAISE(ABORT,'D1_JOURNEY'); END");
    await expectLater(
        complete(),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_JOURNEY'))));
    final rows = await app.db.progress.query('journey_progress');
    report('D1_C_failed_journey', [], {
      'db': rows,
      'cache_stars': app.journey.resultFor(station)?.stars,
    });
    expect(rows, isEmpty);
    expect(await snapshot(app), before);
    expect(app.journey.resultFor(station), isNull);
    expect(app.journey.passedCount, 0);
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await complete();
    final row = (await app.db.progress.query('journey_progress')).single;
    final result = app.journey.resultFor(station)!;
    expect(row['station_id'], station);
    expect(row['stars'], result.stars);
    expect(row['best_correct'], result.bestCorrect);
    expect(row['best_total'], result.bestTotal);
    expect(result.stars, 3);
    expect(result.bestCorrect, 8);
    expect(result.bestTotal, 8);
    expect(app.game.profile.xp, 60);
    expect(app.game.profile.coins, 24);
    expect(app.game.profile.stationsPassed, 1);
    expect(app.rewardSerial, 1);
    final rewarded = await snapshot(app);
    aligned(rewarded);
    await complete();
    expect(await app.db.progress.query('journey_progress'), hasLength(1));
    expect(await snapshot(app), rewarded,
        reason: 'successful repeated station result grants no first reward');
  });

  test('D1 D sentence INSERT failure preserves first solve and attempt count',
      () async {
    final app = await boot();
    const prompt = 'd1-sentence';
    final before = await snapshot(app);
    expect(app.practice.sentence(prompt), isNull);
    expect(await app.db.progress.query('sentence_progress'), isEmpty);
    Future<void> solve() => app.recordSentenceAttempt(
        promptId: prompt, correct: true, score: 100, combo: 1);
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE INSERT ON sentence_progress BEGIN SELECT RAISE(ABORT,'D1_SENTENCE'); END");
    await expectLater(
        solve(),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_SENTENCE'))));
    final rows = await app.db.progress.query('sentence_progress');
    final failed = app.practice.sentence(prompt);
    report('D1_D_failed_sentence', [], {
      'db': rows,
      'cache_attempts': failed?.attempts,
      'cache_solved': failed?.solved,
      'cache_best_score': failed?.bestScore,
    });
    expect(rows, isEmpty);
    expect(await snapshot(app), before);
    expect(failed, isNull);
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await solve();
    final row = (await app.db.progress.query('sentence_progress')).single;
    final result = app.practice.sentence(prompt)!;
    expect(row['attempts'], 1);
    expect(row['solved'], 1);
    expect(row['best_score'], 100);
    expect(result.attempts, row['attempts']);
    expect(result.solved, isTrue);
    expect(result.bestScore, row['best_score']);
    expect(app.game.profile.xp, 27); // 12 correct + 15 first solve.
    expect(app.game.profile.coins, 4); // 1 correct + 3 first solve.
    expect(app.stats.today()['quiz_total'], 1);
    expect(app.stats.today()['quiz_correct'], 1);
    aligned(await snapshot(app));
    await app.recordSentenceAttempt(
        promptId: prompt, correct: false, score: 20, combo: 0);
    expect(app.practice.sentence(prompt)!.attempts, 2);
    expect(app.practice.sentence(prompt)!.solved, isTrue);
    expect(app.practice.sentence(prompt)!.bestScore, 100);
    await solve();
    final repeated = (await app.db.progress.query('sentence_progress')).single;
    expect(repeated['attempts'], 3);
    expect(repeated['solved'], 1);
    expect(repeated['best_score'], 100);
    expect(app.practice.sentence(prompt)!.attempts, 3);
    expect(app.game.profile.xp, 41); // One bonus, two right, one wrong.
    expect(app.game.profile.coins, 5);
    expect(app.stats.today()['quiz_total'], 3);
    expect(app.stats.today()['quiz_correct'], 2);
    aligned(await snapshot(app));
  });

  test('D1 E story completion INSERT failure preserves first-completion retry',
      () async {
    final app = await boot();
    const story = 'd1-story';
    await app.saveStoryNode(story, 'A');
    final originalRows = await app.db.progress.query('story_progress');
    final original = app.practice.story(story)!;
    final before = await snapshot(app);
    expect(original.completed, isFalse);
    Future<void> complete() => app.completeStory(
        storyId: story, nodeId: 'B', correct: 1, total: 1);
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE INSERT ON story_progress WHEN NEW.completed = 1 BEGIN SELECT RAISE(ABORT,'D1_STORY_COMPLETE'); END");
    await expectLater(
        complete(),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_STORY_COMPLETE'))));
    final rows = await app.db.progress.query('story_progress');
    final failed = app.practice.story(story)!;
    report('D1_E_failed_story_completion', [], {
      'db': rows,
      'cache_node': failed.nodeId,
      'cache_completed': failed.completed,
      'cache_best_correct': failed.bestCorrect,
      'cache_best_total': failed.bestTotal,
    });
    expect(rows, originalRows);
    expect(await snapshot(app), before);
    expect(failed.completed, isFalse);
    expect(failed.nodeId, original.nodeId);
    expect(failed.bestCorrect, original.bestCorrect);
    expect(failed.bestTotal, original.bestTotal);
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await complete();
    final row = (await app.db.progress.query('story_progress')).single;
    final result = app.practice.story(story)!;
    expect(row['completed'], 1);
    expect(row['node_id'], 'B');
    expect(result.completed, isTrue);
    expect(result.nodeId, row['node_id']);
    expect(result.bestCorrect, row['best_correct']);
    expect(result.bestTotal, row['best_total']);
    expect(result.bestCorrect, 1);
    expect(result.bestTotal, 1);
    expect(app.game.profile.xp, 52); // 12 correct + 40 first completion.
    expect(app.game.profile.coins, 9);
    expect(app.stats.today()['quiz_total'], 1);
    expect(app.stats.today()['quiz_correct'], 1);
    aligned(await snapshot(app));
    await app.completeStory(
        storyId: story, nodeId: 'B', correct: 1, total: 2);
    final repeated = (await app.db.progress.query('story_progress')).single;
    expect(repeated['best_correct'], 1);
    expect(repeated['best_total'], 1);
    expect(app.practice.story(story)!.bestCorrect, 1);
    expect(app.practice.story(story)!.bestTotal, 1);
    expect(app.game.profile.xp, 66); // Only 12 correct + 2 wrong on repeat.
    expect(app.game.profile.coins, 10);
    expect(app.stats.today()['quiz_total'], 3);
    expect(app.stats.today()['quiz_correct'], 2);
    aligned(await snapshot(app));
  });

  test('D1 F story node INSERT failure retains node A until retry persists B',
      () async {
    final app = await boot();
    const story = 'd1-story';
    await app.saveStoryNode(story, 'A');
    final originalRows = await app.db.progress.query('story_progress');
    final before = await snapshot(app);
    expect(app.practice.story(story)!.nodeId, 'A');
    await app.db.progress.execute(
        "CREATE TRIGGER d1_fail BEFORE INSERT ON story_progress BEGIN SELECT RAISE(ABORT,'D1_STORY_NODE'); END");
    await expectLater(
        app.saveStoryNode(story, 'B'),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'SQL failure', contains('D1_STORY_NODE'))));
    final rows = await app.db.progress.query('story_progress');
    report('D1_F_failed_story_node', [], {
      'db': rows,
      'cache_node': app.practice.story(story)!.nodeId,
    });
    expect(rows, originalRows);
    expect(await snapshot(app), before);
    expect(app.practice.story(story)!.nodeId, 'A');
    await app.db.progress.execute('DROP TRIGGER d1_fail');
    await app.saveStoryNode(story, 'B');
    final row = (await app.db.progress.query('story_progress')).single;
    expect(row['node_id'], 'B');
    expect(app.practice.story(story)!.nodeId, row['node_id']);
    expect(row['completed'], 0);
    expect(app.practice.story(story)!.completed, isFalse);
    expect(await snapshot(app), before);
  });

  testWidgets(
      'A successful animated verb answer persists card activity and reward',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    final Map<String, Object?> before =
        (await tester.runAsync(() => snapshot(app)))!;
    await startVerb(tester, app);
    final ProbeDatabase db = probes[app]!;
    final Future<void> reward = rewardPublished(app);
    bool rewardDone = false;
    unawaited(reward.then((_) {
      rewardDone = true;
    }));
    final CardStack stack = tester.widget<CardStack>(find.byType(CardStack));
    expect(
        (stack.itemBuilder(tester.element(find.byType(CardStack)), 0)
                as ConjugationCard)
            .conjugation
            .refId,
        refA);
    stack.controller!.swipe(SwipeDirection.right);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await driveUntil(tester, () => rewardDone);
    await tester.pump();
    final Map<String, Object?> after =
        (await tester.runAsync(() => snapshot(app)))!;
    aligned(after);
    final Map card = (after['cards_db']! as Map)[refA] as Map;
    expect(card['box'], 1);
    expect(card['status'], 'learning');
    expect(card['times_seen'], 1);
    expect(card['times_right'], 1);
    expect((card['due_at'] as int) - (card['last_seen_at'] as int),
        const Duration(days: 1).inMilliseconds);
    expect((after['daily_db']! as Map)['cards_swiped'], 1);
    expect((after['profile_db']! as Map)['xp'], 7);
    expect((after['profile_db']! as Map)['coins'], 0);
    expect((after['profile_db']! as Map)['total_cards'], 1);
    expect((after['profile_db']! as Map)['total_verbs'], 1);
    expect(after['quests_db'], <String, Object?>{
      'cards': <String, Object?>{'progress': 1, 'claimed': 0},
      'quiz': <String, Object?>{'progress': 0, 'claimed': 0},
      'verbs': <String, Object?>{'progress': 1, 'claimed': 0},
    });
    expect(after['achievements_db'], <String>['first_card']);
    await tester.pumpWidget(const SizedBox.shrink());
    late Map<String, Object?> reopened;
    await tester.runAsync(() async {
      await app.close();
      reopened = await snapshot(await boot());
    });
    for (final String key in <String>[
      'cards_db',
      'daily_db',
      'profile_db',
      'quests_db',
      'achievements_db'
    ]) {
      expect(reopened[key], after[key]);
    }
    aligned(reopened);
    report('A_success', <String>[
      'real CardStack animation completed',
      ...db.events,
      'reopen verified'
    ], <String, Object?>{
      'before': before,
      'after': after,
      'reopened': reopened
    });
  });

  testWidgets(
      'B card insert rollback leaves current card and shows retry error',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    final before = (await tester.runAsync(() => snapshot(app)))!;
    await tester.runAsync(() => app.db.progress.execute(
        "CREATE TRIGGER fa006_card_failure BEFORE INSERT ON card_state WHEN NEW.ref_id = '$refA' BEGIN SELECT RAISE(ABORT, 'FA006_CARD_FAIL'); END"));
    await startVerb(tester, app);
    final CardStack stack = tester.widget<CardStack>(find.byType(CardStack));
    stack.controller!.swipe(SwipeDirection.right);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await driveUntil(tester,
        () => find.textContaining('Cevap kaydedilemedi').evaluate().isNotEmpty);
    final after = (await tester.runAsync(() => snapshot(app)))!;
    expect(after, before);
    expect(find.byType(CardStack), findsOneWidget);
    expect(find.textContaining('Cevap kaydedilemedi'), findsOneWidget);
    report('B_card_rollback', [
      'actual animation',
      'trigger abort',
      'all caches and DB unchanged',
      'retry message'
    ], {
      'unchanged': true
    });
    await tester.pumpWidget(const SizedBox.shrink());
    bool closed = false;
    unawaited(app.close().then((_) {
      closed = true;
    }));
    await driveUntil(tester, () => closed);
  });

  test('C game failure rolls back the whole answer and retry succeeds',
      () async {
    final app = await boot();
    final before = await snapshot(app);
    await app.db.progress.execute(
        "CREATE TRIGGER fa006_game_failure BEFORE UPDATE ON game_profile BEGIN SELECT RAISE(ABORT, 'FA006_GAME_FAIL'); END");
    Future<AnswerResult> answer() => app.recordAnswer(
        cardType: AnswerCardType.conjugation,
        refId: refA,
        action: SwipeAction.know,
        now: DateTime.now());
    await expectLater(
        answer(),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'message', contains('FA006_GAME_FAIL'))));
    expect(await snapshot(app), before);
    await app.db.progress.execute('DROP TRIGGER fa006_game_failure');
    await answer();
    final after = await snapshot(app);
    expect((after['daily_db']! as Map)['cards_swiped'], 1);
    expect((after['profile_db']! as Map)['xp'], 7);
    expect(app.verbCards.stateFor(refA).timesSeen, 1);
    await app.close();
    final reopened = await snapshot(await boot());
    expect(reopened['cards_db'], after['cards_db']);
    expect(reopened['profile_db'], after['profile_db']);
    report('C_atomic_retry', [
      'profile trigger rolls whole answer back',
      'retry commits once',
      'reopen verified'
    ], {
      'before': before,
      'after': after
    });
  });

  test('C2 daily failure preserves cache and next successful write counts once',
      () async {
    final AppState app = await boot();
    await app.db.progress.execute(
        '''CREATE TRIGGER fa006_daily_failure BEFORE INSERT ON daily_stats
      BEGIN SELECT RAISE(ABORT, 'FA006_DAILY_FAIL'); END''');
    await expectLater(
        app.recordActivity(swiped: 1, verbSwiped: 1),
        throwsA(isA<DatabaseException>().having(
            (DatabaseException e) => e.toString(),
            'message',
            contains('FA006_DAILY_FAIL'))));
    final Map<String, Object?> failed = await snapshot(app);
    expect(failed['daily_db'], isEmpty);
    expect((failed['daily_cache']! as Map)['cards_swiped'], 0);
    expect((failed['profile_db']! as Map)['xp'], 0);
    await app.db.progress.execute('DROP TRIGGER fa006_daily_failure');
    await app.recordActivity(swiped: 1, verbSwiped: 1);
    final Map<String, Object?> next = await snapshot(app);
    expect((next['daily_db']! as Map)['cards_swiped'], 1);
    expect((next['profile_db']! as Map)['total_cards'], 1);
    await app.close();
    final Map<String, Object?> reopened = await snapshot(await boot());
    expect(reopened['daily_db'], next['daily_db']);
    report('C2_daily_cache', <String>[
      'cache unchanged',
      'daily insert aborted',
      'game not reached',
      'next operation writes count 1 and rewards one action',
      'reopen verified'
    ], <String, Object?>{
      'failed': failed,
      'next_success': next,
      'reopened': reopened
    });
  });

  test(
      'D export waits accepted answer and imports a complete snapshot',
      () async {
    final AppState app = await boot();
    final ProbeDatabase db = probes[app]!;
    final OperationGate barrier = gate();
    db.transactionGate = barrier;
    final Future<AnswerResult> activity = app.recordAnswer(
        cardType: AnswerCardType.conjugation,
        refId: refA,
        action: SwipeAction.know,
        now: DateTime.now());
    await barrier.entered.future.timeout(deadline);
    final Map<String, Object?> blocked = await snapshot(app);
    bool exported = false;
    final pendingExport = app.exportProgress().then((value) {
      exported = true;
      return value;
    });
    await Future<void>.value();
    expect(exported, isFalse);
    barrier.release();
    await activity;
    final String json = await pendingExport.timeout(deadline);
    final AppState restored = await boot('export-target');
    await ProgressBackup.import(restored.db.progress, json);
    await restored.reloadProgress();
    final Map<String, Object?> imported = await snapshot(restored);
    expect((imported['cards_db']! as Map).keys, [refA]);
    expect((imported['daily_db']! as Map)['cards_swiped'], 1);
    expect((imported['profile_db']! as Map)['xp'], 7);
    barrier.release();
    await activity;
    final Map<String, Object?> sourceAfter = await snapshot(app);
    expect((sourceAfter['profile_db']! as Map)['xp'], 7);
    expect((imported['profile_db']! as Map)['total_cards'], 1);
    aligned(imported);
    aligned(sourceAfter);
    report('D_pending_atomic_answer', <String>[
      'no answer writes before gate',
      'game transaction gated BEFORE BEGIN',
      'export waits for accepted answer before reading',
      'gate released',
      'source reward committed',
      'export returned complete answer',
      'real import into separate fresh DB'
    ], <String, Object?>{
      'blocked_source': blocked,
      'restored_export': imported,
      'source_after': sourceAfter,
      'format': (jsonDecode(json) as Map)['format']
    });
  });

  testWidgets(
      'E restore drains A1 and A2 before importing B and publishing caches',
      (WidgetTester tester) async {
    late AppState app;
    late String backupB;
    await tester.runAsync(() async {
      app = await boot();
      await app.verbCards.save(answerA());
      final AppState b = await boot('b');
      await b.verbCards.save(const SrsCard(
          refId: refB,
          box: 3,
          status: CardStatus.known,
          timesSeen: 4,
          timesRight: 4));
      await b.recordActivity(swiped: 4, verbSwiped: 4);
      backupB = await ProgressBackup.export(b.db.progress);
      await b.close();
    });
    final ProbeDatabase db = probes[app]!;
    final DailyStatsStore oldStats = app.stats;
    final GameStore oldGame = app.game;
    final List<String> events = <String>[];
    final OperationGate barrier = gate();
    db.transactionGate = barrier;
    late Future<void> first;
    await tester.runAsync(() async {
      first = app.recordActivity(swiped: 1, verbSwiped: 1);
    });
    await driveUntil(tester, () => barrier.entered.isCompleted);
    events.add('A1 transaction gated before BEGIN; cache unchanged');
    late Future<void> second;
    await tester.runAsync(() async {
      second = app.recordActivity(swiped: 1);
    });
    events.add('A2 closure queued behind A1');
    await show(tester, app, const BackupScreen());
    await tester.enterText(find.byType(TextField), backupB);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Geri yükle')));
    await tester.pump();
    expect(app.progress.restoring, isTrue);
    final Map<String, Object?> afterImport =
        (await tester.runAsync(() => snapshot(app)))!;
    expect(afterImport['daily_db'], isEmpty);
    expect((afterImport['profile_db']! as Map)['xp'], 0);
    expect(identical(app.stats, oldStats), isTrue);
    expect(identical(app.game, oldGame), isTrue);
    expect(find.textContaining('hemen yenilendi'), findsNothing);
    events.add('restore gate closed; B import waits for A1/A2');
    final Completer<void> reloaded = Completer<void>();
    void listener() {
      if (!identical(app.stats, oldStats) && !reloaded.isCompleted) {
        events.add('reload replaced caches after A1/A2');
        reloaded.complete();
      }
    }

    app.addListener(listener);
    events.add('release A1 before import; success message still absent');
    barrier.release();
    await driveUntil(tester, () => reloaded.isCompleted);
    await tester.runAsync(() async {
      await first;
      await second;
    });
    app.removeListener(listener);
    await tester.pumpAndSettle();
    expect(find.textContaining('hemen yenilendi'), findsOneWidget);
    events.add('backup screen success message observed');
    final Map<String, Object?> finalState =
        (await tester.runAsync(() => snapshot(app)))!;
    expect((finalState['daily_db']! as Map)['cards_swiped'], 4);
    expect((finalState['profile_db']! as Map)['xp'], 28);
    expect((finalState['profile_db']! as Map)['total_cards'], 4);
    expect((finalState['profile_db']! as Map)['total_verbs'], 4);
    expect((finalState['cards_db']! as Map).keys, <String>[refB]);
    aligned(finalState);
    await tester.runAsync(() => app.reloadProgress());
    expect((await tester.runAsync(() => snapshot(app)))!['profile_db'],
        finalState['profile_db']);
    await tester.pumpWidget(const SizedBox.shrink());
    late Map<String, Object?> reopened;
    await tester.runAsync(() async {
      await app.close();
      reopened = await snapshot(await boot());
    });
    expect(reopened['daily_db'], finalState['daily_db']);
    expect(reopened['profile_db'], finalState['profile_db']);
    report('E_restore_pending', events, <String, Object?>{
      'before_import_while_A_is_pending': afterImport,
      'final': finalState,
      'reopened': reopened,
      'old_stores_used_until_reload': true,
      'success_message_after_queued_writes': true
    });
  });

  testWidgets('E control canceled and invalid restore start no import writes',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    late String backup;
    await tester.runAsync(() async {
      backup = await ProgressBackup.export(app.db.progress);
    });
    final Map<String, Object?> before =
        (await tester.runAsync(() => snapshot(app)))!;
    final ProbeDatabase db = probes[app]!;
    db.events.clear();
    await show(tester, app, const BackupScreen());
    await tester.enterText(find.byType(TextField), backup);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vazgeç'));
    await tester.pumpAndSettle();
    expect(db.events, isEmpty);
    await tester.enterText(find.byType(TextField), '{"format":1}');
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Geri yükle')));
    await tester.pumpAndSettle();
    await driveUntil(tester, () => find.textContaining('Yedek eksik veya bozuk').evaluate().isNotEmpty);
    expect(find.textContaining('Yedek eksik veya bozuk'), findsOneWidget);
    expect(db.events, isEmpty);
    expect(await tester.runAsync(() => snapshot(app)), before);
    report('E_cancel_invalid', <String>[
      'cancel confirmed no writes',
      'invalid required tables rejected before transaction'
    ], <String, Object?>{
      'unchanged': true,
      'observed_store_write_events': db.events,
      'import_transaction_observed': false
    });
  });

  test(
      'F close waits queued activity and disposed notification does not fail commit',
      () async {
    final AppState app = await boot();
    final ProbeDatabase db = probes[app]!;
    final OperationGate barrier = gate();
    db.transactionGate = barrier;
    final Future<void> activity = app.recordActivity(swiped: 1, verbSwiped: 1);
    await barrier.entered.future.timeout(deadline);
    bool closed = false;
    final Future<void> closing = app.close().then((_) {
      closed = true;
    });
    await Future<void>.value();
    expect(closed, isFalse);
    expect(db.isOpen, isTrue);
    barrier.release();
    await activity;
    await closing.timeout(deadline);
    expect(db.events, contains('transaction.committed'));
    expect(app.db.progress.isOpen, isFalse);
    db.events.add('real AppDatabase close completed after transaction');
    final Map<String, Object?> reopened = await snapshot(await boot());
    expect((reopened['daily_db']! as Map)['cards_swiped'], 1);
    expect((reopened['profile_db']! as Map)['xp'], 7);
    report('F_close_queue', db.events, <String, Object?>{
      'waited_for_queued_transaction': true,
      'debug_future_error': null,
      'reopened': reopened,
      'release_mode_or_process_kill_tested': false
    });
  });

  test('F2 close waits accepted standalone card save before SQL dispatch',
      () async {
    final app = await boot();
    final db = probes[app]!;
    final barrier = gate();
    db.gatedInsertTable = 'card_state';
    db.insertGate = barrier;
    final save = app.verbCards.save(answerA());
    await barrier.entered.future.timeout(deadline);
    bool closed = false;
    final closing = app.close().then((_) => closed = true);
    await Future<void>.value();
    expect(closed, isFalse);
    expect(db.isOpen, isTrue);
    barrier.release();
    await save;
    await closing.timeout(deadline);
    final reopened = await snapshot(await boot());
    expect((reopened['cards_db']! as Map).keys, [refA]);
    report('F2_close_card', db.events, <String, Object?>{
      'closed_before_card_sql_dispatch': false,
      'save_future_failed': false,
      'reopened': reopened,
    });
  });

  Future<AnswerResult> answer(AppState app,
          {AnswerCardType type = AnswerCardType.conjugation,
          String ref = refA,
          SwipeAction action = SwipeAction.know,
          DateTime? at}) =>
      app.recordAnswer(
          cardType: type,
          refId: ref,
          action: action,
          now: at ?? DateTime.now());

  // Each trigger is reached through the real answer entry, not standalone save.
  for (final point in <(String, String)>[
    ('card', 'BEFORE INSERT ON card_state'),
    ('daily', 'BEFORE INSERT ON daily_stats'),
    ('profile', 'BEFORE UPDATE ON game_profile'),
    ('quest seed', 'BEFORE INSERT ON daily_quests'),
    ('quest update', 'BEFORE UPDATE ON daily_quests'),
    ('achievement', 'BEFORE INSERT ON achievements'),
  ]) {
    test('atomic answer rollback and recovery at ${point.$1}', () async {
      final app = await boot();
      final before = await snapshot(app);
      await app.db.progress.execute(
          "CREATE TRIGGER injected ${point.$2} BEGIN SELECT RAISE(ABORT,'ATOMIC_FAIL'); END");
      await expectLater(
          answer(app),
          throwsA(isA<DatabaseException>().having(
              (e) => e.toString(), 'injected error', contains('ATOMIC_FAIL'))));
      expect(await snapshot(app), before);
      await app.db.progress.execute('DROP TRIGGER injected');
      await answer(app);
      expect(app.verbCards.stateFor(refA).timesSeen, 1);
      expect(app.stats.today()['cards_swiped'], 1);
      expect(app.game.profile.xp, 7);
      expect(app.rewardSerial, 1);
      await answer(app, ref: 'separate:present:je');
      expect(app.game.profile.xp, 14);
      expect(app.stats.today()['cards_swiped'], 2);
      expect(app.rewardSerial, 2);
      aligned(await snapshot(app));
      report('atomic_${point.$1}', [
        'injected error observed',
        'whole snapshot unchanged',
        'retry once',
        'next distinct answer succeeds'
      ], {
        'rollback': true,
        'xp_after_two_successes': 14
      });
    });
  }

  test('new-day second quest seed failure rolls back the first seed too',
      () async {
    final app = await boot();
    final before = await snapshot(app);
    final at = DateTime(2032, 2, 3, 9);
    final day = DailyStatsStore.keyFor(at);
    await app.db.progress.execute(
        "CREATE TRIGGER second_seed BEFORE INSERT ON daily_quests WHEN NEW.day = '$day' AND NEW.quest_id = 'quiz' BEGIN SELECT RAISE(ABORT,'SECOND_SEED_FAIL'); END");
    await expectLater(
        answer(app, at: at),
        throwsA(isA<DatabaseException>().having(
            (e) => e.toString(), 'message', contains('SECOND_SEED_FAIL'))));
    expect(await snapshot(app), before);
    expect(
        await app.db.progress
            .query('daily_quests', where: 'day = ?', whereArgs: [day]),
        isEmpty);
    expect(
        await app.db.progress
            .query('daily_stats', where: 'day = ?', whereArgs: [day]),
        isEmpty);
    await app.db.progress.execute('DROP TRIGGER second_seed');
    await answer(app, at: at);
    expect(
        await app.db.progress
            .query('daily_quests', where: 'day = ?', whereArgs: [day]),
        hasLength(3));
    expect(app.game.profile.xp, 7);
  });

  test('standalone save and add publish only after successful writes',
      () async {
    final app = await boot();
    final before = await snapshot(app);
    for (final table in ['card_state', 'daily_stats']) {
      await app.db.progress.execute(
          "CREATE TRIGGER standalone BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT,'STANDALONE_FAIL'); END");
      await expectLater(
          table == 'card_state'
              ? app.verbCards.save(answerA())
              : app.stats.add(swiped: 1),
          throwsA(isA<DatabaseException>().having(
              (e) => e.toString(), 'message', contains('STANDALONE_FAIL'))));
      expect(await snapshot(app), before);
      await app.db.progress.execute('DROP TRIGGER standalone');
    }
  });

  test(
      'recordActivity profile rollback does not undo an earlier independent card commit',
      () async {
    final app = await boot();
    await app.verbCards.save(answerA());
    final before = await snapshot(app);
    await app.db.progress.execute(
        "CREATE TRIGGER activity_fail BEFORE UPDATE ON game_profile BEGIN SELECT RAISE(ABORT,'ACTIVITY_FAIL'); END");
    await expectLater(app.recordActivity(swiped: 1, verbSwiped: 1),
        throwsA(isA<DatabaseException>()));
    expect(await snapshot(app), before);
    await app.db.progress.execute('DROP TRIGGER activity_fail');
    await app.recordActivity(swiped: 1, verbSwiped: 1);
    expect(app.stats.today()['cards_swiped'], 1);
    expect(app.game.profile.xp, 7);
  });

  test('quest bonus and first achievement rollback then claim only once',
      () async {
    final app = await boot();
    final day = DailyStatsStore.keyFor(DateTime.now());
    await app.db.progress.update('daily_quests', {'progress': 11},
        where: 'day = ? AND quest_id = ?', whereArgs: [day, 'cards']);
    app.game = await GameStore.load(probes[app]!);
    final before = await snapshot(app);
    await app.db.progress.execute(
        "CREATE TRIGGER threshold_fail BEFORE UPDATE ON game_profile BEGIN SELECT RAISE(ABORT,'THRESHOLD_FAIL'); END");
    Future<AnswerResult> word() =>
        answer(app, type: AnswerCardType.word, ref: 'word-probe');
    await expectLater(word(), throwsA(isA<DatabaseException>()));
    expect(await snapshot(app), before);
    expect(app.cards.stateFor('word-probe').timesSeen, 0);
    expect(
        await app.db.progress.query('card_state', where: "card_type = 'word'"),
        isEmpty);
    await app.db.progress.execute('DROP TRIGGER threshold_fail');
    final result = await word();
    expect(result.newLearned, true);
    expect(result.reward.xp, 92); // 4 card + 8 new + 80 quest
    expect(result.reward.coins, 10); // 2 new + 8 quest
    expect(result.reward.completedQuests, hasLength(1));
    expect(app.game.unlockedAchievements, contains('first_card'));
    expect(app.game.quests.singleWhere((q) => q.id == 'cards').claimed, true);
    final next = await word();
    expect(next.before.timesSeen, 1);
    expect(next.newLearned, false);
    expect(next.reward.xp, 4);
    expect(next.reward.coins, 0);
    expect(next.reward.completedQuests, isEmpty);
    expect(next.reward.unlockedAchievements, isEmpty);
    report('threshold_retry', [
      'claim/achievement rolled back',
      'retry claims once',
      'second legitimate answer no duplicate bonus'
    ], {
      'first_xp': 92,
      'first_coins': 10,
      'second_xp': 4
    });
  });

  test('all four actions and queued same-ref answers use committed SRS state',
      () async {
    final app = await boot();
    final at = DateTime(2031, 3, 4, 10);
    SrsCard expected = const SrsCard(refId: refA);
    for (final action in SwipeAction.values) {
      expected = BoxScheduler.apply(expected, action, now: at);
      final result = await answer(app, action: action, at: at);
      expect(cardFields(result.after), cardFields(expected));
    }
    final first = answer(app, ref: 'repeat:present:je', at: at);
    final second = answer(app, ref: 'repeat:present:je', at: at);
    expect((await first).after.box, 1);
    final result = await second;
    expect(result.before.box, 1);
    expect(result.before.timesSeen, 1);
    expect(result.after.box, 2);
    expect(result.after.timesSeen, 2);
  });

  test(
      'one captured local event time drives card daily quest and reward writes',
      () async {
    final app = await boot();
    final at = DateTime(2031, 12, 31, 23, 59, 59);
    final gateNow = gate();
    probes[app]!.transactionGate = gateNow;
    final pending = answer(app, at: at);
    await gateNow.entered.future;
    expect(app.verbCards.stateFor(refA).timesSeen, 0);
    gateNow.release();
    await pending;
    final card = (await app.db.progress.query('card_state')).single;
    expect(card['last_seen_at'], at.millisecondsSinceEpoch);
    expect(card['updated_at'], at.millisecondsSinceEpoch);
    expect(
        card['due_at'], at.add(const Duration(days: 1)).millisecondsSinceEpoch);
    final day = DailyStatsStore.keyFor(at);
    expect((await app.db.progress.query('daily_stats')).single['day'], day);
    final quests = await app.db.progress
        .query('daily_quests', where: 'day = ?', whereArgs: [day]);
    expect(quests, hasLength(3));
    expect(quests.singleWhere((q) => q['quest_id'] == 'verbs')['progress'], 1);
    expect((await app.db.progress.query('achievements')).single['unlocked_at'],
        at.millisecondsSinceEpoch);
    expect((await app.db.progress.query('game_profile')).single['updated_at'],
        at.millisecondsSinceEpoch);
    expect(app.stats.forDay(at)!['cards_swiped'], 1);
  });

  Future<void> showAnswer(WidgetTester tester, AppState app, bool word) async {
    if (word) {
      await show(
          tester,
          app,
          const SwipeSessionScreen(
              title: 'Atomic word', candidateIds: ['word-probe']));
    } else {
      await startVerb(tester, app);
    }
  }

  Future<void> swipe(WidgetTester tester, SwipeDirection direction) async {
    tester
        .widget<CardStack>(find.byType(CardStack))
        .controller!
        .swipe(direction);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  for (final word in [true, false]) {
    testWidgets(
        'real ${word ? 'word' : 'verb'} animation pending rollback retry and reopen',
        (tester) async {
      final app = (await tester.runAsync(boot))!;
      await showAnswer(tester, app, word);
      final boundary = gate();
      probes[app]!.transactionGate = boundary;
      await tester.runAsync(() => app.db.progress.execute(
          "CREATE TRIGGER ui_fail BEFORE UPDATE ON game_profile BEGIN SELECT RAISE(ABORT,'UI_FAIL'); END"));
      await swipe(tester, SwipeDirection.right);
      await driveUntil(tester, () => boundary.entered.isCompleted);
      expect(find.text('Kaydediliyor…'), findsOneWidget);
      final controller =
          tester.widget<CardStack>(find.byType(CardStack)).controller!;
      controller.swipe(SwipeDirection.right);
      controller.swipe(SwipeDirection.left);
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(CardStack), findsOneWidget);
      expect(app.rewardSerial, 0);
      expect(
          (word ? app.cards : app.verbCards)
              .stateFor(word ? 'word-probe' : refA)
              .timesSeen,
          0);
      boundary.release();
      await driveUntil(
          tester,
          () =>
              find.textContaining('Cevap kaydedilemedi').evaluate().isNotEmpty);
      expect(find.byType(CardStack), findsOneWidget);
      expect(app.stats.today()['cards_swiped'], 0);
      expect(app.game.profile.xp, 0);
      expect(app.rewardSerial, 0);
      await tester
          .runAsync(() => app.db.progress.execute('DROP TRIGGER ui_fail'));
      await swipe(tester, SwipeDirection.right);
      await driveUntil(tester, () => app.rewardSerial == 1);
      await tester.pump();
      expect(find.byType(CardStack), findsNothing);
      final state = (word ? app.cards : app.verbCards)
          .stateFor(word ? 'word-probe' : refA);
      expect(state.timesSeen, 1);
      expect(state.box, 1);
      expect(app.stats.today()['cards_swiped'], 1);
      expect(app.stats.today()['new_learned'], word ? 1 : 0);
      expect(app.game.profile.xp, word ? 12 : 7);
      expect(app.game.profile.coins, word ? 2 : 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await app.close();
        final reopened = await boot();
        expect(
            (word ? reopened.cards : reopened.verbCards)
                .stateFor(word ? 'word-probe' : refA)
                .timesSeen,
            1);
        expect(reopened.game.profile.xp, word ? 12 : 7);
      });
      report('ui_${word ? 'word' : 'verb'}', [
        'animation gated',
        'duplicate answers ignored',
        'last card not completed',
        'rollback card retained',
        'user retry commits once',
        'reopen verified'
      ], {
        'xp': word ? 12 : 7,
        'times_seen': 1
      });
    });

    testWidgets(
        'unmounted ${word ? 'word' : 'verb'} screen does not cancel accepted answer',
        (tester) async {
      final app = (await tester.runAsync(boot))!;
      await showAnswer(tester, app, word);
      final boundary = gate();
      probes[app]!.transactionGate = boundary;
      await swipe(tester, SwipeDirection.right);
      await driveUntil(tester, () => boundary.entered.isCompleted);
      await tester.pumpWidget(const SizedBox.shrink());
      boundary.release();
      await driveUntil(tester, () => app.rewardSerial == 1);
      expect(tester.takeException(), isNull);
      expect(
          (word ? app.cards : app.verbCards)
              .stateFor(word ? 'word-probe' : refA)
              .timesSeen,
          1);
    });
  }

  testWidgets(
      'dontKnow reinserts once and next animated answer advances committed card',
      (tester) async {
    final app = (await tester.runAsync(boot))!;
    await startVerb(tester, app);
    await swipe(tester, SwipeDirection.left);
    await driveUntil(tester, () => app.rewardSerial == 1);
    await tester.pump();
    expect(find.byType(CardStack), findsOneWidget);
    expect(tester.widget<CardStack>(find.byType(CardStack)).itemCount, 2);
    expect(app.verbCards.stateFor(refA).lapses, 1);
    await swipe(tester, SwipeDirection.right);
    await driveUntil(tester, () => app.rewardSerial == 2);
    await tester.pump();
    expect(find.byType(CardStack), findsNothing);
    expect(app.verbCards.stateFor(refA).timesSeen, 2);
    expect(app.verbCards.stateFor(refA).box, 1);
  });

  test('answer and activity publish prepared caches without post-commit reads',
      () async {
    final app = await boot();
    final probe = probes[app]!;
    probe.onTransactionCommitted = () => probe.rejectReads = true;
    await answer(app);
    expect(app.verbCards.stateFor(refA).timesSeen, 1);
    expect(app.game.profile.xp, 7);
    expect(
        probe.events.where((e) => e == 'transaction.committed'), hasLength(1));
    await app.recordActivity(swiped: 1);
    expect(app.stats.today()['cards_swiped'], 2);
    expect(app.game.profile.xp, 11);
    expect(app.rewardSerial, 2);
    expect(
        probe.events.where((e) => e == 'transaction.committed'), hasLength(2));
  });

  test('close waits accepted atomic answer without post-commit dispose error',
      () async {
    final app = await boot();
    final boundary = gate();
    probes[app]!.transactionGate = boundary;
    final pending = answer(app);
    await boundary.entered.future;
    final closing = app.close();
    boundary.release();
    final result = await pending;
    await closing;
    expect(result.after.timesSeen, 1);
    expect(app.rewardSerial, 1);
    final reopened = await boot();
    expect(reopened.verbCards.stateFor(refA).timesSeen, 1);
    expect(reopened.game.profile.xp, 7);
  });
Future<String> backupB() async {
    final b = await boot('backup-source');
    await b.verbCards.save(const SrsCard(refId: refB, box: 3,
        status: CardStatus.known, timesSeen: 4, timesRight: 4));
    await b.recordActivity(swiped: 4, verbSwiped: 4);
    await b.settings.setInt('daily_goal', 35);
    final json = await b.exportProgress();
    await b.close();
    return json;
  }

  test('FA006C bound stores reject stale references and close rejects new writes', () async {
    final app = await boot();
    final oldCards = app.cards;
    final oldVerbs = app.verbCards;
    final oldSettings = app.settings;
    final oldStats = app.stats;
    final oldFlags = app.flags;
    final oldJourney = app.journey;
    final oldGame = app.game;
    final oldPractice = app.practice;
    final json = await backupB();
    await app.restoreProgress(json);
    final before = await snapshot(app);
    final attempts = <Future<void> Function()>[
      () => oldCards.save(const SrsCard(refId: 'old')),
      () => oldCards.reset(),
      () => oldVerbs.save(answerA()),
      () => oldSettings.set('daily_goal', '90'),
      () => oldStats.add(swiped: 5),
      () => oldFlags.toggle(refId: 'old', cardType: 'word'),
      () async { await oldJourney.record(stationId:'old', stars:3, correct:8,total:8); },
      () async { await oldGame.record(cards: 9); },
      () => oldPractice.saveStoryNode('old', 'node'),
      () async { await oldPractice.completeStory(storyId:'old',nodeId:'node',correct:1,total:1); },
      () async { await oldPractice.recordSentence(promptId:'old',solved:true,score:1); },
    ];
    for (final attempt in attempts) {
      await expectLater(attempt(), throwsA(isA<ProgressUnavailable>()));
    }
    expect(await snapshot(app), before);
    expect(app.dailyGoal, 35);
    expect(app.rewardSerial, 0);
    await app.restoreProgress(json);
    expect(app.game.profile.xp, 28);
    await answer(app);
    expect(app.game.profile.xp, 35);
    final currentStore = app.cards;
    final firstClose = app.close();
    expect(identical(firstClose, app.close()), isTrue);
    await expectLater(currentStore.save(const SrsCard(refId:'late')),
        throwsA(isA<ProgressUnavailable>()));
    await expectLater(app.setDailyGoal(55), throwsA(isA<ProgressUnavailable>()));
    await expectLater(app.recordActivity(swiped:1), throwsA(isA<ProgressUnavailable>()));
    await firstClose;
    final reopened = await boot();
    expect(reopened.game.profile.xp, 35);
    expect(reopened.cards.snapshot(), isEmpty);
    report('C_all_write_admission', ['restore B', '11 stale store operations rejected',
      'repeat restore without reward','new answer accepted','close rejects new writes'],
      {'stale_operations':attempts.length,'restored_xp':28,'after_new_answer_xp':35});
  });

  test('FA006C restore rejects new jobs and double restore; close drains accepted restore', () async {
    final app = await boot();
    final json = await backupB();
    final boundary = gate();
    probes[app]!.transactionGate = boundary;
    final first = answer(app);
    await boundary.entered.future;
    final second = app.recordActivity(swiped:1);
    final restoring = app.restoreProgress(json);
    expect(app.progress.restoring, isTrue);
    await expectLater(answer(app), throwsA(isA<ProgressUnavailable>()));
    await expectLater(app.restoreProgress(json), throwsA(isA<ProgressUnavailable>()));
    await expectLater(app.verbCards.save(answerA()), throwsA(isA<ProgressUnavailable>()));
    final closing = app.close();
    boundary.release();
    await first;
    await second;
    await restoring;
    await closing;
    expect(app.progress.accepting, isFalse);
    final reopened = await boot();
    expect(reopened.game.profile.xp, 28);
    expect(reopened.verbCards.snapshot().keys, [refB]);
    expect(reopened.stats.today()['cards_swiped'], 4);
    report('C_restore_close', ['A1 gated','A2 accepted','restore accepted',
      'new answer/store/restore rejected','close accepted','A1 A2 finish',
      'B imported','cache published','DB closed','reopen B'],
      {'xp':28,'daily':4,'cards':[refB]});
  });

  for (final point in ['delete', 'insert']) {
    test('FA006C restore $point SQL failure rolls overwrite back and preserves caches', () async {
      final app = await boot();
      await answer(app);
      final json = await backupB();
      final before = await snapshot(app);
      final old = app.verbCards;
      final sql = point == 'delete'
          ? "CREATE TRIGGER restore_fail BEFORE DELETE ON card_state BEGIN SELECT RAISE(ABORT,'RESTORE_FAIL'); END"
          : "CREATE TRIGGER restore_fail BEFORE INSERT ON daily_stats BEGIN SELECT RAISE(ABORT,'RESTORE_FAIL'); END";
      await app.db.progress.execute(sql);
      await expectLater(app.restoreProgress(json), throwsA(isA<DatabaseException>()
          .having((e)=>e.toString(),'injected failure',contains('RESTORE_FAIL'))));
      expect(await snapshot(app), before);
      expect(identical(old, app.verbCards), isTrue);
      expect(app.recoveryRequired, isFalse);
      expect(app.progress.accepting, isTrue);
      await app.db.progress.execute('DROP TRIGGER restore_fail');
      await app.restoreProgress(json);
      expect(app.game.profile.xp, 28);
      report('C_restore_rollback_$point',['SQL fault after overwrite begins',
        'transaction rolled back','cache unchanged','retry imports B'],
        {'before_xp':7,'after_failure_xp':7,'after_retry_xp':28});
    });
  }

  for (final recover in [true, false]) {
    test('FA006C post-commit cache failure recovery=$recover gates writes', () async {
      final app = await boot();
      await answer(app);
      final old = app.verbCards;
      final json = await backupB();
      await app.db.progress.execute("""CREATE TRIGGER load_fail BEFORE INSERT ON game_profile
        WHEN EXISTS(SELECT 1 FROM game_profile)
        BEGIN SELECT RAISE(ABORT,'LOAD_FAIL_AFTER_IMPORT'); END""");
      await expectLater(app.restoreProgress(json), throwsA(isA<ProgressUnavailable>()
          .having((e)=>e.message,'committed status',contains('veritabanına yazıldı'))));
      expect(app.recoveryRequired, isTrue);
      expect(identical(old, app.verbCards), isTrue);
      expect(app.game.profile.xp, 7);
      expect((await app.db.progress.query('game_profile')).single['xp'], 28);
      await expectLater(answer(app), throwsA(isA<ProgressUnavailable>()));
      await expectLater(old.save(answerA()), throwsA(isA<ProgressUnavailable>()));
      await expectLater(app.exportProgress(), throwsA(isA<ProgressUnavailable>()));
      await app.db.progress.execute('DROP TRIGGER load_fail');
      if (recover) {
        await app.recoverProgress();
        expect(app.recoveryRequired, isFalse);
        expect(app.game.profile.xp, 28);
        expect(app.verbCards.snapshot().keys, [refB]);
        await expectLater(old.save(answerA()), throwsA(isA<ProgressUnavailable>()));
        expect(app.rewardSerial, 1);
      }
      await app.close();
      expect((await boot()).game.profile.xp, 28);
      report('C_post_commit_$recover',['B commit','load trigger fails',
        'old cache gated','new writes and export rejected',
        recover ? 'reload only, no reimport' : 'normal close','reopen B'],
        {'db_xp_after_import':28,'cache_xp_after_failure':7,'recovery_required_after_failure':true});
    });
  }

  test('FA006C later write cannot interleave after first export table read', () async {
    final app = await boot();
    await answer(app);
    final probe = ProbeDatabase(app.db.progress);
    final boundary = gate();
    final tables = <String>[];
    probe.afterTransactionRead = (table) async {
      tables.add(table);
      if (table == 'card_state') await boundary.wait();
    };
    // Same production coordinator and exporter, real SQLite Transaction.
    // The AppState entry itself is covered by D.
    final exporting = app.progress.run(() => ProgressBackup.export(probe));
    await boundary.entered.future;
    bool written = false;
    final later = app.recordActivity(swiped:1).then((_)=>written=true);
    await Future<void>.value();
    expect(written, isFalse);
    boundary.release();
    final json = await exporting;
    probe.afterTransactionRead = null;
    await later;
    final target = await boot('snapshot-target');
    await target.restoreProgress(json);
    expect(target.verbCards.stateFor(refA).timesSeen, 1);
    expect(target.stats.today()['cards_swiped'], 1);
    expect(target.game.profile.xp, 7);
    expect(target.game.quests.firstWhere((q)=>q.id=='cards').progress, 1);
    expect(app.stats.today()['cards_swiped'], 2);
    expect(app.game.profile.xp, 11);
    expect(tables, containsAllInOrder(['card_state','daily_stats','game_profile','daily_quests']));
    report('C_export_snapshot',['card table read; transaction held','later write accepted',
      'later write waits','all backup tables read','export finished','later write committed',
      'separate DB imports complete earlier state'],
      {'backup_xp':7,'source_xp':11,'backup_daily':1,'source_daily':2,'read_tables':tables});
  });

  test('FA006C export propagates injected transaction read error and queue recovers', () async {
    final app = await boot();
    final probe = ProbeDatabase(app.db.progress);
    probe.failTransactionReadTable = 'daily_stats';
    await expectLater(app.progress.run(() => ProgressBackup.export(probe)),
        throwsA(isA<DatabaseException>().having((e)=>e.toString(),
            'real SQL read failure',contains('fa006c_injected_missing_table'))));
    probe.failTransactionReadTable=null;
    await answer(app);
    final json=await app.exportProgress();
    expect((jsonDecode(json) as Map)['card_state'], hasLength(1));
  });

  test('FA006C failed queued job does not poison export or idempotent close', () async {
    final app = await boot();
    await app.db.progress.execute("CREATE TRIGGER fail_card BEFORE INSERT ON card_state BEGIN SELECT RAISE(ABORT,'FAILED_JOB'); END");
    await expectLater(answer(app), throwsA(isA<DatabaseException>()));
    await app.db.progress.execute('DROP TRIGGER fail_card');
    final good = answer(app);
    final exporting = app.exportProgress();
    final closing = app.close();
    expect(identical(closing, app.close()), isTrue);
    await good;
    final json = jsonDecode(await exporting) as Map;
    expect(json['card_state'], hasLength(1));
    expect((json['game_profile'] as List).single['xp'], 7);
    await closing;
  });

  for (final word in [true,false]) {
    testWidgets('FA006C stale screen word=$word animation cannot write after restore', (tester) async {
      final app=(await tester.runAsync(boot))!;
      final json=(await tester.runAsync(backupB))!;
      await showAnswer(tester,app,word);
      final controller=tester.widget<CardStack>(find.byType(CardStack)).controller!;
      controller.swipe(SwipeDirection.right);
      await tester.pump();
      await tester.runAsync(()=>app.restoreProgress(json));
      await tester.pump(const Duration(milliseconds:600));
      await tester.pumpAndSettle();
      expect(find.textContaining('oturum eskidi'), findsOneWidget);
      expect(app.game.profile.xp,28);
      expect(app.stats.today()['cards_swiped'],4);
      expect(app.rewardSerial,0);
      expect(app.verbCards.snapshot().keys,[refB]);
      expect(find.byType(CardStack), findsOneWidget);
    });
  }

  testWidgets('FA006C BackupScreen export success and read failure produce distinct UI', (tester) async {
    final app=(await tester.runAsync(boot))!;
    await tester.runAsync(()=>answer(app));
    await show(tester,app,BackupScreen(exportDirectory: () async => Directory(devicePath)));
    await tester.tap(find.text('Yedek al'));
    await driveUntil(tester,()=>find.textContaining('panoya kopyalandı').evaluate().isNotEmpty || find.textContaining('Yedek alınamadı').evaluate().isNotEmpty);
    expect(find.textContaining('panoya kopyalandı'), findsOneWidget,
        reason: tester.widgetList<Text>(find.byType(Text)).map((w)=>w.data).join(' | '));
    final files=Directory(devicePath).listSync().whereType<File>().where((f)=>f.path.endsWith('.json')).toList();
    expect(files,hasLength(1));
    final json=jsonDecode(files.single.readAsStringSync()) as Map;
    expect((json['game_profile'] as List).single['xp'],7);
    final bytes=files.single.readAsBytesSync();
    await tester.runAsync(()=>app.db.progress.execute('DROP TABLE card_state'));
    await tester.tap(find.text('Yedek al'));
    await driveUntil(tester,()=>find.textContaining('Yedek alınamadı').evaluate().isNotEmpty);
    expect(files.single.readAsBytesSync(),bytes);
    expect(Directory(devicePath).listSync().whereType<File>().where((f)=>f.path.endsWith('.json')),hasLength(1));
  });

  testWidgets('FA006C BackupScreen import SQL error has no success', (tester) async {
    final app=(await tester.runAsync(boot))!;
    final json=(await tester.runAsync(backupB))!;
    await tester.runAsync(()=>app.db.progress.execute("CREATE TRIGGER ui_restore_fail BEFORE INSERT ON daily_stats BEGIN SELECT RAISE(ABORT,'UI_RESTORE_FAIL'); END"));
    await show(tester,app,const BackupScreen());
    await tester.enterText(find.byType(TextField),json);
    await tester.ensureVisible(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.widgetWithText(FilledButton,'Geri yükle')));
    await driveUntil(tester,()=>find.textContaining('Geri yüklenemedi').evaluate().isNotEmpty);
    expect(find.textContaining('hemen yenilendi'),findsNothing);
    expect(app.game.profile.xp,0);
    expect(app.progress.accepting,isTrue);
  });

  testWidgets('FA006C unmounted BackupScreen accepted restore completes before close', (tester) async {
    final app=(await tester.runAsync(boot))!;
    final json=(await tester.runAsync(backupB))!;
    await show(tester,app,const BackupScreen());
    final boundary=gate();
    probes[app]!.transactionGate=boundary;
    final pending=app.recordActivity(swiped:1);
    await driveUntil(tester,()=>boundary.entered.isCompleted);
    await tester.enterText(find.byType(TextField),json);
    await tester.ensureVisible(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.widgetWithText(FilledButton,'Geri yükle')));
    await tester.pump();
    expect(app.progress.restoring,isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    bool closed=false;
    final closing=app.close().then((_)=>closed=true);
    boundary.release();
    await driveUntil(tester,()=>closed);
    await pending;
    await closing;
    apps.remove(app);
    expect(tester.takeException(),isNull);
    final reopened=(await tester.runAsync(boot))!;
    expect(reopened.game.profile.xp,28);
  });

test('FA006C every store write accepted before export and close is drained', () async {
    final app = await boot();
    final barrier = gate();
    probes[app]!.transactionGate = barrier;
    final first = answer(app);
    await barrier.entered.future;
    final jobs = <Future<dynamic>>[
      app.cards.save(const SrsCard(refId:'saved-word',starred:true)),
      app.verbCards.save(const SrsCard(refId:'saved:present:tu',starred:true)),
      app.settings.set('custom','kept'),
      app.stats.add(swiped:1),
      app.flags.toggle(refId:'flag',cardType:'word'),
      app.journey.record(stationId:'synthetic-station',stars:2,correct:7,total:8),
      app.game.record(cards:1),
      app.practice.saveStoryNode('story','first'),
      app.practice.completeStory(storyId:'story',nodeId:'last',correct:1,total:1),
      app.practice.recordSentence(promptId:'sentence',solved:true,score:100),
      app.setDailyGoal(45),
    ];
    final exporting=app.exportProgress();
    final closing=app.close();
    expect(app.db.progress.isOpen,isTrue);
    barrier.release();
    await first;
    await Future.wait(jobs);
    final json=jsonDecode(await exporting) as Map;
    await closing;
    expect(json['card_state'],hasLength(3));
    expect(json['flagged_cards'],hasLength(1));
    expect(json['journey_progress'],hasLength(1));
    expect((json['story_progress'] as List).single['node_id'],'last');
    expect((json['sentence_progress'] as List).single['solved'],1);
    expect((json['daily_stats'] as List).single['cards_swiped'],2);
    expect((json['game_profile'] as List).single['xp'],11);
    final reopened=await boot();
    expect(reopened.dailyGoal,45);
    expect(reopened.settings.get('custom'),'kept');
    expect(reopened.cards.stateFor('saved-word').starred,isTrue);
    report('C_all_store_drain',['answer gated','11 store/app jobs accepted',
      'export accepted','close starts','gate released','all jobs complete',
      'export complete','close complete','reopen verified'],
      {'cards':3,'daily':2,'xp':11,'goal':45});
  });

  test('FA006C expired operation lease cannot bypass generation or closing', () async {
    final app=await boot();
    final old=app.verbCards;
    final barrier=gate();
    late Future<void> delayed;
    await app.progress.run(() async {
      delayed=barrier.released.future.then((_)=>old.save(answerA()));
    });
    final failure=expectLater(delayed,throwsA(isA<ProgressUnavailable>()));
    await app.restoreProgress(await backupB());
    barrier.release();
    await failure;
    expect(app.verbCards.snapshot().keys,[refB]);
    expect(app.game.profile.xp,28);
  });

  testWidgets('FA006C BackupScreen post-commit failure offers reload without reimport', (tester) async {
    final app=(await tester.runAsync(boot))!;
    final json=(await tester.runAsync(backupB))!;
    await tester.runAsync(()=>app.db.progress.execute("""CREATE TRIGGER ui_load_fail
      BEFORE INSERT ON game_profile WHEN EXISTS(SELECT 1 FROM game_profile)
      BEGIN SELECT RAISE(ABORT,'UI_LOAD_FAIL'); END"""));
    await show(tester,app,const BackupScreen());
    await tester.enterText(find.byType(TextField),json);
    await tester.ensureVisible(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton,'Geri yükle'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of:find.byType(AlertDialog),matching:find.widgetWithText(FilledButton,'Geri yükle')));
    await driveUntil(tester,()=>find.textContaining('veritabanına yazıldı').evaluate().isNotEmpty);
    expect(app.recoveryRequired,isTrue);
    expect(find.textContaining('hemen yenilendi'),findsNothing);
    await tester.runAsync(()=>app.db.progress.execute('DROP TRIGGER ui_load_fail'));
    await tester.ensureVisible(find.text('İlerlemeyi yeniden yükle'));
    await tester.tap(find.text('İlerlemeyi yeniden yükle'));
    await driveUntil(tester,()=>find.text('İlerleme yeniden yüklendi.').evaluate().isNotEmpty);
    expect(app.recoveryRequired,isFalse);
    expect(app.game.profile.xp,28);
    expect(app.rewardSerial,0);
    expect(app.dailyGoal,35);
  });

test('FA006C invalid backup does not undo earlier accepted answer or rotate generation', () async {
    final app=await boot();
    final generation=app.progressGeneration;
    final oldStore=app.verbCards;
    final barrier=gate();
    probes[app]!.transactionGate=barrier;
    final accepted=answer(app);
    await barrier.entered.future;
    final invalid=app.restoreProgress('{"format":1}');
    final rejected=expectLater(invalid,throwsA(isA<FormatException>()));
    expect(app.progress.restoring,isTrue);
    barrier.release();
    await accepted;
    await rejected;
    expect(app.progressGeneration,generation);
    expect(identical(oldStore,app.verbCards),isTrue);
    expect(app.progress.accepting,isTrue);
    expect(app.verbCards.stateFor(refA).timesSeen,1);
    expect(app.stats.today()['cards_swiped'],1);
    expect(app.game.profile.xp,7);
    aligned(await snapshot(app));
    report('C_invalid_after_accepted',['A answer accepted and gated',
      'invalid restore accepted behind A','A commits','backup validation fails',
      'no import writes or generation change'],
      {'xp':7,'daily':1,'times_seen':1,'generation_unchanged':true});
  });

  testWidgets('FA007 real shell learning backup restore reentry and reopen',
      (tester) async {
    final app = (await tester.runAsync(boot))!;
    await tester.runAsync(() async {
      await app.setLevel(CefrLevel.a1);
      await app.setDailyGoal(5);
    });
    await show(tester, app, const AppShell());
    final shellState = tester.state(find.byType(AppShell));
    final events = <String>['A: A1 goal=5, real AppShell'];

    Future<void> startFromVisibleDeck() async {
      await tester.tap(find.text('Oturumu başlat'));
      await driveUntil(tester, () => find.byType(CardStack).evaluate().isNotEmpty);
      await tester.pumpAndSettle();
    }

    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }

    Future<void> openBackup() async {
      // Only the Android output-directory seam is replaced. The real screen,
      // export/import, JSON and flushed File.writeAsString remain untouched.
      // Keep the shell AND its active session underneath this pushed route.
      unawaited(Navigator.of(tester.element(find.byType(CardStack))).push<void>(
        MaterialPageRoute<void>(builder: (_) => BackupScreen(
          exportDirectory: () async => Directory(devicePath),
        )),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> answerWithPendingCheck(SwipeDirection direction) async {
      final boundary = gate();
      probes[app]!.transactionGate = boundary;
      final serial = app.rewardSerial;
      await swipe(tester, direction);
      await driveUntil(tester, () => boundary.entered.isCompleted);
      expect(find.text('Kaydediliyor…'), findsOneWidget);
      expect(find.text('Oturum bitti'), findsNothing);
      expect(app.rewardSerial, serial);
      boundary.release();
      await driveUntil(tester, () => app.rewardSerial == serial + 1);
      await tester.pumpAndSettle();
      expect(find.text('Oturum bitti'), findsOneWidget);
    }

    await startFromVisibleDeck();
    expect(tester.widget<SwipeSessionScreen>(find.byType(SwipeSessionScreen))
        .candidateIds, ['word-probe']);
    await answerWithPendingCheck(SwipeDirection.right);
    expect(app.cards.stateFor('word-probe').timesSeen, 1);
    expect(app.cards.stateFor('word-probe').box, 1);
    expect(app.game.profile.xp, 12);
    expect(app.game.profile.coins, 2);
    await back();
    await tester.tap(find.descendant(of: find.byType(NavigationBar),
        matching: find.text('Fiiller')));
    await tester.pumpAndSettle();
    final verbDeckState = tester.state(find.byType(VerbDeckScreen));
    await startFromVisibleDeck();
    expect(tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen))
        .selectedRefIds, [refA]);
    // Hard is an ordinary answer: box 0 stays due, allowing another real
    // session without changing the clock, SRS policy or persisted fixture.
    await answerWithPendingCheck(SwipeDirection.up);
    expect(app.verbCards.stateFor(refA).timesSeen, 1);
    expect(app.verbCards.stateFor(refA).starred, isTrue);
    expect(app.game.profile.xp, 19);
    expect(app.stats.today()['cards_swiped'], 2);
    expect(app.stats.today()['new_learned'], 1);
    events.add('B: word right + verb hard committed; XP=19 coins=2 daily=2');
    final backedUp = (await tester.runAsync(() => snapshot(app)))!;
    aligned(backedUp);
    final wordBefore = cardFields(app.cards.stateFor('word-probe'));

    await back();
    await startFromVisibleDeck();
    await openBackup();
    await tester.tap(find.text('Yedek al'));
    await driveUntil(tester, () =>
        find.textContaining('panoya kopyalandı').evaluate().isNotEmpty ||
        find.textContaining('Yedek alınamadı').evaluate().isNotEmpty);
    expect(find.textContaining('panoya kopyalandı'), findsOneWidget);
    final files = Directory(devicePath).listSync().whereType<File>()
        .where((file) => file.path.endsWith('.json')).toList();
    expect(files, hasLength(1));
    final backup = files.single.readAsStringSync();
    final json = jsonDecode(backup) as Map<String, dynamic>;
    final rows = json['card_state'] as List<dynamic>;
    expect(rows.map((dynamic row) => '${row['card_type']}:${row['ref_id']}'),
        unorderedEquals(['word:word-probe', 'conjugation:$refA']));
    expect(rows.every((dynamic row) => row['times_seen'] == 1), isTrue);
    final wordRow = rows.singleWhere((dynamic row) => row['card_type'] == 'word')
        as Map<String, dynamic>;
    for (final field in wordBefore.entries) {
      expect(wordRow[field.key], field.value);
    }
    expect((json['game_profile'] as List).single['xp'], 19);
    expect((json['daily_stats'] as List).single['cards_swiped'], 2);
    events.add('C: BackupScreen wrote real JSON file with both cards');

    await back();
    await answerWithPendingCheck(SwipeDirection.up);
    await tester.runAsync(() => app.setDailyGoal(35));
    expect(app.game.profile.xp, 26);
    expect(app.verbCards.stateFor(refA).timesSeen, 2);
    expect(app.stats.today()['cards_swiped'], 3);
    expect(app.dailyGoal, 35);
    expect(files.single.readAsStringSync(), backup);
    events.add('D: extra real verb answer; XP=26 daily=3 goal=35');

    await back();
    await startFromVisibleDeck();
    final staleStore = app.verbCards;
    final oldGeneration = app.progressGeneration;
    await openBackup();
    await tester.enterText(find.byType(TextField), backup);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.tap(find.widgetWithText(FilledButton, 'Geri yükle'));
    await tester.pumpAndSettle();
    expect(find.text('Mevcut ilerleme silinecek'), findsOneWidget);
    expect(app.game.profile.xp, 26, reason: 'confirmation has not imported yet');
    final serialBeforeRestore = app.rewardSerial;
    await tester.tap(find.descendant(of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Geri yükle')));
    await driveUntil(tester, () =>
        find.textContaining('hemen yenilendi').evaluate().isNotEmpty);
    expect(app.progressGeneration, oldGeneration + 1);
    expect(app.rewardSerial, serialBeforeRestore);
    expect(app.dailyGoal, 5);
    expect(app.level, CefrLevel.a1);
    final restored = (await tester.runAsync(() => snapshot(app)))!;
    aligned(restored);
    for (final key in ['cards_db', 'daily_db', 'profile_db',
        'quests_db', 'achievements_db']) {
      expect(restored[key], backedUp[key], reason: '$key overwritten from backup');
    }
    expect(app.cards.stateFor('word-probe').timesSeen, 1);
    expect(cardFields(app.cards.stateFor('word-probe')), wordBefore);
    await tester.runAsync(() => expectLater(
        staleStore.save(staleStore.stateFor(refA)),
        throwsA(isA<ProgressUnavailable>())));
    events.add('E: confirmed restore returned XP=19 daily=2 goal=5; no reward');

    await back();
    await swipe(tester, SwipeDirection.right);
    await tester.pumpAndSettle();
    expect(find.textContaining('oturum eskidi'), findsOneWidget);
    expect(find.byType(CardStack), findsOneWidget);
    expect(app.rewardSerial, serialBeforeRestore);
    expect(app.verbCards.stateFor(refA).timesSeen, 1);
    // Dismiss the real transient message with a user gesture before tapping
    // the bottom launch button; an overlaid SnackBar is not a stale route.
    await tester.drag(find.byType(SnackBar), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await back();
    // Normal back + tab navigation, without pumpWidget/show/reset. Assert
    // retained State identity so constructor-only reentry cannot mask a bug.
    await tester.tap(find.descendant(of: find.byType(NavigationBar),
        matching: find.text('Kelimeler')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationBar),
        matching: find.text('Fiiller')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AppShell)), same(shellState));
    expect(tester.state(find.byType(VerbDeckScreen)), same(verbDeckState));
    await startFromVisibleDeck();
    expect(tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen))
        .selectedRefIds, [refA]);
    await swipe(tester, SwipeDirection.right);
    await driveUntil(tester, () => app.rewardSerial == serialBeforeRestore + 1);
    await tester.pumpAndSettle();
    expect(find.text('Oturum bitti'), findsOneWidget);
    expect(app.verbCards.stateFor(refA).timesSeen, 2);
    expect(app.verbCards.stateFor(refA).timesRight, 1);
    expect(app.verbCards.stateFor(refA).box, 1);
    expect(app.game.profile.xp, 26);
    expect(app.game.profile.coins, 2);
    expect(app.stats.today()['cards_swiped'], 3);
    final finalState = (await tester.runAsync(() => snapshot(app)))!;
    aligned(finalState);
    events.add('F: stale session rejected; SAME retained shell/deck opened new session');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => app.close());
    final reopened = (await tester.runAsync(boot))!;
    final reopenedState = (await tester.runAsync(() => snapshot(reopened)))!;
    aligned(reopenedState);
    for (final key in ['cards_db', 'daily_db', 'profile_db',
        'quests_db', 'achievements_db']) {
      expect(reopenedState[key], finalState[key], reason: '$key survives normal close');
    }
    expect(reopened.cards.stateFor('word-probe').timesSeen, 1);
    expect(cardFields(reopened.cards.stateFor('word-probe')), wordBefore);
    expect(reopened.dailyGoal, 5);
    expect(reopened.level, CefrLevel.a1);
    expect(tester.takeException(), isNull);
    events.add('G: normal close + reopen same temporary directory preserved final state');
    debugPrintSynchronously('FA007_RESULT ${jsonEncode({
      'events': events,
      'backup_bytes': files.single.lengthSync(),
      'backup': backedUp,
      'restored': restored,
      'final': reopenedState,
      'word_ref_id': 'word-probe', 'verb_ref_id': refA,
      'word_fields_preserved': wordBefore,
      'retained_shell_and_verb_deck': true,
      'real_backup_screen_directory_only_injection': true,
    })}');
  });

  testWidgets('FA006C new real verb session after restore continues B card state', (tester) async {
    final app=(await tester.runAsync(boot))!;
    final data=jsonDecode((await tester.runAsync(backupB))!) as Map<String,dynamic>;
    // B uses the same real fixture conjugation in this experiment, with 4
    // previous successful answers. It is distinct from A's empty progress.
    (data['card_state'] as List).single['ref_id']=refA;
    await tester.runAsync(()=>app.restoreProgress(jsonEncode(data)));
    expect(app.verbCards.stateFor(refA).timesSeen,4);
    expect(app.verbCards.stateFor(refA).box,3);
    await startVerb(tester,app);
    await swipe(tester,SwipeDirection.right);
    await driveUntil(tester,()=>app.rewardSerial==1);
    expect(app.verbCards.stateFor(refA).timesSeen,5);
    expect(app.verbCards.stateFor(refA).box,4);
    expect(app.game.profile.xp,35);
    expect(app.stats.today()['cards_swiped'],5);
    expect(tester.takeException(),isNull);
    report('C_new_session_B',['restore B with real conjugation refId',
      'open real VerbDeckScreen','start session','animate answer','commit'],
      {'ref_id':refA,'before_box':3,'after_box':4,'before_seen':4,
       'after_seen':5,'xp':35,'daily':5});
  });

}
