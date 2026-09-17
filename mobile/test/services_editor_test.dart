import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/services_editor.dart';

/// Modifier les prestations au moment d'encaisser (§3.4).
void main() {
  const catalogue = [
    ServiceItem(id: 'coupe', name: 'Coupe', price: 15, duration: 30),
    ServiceItem(id: 'fade', name: 'Fade', price: 25, duration: 40),
    ServiceItem(id: 'barbe', name: 'Barbe', price: 10, duration: 15),
  ];

  group('Changement', () {
    test('rien ne change si les prestations sont les mêmes', () {
      expect(servicesChanged(['coupe', 'barbe'], ['barbe', 'coupe']), isFalse,
          reason: 'l’ordre ne compte pas');
    });

    test('une prestation ajoutée sur place', () {
      expect(servicesChanged(['coupe'], ['coupe', 'barbe']), isTrue);
    });

    test('une prestation pas faite', () {
      expect(servicesChanged(['coupe', 'barbe'], ['coupe']), isTrue);
    });

    test('une prestation remplacée', () {
      expect(servicesChanged(['fade'], ['coupe']), isTrue);
    });
  });

  group('Total', () {
    test('additionne les prix du catalogue', () {
      expect(servicesTotal(catalogue, ['coupe', 'barbe']), 25);
    });

    test('une prestation absente du catalogue empêche un faux total', () {
      expect(servicesTotal(catalogue, ['coupe', 'ancienne']), isNull);
    });
  });

  test('le rendez-vous lu du serveur porte ses prestations', () {
    final b = Booking.fromJson(const {'id': 'b1', 'service_ids': ['coupe', 'barbe']});
    expect(b.serviceIds, ['coupe', 'barbe']);
    expect(Booking.fromJson(const {'id': 'b2'}).serviceIds, isEmpty);
  });

  group('Éditeur', () {
    Future<List<String>> monter(WidgetTester tester, List<String> selection) async {
      final touches = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServicesEditor(
              catalogue: catalogue,
              selected: selection,
              onToggle: touches.add,
              fallbackTotal: 40,
            ),
          ),
        ),
      ));
      return touches;
    }

    testWidgets('montre le total des prestations cochées', (tester) async {
      await monter(tester, ['coupe', 'barbe']);

      expect(find.text('25 DT'), findsOneWidget);
    });

    testWidgets('toucher une prestation l’ajoute ou la retire', (tester) async {
      final touches = await monter(tester, ['coupe']);

      await tester.tap(find.text('Barbe · 10 DT'));
      await tester.tap(find.text('Coupe · 15 DT'));

      expect(touches, ['barbe', 'coupe']);
    });

    testWidgets('sans prestation, il explique qu’il faut annuler', (tester) async {
      await monter(tester, []);

      expect(find.textContaining('لازم خدمة وحدة على الأقل'), findsOneWidget);
    });

    testWidgets('une prestation retirée du catalogue garde le prix du rendez-vous',
        (tester) async {
      await monter(tester, ['coupe', 'ancienne']);

      expect(find.text('40 DT'), findsOneWidget);
    });
  });
}
