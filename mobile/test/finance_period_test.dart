import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/finance_period.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/screens/finance_screen.dart';
import 'package:provider/provider.dart';

/// Compte de résultat par période (§3.4) : mois, semaine, période libre.
class _FauxDepot extends CashRepository {
  _FauxDepot() : super(ApiClient(TokenStore()));

  final periodes = <(DateTime?, DateTime?)>[];

  @override
  Future<Pilot> pilot(String salonId, {DateTime? start, DateTime? end}) async {
    periodes.add((start, end));
    return const Pilot(pnl: Pnl(revenue: 1000, result: 250), target: 3000);
  }

  @override
  Future<({List<RecurringCharge> charges, double monthlyEquivalent})> charges(
          String salonId,
          {bool includeInactive = false}) async =>
      (charges: const <RecurringCharge>[], monthlyEquivalent: 0.0);
}

void main() {
  group('Mois', () {
    test('du premier au dernier jour', () {
      final r = monthRange(DateTime(2026, 9, 15), 0);
      expect(r.start, DateTime(2026, 9, 1));
      expect(r.end, DateTime(2026, 9, 30));
    });

    test('janvier recule vers décembre de l’année précédente', () {
      final r = monthRange(DateTime(2026, 1, 10), -1);
      expect(r.start, DateTime(2025, 12, 1));
      expect(r.end, DateTime(2025, 12, 31));
    });

    test('février d’une année bissextile compte 29 jours', () {
      expect(monthRange(DateTime(2028, 2, 3), 0).end, DateTime(2028, 2, 29));
    });
  });

  group('Semaine', () {
    test('commence le lundi, comme la paie et le serveur', () {
      final r = weekRange(DateTime(2026, 9, 16), 0); // mercredi
      expect(r.start, DateTime(2026, 9, 14));
      expect(r.start.weekday, DateTime.monday);
      expect(r.end, DateTime(2026, 9, 20));
    });

    test('un dimanche appartient à la semaine commencée le lundi d’avant', () {
      expect(weekRange(DateTime(2026, 9, 20), 0).start, DateTime(2026, 9, 14));
    });

    test('un lundi ouvre sa propre semaine', () {
      expect(weekRange(DateTime(2026, 9, 14), 0).start, DateTime(2026, 9, 14));
    });

    test('la semaine précédente, à cheval sur deux mois', () {
      final r = weekRange(DateTime(2026, 9, 2), -1);
      expect(r.start, DateTime(2026, 8, 24));
      expect(r.end, DateTime(2026, 8, 30));
    });
  });

  group('Libellé', () {
    final maintenant = DateTime(2026, 9, 15);

    test('le mois porte son nom', () {
      expect(
          rangeLabel(PeriodMode.month, monthRange(maintenant, 0), now: maintenant),
          'سبتمبر 2026');
    });

    test('une semaine de cette année, sans l’année', () {
      expect(
          rangeLabel(PeriodMode.week, weekRange(maintenant, 0), now: maintenant),
          '14/09 → 20/09');
    });

    test('une période d’une autre année porte l’année', () {
      final r = (start: DateTime(2025, 12, 20), end: DateTime(2026, 1, 5));
      expect(rangeLabel(PeriodMode.custom, r, now: maintenant),
          '20/12/2025 → 05/01');
    });
  });

  group('Écran « الميزانية »', () {
    Future<_FauxDepot> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final depot = _FauxDepot();
      await tester.pumpWidget(Provider<CashRepository>.value(
        value: depot,
        child: const MaterialApp(home: FinanceScreen(salonId: 's1')),
      ));
      await tester.pumpAndSettle();
      return depot;
    }

    testWidgets('s’ouvre sur le mois, objectif compris', (tester) async {
      final depot = await monter(tester);

      final (debut, fin) = depot.periodes.last;
      expect(debut!.day, 1);
      expect(fin!.month, debut.month);
      expect(find.text('🎯 الهدف'), findsOneWidget);
    });

    testWidgets('la semaine va du lundi au dimanche, sans objectif mensuel',
        (tester) async {
      final depot = await monter(tester);

      await tester.tap(find.text('أسبوع'));
      await tester.pumpAndSettle();

      final (debut, fin) = depot.periodes.last;
      expect(debut!.weekday, DateTime.monday);
      expect(fin!.difference(debut).inDays, 6);
      expect(find.text('🎯 الهدف'), findsNothing,
          reason: 'un objectif mensuel comparé à une semaine serait trompeur');
    });

    testWidgets('remonter d’une semaine recule de sept jours', (tester) async {
      final depot = await monter(tester);

      await tester.tap(find.text('أسبوع'));
      await tester.pumpAndSettle();
      final (courante, _) = depot.periodes.last;

      await tester.tap(find.byTooltip('اللي قبل'));
      await tester.pumpAndSettle();
      final (precedente, _) = depot.periodes.last;

      expect(courante!.difference(precedente!).inDays, 7);
    });
  });
}
