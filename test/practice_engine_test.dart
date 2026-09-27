import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/data/repositories.dart';
import 'package:french_app/domain/adventure.dart';
import 'package:french_app/domain/adventure_expansion.dart';
import 'package:french_app/domain/free_writing.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/sentence_practice.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('her CEFR seviyesi için geçerli hikâye ve cümleler vardır', () {
    for (final CefrLevel level in CefrLevel.values) {
      final List<StoryAdventure> stories = storiesForLevel(level);
      expect(stories, hasLength(greaterThanOrEqualTo(2)),
          reason: '${level.code} dünyasında yeterli bölüm yok');
      expect(promptsForLevel(level), hasLength(greaterThanOrEqualTo(3)));

      for (int i = 0; i < stories.length; i++) {
        final StoryAdventure story = stories[i];
        expect(story.chapter, i + 1,
            reason: '${level.code} bölüm sırası bozuk');
        expect(story.quiz, isNotEmpty, reason: '${story.id} hikâye sınavı yok');
        final Set<String> nodeIds =
            story.nodes.map((StoryNode n) => n.id).toSet();
        expect(nodeIds, contains(story.startNodeId));
        for (final StoryNode node in story.nodes) {
          for (final StoryChoice choice in node.choices) {
            expect(nodeIds, contains(choice.nextNodeId),
                reason: '${story.id}/${node.id} bozuk dal');
          }
        }
      }
    }
    final List<StoryAdventure> allStories = <StoryAdventure>[
      ...storyCatalog,
      ...expandedStoryCatalog,
    ];
    expect(
      allStories.map((StoryAdventure story) => story.id).toSet(),
      hasLength(allStories.length),
      reason: 'hikâye kimlikleri benzersiz değil',
    );
  });

  test('cümle motoru kabul edilen varyasyon ve aksansız girişi tanır', () {
    final SentencePrompt coffee = sentencePromptCatalog
        .firstWhere((SentencePrompt p) => p.id == 'a1_coffee');
    final SentenceEvaluation result =
        SentenceEvaluator.evaluate("Je voudrais un cafe.", coffee);
    expect(result.correct, isTrue);
    expect(result.score, 100);
  });

  test('cümle motoru çekim ve edat hatalarını ayrı gösterir', () {
    final SentencePrompt wakeup = sentencePromptCatalog
        .firstWhere((SentencePrompt p) => p.id == 'a2_wakeup');
    final SentenceEvaluation result =
        SentenceEvaluator.evaluate('Hier je suis levé sept heures', wakeup);
    expect(result.correct, isFalse);
    expect(
      result.issues.map((SentenceIssue issue) => issue.type),
      containsAll(<SentenceIssueType>[
        SentenceIssueType.conjugation,
        SentenceIssueType.preposition,
      ]),
    );
  });

  test('serbest yazı koçu hataları kategori, kural ve düzeltmeyle verir', () {
    final WritingEvaluation result = FreeWritingAnalyzer.analyze(
      "je est tres fatigué , et je pas parle francais. "
      "J'habite en Paris et j'ai beaucoup des travail.",
    );

    final Set<WritingIssueType> types =
        result.issues.map((WritingIssue issue) => issue.type).toSet();
    expect(
      types,
      containsAll(<WritingIssueType>{
        WritingIssueType.conjugation,
        WritingIssueType.negation,
        WritingIssueType.preposition,
        WritingIssueType.spelling,
        WritingIssueType.punctuation,
      }),
    );
    expect(result.issues.every((WritingIssue issue) => issue.rule.isNotEmpty),
        isTrue);
    expect(result.correctedText, contains('Je suis très fatigué,'));
    expect(result.correctedText, contains('je ne parle pas français'));
    expect(result.correctedText, contains("J’habite à Paris"));
    expect(result.correctedText, contains('beaucoup de travail'));
  });

  test('serbest yazı koçu temiz cümleyi gereksiz yere bozmaz', () {
    const String text = 'J’habite à Paris et je suis étudiant.';
    final WritingEvaluation result = FreeWritingAnalyzer.analyze(text);
    expect(result.score, 100);
    expect(result.issues, isEmpty);
    expect(result.correctedText, text);
    expect(result.strengths, isNotEmpty);
  });

  test('hikâye ve cümle ilerlemesi kalıcıdır, ilk ödül çoğalmaz', () async {
    final Database db =
        await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await db.execute('''CREATE TABLE story_progress (
      story_id TEXT PRIMARY KEY, node_id TEXT NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0,
      best_correct INTEGER NOT NULL DEFAULT 0,
      best_total INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE sentence_progress (
      prompt_id TEXT PRIMARY KEY, attempts INTEGER NOT NULL DEFAULT 0,
      solved INTEGER NOT NULL DEFAULT 0,
      best_score INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    )''');

    final PracticeStore store = await PracticeStore.load(db);
    await store.saveStoryNode('a2_train', 'change');
    expect(store.story('a2_train')?.nodeId, 'change');
    expect(
      await store.completeStory(
        storyId: 'a2_train',
        nodeId: 'end',
        correct: 1,
        total: 2,
      ),
      isTrue,
    );
    expect(
      await store.completeStory(
        storyId: 'a2_train',
        nodeId: 'end',
        correct: 2,
        total: 2,
      ),
      isFalse,
    );
    expect(
        await store.recordSentence(
            promptId: 'a2_ticket', solved: true, score: 100),
        isTrue);
    expect(
        await store.recordSentence(
            promptId: 'a2_ticket', solved: true, score: 100),
        isFalse);

    final PracticeStore reopened = await PracticeStore.load(db);
    expect(reopened.story('a2_train')?.bestCorrect, 2);
    expect(reopened.sentence('a2_ticket')?.attempts, 2);
    expect(reopened.sentence('a2_ticket')?.solved, isTrue);
  });
}
