import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/domain/lesson.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/verb.dart';
import 'package:french_app/features/grammar/grammar_screens.dart';
import 'package:french_app/features/verbs/verb_screens.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
    temp = await Directory.systemTemp.createTemp('frenchapp_fa004_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
    // No native speech engine or network service is used.
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

  Future<AppState> boot({VerbTense? emptyTense}) async {
    if (emptyTense != null) {
      // Mutate only an isolated asset fixture; the packaged DB stays untouched.
      final File fixture =
          await File('assets/db/content.db').copy('${temp.path}/fixture.db');
      final Database db = await databaseFactoryFfi.openDatabase(fixture.path);
      await db.delete('conjugations',
          where: 'tense = ?', whereArgs: <Object?>[emptyTense.key]);
      await db.close();
      final Uint8List bytes = await fixture.readAsBytes();
      binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (ByteData? message) async =>
            const StringCodec().decodeMessage(message) == 'assets/db/content.db'
                ? ByteData.sublistView(bytes)
                : null,
      );
    }
    final AppState app = await AppState.create();
    currentApp = app;
    await app.setLevel(CefrLevel.a1);
    await app.setReducedMotion(true);
    return app;
  }

  Future<void> show(WidgetTester tester, AppState app, Widget screen) async {
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

  void expectSelected(WidgetTester tester, VerbTense tense) {
    final AnimatedContainer tile = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text(tense.label),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final Border border = (tile.decoration! as BoxDecoration).border! as Border;
    expect(border.top.width, 2, reason: '${tense.key} must be selected');
  }

  Future<void> openLesson(
      WidgetTester tester, AppState app, VerbTense tense) async {
    late GrammarLesson lesson;
    await tester.runAsync(() async {
      lesson = (await app.lessons.all())
          .firstWhere((GrammarLesson l) => l.tenseKey == tense.key);
    });
    await show(tester, app, LessonScreen(lesson: lesson));
    await tester.tap(find.text('${tense.label} ile pratik yap'));
    await tester.pumpAndSettle();
    expect(find.byType(VerbDeckScreen), findsOneWidget);
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Oturumu başlat'));
    // SQLite performs real IO; give it real time without an unbounded loop.
    for (int i = 0; i < 20; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(VerbSessionScreen).evaluate().isNotEmpty ||
          find.byType(SnackBar).evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('normal verb entry keeps present default',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    await show(tester, app, const VerbDeckScreen());
    expectSelected(tester, VerbTense.present);
  });

  for (final VerbTense tense in <VerbTense>[
    VerbTense.passeCompose,
    VerbTense.imparfait,
  ]) {
    testWidgets('lesson ${tense.key} selects its tense and builds real cards',
        (WidgetTester tester) async {
      final AppState app = (await tester.runAsync(boot))!;
      await openLesson(tester, app, tense);
      expectSelected(tester, tense);
      await start(tester);
      final VerbSessionScreen session =
          tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen));
      expect(session.tense, tense);
      expect(session.conjugations, isNotEmpty);
      for (final Conjugation card in session.conjugations) {
        expect(card.tense, tense);
        expect(card.refId, '${card.verb.id}:${tense.key}:${card.person}');
        expect(card.form, isNotEmpty);
        expect(card.verb.level, CefrLevel.a1);
      }
      final CardStack stack = tester.widget<CardStack>(find.byType(CardStack));
      expect(stack.itemCount, greaterThan(0));
      for (int i = 0; i < stack.itemCount; i++) {
        final ConjugationCard rendered = stack.itemBuilder(
            tester.element(find.byType(CardStack)), i) as ConjugationCard;
        expect(rendered.conjugation.tense, tense);
        expect(rendered.conjugation.refId,
            '${rendered.conjugation.verb.id}:${tense.key}:${rendered.conjugation.person}');
      }
      expect(app.level, CefrLevel.a1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('user tense survives route rebuild and AppState notification',
      (WidgetTester tester) async {
    final AppState app = (await tester.runAsync(boot))!;
    await openLesson(tester, app, VerbTense.passeCompose);
    await tester.tap(find.text(VerbTense.imparfait.label));
    await tester.pumpAndSettle();
    final Element deck = tester.element(find.byType(VerbDeckScreen));
    deck.markNeedsBuild();
    app.notifyProgressChanged();
    await tester.pumpAndSettle();
    expectSelected(tester, VerbTense.imparfait);
    await start(tester);
    final VerbSessionScreen session =
        tester.widget<VerbSessionScreen>(find.byType(VerbSessionScreen));
    expect(session.tense, VerbTense.imparfait);
    expect(
        session.conjugations
            .every((Conjugation c) => c.tense == VerbTense.imparfait),
        isTrue);
  });

  for (final String? key in <String?>[null, 'unknown_tense', 'subjonctif']) {
    testWidgets('unavailable lesson tense $key offers no misleading practice',
        (WidgetTester tester) async {
      final AppState app = (await tester.runAsync(boot))!;
      await show(
          tester,
          app,
          LessonScreen(
              lesson: GrammarLesson(
            id: 'synthetic',
            slug: 'synthetic',
            title: 'Sentetik ders',
            level: CefrLevel.a1,
            sortOrder: 0,
            bodyMd: 'Test.',
            tenseKey: key,
          )));
      expect(find.textContaining('ile pratik yap'), findsNothing);
      expect(find.byType(VerbDeckScreen), findsNothing);
      expect(app.level, CefrLevel.a1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'empty lesson tense stays selected and does not fall back to present',
      (WidgetTester tester) async {
    final AppState app =
        (await tester.runAsync(() => boot(emptyTense: VerbTense.imparfait)))!;
    await tester.runAsync(() async {
      final List<Verb> verbs = await app.verbs.byLevels(app.activeLevels);
      expect(await app.verbs.conjugationsForTense(verbs, VerbTense.present),
          isNotEmpty); // A fallback would incorrectly create a session.
    });
    await openLesson(tester, app, VerbTense.imparfait);
    final int xp = app.game.profile.xp;
    final int coins = app.game.profile.coins;
    await start(tester);
    expect(find.text('Bu filtre ve zaman için çalışılabilir fiil yok.'),
        findsOneWidget);
    expect(find.byType(VerbSessionScreen), findsNothing);
    expectSelected(tester, VerbTense.imparfait);
    expect(app.game.profile.xp, xp);
    expect(app.game.profile.coins, coins);
    expect(app.verbCards.snapshot(), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
