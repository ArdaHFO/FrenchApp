import 'word.dart';

enum WordSearchLanguage { all, french, turkish }

enum WordMatchLanguage { french, turkish, english }

class WordSearchResult {
  const WordSearchResult({
    required this.word,
    required this.matchLanguage,
    required this.score,
  });

  final Word word;
  final WordMatchLanguage matchLanguage;
  final int score;
}

/// Aranacak alanların aksansız biçimlerini bir kez hazırlar.
/// Böylece her tuş vuruşunda 15 binden fazla kelime yeniden dönüştürülmez.
class WordSearchIndex {
  WordSearchIndex._(this._documents);

  final List<_IndexedWord> _documents;
}

class _IndexedWord {
  const _IndexedWord({
    required this.word,
    required this.lemma,
    required this.display,
    required this.turkish,
    required this.turkishSenses,
    required this.english,
  });

  final Word word;
  final String lemma;
  final String display;
  final String turkish;
  final List<String> turkishSenses;
  final String english;
}

/// Aksan duyarsız, Fransızca ve Türkçe alanları ayrı puanlayan sözlük araması.
///
/// Bütün havuz taranır. Erken çıkış yapılmaz; aksi hâlde sıklık sırasında geç
/// duran doğru bir Türkçe karşılık, ilk Fransızca eşleşmeler yüzünden kaybolur.
class WordSearchEngine {
  const WordSearchEngine._();

  static const Map<String, String> _foldMap = <String, String>{
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'ç': 'c',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'ö': 'o',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ÿ': 'y',
    'œ': 'oe',
    'æ': 'ae',
    'ı': 'i',
    'ğ': 'g',
    'ş': 's',
  };

  static String fold(String value) {
    final StringBuffer buffer = StringBuffer();
    for (final int rune in value.toLowerCase().replaceAll('’', "'").runes) {
      final String character = String.fromCharCode(rune);
      // Türkçe büyük İ bazı platformlarda i + combining dot olur.
      if (rune == 0x0307) continue;
      buffer.write(_foldMap[character] ?? character);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r"[^a-z0-9']+"), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static List<WordSearchResult> search(
    Iterable<Word> words,
    String raw, {
    WordSearchLanguage language = WordSearchLanguage.all,
    int limit = 80,
  }) {
    return searchIndex(
      buildIndex(words),
      raw,
      language: language,
      limit: limit,
    );
  }

  static WordSearchIndex buildIndex(Iterable<Word> words) {
    return WordSearchIndex._(<_IndexedWord>[
      for (final Word word in words)
        _IndexedWord(
          word: word,
          lemma: fold(word.lemma),
          display: fold(word.display),
          turkish: fold(word.meaningTr),
          turkishSenses: word.meaningTr
              .split(RegExp(r'[,;/()]'))
              .map(fold)
              .where((String part) => part.isNotEmpty)
              .toList(growable: false),
          english: fold(word.meaningEn),
        ),
    ]);
  }

  static List<WordSearchResult> searchIndex(
    WordSearchIndex index,
    String raw, {
    WordSearchLanguage language = WordSearchLanguage.all,
    int limit = 80,
  }) {
    final String query = fold(raw);
    if (query.length < 2 || limit <= 0) return const <WordSearchResult>[];

    final List<WordSearchResult> matches = <WordSearchResult>[];
    for (final _IndexedWord document in index._documents) {
      final ({int score, WordMatchLanguage language})? match =
          _score(document, query, language);
      if (match == null) continue;
      matches.add(
        WordSearchResult(
          word: document.word,
          matchLanguage: match.language,
          score: match.score,
        ),
      );
    }
    matches.sort((WordSearchResult a, WordSearchResult b) {
      final int byScore = a.score.compareTo(b.score);
      if (byScore != 0) return byScore;
      final int byFrequency = a.word.freqRank.compareTo(b.word.freqRank);
      if (byFrequency != 0) return byFrequency;
      return a.word.lemma.compareTo(b.word.lemma);
    });
    return matches.length <= limit ? matches : matches.sublist(0, limit);
  }

  static ({int score, WordMatchLanguage language})? _score(
    _IndexedWord document,
    String query,
    WordSearchLanguage filter,
  ) {
    final List<({int score, WordMatchLanguage language})> scores =
        <({int score, WordMatchLanguage language})>[];

    if (filter != WordSearchLanguage.turkish) {
      final int? french = _fieldScore(document.lemma, query, exact: 0);
      final int? displayed = _fieldScore(document.display, query, exact: 0);
      final int? bestFrench = _minimum(french, displayed);
      if (bestFrench != null) {
        scores.add((score: bestFrench, language: WordMatchLanguage.french));
      }
    }

    if (filter != WordSearchLanguage.french) {
      int? turkishScore;
      if (document.turkish == query || document.turkishSenses.contains(query)) {
        turkishScore = 1;
      } else {
        turkishScore = _fieldScore(document.turkish, query, exact: 2);
      }
      if (turkishScore != null) {
        scores.add(
          (score: turkishScore, language: WordMatchLanguage.turkish),
        );
      }
    }

    if (filter == WordSearchLanguage.all) {
      final int? english = _fieldScore(document.english, query, exact: 40);
      if (english != null) {
        scores.add((score: english, language: WordMatchLanguage.english));
      }
    }

    if (scores.isEmpty) return null;
    scores.sort((a, b) => a.score.compareTo(b.score));
    return scores.first;
  }

  static int? _fieldScore(String field, String query, {required int exact}) {
    if (field.isEmpty) return null;
    if (field == query) return exact;
    if (field.startsWith('$query ')) return exact + 5;
    if (' $field '.contains(' $query ')) return exact + 7;
    if (field.startsWith(query) || field.contains(' $query')) return exact + 11;
    if (field.contains(query)) return exact + 18;
    return null;
  }

  static int? _minimum(int? a, int? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a < b ? a : b;
  }
}
