import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/widgets/my_pay_card.dart';
import 'package:provider/provider.dart';

/// La paie vue par le coiffeur (§3.4) : ce qu'il touchera, ce qu'il a reçu.
class _FauxDepot extends CashRepository {
  _FauxDepot() : super(ApiClient(TokenStore()));

  final semainesDemandees = <DateTime?>[];

  @override
  Future<PayrollLine> myPayroll({DateTime? weekOf}) async {
    semainesDemandees.add(weekOf);
    return const PayrollLine(
      staffId: 'st1',
      services: 6,
      earned: 150,
      tips: 10,
      balance: 160,
      paid: 100,
      remaining: 60,
      weekStart: '2026-09-14',
      weekEnd: '2026-09-21',
      payouts: [
        PayrollPayout(id: 'p1', amount: 100, paidFrom: 'cash', day: '2026-09-16'),
      ],
    );
  }

  @override
  Future<MonthBalance> myBalance({int? year, int? month}) async =>
      const MonthBalance(period: '2026-09', services: 20, earned: 500, tips: 40, paid: 300);
}

void main() {
  Widget cadre(Widget child, {double largeur = 400}) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(child: SizedBox(width: largeur, child: child)),
            ),
          ),
        ),
      );

  test('le mois lu depuis le serveur porte ce qui a été reçu', () {
    final m = MonthBalance.fromJson(const {
      'period': '2026-09',
      'services': 20,
      'earned': 500,
      'tips': 40,
      'advances': 60,
      'balance': 480,
      'paid': 300,
    });
    expect(m.earnedWithTips, 540);
    expect(m.paid, 300);
    expect(m.balance, 480);
  });

  group('Carte « خلاصي هالأسبوع »', () {
    testWidgets('ce qui lui reste à toucher', (tester) async {
      await tester.pumpWidget(cadre(const MyPayCard(
        week: PayrollLine(staffId: 'st1', earned: 150, tips: 10, balance: 160),
      )));

      expect(find.text('باقي ليك'), findsOneWidget);
      expect(find.text('160.00 DT'), findsWidgets);
    });

    testWidgets('une semaine entièrement payée', (tester) async {
      await tester.pumpWidget(cadre(const MyPayCard(
        week: PayrollLine(
            staffId: 'st1', earned: 150, balance: 150, paid: 150, remaining: 0),
      )));

      expect(find.text('✅ وصلك الخلاص كامل'), findsOneWidget);
      expect(find.text('وصلني'), findsOneWidget);
    });

    testWidgets('trop d’avance : il doit au salon, et le voit', (tester) async {
      await tester.pumpWidget(cadre(const MyPayCard(
        week: PayrollLine(staffId: 'st1', earned: 70, advances: 100, balance: -30),
      )));

      expect(find.text('عليك للصالون'), findsOneWidget);
      expect(find.text('30.00 DT'), findsOneWidget);
    });

    testWidgets('le mois résume gagné et reçu', (tester) async {
      await tester.pumpWidget(cadre(const MyPayCard(
        week: PayrollLine(staffId: 'st1', balance: 0),
        month: MonthBalance(earned: 500, tips: 40, paid: 300),
      )));

      expect(find.textContaining('540.00 DT مكسوب'), findsOneWidget);
      expect(find.textContaining('300.00 DT وصلك'), findsOneWidget);
    });

    testWidgets('sans données, la carte ne ment pas avec des zéros',
        (tester) async {
      await tester.pumpWidget(cadre(const MyPayCard(week: null)));

      expect(find.text('💰 خلاصي هالأسبوع'), findsNothing);
    });

    testWidgets('tient sur un écran étroit', (tester) async {
      await tester.pumpWidget(cadre(
          const MyPayCard(
            week: PayrollLine(
                staffId: 'st1', earned: 1250, tips: 80, advances: 300, balance: 1030, paid: 500, remaining: 530),
            month: MonthBalance(earned: 4800, tips: 320, paid: 3900),
          ),
          largeur: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('Feuille « خلاصي »', () {
    Future<_FauxDepot> monter(WidgetTester tester) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final depot = _FauxDepot();
      await tester.pumpWidget(Provider<CashRepository>.value(
        value: depot,
        child: const MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: MyPaySheet()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return depot;
    }

    testWidgets('montre le reste, les versements reçus et le mois',
        (tester) async {
      await monter(tester);

      expect(find.text('باقي ليك'), findsOneWidget);
      expect(find.text('60.00 DT'), findsOneWidget);
      expect(find.textContaining('كاش · 2026-09-16'), findsOneWidget);
      expect(find.text('وصلني هالشهر'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remonte à la semaine précédente, pas vers le futur',
        (tester) async {
      final depot = await monter(tester);

      await tester.tap(find.byTooltip('الأسبوع اللي فات'));
      await tester.pumpAndSettle();

      expect(depot.semainesDemandees, hasLength(2));
      final avant = depot.semainesDemandees[0]!;
      final apres = depot.semainesDemandees[1]!;
      // Deux `DateTime.now()` pris à quelques millisecondes d'écart : on
      // compare en heures, pas en jours entiers arrondis vers le bas.
      expect(avant.difference(apres).inMinutes / 60, closeTo(168, 1));
    });
  });
}
