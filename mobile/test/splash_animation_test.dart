import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/screens/splash_screen.dart';

/// Respiration des anneaux du splash.
///
/// Un anneau figé et un anneau animé se ressemblent dans le code : la seule
/// différence est que la valeur change entre deux images. C'est exactement ce
/// que ces tests mesurent — l'écran était resté immobile en production sans
/// que rien ne le signale.
void main() {
  /// Facteur d'échelle des anneaux à l'image courante, extérieur puis intérieur.
  ///
  /// On vise les anneaux par leur clé : Material insère ses propres `Transform`
  /// dans l'arbre, et `find.byType` en ramenait quatre au lieu de deux.
  List<double> ringScales(WidgetTester tester) => const [280, 200]
      .map((size) => tester
          .widget<Transform>(find.byKey(ValueKey('splash-ring-$size')))
          .transform
          .getMaxScaleOnAxis())
      .toList();

  Future<void> pumpSplash(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: MaterialApp(
          home: SplashScreen(onContinue: () {}),
        ),
      ),
    );
  }

  /// Démonte l'écran : le contrôleur tourne en boucle, un ticker encore actif
  /// ferait échouer le test au démontage.
  Future<void> tearDownSplash(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  testWidgets('les anneaux respirent', (tester) async {
    await pumpSplash(tester);

    final start = ringScales(tester);
    expect(start, hasLength(2), reason: 'deux anneaux décoratifs');

    // Mesure au sommet du cycle. `easeInOut` est presque plat au départ : un
    // quart de cycle ne prouverait rien, l'anneau extérieur n'aurait bougé
    // que de 0,08 % à cause de son décalage de phase.
    await tester.pump(const Duration(milliseconds: 1600));
    final peak = ringScales(tester);

    expect(peak[0], greaterThan(start[0] + 0.01),
        reason: 'l’anneau extérieur doit respirer');
    expect(peak[1], greaterThan(start[1] + 0.01),
        reason: 'l’anneau intérieur doit respirer');

    await tearDownSplash(tester);
  });

  testWidgets('l’amplitude reste discrète', (tester) async {
    await pumpSplash(tester);

    var maxSeen = 1.0;
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      for (final scale in ringScales(tester)) {
        if (scale > maxSeen) maxSeen = scale;
      }
    }

    // Au-delà, l'œil lit un rebond plutôt qu'une respiration — et un écran
    // d'accueil qui rebondit fait bon marché.
    expect(maxSeen, greaterThan(1.0), reason: 'ça doit tout de même grandir');
    expect(maxSeen, lessThan(1.08), reason: 'mais rester sobre');

    await tearDownSplash(tester);
  });

  testWidgets('l’anneau intérieur atteint son sommet avant l’extérieur',
      (tester) async {
    await pumpSplash(tester);

    // On cherche l'instant du maximum de chacun plutôt que de comparer deux
    // valeurs à un instant arbitraire : c'est le décalage lui-même qu'on veut
    // vérifier, et il ne dépend pas du moment où l'on regarde.
    var peakOuter = (frame: 0, scale: 0.0);
    var peakInner = (frame: 0, scale: 0.0);

    for (var frame = 1; frame <= 32; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
      final scales = ringScales(tester);
      if (scales[0] > peakOuter.scale) peakOuter = (frame: frame, scale: scales[0]);
      if (scales[1] > peakInner.scale) peakInner = (frame: frame, scale: scales[1]);
    }

    // En phase, les deux cercles donneraient un simple zoom ; décalés, ils
    // dessinent une onde qui part du logo vers l'extérieur.
    expect(peakInner.frame, lessThan(peakOuter.frame));

    await tearDownSplash(tester);
  });

  testWidgets('« réduire les animations » fige les anneaux', (tester) async {
    await pumpSplash(tester, reduceMotion: true);

    final start = ringScales(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    final later = ringScales(tester);

    // Réglage d'accessibilité, pas une préférence esthétique : le mouvement
    // donne des vertiges à certains utilisateurs.
    expect(later[0], closeTo(start[0], 0.001));
    expect(later[1], closeTo(start[1], 0.001));
    // On n'exige pas une échelle de 1.0 exactement : l'anneau extérieur est
    // déphasé, son image figée n'est pas au tout début du cycle. Ce qui compte
    // est qu'elle ne bouge plus et reste dans les bornes prévues.
    for (final scale in start) {
      expect(scale, inInclusiveRange(1.0, 1.055));
    }

    await tearDownSplash(tester);
  });
}
