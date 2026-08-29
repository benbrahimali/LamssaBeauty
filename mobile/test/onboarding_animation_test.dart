import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/screens/onboarding_screen.dart';

/// Respiration des cercles de l'onboarding.
///
/// Ils étaient figés alors que le splash respirait juste avant : la rupture se
/// voyait d'un écran à l'autre. Ces tests mesurent le mouvement réel, qu'aucune
/// analyse statique ne peut voir.
void main() {
  List<double> ringScales(WidgetTester tester) => const [196, 140]
      .map((size) => tester
          .widget<Transform>(find.byKey(ValueKey('breathing-ring-$size')))
          .transform
          .getMaxScaleOnAxis())
      .toList();

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: OnboardingScreen(onFinish: () {}),
        ),
      ),
    );
  }

  /// Le contrôleur tourne en boucle : un ticker encore actif ferait échouer le
  /// test au démontage.
  Future<void> tearDownOnboarding(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('les cercles de l’onboarding respirent', (tester) async {
    await pumpOnboarding(tester);

    final start = ringScales(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    final peak = ringScales(tester);

    expect(peak[0], greaterThan(start[0] + 0.01), reason: 'anneau extérieur');
    expect(peak[1], greaterThan(start[1] + 0.01), reason: 'anneau intérieur');

    await tearDownOnboarding(tester);
  });

  testWidgets('l’amplitude est la même qu’au splash', (tester) async {
    await pumpOnboarding(tester);

    var maxSeen = 1.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      for (final scale in ringScales(tester)) {
        if (scale > maxSeen) maxSeen = scale;
      }
    }

    // Une amplitude différente de celle du splash se lirait comme une
    // incohérence entre deux écrans qui se suivent.
    expect(maxSeen, greaterThan(1.0));
    expect(maxSeen, lessThan(1.08));

    await tearDownOnboarding(tester);
  });

  testWidgets('« réduire les animations » fige aussi l’onboarding',
      (tester) async {
    await pumpOnboarding(tester, reduceMotion: true);

    final start = ringScales(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    final later = ringScales(tester);

    expect(later[0], closeTo(start[0], 0.001));
    expect(later[1], closeTo(start[1], 0.001));

    await tearDownOnboarding(tester);
  });
}
