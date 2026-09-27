import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:french_app/app/theme.dart';
import 'package:french_app/features/onboarding/paris_opening_screen.dart';
import 'package:french_app/ui/game_companion.dart';

void main() {
  testWidgets('Paris açılışı telefon ekranında animasyonla taşmadan çizilir',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const ParisOpeningScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));

    expect(find.text('PARLONS!  •  FRANÇAIS'), findsOneWidget);
    expect(find.text('Bonjour, maceracı!'), findsOneWidget);
    expect(find.text('Sözlük hazırlanıyor'), findsOneWidget);
    expect(find.byType(GameCompanion), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hareket azaltıldığında açılış sahnesi sabit kalır',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: ParisOpeningScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Bonjour, maceracı!'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
