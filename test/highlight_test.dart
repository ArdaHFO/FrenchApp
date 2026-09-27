import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/features/vocab/highlighted_sentence.dart';

/// Vurgulama sezgisi cümleyi bozmamalı: kalınlaştırsa da kalınlaştırmasa da
/// ekrandaki metin cümlenin aynısı olmalı.
void main() {
  Future<String> render(
    WidgetTester tester,
    String sentence,
    String lemma,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HighlightedSentence(
            sentence: sentence,
            lemma: lemma,
            highlightColor: Colors.red,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
    final RichText rt = tester.widget<RichText>(find.byType(RichText).first);
    return rt.text.toPlainText();
  }

  bool hasBold(WidgetTester tester) {
    final RichText rt = tester.widget<RichText>(find.byType(RichText).first);
    bool bold = false;
    rt.text.visitChildren((InlineSpan span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.w800) {
        bold = true;
      }
      return true;
    });
    return bold;
  }

  testWidgets('cümle olduğu gibi korunur', (WidgetTester tester) async {
    const List<List<String>> cases = <List<String>>[
      <String>['Je mange une pomme.', 'manger'],
      <String>["L'eau est froide, n'est-ce pas ?", 'eau'],
      <String>['Les chevaux courent vite !', 'cheval'],
      <String>['Il a dit : « bonjour ».', 'dire'],
      <String>['Rien.', 'rien'],
    ];
    for (final List<String> c in cases) {
      final String out = await render(tester, c[0], c[1]);
      expect(out, c[0], reason: '"${c[1]}" için cümle bozuldu');
    }
  });

  testWidgets('çekimli biçimi bulur', (WidgetTester tester) async {
    await render(tester, 'Je mange une pomme.', 'manger');
    expect(hasBold(tester), isTrue, reason: 'mange vurgulanmadı');

    await render(tester, 'Nous parlons français.', 'parler');
    expect(hasBold(tester), isTrue, reason: 'parlons vurgulanmadı');
  });

  testWidgets('alakasız cümlede hiçbir şeyi vurgulamaz',
      (WidgetTester tester) async {
    await render(tester, 'Il fait beau aujourd\'hui.', 'ordinateur');
    expect(hasBold(tester), isFalse);
  });
}
