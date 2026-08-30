import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/salon_admin_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/screens/manage_salon_screen.dart';
import 'package:provider/provider.dart';

/// Mise en page de « إدارة صالوني » sur un écran d'appareil.
///
/// L'onglet des horaires empile sept rangées à interrupteur : sur un téléphone
/// ordinaire elles dépassent la hauteur disponible. Sans défilement, c'est
/// « A RenderFlex overflowed by 45 pixels on the bottom » — et un débordement
/// finit par corrompre l'arbre, comme sur l'écran Caisse.
class _FauxAdmin extends SalonAdminRepository {
  _FauxAdmin() : super(ApiClient(TokenStore()));

  @override
  Future<List<ServiceItem>> services(String salonId,
          {bool includeInactive = false}) async =>
      const [
        ServiceItem(id: 's1', name: 'Coupe homme', price: 25, duration: 30),
        ServiceItem(id: 's2', name: 'Barbe', price: 15, duration: 20),
      ];

  @override
  Future<List<Coiffeur>> staff(String salonId) async => const [
        Coiffeur(id: 'c1', name: 'Ahmed Trabelsi'),
        Coiffeur(id: 'c2', name: 'Rania Ben Salah'),
      ];
}

class _FauxSalons extends SalonRepository {
  _FauxSalons() : super(ApiClient(TokenStore()));

  @override
  Future<SalonDetail> detail(String salonId) async => SalonDetail(
        salon: const Salon(
          id: 'salon1',
          name: 'Barbier El Menzah',
          type: SalonType.barbershop,
          photos: ['a.jpg', 'b.jpg'],
        ),
        hours: {
          for (final j in kWeekdays)
            j.key: DayHours(
              closed: j.key == 'sun',
              // Une pause allonge la ligne : c'est le pire cas d'affichage.
              breakStart: '12:30',
              breakEnd: '13:30',
            ),
        },
      );
}

void main() {
  Future<void> monter(WidgetTester tester, {double police = 1.0}) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SalonAdminRepository>.value(value: _FauxAdmin()),
          Provider<SalonRepository>.value(value: _FauxSalons()),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(police)),
              child: const ManageSalonScreen(
                salonId: 'salon1',
                salonName: 'Barbier El Menzah',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void ecranDe(WidgetTester tester, double hauteur) {
    tester.view.physicalSize = Size(720, hauteur);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  /// Ouvre l'onglet dont le libellé commence par [prefixe].
  Future<void> ongletHoraires(WidgetTester tester) async {
    await tester.tap(find.text('الأوقات'));
    await tester.pumpAndSettle();
  }

  testWidgets('les sept jours tiennent dans l’écran', (tester) async {
    ecranDe(tester, 1612);
    await monter(tester);
    await ongletHoraires(tester);

    expect(tester.takeException(), isNull,
        reason: 'sept rangées à interrupteur dépassent la hauteur : '
            'l’onglet doit défiler');
  });

  testWidgets('sur un petit écran l’onglet défile', (tester) async {
    ecranDe(tester, 1280);
    await monter(tester);
    await ongletHoraires(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('une police agrandie ne fait pas déborder', (tester) async {
    ecranDe(tester, 1612);
    await monter(tester, police: 1.3);
    await ongletHoraires(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('les autres onglets restent sains', (tester) async {
    ecranDe(tester, 1280);
    await monter(tester);

    for (final onglet in ['الفريق (2)', 'التصاور (2)']) {
      await tester.tap(find.text(onglet));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'onglet $onglet');
    }
  });
}
