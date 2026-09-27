import 'dart:math';

import '../../app/app_state.dart';
import '../../data/repositories.dart';
import '../../domain/verb.dart';
import '../../domain/word.dart';

/// Soru tipleri. `conjugation` yalnızca fiil kartlarından üretilir.
enum QuizKind { frToTr, trToFr, cloze, conjugation }

extension QuizKindX on QuizKind {
  String get labelTr => switch (this) {
        QuizKind.frToTr => 'Anlamı seç',
        QuizKind.trToFr => 'Fransızcasını seç',
        QuizKind.cloze => 'Boşluğu doldur',
        QuizKind.conjugation => 'Çekimi seç',
      };
}

class QuizQuestion {
  QuizQuestion({
    required this.kind,
    required this.refId,
    required this.isVerbCard,
    required this.prompt,
    required this.subPrompt,
    required this.correct,
    required this.options,
    this.speakText,
  });

  final QuizKind kind;
  final String refId;
  final bool isVerbCard;
  final String prompt;
  final String? subPrompt;
  final String correct;
  final List<String> options;
  final String? speakText;
}

/// Soru üreteci.
///
/// Hem serbest quiz hem harita durakları bunu kullanır; tek fark hangi
/// kimliklerin verildiği. Serbest quiz SRS havuzunu, durak ise kendi
/// sabit kelime listesini gönderir.
class QuizEngine {
  QuizEngine._();

  static Future<List<QuizQuestion>> build({
    required AppState app,
    required List<String> wordIds,
    required List<String> verbRefIds,
    required int count,
    required Random rng,
  }) async {
    final List<QuizQuestion> out = <QuizQuestion>[];

    for (final String refId in wordIds) {
      if (out.length >= count) break;
      final Word? w = app.words.learningWordById(refId);
      if (w == null) continue;
      final List<Word> distractors = app.words.distractorsFor(w);
      if (distractors.length < 3) continue;

      // Unicode letter boundaries keep "an" from blanking the middle of "mange".
      final clozeMatch = RegExp(
        '(?<![\\p{L}\\p{M}\\p{N}_])${RegExp.escape(w.lemma)}(?![\\p{L}\\p{M}\\p{N}_])',
        caseSensitive: false,
        unicode: true,
      );
      final bool canCloze = w.hasExample && clozeMatch.hasMatch(w.sentenceFr!);
      final List<QuizKind> kinds = <QuizKind>[
        QuizKind.frToTr,
        QuizKind.trToFr,
        if (canCloze) QuizKind.cloze,
      ];
      final QuizKind kind = kinds[rng.nextInt(kinds.length)];

      switch (kind) {
        case QuizKind.frToTr:
          out.add(
            QuizQuestion(
              kind: kind,
              refId: refId,
              isVerbCard: false,
              prompt: w.display,
              subPrompt: w.ipa,
              correct: w.meaningTr,
              options: <String>[
                w.meaningTr,
                ...distractors.map((Word d) => d.meaningTr),
              ]..shuffle(rng),
              speakText: w.display,
            ),
          );
        case QuizKind.trToFr:
          out.add(
            QuizQuestion(
              kind: kind,
              refId: refId,
              isVerbCard: false,
              prompt: w.meaningTr,
              subPrompt: 'Hangisi bu anlama gelir?',
              correct: w.display,
              options: <String>[
                w.display,
                ...distractors.map((Word d) => d.display),
              ]..shuffle(rng),
            ),
          );
        case QuizKind.cloze:
          out.add(
            QuizQuestion(
              kind: kind,
              refId: refId,
              isVerbCard: false,
              prompt: w.sentenceFr!.replaceFirst(clozeMatch, '_____'),
              subPrompt: w.sentenceTr ?? w.sentenceEn,
              correct: w.lemma,
              options: <String>[
                w.lemma,
                ...distractors.map((Word d) => d.lemma),
              ]..shuffle(rng),
            ),
          );
        case QuizKind.conjugation:
          break;
      }
    }

    if (verbRefIds.isNotEmpty) {
      final List<Verb> verbs = await app.verbs.all();
      final Map<String, Verb> byId = <String, Verb>{
        for (final Verb v in verbs) v.id: v,
      };
      for (final String refId in verbRefIds) {
        final List<String> parts = refId.split(':');
        if (parts.length != 3) continue;
        final Verb? verb = byId[parts[0]];
        final VerbTense? tense = VerbTenseX.fromKey(parts[1]);
        if (verb == null || verb.needsReview || tense == null) continue;

        final Map<VerbTense, Map<String, String>> tables =
            await app.verbs.tablesFor(verb);
        final Map<String, String>? row = tables[tense];
        final String? correct = row?[parts[2]];
        if (row == null || correct == null) continue;

        // Çeldiriciler aynı fiilin diğer şahıs çekimleri, sonra diğer
        // zamanlardaki hâli. Rastgele değil, kurala göre.
        final List<String> pool = <String>[
          ...row.entries
              .where((MapEntry<String, String> e) => e.value != correct)
              .map((MapEntry<String, String> e) => e.value),
          ...tables.entries
              .where((MapEntry<VerbTense, Map<String, String>> e) =>
                  e.key != tense)
              .expand((MapEntry<VerbTense, Map<String, String>> e) =>
                  <String>[e.value[parts[2]] ?? ''])
              .where((String s) => s.isNotEmpty && s != correct),
        ];
        final List<String> distinct = <String>[];
        for (final String s in pool) {
          if (!distinct.contains(s)) distinct.add(s);
          if (distinct.length >= 3) break;
        }
        if (distinct.length < 3) continue;

        out.add(
          QuizQuestion(
            kind: QuizKind.conjugation,
            refId: refId,
            isVerbCard: true,
            prompt: '${verb.infinitive} · ${parts[2]}',
            subPrompt: '${tense.label} — ${verb.meaningTr}',
            correct: correct,
            options: <String>[correct, ...distinct]..shuffle(rng),
            speakText: conjugationDisplay(
              parts[2],
              correct,
              tense: tense,
              aspiratedH: verb.aspiratedH,
            ),
          ),
        );
      }
    }

    out.shuffle(rng);
    return out.take(count).toList();
  }
}
