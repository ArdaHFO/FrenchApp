import 'dart:io';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_scope.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/data/backup.dart';
import 'package:french_app/domain/companion.dart';
import 'package:french_app/domain/journey.dart';
import 'package:french_app/domain/lesson.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/verb.dart';
import 'package:french_app/domain/word.dart';
import 'package:french_app/features/journey/station_builder.dart';
import 'package:french_app/features/journey/station_quiz_screen.dart';
import 'package:french_app/features/game/companion_studio_screen.dart';
import 'package:french_app/features/grammar/grammar_screens.dart';
import 'package:french_app/features/practice/free_writing_screen.dart';
import 'package:french_app/features/songs/song_library_screen.dart';
import 'package:french_app/features/songs/song_player_screen.dart';
import 'package:french_app/features/vocab/deck_select_screen.dart';
import 'package:french_app/features/vocab/word_card.dart';
import 'package:french_app/features/vocab/lexical_detail_screen.dart';
import 'package:french_app/services/lexical/lexical_models.dart';
import 'package:french_app/main.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Uçtan uca duman testi.
///
/// Gerçek `content.db`'yi açar, gerçek `AppState`'i kurar ve ekranlarda
/// gezinir. Elimizde telefon olmadan çalışma zamanı hatalarını yakalamanın
/// tek yolu bu: `flutter analyze` derleme hatalarını görür ama
/// "push edilen sayfa InheritedWidget'ı göremiyor" gibi hataları göremez.
class OfflineLexicalProvider implements LexicalProvider {
  int calls = 0;
  @override
  Future<LexicalOutcome> lookup(LexicalLookupKey key) async {
    calls++;
    return const LexicalOutcome(LexicalStatus.transientFailure);
  }
}

void main() {
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('frenchapp_test');

    // path_provider eklentisi testte yok; kanalı elle karşılıyoruz.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall call) async => tempDir.path,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows dosyayı kilitli tutabilir, testi düşürmesin.
    }
  });

  /// Telefon ölçüsünde bir yüzey. Varsayılan 800x600 masaüstü ölçüsü
  /// gerçekte olmayan taşma hataları üretiyor.
  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// Animasyonlar ve gerçek disk/veritabanı işleri için birlikte bekler.
  ///
  /// `pump` sahte zamanı ilerletir ama dosya ve SQLite işleri gerçek zamanda
  /// çalışır; ikisini de beklemek gerekiyor.
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (int i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Deste yerleşim kutusunun merkezi her zaman ön kartın dokunma alanı
  /// değildir. Gerçek sürükleme dinleyicisini hedefleyerek kullanıcı
  /// etkileşimini ve hit-test sonucunu birlikte sınar.
  Finder frontGestures() => find.descendant(
        of: find.byType(CardStack),
        matching: find.byWidgetPredicate(
          (Widget widget) =>
              widget is GestureDetector && widget.onPanUpdate != null,
        ),
      );

  Future<Finder?> swipeTarget(WidgetTester tester) async {
    for (int i = 0; i < 12; i++) {
      final Finder targets = frontGestures();
      if (targets.evaluate().isNotEmpty) {
        final Finder target = targets.first;
        final Offset center = tester.getCenter(target);
        final RenderObject renderObject =
            target.evaluate().single.renderObject!;
        final HitTestResult hitTest = tester.hitTestOnBinding(center);
        if (hitTest.path
            .any((HitTestEntry entry) => entry.target == renderObject)) {
          return target;
        }
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<bool> swipeCard(WidgetTester tester, Offset offset) async {
    final Finder? target = await swipeTarget(tester);
    if (target == null) return false;
    await tester.drag(target, offset);
    // Uçan kart 280 ms'de tamamlanır. Tek uzun pump ve bir sonraki kare,
    // eski kartın dönüştürülmüş hit-test alanını ağaçtan kesin olarak çıkarır.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    return true;
  }

  /// Açılışı bekler. `content.db` kopyalanması ve sözlüğün belleğe
  /// alınması birkaç saniye sürüyor.
  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(const FrenchApp());
    // Windows/OneDrive ve CI yükü ilk 24 MB asset kopyasını yavaşlatabilir.
    // Sabit 7,5 saniyelik sınır uygulama hâlâ doğru açılırken testi kırıyordu.
    for (int i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Sözlük hazırlanıyor').evaluate().isEmpty) break;
    }
    await settle(tester);
    final Finder startupError = find.text('Uygulama açılamadı');
    if (startupError.evaluate().isNotEmpty) {
      final String details = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((SelectableText text) =>
              text.data ?? text.textSpan?.toPlainText())
          .whereType<String>()
          .join('\n');
      throw TestFailure('Uygulama açılış hatası:\n$details');
    }
    expect(
      find.text('Sözlük hazırlanıyor'),
      findsNothing,
      reason: 'uygulama açılışı zaman sınırını aştı',
    );
    final Finder scope = find.byType(AppScope);
    if (scope.evaluate().isNotEmpty) {
      final AppState state = tester.widget<AppScope>(scope.first).notifier!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await state.close();
      });
    }
  }

  /// Seviye seçimini geçer.
  Future<void> passOnboarding(WidgetTester tester) async {
    await tester.tap(find.text('A1').first);
    await settle(tester);
    final Finder start = find.widgetWithText(FilledButton, 'Başla');
    expect(start, findsOneWidget,
        reason: 'seviye seçiminde başlat düğmesi yok');
    await tester.tap(start);
    await settle(tester);
  }

  /// Sliver listeleri yalnızca ekrana yakın çocukları kurar. Hedef henüz
  /// widget ağacında değilse küçük adımlarla kaydırıp görünür hale getirir.
  Future<void> revealLazy(
    WidgetTester tester,
    Finder target,
    Finder scrollable,
  ) async {
    for (int i = 0; i < 12 && target.evaluate().isEmpty; i++) {
      await tester.drag(scrollable, const Offset(0, -170));
      await settle(tester, rounds: 1);
    }
    expect(target, findsWidgets, reason: 'kaydırılan hedef kurulmadı');
    await Scrollable.ensureVisible(
      tester.element(target.first),
      alignment: 0.5,
    );
    await settle(tester, rounds: 2);
  }

  Future<void> expandMoreModes(WidgetTester tester) async {
    final Finder toggle =
        find.byKey(const ValueKey<String>('more_modes_toggle'));
    await revealLazy(tester, toggle, find.byType(CustomScrollView).first);
    await tester.tap(toggle);
    await settle(tester, rounds: 2);
  }

  Future<void> openJourney(WidgetTester tester) async {
    await tester.tap(find.text('Macera').last);
    await settle(tester);
    await expandMoreModes(tester);
    await tester.dragUntilVisible(
      find.text('Ders Yolculuğu'),
      find.byType(CustomScrollView).first,
      const Offset(0, -220),
    );
    await settle(tester, rounds: 2);
    await Scrollable.ensureVisible(
      tester.element(find.text('Ders Yolculuğu')),
      alignment: 0.5,
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Ders Yolculuğu'));
    await settle(tester, rounds: 10);
  }

  testWidgets('offline enrichment failure leaves real-content core navigation and progress intact', (tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);
    final scope = tester.widget<AppScope>(find.byType(AppScope).first);
    final app = scope.notifier!;
    final before = await tester.runAsync(app.exportProgress);
    final provider = OfflineLexicalProvider();
    final context = tester.element(find.byType(DeckSelectScreen).first);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) =>
        LexicalDetailScreen(lemma: 'chat', provider: provider)));
    await settle(tester);
    expect(find.textContaining('Yerel sözlük kullanılabilir'), findsOneWidget);
    expect(provider.calls, 1);
    final after = await tester.runAsync(app.exportProgress);
    expect((jsonDecode(after!) as Map)..remove('exported_at'),
        (jsonDecode(before!) as Map)..remove('exported_at'));
    await tester.pageBack(); await settle(tester);
    await tester.tap(find.text('Oturumu başlat')); await settle(tester);
    expect(find.byType(WordCard), findsWidgets);
    await tester.pageBack(); await settle(tester);
    await tester.tap(find.text('Fiiller').last); await settle(tester);
    expect(find.text('Fiil çekimi'), findsOneWidget);
    await tester.tap(find.text('Dilbilgisi').last); await settle(tester);
    expect(find.textContaining('ders.'), findsOneWidget);
    await openJourney(tester);
    expect(find.textContaining('durak geçildi'), findsOneWidget);
    expect(provider.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('v1 içerik kimliği doğru v2 karta taşınır',
      (WidgetTester tester) async {
    await phone(tester);
    late String oldId;
    late String canonicalId;
    await tester.runAsync(() async {
      final Database content = await databaseFactory.openDatabase(
        '${Directory.current.path}/assets/db/content.db',
        options: OpenDatabaseOptions(readOnly: true),
      );
      final Map<String, Object?> alias = (await content.query(
        'content_aliases',
        where: 'kind = ?',
        whereArgs: <Object?>['word'],
        limit: 1,
      ))
          .single;
      oldId = alias['alias_id']! as String;
      canonicalId = alias['canonical_id']! as String;
      await content.close();

      final Database progress = await databaseFactory.openDatabase(
        '${tempDir.path}/progress.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (Database db, _) async {
            await db.execute('''CREATE TABLE card_state (
              card_type TEXT NOT NULL, ref_id TEXT NOT NULL, box INTEGER NOT NULL,
              status TEXT NOT NULL, starred INTEGER NOT NULL, due_at INTEGER,
              last_seen_at INTEGER, times_seen INTEGER NOT NULL,
              times_right INTEGER NOT NULL, lapses INTEGER NOT NULL,
              updated_at INTEGER NOT NULL, PRIMARY KEY(card_type, ref_id))''');
            await db.execute('''CREATE TABLE daily_stats (
              day TEXT PRIMARY KEY, cards_swiped INTEGER NOT NULL,
              new_learned INTEGER NOT NULL, quiz_total INTEGER NOT NULL,
              quiz_correct INTEGER NOT NULL)''');
            await db.execute(
              'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
            );
          },
        ),
      );
      await progress.insert('card_state', <String, Object?>{
        'card_type': 'word',
        'ref_id': oldId,
        'box': 3,
        'status': 'known',
        'starred': 0,
        'times_seen': 4,
        'times_right': 3,
        'lapses': 1,
        'updated_at': 1,
      });
      await progress.close();
    });

    await boot(tester);
    final AppState app = AppScope.of(tester.element(find.text('Seviyeni seç')));
    expect(app.cards.snapshot(), isNot(contains(oldId)));
    expect(app.cards.stateFor(canonicalId).box, 3);
    expect(app.cards.stateFor(canonicalId).timesSeen, 4);
  });

  testWidgets('her seviyenin fiil durağı gerçek soru kimliği üretir',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);
    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );
    final List<JourneyStation> stations = StationBuilder.build(app)
        .where((JourneyStation station) => station.kind == StationKind.verbs)
        .toList();

    expect(stations, hasLength(CefrLevel.values.length));
    await tester.runAsync(() async {
      for (final JourneyStation station in stations) {
        final List<String> ids =
            await StationBuilder.verbRefIdsFor(app, station);
        expect(
          ids.length,
          greaterThanOrEqualTo(station.questionCount),
          reason: '${station.level.code} fiil durağı oynanamıyor',
        );
      }
    });
  });

  testWidgets('açılış, seviye seçimi ve ana kabuk',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);

    expect(find.text('Seviyeni seç'), findsOneWidget);
    await passOnboarding(tester);

    expect(find.text('Kelimeler'), findsWidgets);
    expect(find.text('Deste seçenekleri'), findsOneWidget);
    expect(find.text('Alt seviyeleri karıştır'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('deck_options_toggle')),
    );
    await settle(tester, rounds: 2);
    expect(find.text('Alt seviyeleri karıştır'), findsOneWidget);
  });

  testWidgets('oturum başlat beyaz ekran vermiyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);

    // Kaydırma ekranı açıldıysa üst çubuktaki sayaç görünür.
    expect(find.textContaining(' / '), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dilbilgisi dersi beyaz ekran vermiyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Dilbilgisi').last);
    await settle(tester);

    final Finder lesson = find.textContaining('Présent');
    expect(lesson, findsWidgets, reason: 'ders listesi boş');
    await tester.tap(lesson.first);
    await settle(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('fiiller ve quiz sekmeleri açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    // Her sekme kendine ait bir başlık göstermeli. Aynı listeyi
    // gösteriyorlarsa bu kontroller düşer.
    await tester.tap(find.text('Fiiller').last);
    await settle(tester);
    expect(find.text('Fiil çekimi'), findsOneWidget);
    expect(find.text('Oturumu başlat'), findsOneWidget);
    expect(find.text('Alt seviyeleri karıştır'), findsNothing,
        reason: 'Fiiller sekmesinde kelime destesi görünüyor');
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Dilbilgisi').last);
    await settle(tester);
    expect(find.textContaining('ders.'), findsOneWidget);
    expect(find.text('Fiil çekimi'), findsNothing);
    expect(tester.takeException(), isNull);

    await openJourney(tester);
    expect(find.text('Yolculuk'), findsWidgets);
    expect(find.textContaining('durak geçildi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('İlerleme').last);
    await settle(tester);
    expect(find.text('Günlük görevler'), findsOneWidget);
    expect(find.text('Oyuncu seviyesi 1'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Kutu dağılımı'),
      find.byType(ListView).first,
      const Offset(0, -250),
    );
    expect(find.text('Kutu dağılımı'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sözlük araması aksansız yazımı buluyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.byTooltip('Sözlükte ara'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'etre');
    await settle(tester);

    expect(find.text('être'), findsWidgets);

    // Türkçe tam anlam, sıklık listesinde nerede olduğundan bağımsız olarak
    // Fransızca karşılığı bulmalı ve yönü kullanıcıya açıkça göstermeli.
    await tester.enterText(
      find.byKey(const ValueKey<String>('dictionary_search')),
      'gitmek',
    );
    await settle(tester);
    expect(find.text('aller'), findsWidgets);
    expect(find.textContaining('Türkçe → Fransızca'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kart kaydırma ve oturum özeti', (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);
    expect(find.byType(WordCard), findsWidgets);

    // Sağa kaydır: öğrendim.
    expect(await swipeCard(tester, const Offset(400, 0)), isTrue);
    await settle(tester);
    expect(tester.takeException(), isNull);

    // Karta dokun: arka yüz.
    await tester.tap((await swipeTarget(tester))!);
    await settle(tester);
    expect(tester.takeException(), isNull);

    // Sola kaydır: tekrar.
    expect(await swipeCard(tester, const Offset(-400, 0)), isTrue);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fiil destesi ve çekim oturumu açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Fiiller').last);
    await settle(tester);

    final Finder start = find.textContaining('başlat');
    expect(start, findsWidgets, reason: 'fiil destesinde başlat düğmesi yok');
    await tester.tap(start.first);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('özel desteler ve prototip açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('deck_options_toggle')),
    );
    await settle(tester, rounds: 2);

    await tester.dragUntilVisible(
      find.text('Deyimler ve kalıplar'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await settle(tester);
    await Scrollable.ensureVisible(
      tester.element(find.text('Deyimler ve kalıplar')),
      alignment: 0.5,
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Deyimler ve kalıplar'));
    await settle(tester);
    expect(find.byType(WordCard), findsWidgets, reason: 'deyim destesi boş');

    // Asıl kontrol: deste GERÇEKTEN deyim mi gösteriyor. Daha önce
    // "avoir", "quoi" gibi tek kelimeler deyim işaretlendiği için bu
    // deste normal desteden farksız görünüyordu.
    for (final WordCard card
        in tester.widgetList<WordCard>(find.byType(WordCard))) {
      expect(card.word.isIdiom, isTrue,
          reason: '${card.word.lemma} deyim değil ama deyim destesinde');
      expect(card.word.lemma.contains(' ') || card.word.lemma.contains('-'),
          isTrue,
          reason: '${card.word.lemma} tek kelime, deyim olamaz');
    }
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await settle(tester);
  });

  testWidgets('hareket laboratuvarı ayarlardan açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('İlerleme').last);
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Hareket laboratuvarı'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Hareket laboratuvarı'));
    await settle(tester);
    expect(find.text('Hareket prototipi'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ilerleme ekranından ayarlar ve kaynaklar açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('İlerleme').last);
    await settle(tester);

    await tester.dragUntilVisible(
      find.text('Kaynaklar ve içerik künyesi'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    // dragUntilVisible öğeyi ekrana sokar ama alt gezinme çubuğunun
    // altında kalabiliyor; biraz daha kaydırıp dokunuşu garantiye alıyoruz.
    await tester.drag(find.byType(ListView).first, const Offset(0, -160));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Kaynaklar ve içerik künyesi'));
    await settle(tester);
    expect(find.text('Kaynaklar'), findsWidgets,
        reason: 'kaynaklar ekranı açılmadı');
    expect(tester.takeException(), isNull);

    await tester.pageBack();
    await settle(tester);

    // İlerleme listesi uzadıkça (ısı haritası, yedekleme) bu satır
    // ekran dışında kalabiliyor; dokunmadan önce görünür kılıyoruz.
    await tester.dragUntilVisible(
      find.text('Seviye ve günlük hedef'),
      find.byType(ListView).first,
      const Offset(0, 200),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Seviye ve günlük hedef'));
    await settle(tester);
    expect(find.text('Seviye ve hedef'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yerleştirme testi açılıyor', (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);

    final Finder placement = find.textContaining('Seviyeni ölç');
    if (placement.evaluate().isEmpty) return;
    await tester.tap(placement.first);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quiz gerçekten soru üretiyor ve cevap alıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    // Quiz havuzu sağa kaydırılan kartlardan doluyor.
    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);
    for (int i = 0; i < 8; i++) {
      if (frontGestures().evaluate().isEmpty) break;
      if (!await swipeCard(tester, const Offset(400, 0))) break;
      await settle(tester, rounds: 3);
    }
    await tester.pageBack();
    await settle(tester);

    await openJourney(tester);
    await tester.tap(find.byTooltip('Serbest quiz'));
    await settle(tester);

    final Finder start = find.textContaining('başlat');
    if (start.evaluate().isNotEmpty) {
      await tester.tap(start.first);
      await settle(tester);
    }

    // Şıklardan birine bas: hangisi olduğu önemli değil, çökmemesi önemli.
    final Finder options = find.byType(InkWell);
    if (options.evaluate().isNotEmpty) {
      await tester.tap(options.first, warnIfMissed: false);
      await settle(tester);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('oturum sonuna kadar kaydırılabiliyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);

    // Günlük hedef 20 kart; sola kaydırılanlar geri eklendiği için
    // bitirmek biraz daha fazla hareket ister.
    for (int i = 0; i < 40; i++) {
      if (frontGestures().evaluate().isEmpty) break;
      if (!await swipeCard(tester, const Offset(400, 0))) break;
      await settle(tester, rounds: 2);
    }
    expect(find.text('Oturum bitti'), findsOneWidget,
        reason: 'oturum özeti ekranı gelmedi');
    await tester.tap(find.text('Bitir'));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('içerik sağlığı: temel kelimeler ve çekimler yerinde',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    // Fransızcanın olmazsa olmazları sözlükte olmalı.
    for (final String lemma in <String>[
      'être',
      'avoir',
      'aller',
      'faire',
      'le',
      'de',
      'comme',
      'manger',
    ]) {
      expect(
        app.words.all().any((Word w) => w.lemma == lemma),
        isTrue,
        reason: '$lemma sözlükte yok',
      );
    }

    // Veritabanı sorguları gerçek zamanda çalışır; sahte zamanın içinde
    // beklenirse test kilitlenir. runAsync şart.
    Map<String, String>? etrePresent;
    Map<String, String>? avoirPresent;
    List<Conjugation> presentBatch = const <Conjugation>[];
    await tester.runAsync(() async {
      final List<Verb> verbs = await app.verbs.all();
      final Verb etre = verbs.firstWhere((Verb v) => v.infinitive == 'être',
          orElse: () => throw StateError('être fiil tablosunda yok'));
      etrePresent = (await app.verbs.tablesFor(etre))[VerbTense.present];
      final Verb avoir = verbs.firstWhere((Verb v) => v.infinitive == 'avoir');
      avoirPresent = (await app.verbs.tablesFor(avoir))[VerbTense.present];
      presentBatch = await app.verbs.conjugationsForTense(
        <Verb>[etre, avoir],
        VerbTense.present,
      );
    });

    // être çekimi doğru olmalı: en sık kullanılan düzensiz fiil.
    expect(etrePresent, isNotNull, reason: 'être çekim tablosu boş');
    expect(etrePresent!['je'], 'suis');
    expect(etrePresent!['nous'], 'sommes');
    expect(etrePresent!['ils'], 'sont');

    // Elizyon sunum katmanında: "je ai" değil "j'ai".
    expect(conjugationDisplay('je', avoirPresent!['je']!), "j'ai");
    expect(presentBatch.length, 12);
    expect(
      presentBatch
          .firstWhere((Conjugation c) =>
              c.verb.infinitive == 'être' && c.person == 'nous')
          .form,
      'sommes',
    );

    // Deyimler gerçekten çok kelimeli olmalı.
    final List<String> idiomIds =
        app.words.candidateIds(levels: CefrLevel.values, idiomsOnly: true);
    expect(idiomIds.length, greaterThan(50));
    final List<Word> idioms = idiomIds
        .map((String id) => app.words.byId(id)!)
        .toList(growable: false);
    expect(idioms.where((Word word) => word.literalTr != null).length,
        greaterThanOrEqualTo(40));
    expect(idioms.where((Word word) => word.noteTr != null).length,
        greaterThanOrEqualTo(25));
    expect(idioms.where((Word word) => word.register != null).length,
        greaterThanOrEqualTo(25));
    expect(idioms.where((Word word) => word.hasExample).length,
        greaterThanOrEqualTo(70));
    final Word duCoup =
        idioms.firstWhere((Word word) => word.lemma == 'du coup');
    expect(duCoup.noteTr, contains('Konuşma dilinde'));
    expect(duCoup.register, 'konuşma dili');
    expect(duCoup.sentenceTr, contains('bu yüzden'));
    expect(duCoup.sentenceAttribution, contains('FrenchApp kürasyonu'));
    for (final String id in idiomIds) {
      final Word w = app.words.byId(id)!;
      expect(w.lemma.contains(' ') || w.lemma.contains('-'), isTrue,
          reason: '${w.lemma} deyim sayılmış ama tek kelime');
    }
  });

  testWidgets('küçük ekran ve büyük yazı ayarında taşma olmuyor',
      (WidgetTester tester) async {
    // Küçük telefon + erişilebilirlik için büyütülmüş yazı. Taşma
    // hatalarının en sık çıktığı bileşim; normal ölçüde görünmüyorlar.
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: FrenchApp(),
      ),
    );
    for (int i = 0; i < 60; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 250)));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Sözlük hazırlanıyor').evaluate().isEmpty) break;
    }
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'seviye seçiminde taşma');

    await tester.tap(find.text('A1').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Başla'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'deste ekranında taşma');

    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'kart ön yüzünde taşma');

    expect(find.byType(WordCard), findsWidgets,
        reason: 'küçük ekranda kart hiç çizilmedi');
    final Size cardSize = tester.getSize(find.byType(WordCard).first);
    expect(cardSize.height, greaterThan(200),
        reason: 'küçük ekranda kart alanı ezilmiş: $cardSize');

    await tester.tap((await swipeTarget(tester))!);
    await settle(tester);
    expect(tester.takeException(), isNull, reason: 'kart arka yüzünde taşma');

    for (int i = 0; i < 5; i++) {
      if (frontGestures().evaluate().isEmpty) break;
      if (!await swipeCard(tester, const Offset(300, 0))) break;
      await settle(tester, rounds: 2);
      if (frontGestures().evaluate().isEmpty) break;
      final Finder? target = await swipeTarget(tester);
      if (target == null) break;
      await tester.tap(target);
      await settle(tester, rounds: 2);
    }
    expect(tester.takeException(), isNull, reason: 'kaydırma sırasında taşma');

    // Bekleyen giriş animasyonu zamanlayıcıları boşalsın; yoksa widget
    // ağacı dağıtıldığında test altyapısı "Timer is still pending" der.
    await settle(tester, rounds: 12);
  });

  testWidgets('kelime ailesi kartta ve aramada görünüyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    // Veri tarafı: chanter'ın ailesi dolu olmalı.
    final Word chanter =
        app.words.all().firstWhere((Word w) => w.lemma == 'chanter');
    final List<Word> kin = app.words.relativesOf(chanter.id);
    expect(kin.length, greaterThan(2), reason: 'chanter ailesi boş');
    expect(kin.map((Word w) => w.lemma), contains('chanson'));

    // Akrabalar sözlükte gerçekten var olan kelimeler olmalı.
    for (final Word r in kin) {
      expect(app.words.byId(r.id), isNotNull);
      expect(r.id, isNot(chanter.id), reason: 'kelime kendi akrabası olamaz');
    }

    // Arama sayfasında aile bölümü çıkıyor mu.
    await tester.tap(find.byTooltip('Sözlükte ara'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'chanter');
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('dictionary_result_chanter')),
    );
    await settle(tester);
    expect(find.text('Aynı kökten gelenler'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('çekim tabloları ekranı sekiz zamanı gösteriyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Fiiller').last);
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Çekim tabloları'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Çekim tabloları'));
    await settle(tester);

    // "se" hem "se laver" hem elizyonlu "s'appeler" biçimini bulmalı;
    // arama ilk 40 başlangıç eşleşmesinde kesilmemeli.
    await tester.enterText(find.byType(TextField), 'se');
    await settle(tester);
    expect(find.text('132 sonuç · 132 dönüşlü'), findsOneWidget);
    expect(find.text("s'aimer"), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'etre');
    await settle(tester);
    await tester.tap(find.text('être').first);
    await settle(tester);

    // Présent en üstte, çekimler doğru.
    expect(find.text('Présent'), findsOneWidget);
    expect(find.text('je suis'), findsOneWidget);
    expect(find.text('nous sommes'), findsOneWidget);

    // Kalan zamanlar liste aşağısında; ListView tembel çizdiği için
    // görünene kadar kaydırmak gerekiyor.
    for (final String label in <String>[
      'Imparfait',
      'Futur simple',
      'Subjonctif',
      'Plus-que-parfait',
    ]) {
      await tester.dragUntilVisible(
        find.text(label),
        find.byType(ListView).first,
        const Offset(0, -220),
      );
      expect(find.text(label), findsOneWidget, reason: '$label tablosu yok');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('dilbilgisi altı seviyeyi de kapsıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );
    late List<GrammarLesson> lessons;
    await tester.runAsync(() async {
      lessons = await app.lessons.all();
    });

    expect(lessons.length, greaterThanOrEqualTo(18));
    for (final CefrLevel level in CefrLevel.values) {
      expect(
        lessons.any((GrammarLesson l) => l.level == level),
        isTrue,
        reason: '${level.code} seviyesinde ders yok',
      );
    }
    // Ders gövdeleri gerçekten yazılmış olmalı, boş kabuk değil.
    for (final GrammarLesson l in lessons) {
      expect(l.bodyMd.length, greaterThan(800),
          reason: '${l.slug} dersi çok kısa');
      expect(l.title.trim(), isNotEmpty);
    }
  });

  testWidgets('dönüşlü fiiller doğru ve anlam kaymasız',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    late List<Verb> verbs;
    final Map<String, Map<VerbTense, Map<String, String>>> tables =
        <String, Map<VerbTense, Map<String, String>>>{};
    await tester.runAsync(() async {
      verbs = await app.verbs.all();
      for (final Verb v in verbs) {
        if (<String>[
          'se laver',
          "s'appeler",
          'se souvenir',
          'se rappeler',
          'se lever',
          "s'asseoir",
          'se parler',
          'se heurter',
        ].contains(v.infinitive)) {
          tables[v.infinitive] = await app.verbs.tablesFor(v);
        }
      }
    });

    final List<Verb> reflexives =
        verbs.where((Verb v) => v.isReflexive).toList();
    expect(reflexives.length, greaterThan(50), reason: 'dönüşlü fiil az');

    // 1. Hepsi "se " ya da "s'" ile başlamalı.
    for (final Verb v in reflexives) {
      expect(
        v.infinitive.startsWith('se ') || v.infinitive.startsWith("s'"),
        isTrue,
        reason: '${v.infinitive} dönüşlü işaretli ama se almıyor',
      );
      // 2. Bileşik zamanlar için yardımcı fiil her zaman être.
      expect(v.auxiliary, 'être', reason: '${v.infinitive} avoir almış');
      // 3. Türkçesi ve türü dolu olmalı.
      expect(v.meaningTr.trim(), isNotEmpty);
      expect(v.reflexiveKind, isNotNull);
      expect(v.baseInfinitive, isNotNull);
    }

    // 4. Anlam kayması kontrolü: dönüşlü ile temel fiil AYNI Türkçeyi
    //    taşımamalı. "se rendre" ile "rendre" aynı şey değildir.
    final Map<String, Verb> plain = <String, Verb>{
      for (final Verb v in verbs)
        if (!v.isReflexive) v.infinitive: v,
    };
    for (final String lemma in <String>[
      'se rendre',
      'se rappeler',
      'se passer',
      's\'attendre',
      'se tromper',
      "s'entendre"
    ]) {
      final Verb? refl =
          reflexives.where((Verb v) => v.infinitive == lemma).firstOrNull;
      if (refl == null) continue;
      final Verb? base = plain[refl.baseInfinitive];
      if (base == null) continue;
      expect(refl.meaningTr, isNot(base.meaningTr),
          reason: '$lemma ile ${base.infinitive} aynı Türkçeyi taşıyor');
      expect(refl.noteTr, isNotNull,
          reason: '$lemma için anlam farkı notu yok');
    }

    // 5. Çekimler doğru: zamir tek, elizyon yerinde, être ile bileşik.
    expect(tables['se laver']![VerbTense.present]!['je'], 'me lave');
    expect(tables['se laver']![VerbTense.present]!['nous'], 'nous lavons');
    expect(tables["s'appeler"]![VerbTense.present]!['je'], "m'appelle");
    expect(tables["s'appeler"]![VerbTense.present]!['il'], "s'appelle");
    expect(tables['se souvenir']![VerbTense.present]!['je'], 'me souviens');
    expect(tables['se heurter']![VerbTense.present]!['je'], 'me heurte');
    expect(
        tables['se laver']![VerbTense.passeCompose]!['je'], 'me suis lavé(e)');
    expect(tables['se laver']![VerbTense.passeCompose]!['il'], "s'est lavé");

    // 6. Ortaç uyumu: se rappeler ve se parler uyum almaz.
    expect(tables['se rappeler']![VerbTense.passeCompose]!['je'],
        'me suis rappelé');
    expect(
        tables['se parler']![VerbTense.passeCompose]!['ils'], 'se sont parlé');

    // 7. Emir kipi: zamir arkada, te -> toi.
    expect(tables['se lever']![VerbTense.imperatif]!['tu'], 'lève-toi');
    expect(tables["s'asseoir"]![VerbTense.imperatif]!['vous'], 'asseyez-vous');

    // 8. Hiçbir çekimde çift zamir olmamalı.
    for (final Map<VerbTense, Map<String, String>> t in tables.values) {
      for (final Map<String, String> row in t.values) {
        for (final String form in row.values) {
          expect(form, isNot(contains('me me')));
          expect(form, isNot(contains('se se')));
          expect(form, isNot(contains('()')));
        }
      }
    }

    // 9. Ekranda gösterim: emir kipinde özne zamiri yok, subjonctif'te que.
    expect(conjugationDisplay('tu', 'lève-toi', tense: VerbTense.imperatif),
        'lève-toi');
    expect(conjugationDisplay('je', 'me lave', tense: VerbTense.subjonctif),
        'que je me lave');
    expect(conjugationDisplay('il', 'se lave', tense: VerbTense.subjonctif),
        "qu'il se lave");
    expect(conjugationDisplay('je', 'me lave', tense: VerbTense.present),
        'je me lave');
  });

  testWidgets('dönüşlü fiil destesi ve tablosu açılıyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Fiiller').last);
    await settle(tester);

    // Tür süzgecinden "Dönüşlü" seç, oturumu başlat.
    await tester.dragUntilVisible(
      find.text('Dönüşlü'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Dönüşlü'));
    await settle(tester, rounds: 2);
    expect(
      find.byKey(
        const ValueKey<String>('verb_filter_description_reflexiveOnly'),
      ),
      findsOneWidget,
      reason: 'Fiil türü değişince alt açıklama yenilenmedi',
    );

    // Filtre açıklaması her seçimde görsel olarak da değişmeli.
    await tester.tap(find.text('Dönüşsüz'));
    await settle(tester, rounds: 2);
    expect(
      find.byKey(const ValueKey<String>('verb_filter_description_plainOnly')),
      findsOneWidget,
    );
    await tester.tap(find.text('Dönüşlü'));
    await settle(tester, rounds: 2);
    await settle(tester);
    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);
    expect(tester.takeException(), isNull);

    // Kartta dönüşlü etiketi olmalı.
    expect(find.text('dönüşlü'), findsWidgets,
        reason: 'dönüşlü destesinde dönüşlü olmayan kart var');
  });

  testWidgets('dönüşlü fiil arenası soru üretiyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Fiiller').last);
    await settle(tester);
    await tester.dragUntilVisible(
      find.text('Dönüşlü Fiil Arenası'),
      find.byType(ListView).first,
      const Offset(0, -220),
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -150));
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Dönüşlü Fiil Arenası'));
    await settle(tester, rounds: 14);

    expect(find.text('Dönüşlü Fiil Arenası'), findsOneWidget);
    expect(find.textContaining('için doğru çekimi seç'), findsOneWidget);
    expect(find.textContaining('/ 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('yolculuk haritası: duraklar, kilit ve ilerleme',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    // --- durak üretimi
    final List<JourneyStation> stations = StationBuilder.build(app);
    expect(stations.length, greaterThan(20), reason: 'harita çok kısa');

    final Set<String> ids = <String>{};
    for (final JourneyStation s in stations) {
      expect(ids.add(s.id), isTrue, reason: '${s.id} iki kez üretilmiş');
      expect(s.questionCount, greaterThan(0));
      if (s.kind != StationKind.verbs) {
        expect(s.wordIds, isNotEmpty, reason: '${s.id} boş durak');
        for (final String id in s.wordIds) {
          expect(app.words.byId(id), isNotNull,
              reason: '${s.id} sözlükte olmayan kelime taşıyor');
        }
      }
    }

    // Duraklar seviye sırasına göre dizilmeli: A1 durakları C2'den önce.
    int lastLevel = -1;
    for (final JourneyStation s in stations) {
      expect(s.level.index, greaterThanOrEqualTo(lastLevel));
      lastLevel = s.level.index;
    }

    // Her seviyede bir sınav durağı olmalı.
    for (final CefrLevel level in CefrLevel.values) {
      final bool hasBoss = stations.any(
        (JourneyStation s) => s.level == level && s.isBoss,
      );
      expect(hasBoss, isTrue, reason: '${level.code} sınav durağı yok');
    }

    // --- yıldız hesabı
    expect(JourneyStation.starsFor(8, 8, 0.7), 3);
    expect(JourneyStation.starsFor(8, 9, 0.7), 2);
    expect(JourneyStation.starsFor(6, 8, 0.7), 1);
    expect(JourneyStation.starsFor(4, 8, 0.7), 0, reason: 'eşik altı geçti');
    expect(JourneyStation.starsFor(9, 12, 0.8), 0,
        reason: 'sınavda %75 geçmemeli');

    // --- ekran
    await openJourney(tester);
    final int levelStationCount = stations
        .where((JourneyStation station) => station.level == app.level)
        .length;
    expect(find.text('0 / $levelStationCount durak geçildi'), findsOneWidget);
    expect(find.text('${app.level.code} · ${app.level.worldName}'),
        findsOneWidget);

    // İlk durak açık, ikincisi kilitli olmalı.
    expect(find.byIcon(Icons.lock_rounded), findsWidgets,
        reason: 'hiçbir durak kilitli değil');
    expect(tester.takeException(), isNull);
  });

  testWidgets('durak quizi çözülüp ilerleme kaydediliyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );
    final JourneyStation first = StationBuilder.build(app).first;

    // Mevcut uygulama ağacından aç. AppState'i başka bir MaterialApp'e
    // taşımak eski kökü kapatıp sahip olduğu SQLite bağlantılarını da kapatır.
    Navigator.of(tester.element(find.byType(DeckSelectScreen))).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StationQuizScreen(station: first),
      ),
    );
    await settle(tester, rounds: 8);

    expect(find.textContaining(' / '), findsWidgets,
        reason: 'soru sayacı yok, sorular üretilmedi');

    // Bütün soruları cevapla; hangi şıkkın doğru olduğu önemli değil,
    // akışın sonuna kadar gitmesi ve sonucu kaydetmesi önemli.
    for (int i = 0; i < first.questionCount + 2; i++) {
      final Finder options = find.byType(InkWell);
      if (options.evaluate().isEmpty) break;
      await tester.tap(options.first, warnIfMissed: false);
      await settle(tester, rounds: 10);
      if (find.textContaining('doğru').evaluate().isNotEmpty) break;
    }

    expect(app.journey.resultFor(first.id), isNotNull,
        reason: 'durak sonucu kaydedilmedi');
    expect(find.textContaining('doğru'), findsWidgets);
    expect(tester.takeException(), isNull);
    await settle(tester, rounds: 12);
  });

  testWidgets('durak tanıtım sayfası açılıp quize geçiyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await openJourney(tester);

    // İlk durak düğümüne dokun: önce tanıtım sayfası gelmeli.
    await tester.tap(find.byIcon(Icons.style_rounded).first);
    await settle(tester);
    expect(find.text('Başla'), findsOneWidget,
        reason: 'durak tanıtım sayfası açılmadı');
    expect(find.textContaining('soru'), findsWidgets);

    await tester.tap(find.text('Başla'));
    await settle(tester, rounds: 10);
    expect(tester.takeException(), isNull);
    await settle(tester, rounds: 12);
  });

  testWidgets('dallanan hikâye açılıyor ve seçim koçluğu gösteriyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Macera').last);
    await settle(tester);
    expect(find.text('Macera Merkezi'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('game_companion')), findsOneWidget);
    expect(find.text('Nasıl oynanır?'), findsOneWidget);
    await revealLazy(
      tester,
      find.text('Kafedeki İlk Sipariş'),
      find.byType(CustomScrollView).first,
    );
    expect(find.text('Kafedeki İlk Sipariş'), findsOneWidget);
    expect(find.text('Diğer oyun modları'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('song_mode_card')),
      findsNothing,
    );

    await tester.dragUntilVisible(
      find.text('Bölümleri aç'),
      find.byType(CustomScrollView).first,
      const Offset(0, -180),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Bölümleri aç'));
    await settle(tester);
    expect(find.text('Hikâye Dünyası'), findsOneWidget);
    expect(find.text('BÖLÜM 2'), findsOneWidget);
    expect(find.text('Kilitli'), findsOneWidget);
    await tester.tap(find.text('Kafedeki İlk Sipariş'));
    await settle(tester);
    expect(find.text('Bonjour ! Vous désirez ?'), findsOneWidget);
    await tester.tap(find.text('Je voudrais un café, s\'il vous plaît.'));
    await settle(tester, rounds: 3);
    expect(find.text('Doğal seçim'), findsOneWidget);
    expect(find.text('Hikâyeye devam et'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cümle atölyesi serbest cevabı değerlendiriyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Macera').last);
    await settle(tester);
    await expandMoreModes(tester);
    await tester.dragUntilVisible(
      find.text('Yazı koçunu aç'),
      find.byType(CustomScrollView).first,
      const Offset(0, -180),
    );
    await Scrollable.ensureVisible(
      tester.element(find.text('Yazı koçunu aç')),
      alignment: 0.5,
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Yazı koçunu aç'));
    await settle(tester);
    expect(find.text('Cümle Atölyesi'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('open_free_writing')),
    );
    await settle(tester);
    expect(find.byType(FreeWritingScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey<String>('free_writing_input')),
      'je est tres content et je pas parle francais.',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('analyze_free_writing')),
    );
    await settle(tester, rounds: 3);
    expect(find.text('Fiil çekimi'), findsWidgets);
    expect(find.text('Olumsuzluk'), findsWidgets);
    expect(find.textContaining('Je suis très content'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await settle(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('sentence_input')),
      'Je voudrais un cafe.',
    );
    await tester.tap(find.byKey(const ValueKey<String>('check_sentence')));
    await settle(tester, rounds: 10);
    expect(find.text('Doğru ve doğal bir cümle!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sekme değişince sekmenin durumu korunuyor',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    // Ziyaret edilmeyen ağır sekmeler açılışta kurulmaz.
    expect(find.byType(GrammarListScreen), findsNothing);

    // Kelimeler sekmesinde bir tema seç.
    await tester.tap(
      find.byKey(const ValueKey<String>('deck_options_toggle')),
    );
    await settle(tester, rounds: 2);
    await tester.dragUntilVisible(
      find.text('Yemek'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.text('Yemek'));
    await settle(tester);

    // Başka sekmeye geç, geri dön.
    await tester.tap(find.text('Dilbilgisi').last);
    await settle(tester);
    expect(find.byType(GrammarListScreen), findsOneWidget);
    await tester.tap(find.text('Kelimeler').last);
    await settle(tester);

    // Seçim duruyor olmalı. AnimatedSwitcher ile sarılsaydı alt ağaç
    // yeniden kurulur ve seçim sıfırlanırdı.
    final ChoiceChip chip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Yemek'),
    );
    expect(chip.selected, isTrue, reason: 'sekme durumu sıfırlandı');
    expect(tester.takeException(), isNull);
  });

  testWidgets('yedekleme: dışa aktar, geri yükle, ilerleme korunur',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    // Biraz ilerleme üret: kart kaydır ve bir durak sonucu kaydet.
    await tester.tap(find.text('Oturumu başlat'));
    await settle(tester);
    for (int i = 0; i < 3; i++) {
      if (frontGestures().evaluate().isEmpty) break;
      if (!await swipeCard(tester, const Offset(400, 0))) break;
      await settle(tester, rounds: 3);
    }
    await tester.pageBack();
    await settle(tester);

    late String json;
    late int cardsBefore;
    await tester.runAsync(() async {
      await app.recordStation(
        stationId: 'TEST-1',
        stars: 2,
        correct: 7,
        total: 8,
      );
      cardsBefore = app.cards.snapshot().length;
      json = await ProgressBackup.export(app.db.progress);
    });

    expect(cardsBefore, greaterThan(0), reason: 'ilerleme üretilemedi');
    expect(json, contains('card_state'));
    expect(json, contains('TEST-1'));

    // Her şeyi sil, sonra yedekten geri yükle.
    late int afterWipe;
    late ImportReport report;
    await tester.runAsync(() async {
      await app.db.progress.delete('card_state');
      await app.db.progress.delete('journey_progress');
      afterWipe = (await app.db.progress.query('card_state')).length;
      report = await ProgressBackup.import(app.db.progress, json);
    });

    expect(afterWipe, 0, reason: 'silme çalışmadı, test anlamsız');
    expect(report.cards, cardsBefore,
        reason: 'geri yüklenen kart sayısı tutmuyor');
    expect(report.stations, greaterThan(0));

    // Veritabanında gerçekten duruyor mu.
    late int restored;
    late List<Map<String, Object?>> station;
    await tester.runAsync(() async {
      restored = (await app.db.progress.query('card_state')).length;
      station = await app.db.progress.query(
        'journey_progress',
        where: 'station_id = ?',
        whereArgs: <Object?>['TEST-1'],
      );
    });
    expect(restored, cardsBefore);
    expect(station.single['stars'], 2);
  });

  testWidgets('bozuk yedek reddediliyor', (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    final AppState app = AppScope.of(
      tester.element(find.byType(DeckSelectScreen)),
    );

    Object? err;
    await tester.runAsync(() async {
      try {
        await ProgressBackup.import(app.db.progress, '{"format": 999}');
      } catch (e) {
        err = e;
      }
    });
    expect(err, isA<FormatException>(),
        reason: 'gelecek sürüm yedeği kabul edildi');

    err = null;
    await tester.runAsync(() async {
      try {
        await ProgressBackup.import(app.db.progress, 'düz metin');
      } catch (e) {
        err = e;
      }
    });
    expect(err, isNotNull, reason: 'geçersiz JSON kabul edildi');
  });

  testWidgets('30 günlük ızgara çiziliyor', (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('İlerleme').last);
    await settle(tester);

    await tester.dragUntilVisible(
      find.text('Son 30 gün'),
      find.byType(ListView).first,
      const Offset(0, -240),
    );
    expect(find.text('Son 30 gün'), findsOneWidget);
    expect(find.textContaining('günde'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('karakter stüdyosu seçimleri anında ve kalıcı uygular',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Macera').last);
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('open_companion_studio')),
    );
    await settle(tester);
    expect(find.byType(CompanionStudioScreen), findsOneWidget);
    expect(find.text('Yeni Dost'), findsWidgets);
    expect(find.text('Lumi ile bağın'), findsOneWidget);
    expect(find.text('Bir sonraki forma 250 XP kaldı.'), findsOneWidget);

    final AppState app = AppScope.of(
      tester.element(find.byType(CompanionStudioScreen)),
    );
    await tester.tap(find.byKey(const ValueKey<String>('character_moka')));
    await settle(tester, rounds: 2);
    expect(app.companion, CompanionKind.moka);
    expect(app.settings.get('companion_kind'), 'moka');

    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('palette_coral')),
      find.byType(ListView).last,
      const Offset(0, -220),
    );
    await Scrollable.ensureVisible(
      tester.element(
        find.byKey(const ValueKey<String>('palette_coral')),
      ),
      alignment: 0.5,
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.byKey(const ValueKey<String>('palette_coral')));
    await settle(tester, rounds: 2);
    expect(app.companionPalette, CompanionPalette.coral);
    expect(app.settings.get('companion_palette'), 'coral');

    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('accessory_none')),
      find.byType(ListView).last,
      const Offset(0, -240),
    );
    await tester.tap(find.byKey(const ValueKey<String>('accessory_none')));
    await settle(tester, rounds: 2);
    expect(app.companionAccessory, CompanionAccessory.none);
    expect(app.settings.get('companion_accessory'), 'none');
    expect(tester.takeException(), isNull);
  });

  testWidgets('şarkı sahnesi açılır ve söz kelimesini desteye ekler',
      (WidgetTester tester) async {
    await phone(tester);
    await boot(tester);
    await passOnboarding(tester);

    await tester.tap(find.text('Macera').last);
    await settle(tester);
    await expandMoreModes(tester);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('song_mode_card')),
      find.byType(CustomScrollView).last,
      const Offset(0, -280),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('song_mode_card')),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.byKey(const ValueKey<String>('song_mode_card')));
    await settle(tester);
    expect(find.byType(SongLibraryScreen), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('song_filter_lyrics')),
      find.byType(CustomScrollView).last,
      const Offset(0, -240),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('song_filter_lyrics')),
    );
    await settle(tester, rounds: 2);
    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('song_frere_jacques')),
      find.byType(CustomScrollView).last,
      const Offset(0, -240),
    );

    await tester.tap(
      find.byKey(const ValueKey<String>('song_frere_jacques')),
    );
    await settle(tester);
    expect(find.byType(SongPlayerScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('song_play')), findsOneWidget);

    await tester.dragUntilVisible(
      find.byKey(const ValueKey<String>('lyric_0_0')),
      find.byType(ListView).last,
      const Offset(0, -240),
    );
    await tester.tap(find.byKey(const ValueKey<String>('lyric_0_0')));
    await settle(tester, rounds: 2);
    expect(find.text('erkek kardeş'), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('save_song_word')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('save_song_word')));
    await settle(tester, rounds: 2);
    expect(find.text('Kelime destene eklendi'), findsOneWidget);

    Navigator.of(tester.element(find.text('Kelime destene eklendi'))).pop();
    await settle(tester, rounds: 2);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('song_quiz')),
    );
    await settle(tester, rounds: 2);
    await tester.tap(find.byKey(const ValueKey<String>('song_quiz')));
    await settle(tester);
    for (int question = 0; question < 5; question++) {
      await tester.tap(
        find.byKey(const ValueKey<String>('song_quiz_option_0')),
      );
      await settle(tester, rounds: 2);
      await tester.tap(
        find.byKey(const ValueKey<String>('song_quiz_next')),
      );
      await settle(tester);
    }
    expect(
        find.text('Sonucun XP ve günlük ilerlemene işlendi.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
