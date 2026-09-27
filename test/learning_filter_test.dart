import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/srs/session_builder.dart';
import 'package:french_app/domain/srs/srs_card.dart';
import 'package:french_app/domain/word.dart';
import 'package:french_app/features/quiz/quiz_engine.dart';
import 'package:french_app/features/quiz/quiz_screen.dart';
import 'package:french_app/features/vocab/deck_select_screen.dart';
import 'package:french_app/features/vocab/swipe_session_screen.dart';
import 'package:french_app/features/vocab/word_card.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Synthetic content delivered through the same asset boundary as production.
// AppDatabase creates only a fresh progress DB in this test's temporary folder.
Map<String, Object?> wordRow(
  String id, {
  bool needsReview = false,
  bool idiom = false,
  bool function = false,
  String level = 'A1',
  String theme = 'general',
}) =>
    <String, Object?>{
      'id': id,
      'lemma_fr': 'fr_$id',
      'meaning_en': 'en_$id',
      'meaning_tr': 'tr_$id',
      'pos': 'NOM',
      'level': level,
      'theme': theme,
      'freq_rank': 1,
      'needs_review': needsReview ? 1 : 0,
      'reviewed': 0,
      'is_idiom': idiom ? 1 : 0,
      'is_function': function ? 1 : 0,
    };

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
    temp = await Directory.systemTemp.createTemp('frenchapp_fa002_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
  });
  tearDown(() async {
    await currentApp?.close();
    currentApp = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    binding.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
    await temp.delete(recursive: true);
  });

  Future<AppState> boot(List<Map<String, Object?>> rows) async {
    final String path = '${temp.path}/fixture.db';
    final Database db = await databaseFactoryFfi.openDatabase(path);
    try {
      await db.execute('''CREATE TABLE words (
        id TEXT PRIMARY KEY, lemma_fr TEXT, meaning_en TEXT, meaning_tr TEXT,
        pos TEXT, level TEXT, theme TEXT, freq_rank INTEGER,
        needs_review INTEGER, reviewed INTEGER, is_idiom INTEGER,
        is_function INTEGER)''');
      await db.execute('''CREATE TABLE examples (
        word_id TEXT, ordinal INTEGER, sentence_fr TEXT, sentence_en TEXT,
        sentence_tr TEXT, sentence_fr_id INTEGER, author_fr TEXT,
        sentence_en_id INTEGER, author_en TEXT, sentence_tr_id INTEGER,
        author_tr TEXT)''');
      await db.execute('''CREATE TABLE word_relations (
        word_id TEXT, related_id TEXT, ordinal INTEGER)''');
      await db.execute('CREATE TABLE meta (key TEXT, value TEXT)');
      await db.execute('CREATE TABLE verbs (id TEXT, freq_rank INTEGER)');
      for (final Map<String, Object?> row in rows) {
        await db.insert('words', row);
        final String id = row['id']! as String;
        await db.insert('examples', <String, Object?>{
          'word_id': id,
          'ordinal': 0,
          'sentence_fr': 'Voici fr_$id.',
          'sentence_en': 'Example en_$id.',
          'sentence_tr': 'Örnek tr_$id.',
        });
      }
    } finally {
      await db.close();
    }
    final Uint8List bytes = await File(path).readAsBytes();
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        final String? key = const StringCodec().decodeMessage(message);
        return key == 'assets/db/content.db'
            ? ByteData.sublistView(bytes)
            : null;
      },
    );
    final AppState app = await AppState.create();
    currentApp = app;
    await app.setReducedMotion(true);
    return app;
  }

  Future<List<Object?>> progressSnapshot(AppState app) async => <Object?>[
        for (final String table in <String>[
          'card_state',
          'daily_stats',
          'game_profile',
          'daily_quests',
          'achievements',
          'journey_progress',
          'flagged_cards',
          'app_settings',
          'story_progress',
          'sentence_progress',
        ])
          await app.db.progress.query(table, orderBy: 'rowid'),
      ];

  Future<void> showScreen(
    WidgetTester tester,
    AppState app,
    Widget screen,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(AppScope(
      state: app,
      child: MaterialApp(home: screen),
    ));
    await tester.pumpAndSettle();
  }

  // Inspect every card supplied to the real CardStack, including offscreen cards.
  List<String> sessionIds(WidgetTester tester) {
    final Finder finder = find.byType(CardStack);
    final CardStack stack = tester.widget<CardStack>(finder);
    return <String>[
      for (int i = 0; i < stack.itemCount; i++)
        (stack.itemBuilder(tester.element(finder), i) as WordCard).word.id,
    ];
  }

  Future<void> revealDeck(WidgetTester tester, String title) async {
    await tester.tap(find.byKey(const ValueKey<String>('deck_options_toggle')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  test('FA-002: eski quiz kaydi needsReview hedefini kabul etmez', () async {
    final AppState app = await boot(<Map<String, Object?>>[
      wordRow('blocked', needsReview: true),
      for (int i = 0; i < 4; i++) wordRow('safe$i'),
    ]);
    await app.cards.save(const SrsCard(
      refId: 'blocked',
      box: 2,
      timesSeen: 3,
      starred: true,
    ));
    final List<Map<String, Object?>> before =
        await app.db.progress.query('card_state');
    final List<QuizQuestion> questions = await QuizEngine.build(
      app: app,
      wordIds: app.cards.quizPool().map((SrsCard c) => c.refId).toList(),
      verbRefIds: <String>[],
      count: 12,
      rng: Random(2),
    );
    expect(
        questions.map((QuizQuestion q) => q.refId), isNot(contains('blocked')),
        reason: 'needsReview karti eski quiz havuzundan hedef olamaz');
    expect(questions, isEmpty);
    expect(await app.db.progress.query('card_state'), before);
  });

  test(
      'FA-002: normal deste seviye tema function arsiv ve SRS kurallarini korur',
      () async {
    final AppState app = await boot(<Map<String, Object?>>[
      wordRow('fresh'),
      wordRow('due'),
      wordRow('future'),
      wordRow('archived'),
      wordRow('blocked', needsReview: true),
      wordRow('higher', level: 'C1'),
      wordRow('function', function: true),
      wordRow('food', theme: 'food'),
    ]);
    final DateTime now = DateTime(2026, 9, 12);
    await app.cards.save(SrsCard(
      refId: 'due',
      box: 1,
      timesSeen: 1,
      dueAt: now.subtract(const Duration(days: 1)),
    ));
    await app.cards.save(SrsCard(
      refId: 'future',
      box: 1,
      timesSeen: 1,
      dueAt: now.add(const Duration(days: 1)),
    ));
    await app.cards.save(const SrsCard(
      refId: 'archived',
      status: CardStatus.archived,
    ));
    final List<Object?> before = await progressSnapshot(app);
    final List<String> candidates = app.words.candidateIds(
      levels: <CefrLevel>[CefrLevel.a1],
      theme: WordTheme.general,
    );
    expect(candidates,
        unorderedEquals(<String>['fresh', 'due', 'future', 'archived']));
    expect(app.words.byId('fresh')!.needsReview, isFalse);
    expect(
        (await app.db.content
                .query('words', where: 'id=?', whereArgs: <Object?>['fresh']))
            .single['reviewed'],
        0);
    List<String> build(bool includeNotDue) => SessionBuilder.build(
          candidateRefIds: app.words.learningIds(candidates),
          states: app.cards.snapshot(),
          now: now,
          size: 20,
          includeNotDue: includeNotDue,
        );
    expect(build(false), unorderedEquals(<String>['fresh', 'due']));
    expect(build(true), unorderedEquals(<String>['fresh', 'due', 'future']));
    expect(await progressSnapshot(app), before);
  });

  for (final String title in <String>[
    'Yıldızlılar',
    'Zorlandıklarım',
    'Deyimler ve kalıplar',
  ]) {
    testWidgets('FA-002: $title karisik havuzu filtreler ve kayitlari korur',
        (WidgetTester tester) async {
      final AppState app = (await tester.runAsync(() async {
        final AppState app = await boot(<Map<String, Object?>>[
          wordRow('safe'),
          wordRow('blocked', needsReview: true),
          wordRow('higher_function', level: 'C1', function: true),
          wordRow('idiom', level: 'B2', idiom: true),
          wordRow('blocked_idiom', level: 'B2', idiom: true, needsReview: true),
          wordRow('archived'),
        ]);
        for (final String id in <String>[
          'safe',
          'blocked',
          'higher_function',
          'idiom',
          'blocked_idiom',
          'archived',
          'missing',
        ]) {
          await app.cards.save(SrsCard(
            refId: id,
            box: 2,
            timesSeen: 3,
            lapses: 6,
            starred: true,
            status:
                id == 'archived' ? CardStatus.archived : CardStatus.learning,
            dueAt: DateTime.now().add(const Duration(days: 365)),
          ));
        }
        return app;
      }))!;
      final List<Object?> before =
          (await tester.runAsync(() => progressSnapshot(app)))!;
      await showScreen(tester, app, const DeckSelectScreen());
      await revealDeck(tester, title);
      final List<String> expected = title == 'Deyimler ve kalıplar'
          ? <String>['idiom']
          : <String>['safe', 'higher_function', 'idiom'];
      if (title != 'Deyimler ve kalıplar') {
        final Finder tile = find
            .ancestor(
              of: find.text(title),
              matching: find.byType(InkWell),
            )
            .first;
        final int count = expected.length;
        expect(
            find.descendant(
                of: tile, matching: find.text('$count çalışılabilir kelime')),
            findsOneWidget);
      }
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(sessionIds(tester), unorderedEquals(expected));
      expect(sessionIds(tester), isNot(contains('blocked')));
      expect(sessionIds(tester), isNot(contains('blocked_idiom')));
      expect(sessionIds(tester), isNot(contains('missing')));
      expect(await tester.runAsync(() => progressSnapshot(app)), before);
      expect(app.cards.stateFor('blocked').starred, isTrue);
      expect(app.cards.stateFor('missing').box, 2);
    });
  }

  testWidgets(
      'FA-002: sarki kaydetme API kaydi saklar ama bos oturum odul vermez',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot(<Map<String, Object?>>[
        wordRow('blocked', needsReview: true),
      ]);
      // Same storage call as SongPlayerScreen and PopularSongScreen.
      await app.cards.star('blocked');
      await app.cards
          .save(const SrsCard(refId: 'missing', starred: true, box: 2));
      return app;
    }))!;
    final List<Object?> before =
        (await tester.runAsync(() => progressSnapshot(app)))!;
    expect(app.words.byId('blocked'), isNotNull);
    expect(app.words.all().map((Word w) => w.id), contains('blocked'));
    expect(app.words.search('fr_blocked').map((hit) => hit.word.id),
        contains('blocked'));
    await showScreen(
        tester,
        app,
        SwipeSessionScreen(
          title: 'Kaydedilenler',
          candidateIds:
              app.cards.starred().map((SrsCard c) => c.refId).toList(),
          includeNotDue: true,
        ));
    expect(find.text('Bu oturum için çalışılabilir kart yok.'), findsOneWidget);
    expect(find.byType(CardStack), findsNothing);
    expect(find.text('Oturum bitti'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(await tester.runAsync(() => progressSnapshot(app)), before);
    expect(app.cards.stateFor('blocked').starred, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'FA-002: dogrudan oturum girdisi filtreden sonra guvenli kartla dolar',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot(<Map<String, Object?>>[
        for (int i = 0; i < 8; i++) wordRow('blocked$i', needsReview: true),
        wordRow('safe'),
        wordRow('other'),
      ]);
      await app.setDailyGoal(5);
      return app;
    }))!;
    await showScreen(
        tester,
        app,
        SwipeSessionScreen(
          title: 'Doğrudan',
          candidateIds: <String>[
            for (int i = 0; i < 8; i++) 'blocked$i',
            'missing',
            'safe',
            'other',
          ],
        ));
    expect(sessionIds(tester), unorderedEquals(<String>['safe', 'other']));
    expect(tester.takeException(), isNull);
  });

  test('FA-002: quiz hedefleri ve tum secenek turleri yalniz uygun iceriktir',
      () async {
    final AppState app = await boot(<Map<String, Object?>>[
      wordRow('blocked', needsReview: true),
      wordRow('blocked_idiom', idiom: true, needsReview: true),
      for (int i = 0; i < 4; i++) wordRow('safe$i'),
    ]);
    final Set<QuizKind> seenKinds = <QuizKind>{};
    final Set<String> forbidden = <String>{
      for (final Word w
          in app.words.all().where((Word w) => w.needsReview)) ...<String>[
        w.display,
        w.lemma,
        w.meaningTr
      ],
    };
    for (int seed = 0; seed < 12; seed++) {
      final List<QuizQuestion> questions = await QuizEngine.build(
        app: app,
        wordIds: <String>['blocked', 'missing', 'blocked_idiom', 'safe0'],
        verbRefIds: <String>[],
        count: 12,
        rng: Random(seed),
      );
      expect(questions.map((QuizQuestion q) => q.refId), <String>['safe0']);
      final QuizQuestion q = questions.single;
      seenKinds.add(q.kind);
      expect(forbidden, isNot(contains(q.correct)));
      expect(q.options.any(forbidden.contains), isFalse);
      final Set<String> allowed = app.words
          .all()
          .where((Word w) => !w.needsReview)
          .map((Word w) => q.kind == QuizKind.frToTr ? w.meaningTr : w.lemma)
          .toSet();
      expect(q.options.toSet(), allowed);
      expect(q.options, contains(q.correct));
    }
    expect(
        seenKinds,
        containsAll(<QuizKind>[
          QuizKind.frToTr,
          QuizKind.trToFr,
          QuizKind.cloze,
        ]));
  });

  testWidgets(
      'FA-002: yetersiz quiz secenekleri uygunsuz kartlarla tamamlanmaz',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot(<Map<String, Object?>>[
        wordRow('target'),
        wordRow('safe1'),
        wordRow('safe2'),
        for (int i = 0; i < 4; i++) wordRow('blocked$i', needsReview: true),
      ]);
      await app.cards
          .save(const SrsCard(refId: 'target', box: 1, timesSeen: 1));
      return app;
    }))!;
    expect(
        app.words
            .distractorsFor(app.words.byId('target')!)
            .map((Word w) => w.id),
        unorderedEquals(<String>['safe1', 'safe2']));
    final List<Object?> before =
        (await tester.runAsync(() => progressSnapshot(app)))!;
    await showScreen(tester, app, const QuizScreen());
    await tester.tap(find.widgetWithText(FilledButton, 'Başla'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Soru üretilemedi.'), findsOneWidget);
    expect(await tester.runAsync(() => progressSnapshot(app)), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FA-002: uygunsuz ve eksik eski kartlar quiz sayisini sisirmez',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(() async {
      final AppState app = await boot(<Map<String, Object?>>[
        wordRow('blocked', needsReview: true),
        for (int i = 0; i < 4; i++) wordRow('safe$i'),
      ]);
      for (final String id in <String>['blocked', 'missing']) {
        await app.cards.save(SrsCard(refId: id, box: 3, timesSeen: 4));
      }
      return app;
    }))!;
    final List<Object?> before =
        (await tester.runAsync(() => progressSnapshot(app)))!;
    await showScreen(tester, app, const QuizScreen());
    expect(find.textContaining('Henüz soru havuzu yok.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Başla'))
            .onPressed,
        isNull);
    expect(await tester.runAsync(() => progressSnapshot(app)), before);
    expect(tester.takeException(), isNull);
  });
}
