import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/widgets/revenue_bar.dart';

/// Graphique des recettes du gérant (§3.4).
///
/// « A RenderFlex overflowed by 1.00 pixels » : deux libellés plus une barre
/// de 90 px réclamaient 131 px dans une boîte de 130. Un pixel suffit à
/// afficher la bande rayée jaune et noire sur l'appareil.
void main() {
  /// Rend une semaine de barres dans la boîte du tableau de bord.
  ///
  /// Un débordement lève une FlutterError, qui fait échouer le test : c'est
  /// exactement le garde-fou qui manquait.
  Future<void> pumpChart(
    WidgetTester tester, {
    double textScale = 1.0,
    double height = 130,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(
                    7,
                    (i) => RevenueBar(
                      value: i * 137.0,
                      ratio: i / 6,
                      label: '${i + 1}',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('le graphique tient dans sa boîte', (tester) async {
    await pumpChart(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('… même avec une police agrandie', (tester) async {
    // Réglage d'accessibilité courant : c'est là que les hauteurs figées
    // cassent, et personne ne teste avec.
    for (final scale in [1.3, 1.6, 2.0]) {
      await pumpChart(tester, textScale: scale);
      expect(tester.takeException(), isNull, reason: 'police ×$scale');
    }
  });

  testWidgets('… et dans une boîte plus étroite', (tester) async {
    await pumpChart(tester, height: 90);
    expect(tester.takeException(), isNull);
  });

  testWidgets('une journée à zéro reste visible', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 130,
              child: Row(children: [
                RevenueBar(value: 0, ratio: 0, label: '1'),
              ]),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    // Sans plancher, un jour sans recette donnerait une barre de hauteur nulle
    // — indistinguable d'une donnée manquante.
    final barre = tester.getSize(find.byType(AnimatedContainer));
    expect(barre.height, greaterThan(2));
    expect(tester.takeException(), isNull);
  });
}
