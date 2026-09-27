import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/domain/journey.dart';
import 'package:french_app/domain/level.dart';
import 'package:french_app/domain/verb.dart';
import 'package:french_app/features/onboarding/placement_test_screen.dart';
import 'package:french_app/motion/card_stack.dart';
import 'package:french_app/motion/swipe_direction.dart';

void main() {
  test('placement requires enough evidence for an advanced level', () {
    expect(
      resolvePlacementLevel(
        <CefrLevel, int>{CefrLevel.c2: 1},
        <CefrLevel, int>{CefrLevel.c2: 1},
      ),
      CefrLevel.a1,
    );
    expect(
      resolvePlacementLevel(
        <CefrLevel, int>{CefrLevel.b2: 5},
        <CefrLevel, int>{CefrLevel.b2: 3},
      ),
      CefrLevel.b2,
    );
  });

  test('journey best score keeps one internally consistent attempt', () {
    const StationResult old = StationResult(
      stationId: 'A1-w0',
      stars: 2,
      bestCorrect: 7,
      bestTotal: 8,
    );
    const StationResult worseRetry = StationResult(
      stationId: 'A1-w0',
      stars: 0,
      bestCorrect: 2,
      bestTotal: 12,
    );
    expect(StationResult.bestOf(old, worseRetry), same(old));
  });

  test('aspirated h suppresses je elision', () {
    expect(conjugationDisplay('je', 'habite'), "j'habite");
    expect(
      conjugationDisplay('je', 'hais', aspiratedH: true),
      'je hais',
    );
  });

  testWidgets('rapid controller commands swipe distinct cards in order',
      (WidgetTester tester) async {
    final CardStackController controller = CardStackController();
    final List<int> swiped = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 320,
          height: 520,
          child: CardStack(
            controller: controller,
            itemCount: 12,
            itemBuilder: (_, int index) => ColoredBox(
              color: Colors.blue,
              child: Text('$index'),
            ),
            onSwiped: (int index, _) => swiped.add(index),
          ),
        ),
      ),
    );
    await tester.pump();

    for (int i = 0; i < 10; i++) {
      controller.swipe(SwipeDirection.right);
    }
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    expect(swiped, List<int>.generate(10, (int i) => i));
  });
}
