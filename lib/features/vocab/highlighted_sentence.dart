import 'package:flutter/material.dart';

/// Örnek cümlede hedef kelimeyi kalınlaştırır.
///
/// Cümledeki biçim çekimli olduğu için tam eşleşme çoğu zaman tutmaz
/// (`manger` → "je **mange**", `cheval` → "les **chevaux**"). Bu yüzden
/// kök benzerliğine bakılıyor: lemmanın baştan birkaç harfi ile başlayan
/// kelime hedef sayılıyor.
///
/// Yanlış bir kelimeyi kalınlaştırmak zararsız; hiç kalınlaştırmamak da
/// öyle. Bu yüzden sezgi bilerek basit tutuldu, sözlük yükü getirmiyor.
class HighlightedSentence extends StatelessWidget {
  const HighlightedSentence({
    super.key,
    required this.sentence,
    required this.lemma,
    required this.style,
    required this.highlightColor,
    this.maxLines = 4,
  });

  final String sentence;
  final String lemma;
  final TextStyle style;
  final Color highlightColor;
  final int maxLines;

  static const Map<String, String> _fold = <String, String>{
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
  };

  static String _norm(String s) {
    final StringBuffer b = StringBuffer();
    for (final int r in s.toLowerCase().runes) {
      final String ch = String.fromCharCode(r);
      b.write(_fold[ch] ?? ch);
    }
    return b.toString();
  }

  /// Lemmanın gövdesi. Fransızca çekim eklerinin çoğu sondan geldiği için
  /// son iki harfi atmak yeterli bir yaklaşımdır; en az dört harf kalır.
  static String _stem(String lemma) {
    final String base = _norm(lemma.split(' ').last);
    if (base.length <= 4) return base;
    final int cut = base.length - 2;
    return base.substring(0, cut < 4 ? 4 : cut);
  }

  @override
  Widget build(BuildContext context) {
    final String stem = _stem(lemma);
    final List<TextSpan> spans = <TextSpan>[];

    // Kelime sınırlarını koruyarak böl: ayraçlar da parça olarak kalır,
    // böylece cümle olduğu gibi yeniden kurulur.
    final RegExp splitter = RegExp(r"([A-Za-zÀ-ÿ' ’-]+|[^A-Za-zÀ-ÿ]+)");
    bool marked = false;

    for (final Match m in splitter.allMatches(sentence)) {
      final String piece = m.group(0)!;
      final bool isWordish = RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(piece);
      if (!isWordish) {
        spans.add(TextSpan(text: piece));
        continue;
      }
      // Parça birden çok kelime içerebilir; tek tek bakıyoruz.
      final List<String> tokens = piece.split(RegExp(r"(?<=[ '’])"));
      for (final String token in tokens) {
        final String core = _norm(token).replaceAll(RegExp(r"[^a-z]"), '');
        if (!marked && stem.length >= 3 && core.startsWith(stem)) {
          marked = true;
          spans.add(TextSpan(
            text: token,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: highlightColor,
            ),
          ));
        } else {
          spans.add(TextSpan(text: token));
        }
      }
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: style, children: spans),
    );
  }
}
