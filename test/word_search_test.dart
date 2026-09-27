import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/word.dart';
import 'package:french_app/domain/word_search.dart';

Word word(String lemma, String turkish, int rank) => Word(
      id: lemma,
      lemma: lemma,
      pos: 'NOM',
      level: CefrLevel.a1,
      theme: WordTheme.general,
      meaningEn: lemma,
      meaningTr: turkish,
      freqRank: rank,
    );

void main() {
  test('Türkçe sorgu Fransızca karşılığı bulur ve tam anlamı öne alır', () {
    final List<WordSearchResult> results = WordSearchEngine.search(
      <Word>[
        word('partir', 'çekip gitmek', 1),
        word('aller', 'gitmek', 20),
        word('trotter', 'tırıs gitmek', 10),
      ],
      'gitmek',
      language: WordSearchLanguage.turkish,
    );

    expect(results.first.word.lemma, 'aller');
    expect(results.first.matchLanguage, WordMatchLanguage.turkish);
  });

  test('Türkçe harfler aksansız da aranır', () {
    final List<WordSearchResult> results = WordSearchEngine.search(
      <Word>[word('femme', 'kadın', 65)],
      'kadin',
    );
    expect(results.single.word.lemma, 'femme');
  });

  test('arama ilk eşleşmelerde kesilmez', () {
    final List<Word> words = <Word>[
      for (int i = 0; i < 100; i++) word('mot$i', 'başka anlam $i', i),
      word('maison', 'ev', 1000),
    ];
    final List<WordSearchResult> results = WordSearchEngine.search(words, 'ev');
    expect(results.first.word.lemma, 'maison');
  });

  test('hazır arama indeksi doğrudan aramayla aynı sonucu verir', () {
    final List<Word> words = <Word>[
      word('femme', 'kadın', 3),
      word('maison', 'ev, konut', 7),
      word('aller', 'gitmek', 1),
    ];
    final WordSearchIndex index = WordSearchEngine.buildIndex(words);

    final List<WordSearchResult> direct = WordSearchEngine.search(words, 'ev');
    final List<WordSearchResult> indexed =
        WordSearchEngine.searchIndex(index, 'ev');

    expect(
      indexed.map((WordSearchResult result) => result.word.id),
      direct.map((WordSearchResult result) => result.word.id),
    );
    expect(indexed.first.matchLanguage, WordMatchLanguage.turkish);
  });
}
