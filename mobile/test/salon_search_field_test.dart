import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/theme/app_theme.dart';
import 'package:lamssa/widgets/salon_search_field.dart';

/// Barre de recherche de l'accueil et de « اكتشف » : chaque icône agit.
void main() {
  Future<void> monter(
    WidgetTester tester, {
    String query = '',
    ValueChanged<String>? onSearch,
    VoidCallback? onLocate,
    bool locating = false,
    bool located = false,
    double largeur = 400,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: largeur,
              child: SalonSearchField(
                query: query,
                onSearch: onSearch ?? (_) {},
                onLocate: onLocate,
                locating: locating,
                located: located,
              ),
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('la loupe lance la recherche', (tester) async {
    String? cherche;
    await monter(tester, onSearch: (q) => cherche = q);

    await tester.enterText(find.byType(TextField), '  Rania  ');
    await tester.tap(find.byIcon(Icons.search_rounded));

    expect(cherche, 'Rania', reason: 'les espaces autour ne comptent pas');
  });

  testWidgets('la touche « rechercher » du clavier aussi', (tester) async {
    String? cherche;
    await monter(tester, onSearch: (q) => cherche = q);

    await tester.enterText(find.byType(TextField), 'Berber');
    await tester.testTextInput.receiveAction(TextInputAction.search);

    expect(cherche, 'Berber');
  });

  testWidgets('la croix n’apparaît qu’avec du texte, et efface la recherche',
      (tester) async {
    String? cherche;
    await monter(tester, onSearch: (q) => cherche = q);
    expect(find.byIcon(Icons.close_rounded), findsNothing);

    await tester.enterText(find.byType(TextField), 'Rania');
    await tester.pump();
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(cherche, '', reason: 'la liste doit revenir à tous les salons');
    expect(find.text('Rania'), findsNothing);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('l’épingle récupère la position', (tester) async {
    var localise = false;
    await monter(tester, onLocate: () => localise = true);

    await tester.tap(find.byIcon(Icons.location_on_rounded));
    expect(localise, isTrue);
  });

  testWidgets('sans action de position, pas d’épingle trompeuse', (tester) async {
    await monter(tester);

    expect(find.byIcon(Icons.location_on_rounded), findsNothing);
    expect(find.byIcon(Icons.my_location_rounded), findsNothing);
  });

  testWidgets('position connue : l’épingle passe en doré', (tester) async {
    await monter(tester, onLocate: () {}, located: true);

    final icone = tester.widget<Icon>(find.byIcon(Icons.my_location_rounded));
    expect(icone.color, AppColors.gold);
  });

  testWidgets('pendant la localisation, un indicateur remplace l’épingle',
      (tester) async {
    await monter(tester, onLocate: () {}, locating: true);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsNothing);
  });

  testWidgets('pas de second cadre à l’intérieur de la barre', (tester) async {
    await monter(tester);

    final deco = tester.widget<TextField>(find.byType(TextField)).decoration!;
    expect(deco.enabledBorder, InputBorder.none);
    expect(deco.focusedBorder, InputBorder.none);
    expect(deco.filled, isFalse);
  });

  testWidgets('affiche la recherche lancée depuis l’autre écran', (tester) async {
    await monter(tester, query: 'Berber');
    expect(find.text('Berber'), findsOneWidget);

    await monter(tester, query: 'Rania');
    expect(find.text('Rania'), findsOneWidget);
  });

  testWidgets('tient sur un écran étroit, texte et position compris',
      (tester) async {
    await monter(tester, onLocate: () {}, located: true, largeur: 280);
    await tester.enterText(find.byType(TextField), 'Salon de coiffure du centre');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
