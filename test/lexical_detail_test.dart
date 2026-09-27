import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/word.dart';
import 'package:french_app/features/vocab/lexical_detail_screen.dart';
import 'package:french_app/services/lexical/lexical_models.dart';

class ControlledProvider implements LexicalProvider {
  final requests = <(LexicalLookupKey, Completer<LexicalOutcome>)>[];
  @override
  Future<LexicalOutcome> lookup(LexicalLookupKey key) {
    final result = Completer<LexicalOutcome>();
    requests.add((key, result));
    return result.future;
  }
}

LexicalOutcome result(String lemma) => LexicalOutcome(LexicalStatus.found,
    data: LexicalEnrichment(
        word: lemma,
        senses: [
          LexicalSense(pos: 'noun', glosses: ['extra $lemma']),
          LexicalSense(pos: 'verb', glosses: ['other POS']),
          LexicalSense(
              pos: 'noun', glosses: ['hidden sense'], tags: ['offensive']),
        ],
        pronunciations: [],
        provenance: LexicalProvenance(
            requestedLemma: lemma,
            responseUrl: 'https://api.wiktapi.dev',
            sourceUrl: 'https://en.wiktionary.org/wiki/$lemma',
            retrievedAt: DateTime.utc(2026))));

void main() {
  testWidgets('older response cannot overwrite newer lookup or disposed screen',
      (tester) async {
    final provider = ControlledProvider();
    Widget screen(String lemma) => MaterialApp(
        home: LexicalDetailScreen(lemma: lemma, provider: provider));
    await tester.pumpWidget(screen('chat'));
    await tester.pumpWidget(screen('chien'));
    expect(provider.requests.length, 2);
    provider.requests[1].$2.complete(result('chien'));
    await tester.pump();
    provider.requests[0].$2.complete(result('chat'));
    await tester.pump();
    expect(find.text('extra chien'), findsOneWidget);
    expect(find.text('extra chat'), findsNothing);
    await tester.pumpWidget(screen('maison'));
    await tester.pumpWidget(const SizedBox.shrink());
    provider.requests[2].$2.complete(result('maison'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'network failure offers duplicate-safe retry with view-only result',
      (tester) async {
    final provider = ControlledProvider();
    await tester.pumpWidget(MaterialApp(
        home: LexicalDetailScreen(lemma: 'chat', provider: provider)));
    provider.requests.single.$2
        .complete(const LexicalOutcome(LexicalStatus.transientFailure));
    await tester.pump();
    expect(find.byKey(const ValueKey('lexical_error')), findsOneWidget);
    final retry = find.byKey(const ValueKey('lexical_retry'));
    await tester.tap(retry);
    await tester.tap(retry);
    expect(provider.requests.length, 2);
    provider.requests.last.$2.complete(result('chat'));
    await tester.pump();
    expect(find.text('extra chat'), findsOneWidget);
    expect(find.text('hidden sense'), findsNothing);
    expect(find.textContaining('Öğrenme destesine eklenmez'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(tester.takeException(), isNull);
  });
  const word = Word(
      id: 'local-stable',
      lemma: 'chat',
      pos: 'NOM',
      level: CefrLevel.a1,
      theme: WordTheme.daily,
      meaningEn: 'approved cat',
      meaningTr: 'kedi',
      freqRank: 1);
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(430, 932)
  ]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
          'local meaning retained and detail scrolls ${size.width} scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final provider = ControlledProvider();
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: LexicalDetailScreen(
                lemma: 'chat', localWord: word, provider: provider)));
        expect(find.text('approved cat'), findsOneWidget);
        provider.requests.single.$2.complete(result('chat'));
        await tester.pump();
        expect(find.text('approved cat'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('extra chat'), 100,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('extra chat'), findsOneWidget);
        expect(find.text('other POS'), findsNothing);
        expect(find.text('hidden sense'), findsNothing);
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('lexical_retry')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
