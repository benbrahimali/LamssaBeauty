import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/widgets/closure_dialog.dart';
import 'package:lamssa/widgets/prompt_dialog.dart';

/// Cycle de vie des boîtes de saisie.
///
/// Un `TextEditingController` créé dans une méthode puis libéré juste après
/// `await showDialog` est encore utilisé pendant l'animation de fermeture :
/// « A TextEditingController was used after being disposed », suivi d'un arbre
/// corrompu — GlobalKeys dupliquées, overflow aberrant, écran rouge sur
/// l'appareil. Ces tests fixent la règle inverse : la boîte possède ses
/// contrôleurs, et rien ne casse une fois la route réellement partie.
void main() {
  /// Ouvre une boîte et rend son résultat, en laissant l'animation de
  /// fermeture se dérouler entièrement — c'est là que le bug se manifestait.
  Future<T?> ouvrirPuisFermer<T>(
    WidgetTester tester,
    Future<T?> Function(BuildContext) ouvrir,
    String boutonDeSortie,
  ) async {
    T? resultat;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => resultat = await ouvrir(context),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(boutonDeSortie));
    await tester.pumpAndSettle();
    return resultat;
  }

  group('PromptDialog', () {
    testWidgets('la fermeture ne laisse aucun contrôleur libéré derrière elle',
        (tester) async {
      await ouvrirPuisFermer<PromptResult>(
        tester,
        (context) => PromptDialog.show(
          context,
          title: 'titre',
          fields: const [PromptField(name: 'a'), PromptField(name: 'b')],
        ),
        'سجّل',
      );

      // pumpAndSettle a déroulé toute l'animation de sortie : si les
      // contrôleurs avaient été libérés trop tôt, l'erreur serait remontée ici.
      expect(tester.takeException(), isNull);
    });

    testWidgets('rend ce que l’utilisateur a saisi', (tester) async {
      late PromptResult? resultat;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => resultat = await PromptDialog.show(
                  context,
                  title: 'titre',
                  fields: const [
                    PromptField(name: 'montant', numeric: true),
                    PromptField(name: 'motif'),
                  ],
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '25,5');
      await tester.enterText(find.byType(TextField).at(1), '  Dépôt banque  ');
      await tester.tap(find.text('سجّل'));
      await tester.pumpAndSettle();

      // La virgule tunisienne doit être lue comme un séparateur décimal.
      expect(resultat!.number('montant'), 25.5);
      expect(resultat!['motif'], 'Dépôt banque');
      expect(resultat!.neutral, isFalse);
    });

    testWidgets('annuler ne rend rien', (tester) async {
      final resultat = await ouvrirPuisFermer<PromptResult>(
        tester,
        (context) => PromptDialog.show(
          context,
          title: 'titre',
          fields: const [PromptField(name: 'a')],
        ),
        'رجوع',
      );
      expect(resultat, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('l’action neutre se distingue d’une saisie', (tester) async {
      final resultat = await ouvrirPuisFermer<PromptResult>(
        tester,
        (context) => PromptDialog.show(
          context,
          title: 'objectif',
          fields: const [PromptField(name: 'objectif', numeric: true)],
          neutralLabel: 'نحّي',
        ),
        'نحّي',
      );

      // Sans ce drapeau, « retirer l'objectif » et « champ vide » seraient
      // indiscernables et l'objectif ne pourrait jamais être retiré.
      expect(resultat!.neutral, isTrue);
    });

    testWidgets('un champ vide rend null, pas zéro', (tester) async {
      final resultat = await ouvrirPuisFermer<PromptResult>(
        tester,
        (context) => PromptDialog.show(
          context,
          title: 'titre',
          fields: const [PromptField(name: 'montant', numeric: true)],
        ),
        'سجّل',
      );

      // Zéro serait une valeur déclarée ; l'absence de saisie n'en est pas une.
      expect(resultat!.number('montant'), isNull);
    });
  });

  group('ClosureDialog', () {
    testWidgets('la fermeture ne laisse aucun contrôleur libéré derrière elle',
        (tester) async {
      await ouvrirPuisFermer<ClosureInput>(
        tester,
        (context) => ClosureDialog.show(context, 245),
        'سكّر',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans comptage, aucun écart n’est prétendu', (tester) async {
      final saisie = await ouvrirPuisFermer<ClosureInput>(
        tester,
        (context) => ClosureDialog.show(context, 245),
        'سكّر',
      );

      // Le cas courant : le gérant ferme sans compter. Un zéro afficherait un
      // écart nul mensonger.
      expect(saisie!.countedCash, isNull);
      expect(saisie.withdrawal, 0);
    });

    testWidgets('l’écart s’affiche dès que le tiroir est compté',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ClosureDialog.show(context, 245),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ناقص'), findsNothing);

      await tester.enterText(find.byType(TextField).first, '240');
      await tester.pumpAndSettle();

      expect(find.textContaining('ناقص'), findsOneWidget,
          reason: 'il manque 5 DT, le gérant doit le voir avant de valider');
      expect(find.text('-5.00 DT'), findsOneWidget);
    });

    testWidgets('un excédent est signalé comme une anomalie, pas comme un gain',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => ClosureDialog.show(context, 245),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '260');
      await tester.pumpAndSettle();

      // Trop d'argent est aussi une erreur : un encaissement non saisi.
      expect(find.textContaining('زايد'), findsOneWidget);
    });

    testWidgets('le comptage et le prélèvement remontent tels quels',
        (tester) async {
      late ClosureInput? saisie;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    saisie = await ClosureDialog.show(context, 245),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '240');
      await tester.pumpAndSettle();
      // Le motif n'apparaît qu'une fois l'écart constaté.
      await tester.enterText(find.byType(TextField).at(1), 'rendu de monnaie');
      await tester.enterText(find.byType(TextField).at(2), '100');
      await tester.tap(find.text('سكّر'));
      await tester.pumpAndSettle();

      expect(saisie!.countedCash, 240);
      expect(saisie!.withdrawal, 100);
      expect(saisie!.reason, 'rendu de monnaie');
    });
  });
}
