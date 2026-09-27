import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/srs/srs_card.dart';
import 'package:french_app/domain/srs/session_builder.dart';
import 'package:french_app/domain/verb.dart';
import 'package:french_app/features/verbs/verb_screens.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:french_app/motion/swipe_direction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String verbId(int i) => 'v${i.toString().padLeft(3, '0')}';

class ObservedDatabase implements Database {
  ObservedDatabase(this.delegate);
  final Database delegate;
  final List<String> queries = <String>[];
  final List<List<Object?>> parameters = <List<Object?>>[];

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) {
    queries.add(sql);
    parameters.add(List<Object?>.of(arguments ?? <Object?>[]));
    return delegate.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final TestWidgetsFlutterBinding binding =
      TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  AppState? currentApp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('frenchapp_fa005_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (_) async => <String>[],
    );
  });
  tearDown(() async {
    await currentApp?.close();
    currentApp = null;
    for (final String channel in <String>[
      'plugins.flutter.io/path_provider',
      'flutter_tts',
    ]) {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), null);
    }
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await temp.delete(recursive: true);
  });

  Future<AppState> boot({
    int count = 11,
    bool leadingWithoutTense = false,
    Future<void> Function(Database db)? customize,
  }) async {
    final String path = '${temp.path}/fixture.db';
    final Database db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE words (id TEXT, freq_rank INTEGER)');
    await db.execute('''CREATE TABLE examples (
      word_id TEXT, ordinal INTEGER, sentence_fr TEXT, sentence_en TEXT,
      sentence_tr TEXT, sentence_fr_id INTEGER, author_fr TEXT,
      sentence_en_id INTEGER, author_en TEXT, sentence_tr_id INTEGER,
      author_tr TEXT)''');
    await db.execute(
        'CREATE TABLE word_relations (word_id TEXT, related_id TEXT, ordinal INTEGER)');
    await db.execute('CREATE TABLE meta (key TEXT, value TEXT)');
    await db.execute('''CREATE TABLE verbs (id TEXT PRIMARY KEY,
      infinitive TEXT, auxiliary TEXT, level TEXT, freq_rank INTEGER,
      needs_review INTEGER, is_reflexive INTEGER, group_no INTEGER)''');
    await db.execute('''CREATE TABLE conjugations (
      verb_id TEXT, tense TEXT, person TEXT, form TEXT,
      PRIMARY KEY (verb_id, tense, person))''');
    await db.transaction((Transaction tx) async {
      // Reverse insertion order ensures repository order is explicit.
      for (int i = count - 1; i >= 0; i--) {
        final String id = verbId(i);
        await tx.insert('verbs', <String, Object?>{
          'id': id,
          'infinitive': 'verbe$id',
          'auxiliary': 'avoir',
          'level': 'A1',
          'freq_rank': i,
          'needs_review': 0,
          'is_reflexive': 0,
          'group_no': 3,
        });
        for (final String tense in <String>['present', 'imparfait']) {
          if (leadingWithoutTense && i < count - 1 && tense == 'present') {
            continue;
          }
          for (final String person
              in (i < count - 1 ? kPersons : <String>['je']).reversed) {
            await tx.insert('conjugations', <String, Object?>{
              'verb_id': id,
              'tense': tense,
              'person': person,
              'form': '$id-$tense-$person',
            });
          }
        }
      }
    });
    if (customize != null) await customize(db);
    await db.close();
    final Uint8List bytes = await File(path).readAsBytes();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async =>
          const StringCodec().decodeMessage(message) == 'assets/db/content.db'
              ? ByteData.sublistView(bytes)
              : null,
    );
    final AppState app = await AppState.create();
    currentApp = app;
    await app.setLevel(CefrLevel.a1);
    await app.setDailyGoal(5);
    await app.setReducedMotion(true);
    return app;
  }

  Future<void> archiveLeading(AppState app, {int count = 10}) async {
    for (int i = 0; i < count; i++) {
      for (final String person in kPersons) {
        await app.verbCards.save(SrsCard(
          refId: '${verbId(i)}:present:$person',
          status: CardStatus.archived,
          timesSeen: 1,
        ));
      }
    }
  }

  Future<void> show(WidgetTester tester, AppState app) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(AppScope(
      state: app,
      child: const MaterialApp(home: VerbDeckScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Oturumu başlat'));
    for (int i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(VerbSessionScreen).evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  List<String> visibleDeck(WidgetTester tester) {
    final Finder finder = find.byType(CardStack);
    if (finder.evaluate().isEmpty) return <String>[];
    final CardStack stack = tester.widget<CardStack>(finder);
    return <String>[
      for (int i = 0; i < stack.itemCount; i++)
        (stack.itemBuilder(tester.element(finder), i) as ConjugationCard)
            .conjugation
            .refId,
    ];
  }

  testWidgets('fresh conjugation beyond old prepool reaches real session',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot();
      await archiveLeading(app);
      expect(app.verbCards.snapshot().length, 60);
      return app;
    }))!;
    await show(tester, app);
    await start(tester);
    expect(visibleDeck(tester), contains('v010:present:je'));
  });

  testWidgets('due tail card is answered under its real conjugation id',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot();
      await archiveLeading(app);
      await app.verbCards.save(SrsCard(
        refId: 'v010:present:je',
        box: 1,
        timesSeen: 2,
        timesRight: 1,
        dueAt: DateTime.utc(2000),
        status: CardStatus.learning,
      ));
      await app.verbCards.save(const SrsCard(refId: 'missing:present:je'));
      await app.verbCards.save(const SrsCard(refId: 'v010:present:tu'));
      return app;
    }))!;
    late List<Map<String, Object?>> before;
    await tester.runAsync(() async {
      before = await app.db.progress.query('card_state',
          where: 'ref_id != ?',
          whereArgs: <Object?>['v010:present:je'],
          orderBy: 'ref_id');
    });
    await show(tester, app);
    await start(tester);
    expect(visibleDeck(tester), <String>['v010:present:je']);
    final CardStack stack = tester.widget<CardStack>(find.byType(CardStack));
    stack.controller!.swipe(SwipeDirection.right);
    await tester.pump(); // Start the animation ticker before advancing time.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    // The answer now commits before cache/reward publication. Pump the Flutter
    // zone until that named completion; do not block it on a competing DB query.
      for (int i = 0; i < 250 && app.rewardSerial == 0; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(app.rewardSerial, 1);
    await tester.pump();
    await tester.runAsync(() async {
      final List<Map<String, Object?>> rows = await app.db.progress.query(
        'card_state',
        where: 'ref_id = ? AND card_type = ?',
        whereArgs: <Object?>['v010:present:je', 'conjugation'],
      );
      expect(rows.single['times_seen'], 3);
      expect(rows.single['times_right'], 2);
      expect(
          await app.db.progress.query('card_state',
              where: 'ref_id != ?',
              whereArgs: <Object?>['v010:present:je'],
              orderBy: 'ref_id'),
          before);
    });
    await tester.pumpWidget(const SizedBox.shrink());
    bool closed = false;
    unawaited(app.close().then((_) {
      closed = true;
    }));
      for (int i = 0; i < 250 && !closed; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(closed, isTrue);
    currentApp = null; // Already closed in its Flutter async zone.
  });

  testWidgets('missing tense in the first slice does not hide later forms',
      (WidgetTester tester) async {
    final AppState app =
        (await tester.runAsync(() => boot(leadingWithoutTense: true)))!;
    await show(tester, app);
    await start(tester);
    expect(visibleDeck(tester), <String>['v010:present:je']);
  });

  for (final bool reflexive in <bool>[true, false]) {
    testWidgets(
        'mixed candidates retain ${reflexive ? 'reflexive' : 'plain'} and irregular filters',
        (WidgetTester tester) async {
      final AppState app = (await tester.runAsync(() async {
        final AppState app = await boot(
            count: 12,
            customize: (Database db) async {
              await db.update('verbs',
                  <String, Object?>{'is_reflexive': reflexive ? 1 : 0});
              await db.update('verbs', <String, Object?>{'needs_review': 1},
                  where: "id = 'v004'");
              await db.update('verbs', <String, Object?>{'level': 'B2'},
                  where: "id = 'v005'");
              await db.update(
                  'verbs', <String, Object?>{'is_reflexive': reflexive ? 0 : 1},
                  where: "id = 'v006'");
              await db.update('verbs', <String, Object?>{'group_no': 1},
                  where: "id = 'v007'");
            });
        for (int i = 0; i < 12; i++) {
          for (final String person in i == 11 ? <String>['je'] : kPersons) {
            if (i >= 2 && i <= 7) continue;
            await app.verbCards.save(SrsCard(
              refId: '${verbId(i)}:present:$person',
              timesSeen: 1,
              status: i == 1 ? CardStatus.learning : CardStatus.archived,
              dueAt: DateTime.utc(2100),
            ));
          }
        }
        for (final String person in kPersons) {
          await app.verbCards.save(SrsCard(
              refId: 'v003:present:$person',
              timesSeen: 1,
              dueAt: DateTime.utc(2000)));
        }
        return app;
      }))!;
      await show(tester, app);
      final Finder choice =
          find.widgetWithText(ChoiceChip, reflexive ? 'Dönüşlü' : 'Dönüşsüz');
      await tester.ensureVisible(choice);
      await tester.tap(choice);
      final Finder irregular = find.byType(SwitchListTile);
      await tester.ensureVisible(irregular);
      await tester.tap(irregular);
      await tester.pumpAndSettle();
      await start(tester);
      final List<String> selected = visibleDeck(tester);
      expect(selected.length, 5);
      expect(selected.toSet().length, 5);
      expect(selected.where((String id) => id.startsWith('v003:')).length, 4);
      expect(selected.where((String id) => id.startsWith('v002:')).length, 1);
      expect(
          selected.every(
              (String id) => id.startsWith('v002:') || id.startsWith('v003:')),
          isTrue);
      final VerbSessionScreen session =
          tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen));
      expect(session.conjugations.length,
          12); // Two six-person tables, five SRS cards.
      expect(
          session.conjugations.every((Conjugation c) =>
              c.verb.isReflexive == reflexive && c.verb.isIrregular),
          isTrue);
    });
  }

  test(
      'real references preserve fixed-time SRS balance, order and includeNotDue',
      () async {
    final AppState app = await boot();
    final List<Verb> verbs = await app.verbs.byLevels(app.activeLevels);
    final List<String> refs =
        await app.verbs.conjugationRefIdsForTense(verbs, VerbTense.present);
    final DateTime now = DateTime.utc(2026, 9, 12);
    final Map<String, SrsCard> states = <String, SrsCard>{
      for (final String id in refs)
        id: SrsCard(refId: id, status: CardStatus.archived),
      'missing:present:je': const SrsCard(refId: 'missing:present:je'),
    };
    for (int i = 0; i < 7; i++) {
      final String id = '${verbId(i)}:present:je';
      states[id] = SrsCard(
          refId: id,
          timesSeen: 1,
          starred: i == 6,
          dueAt: now.subtract(Duration(days: 7 - i)));
    }
    for (int i = 7; i < 10; i++) {
      states.remove('${verbId(i)}:present:je');
    }
    states['v010:present:je'] = SrsCard(
        refId: 'v010:present:je',
        timesSeen: 1,
        dueAt: now.add(const Duration(days: 1)));
    final List<String> selected = SessionBuilder.build(
        candidateRefIds: refs, states: states, now: now, size: 10);
    expect(
        selected,
        <int>[6, 0, 1, 7, 2, 3, 8, 4, 5, 9]
            .map((int i) => '${verbId(i)}:present:je')
            .toList());
    expect(
        SessionBuilder.build(
            candidateRefIds: refs, states: states, now: now, size: 11),
        hasLength(10));
    final List<String> withFuture = SessionBuilder.build(
        candidateRefIds: refs,
        states: states,
        now: now,
        size: 11,
        includeNotDue: true);
    expect(withFuture, hasLength(11));
    expect(withFuture, contains('v010:present:je'));
    expect(withFuture, isNot(contains('missing:present:je')));
  });

  test('805 verbs cross query batches without missing or duplicate real refs',
      () async {
    final AppState app = await boot(
        count: 805,
        customize: (Database db) async {
          await db.insert('conjugations', <String, Object?>{
            'verb_id': 'v804',
            'tense': 'present',
            'person': 'unsupported',
            'form': 'ignored',
          });
        });
    final List<Verb> verbs = await app.verbs.byLevels(app.activeLevels);
    expect(await app.verbs.byLevels(app.activeLevels, limit: 7), hasLength(7));
    final ObservedDatabase observed = ObservedDatabase(app.db.content);
    final VerbRepository repository = VerbRepository(observed);
    final List<String> refs = await repository.conjugationRefIdsForTense(
        <Verb>[...verbs, verbs.first], VerbTense.present);
    final List<String> expected = <String>[
      for (int i = 0; i < 805; i++)
        for (final String person in i == 804 ? <String>['je'] : kPersons)
          '${verbId(i)}:present:$person',
    ];
    expect(refs, expected);
    expect(refs.toSet().length, 4825);
    expect(observed.queries, hasLength(3));
    expect(
        observed.queries.every(
            (String sql) => sql.startsWith('SELECT verb_id, person FROM')),
        isTrue);
    expect(observed.parameters.map((List<Object?> p) => p.length),
        <int>[401, 401, 6]);
    final Map<String, SrsCard> states = <String, SrsCard>{
      for (final String id in refs)
        id: SrsCard(refId: id, status: CardStatus.archived),
    };
    states.remove('v800:present:je');
    states.remove('v804:present:je');
    final List<String> selected = SessionBuilder.build(
        candidateRefIds: refs,
        states: states,
        now: DateTime.utc(2026, 9, 12),
        size: 5);
    expect(selected, <String>['v800:present:je', 'v804:present:je']);
    final List<Conjugation> loaded = await repository.conjugationsForTense(
        <Verb>[verbs[800], verbs[804]], VerbTense.present);
    expect(loaded.map((Conjugation c) => c.refId), <String>[
      for (final String p in kPersons) 'v800:present:$p',
      'v804:present:je'
    ]);
    expect(observed.queries.length, 4);
    expect(observed.parameters.last, <Object?>['present', 'v800', 'v804']);
    expect(
        loaded.every((Conjugation c) => c.tense == VerbTense.present), isTrue);
    // The form loader also handles multiple batches when explicitly requested.
    final List<Conjugation> all = await repository
        .conjugationsForTense(<Verb>[...verbs, verbs.first], VerbTense.present);
    expect(all.map((Conjugation c) => c.refId), expected);
    expect(observed.queries.length, 7);
  });

  testWidgets(
      'all archived or future cards produce empty state without rewards',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot();
      await archiveLeading(app);
      await app.verbCards.save(SrsCard(
          refId: 'v010:present:je', timesSeen: 1, dueAt: DateTime.utc(2100)));
      return app;
    }))!;
    final int xp = app.game.profile.xp;
    final int coins = app.game.profile.coins;
    late List<Map<String, Object?>> before;
    await tester.runAsync(() async {
      before = await app.db.progress.query('card_state', orderBy: 'ref_id');
    });
    await show(tester, app);
    await start(tester);
    expect(find.text('Bu filtre ve zaman için çalışılabilir fiil yok.'),
        findsOneWidget);
    expect(find.byType(VerbSessionScreen), findsNothing);
    expect(app.game.profile.xp, xp);
    expect(app.game.profile.coins, coins);
    await tester.runAsync(() async {
      expect(
          await app.db.progress.query('card_state', orderBy: 'ref_id'), before);
    });
  });

  testWidgets('in-flight start captures tense and ignores a second start',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    await show(tester, app);
    // Capture real UI callbacks before starting. No fake repository or route.
    final VoidCallback launch = tester
        .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Oturumu başlat'))
        .onPressed!;
    launch();
    launch();
    await tester.tap(find.text(VerbTense.imparfait.label));
    for (int i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(VerbSessionScreen).evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    final VerbSessionScreen session =
        tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen));
    expect(session.tense, VerbTense.present);
    expect(visibleDeck(tester), <String>[
      'v000:present:je',
      'v000:present:tu',
      'v000:present:il',
      'v000:present:nous',
      'v000:present:vous'
    ]);
    expect(find.byType(VerbSessionScreen, skipOffstage: false), findsOneWidget);
    Navigator.of(tester.element(find.byType(VerbSessionScreen))).pop();
    await tester.pumpAndSettle();
    await start(tester);
    expect(
        tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen)).tense,
        VerbTense.imparfait);
  });
}
