import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/app_state.dart';
import 'package:french_app/domain/word.dart';
import 'package:french_app/features/quiz/quiz_engine.dart';
import 'package:french_app/features/vocab/word_card.dart';
import 'package:french_app/motion/flip_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Force only the first kind choice; shuffling still uses the actual engine.
class _QuestionKindRandom implements Random {
  _QuestionKindRandom(this.kind);
  final int kind;
  final Random delegate = Random(10);
  bool first = true;
  @override
  int nextInt(int max) {
    if (first) {
      first = false;
      return kind;
    }
    return delegate.nextInt(max);
  }
  @override
  bool nextBool() => delegate.nextBool();
  @override
  double nextDouble() => delegate.nextDouble();
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  AppState? app;
  late List<dynamic> entries;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    entries = (jsonDecode(File('content/overrides/editorial_fa010b.json')
        .readAsStringSync()) as Map<String, dynamic>)['entries'] as List<dynamic>;
  });
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('fa010b_cards_');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => temp.path,
    );
  });
  tearDown(() async {
    await app?.close();
    app = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null,
    );
    await temp.delete(recursive: true);
  });

  Future<AppState> boot(WidgetTester tester) async {
    app = await tester.runAsync(AppState.create);
    return app!;
  }

  testWidgets('approved package loads exact texts and per-language provenance', (tester) async {
    final state = await boot(tester);
    expect(entries.length, 36);
    for (final dynamic value in entries) {
      final entry = value as Map<String, dynamic>;
      final word = state.words.byId(entry['id'] as String)!;
      final initial = entry['initial_words'] as Map<String, dynamic>;
      final finalWord = <String, dynamic>{...initial, ...entry['final_words'] as Map<String, dynamic>};
      final example = entry['final_example'] as Map<String, dynamic>;
      expect(word.lemma, entry['lemma_fr']);
      expect(word.pos, entry['pos']);
      expect(word.meaningTr, finalWord['meaning_tr']);
      expect(word.meaningEn, finalWord['meaning_en']);
      expect(word.noteTr, finalWord['note_tr']);
      expect(word.needsReview, initial['needs_review'] == 1);
      expect(word.sentenceFr, example['sentence_fr']);
      expect(word.sentenceEn, example['sentence_en']);
      expect(word.sentenceTr, example['sentence_tr']);
      expect(word.sentenceFrId, example['sentence_fr_id']);
      expect(word.sentenceEnId, example['sentence_en_id']);
      expect(word.sentenceTrId, example['sentence_tr_id']);
      expect(word.sentenceFrAuthor, example['author_fr']);
      expect(word.sentenceEnAuthor, example['author_en']);
      expect(word.sentenceTrAuthor, example['author_tr']);
    }
  });

  testWidgets('real WordCard shows suivre si pauvre ton peine and notes', (tester) async {
    final state = await boot(tester);
    await tester.binding.setSurfaceSize(const Size(650, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const expected = <String, (String, String)>{
      'w_bbd859f307efa22ca74e': ('takip etmek; izlemek', 'Nous suivons le guide dans le musée.'),
      'w_e3d305b2b614ea9228b9': ('o kadar', 'Ce sac est si lourd !'),
      'w_73fcdaf078f6b239088a': ('yoksul; fakir', 'Je préfère être pauvre que riche.'),
      'w_839349727b712d3b2270': ('ses tonu', 'Elle parle sur un ton calme.'),
      'w_229d28a0a3731c3f97bc': ('zahmet; çaba', 'Elle se donne beaucoup de peine pour nous aider.'),
    };
    for (final entry in expected.entries) {
      final Word word = state.words.byId(entry.key)!;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(
        padding: const EdgeInsets.all(20),
        child: WordCard(key: ValueKey(word.id), word: word),
      ))));
      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();
      expect(find.text(entry.value.$1), findsOneWidget);
      expect(find.text(entry.value.$2), findsOneWidget);
      if (word.noteTr != null) {
        expect(find.text('Not: ${word.noteTr}'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('local and adapted examples retain honest language attribution on card', (tester) async {
    final state = await boot(tester);
    final local = state.words.byId('w_bbd859f307efa22ca74e')!;
    final mixed = state.words.byId('w_900ba5a26ad9ba668e53')!;
    expect(local.sentenceFrId, lessThan(0));
    expect(local.sentenceAttribution, isNot(contains('Tatoeba')));
    final entry = entries.cast<Map<String, dynamic>>().singleWhere((e) => e['id'] == mixed.id);
    final original = entry['initial_example'] as Map<String, dynamic>;
    expect(mixed.sentenceFr, original['sentence_fr']);
    expect(mixed.sentenceFrId, original['sentence_fr_id']);
    expect(mixed.sentenceFrAuthor, original['author_fr']);
    expect(mixed.sentenceEn, "I'm only talking!");
    expect(mixed.sentenceEnId, lessThan(0));
    expect(mixed.sentenceTrId, lessThan(0));
    expect(mixed.sentenceAttribution, contains('FR Tatoeba · ${original['author_fr']}'));
    expect(mixed.sentenceAttribution, contains('EN yerel editoryal'));
    expect(mixed.sentenceAttribution, contains('TR yerel editoryal'));
    for (final word in <Word>[local, mixed]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: WordCard(key: ValueKey(word.id), word: word))));
      await tester.tap(find.byType(FlipCard));
      await tester.pumpAndSettle();
      expect(find.text(word.sentenceAttribution!), findsOneWidget);
      expect(find.textContaining('tatoeba.org'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('updated meanings feed forward and reverse quiz and tant excludes autant', (tester) async {
    final state = await boot(tester);
    final tant = state.words.byId('w_a81aea55f07a4b77c596')!;
    final autant = state.words.all().firstWhere((w) => w.lemma == 'autant' && w.meaningTr == 'o kadar çok');
    expect(tant.meaningTr, autant.meaningTr);
    final changed = entries.cast<Map<String, dynamic>>().where((e) => (e['final_words'] as Map).containsKey('meaning_tr'));
    for (final entry in changed) {
      final word = state.words.byId(entry['id'] as String)!;
      expect(state.words.distractorsFor(word).every((w) => w.meaningTr != word.meaningTr), isTrue);
      for (int kind = 0; kind < 2; kind++) {
        final questions = await QuizEngine.build(app: state, wordIds: <String>[word.id], verbRefIds: const <String>[], count: 1, rng: _QuestionKindRandom(kind));
        expect(questions, hasLength(1), reason: word.id);
        final q = questions.single;
        expect(q.kind, kind == 0 ? QuizKind.frToTr : QuizKind.trToFr);
        expect(kind == 0 ? q.correct : q.prompt, word.meaningTr);
        expect(q.options.where((v) => v == q.correct), hasLength(1));
        expect(q.options.toSet().length, q.options.length);
        if (word.id == tant.id && kind == 1) {
          expect(q.options, isNot(contains(autant.display)));
        }
      }
    }
  });
}
