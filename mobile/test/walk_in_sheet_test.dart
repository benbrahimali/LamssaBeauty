import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/walk_in_sheet.dart';

/// Saisie d'un client de passage (§3.3) : une ou plusieurs prestations.
void main() {
  const services = [
    ServiceItem(id: 'coupe', name: 'Coupe', price: 15, duration: 30),
    ServiceItem(id: 'fade', name: 'Fade', price: 25, duration: 40),
    ServiceItem(id: 'barbe', name: 'Barbe', price: 10, duration: 15),
  ];
  const equipe = [Coiffeur(id: 'st1', name: 'Ahmed')];

  Future<List<WalkInPayload?>> ouvrir(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final resultats = <WalkInPayload?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => resultats.add(
                await showModalBottomSheet<WalkInPayload>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const WalkInSheet(services: services, team: equipe),
                ),
              ),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    return resultats;
  }

  testWidgets('une prestation est choisie par défaut', (tester) async {
    final resultats = await ouvrir(tester);

    await tester.tap(find.text('زيدو و خلّص'));
    await tester.pumpAndSettle();

    expect(resultats.single!.serviceIds, ['coupe']);
  });

  testWidgets('coupe + barbe : le total s’affiche et les deux partent', (tester) async {
    final resultats = await ouvrir(tester);

    await tester.tap(find.text('Barbe · 10 DT'));
    await tester.pump();
    expect(find.text('المجموع : 25 DT'), findsOneWidget);

    await tester.tap(find.text('زيدو و خلّص'));
    await tester.pumpAndSettle();

    expect(resultats.single!.serviceIds, ['coupe', 'barbe'],
        reason: 'dans l’ordre du catalogue, pas du toucher');
  });

  testWidgets('retoucher une prestation la retire', (tester) async {
    final resultats = await ouvrir(tester);

    await tester.tap(find.text('Fade · 25 DT'));
    await tester.tap(find.text('Coupe · 15 DT'));
    await tester.pump();
    await tester.tap(find.text('زيدو و خلّص'));
    await tester.pumpAndSettle();

    expect(resultats.single!.serviceIds, ['fade']);
  });

  testWidgets('sans prestation, rien ne part', (tester) async {
    final resultats = await ouvrir(tester);

    await tester.tap(find.text('Coupe · 15 DT'));
    await tester.pump();
    await tester.tap(find.text('زيدو و خلّص'));
    await tester.pumpAndSettle();

    expect(resultats, isEmpty, reason: 'le bouton est inactif, la feuille reste ouverte');
  });
}
