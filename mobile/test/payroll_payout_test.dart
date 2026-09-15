import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/widgets/payroll_sheet.dart';
import 'package:provider/provider.dart';

/// Paie versée aux coiffeurs, dans « خلاص الأسبوع » (§3.4).
class _FauxDepot extends CashRepository {
  _FauxDepot(this._paie) : super(ApiClient(TokenStore()));

  final Payroll _paie;
  final versements = <(String, String)>[];
  final annulations = <String>[];

  @override
  Future<Payroll> payroll(String salonId, {DateTime? weekOf}) async => _paie;

  @override
  Future<void> payStaff({
    required String salonId,
    required String staffId,
    DateTime? weekOf,
    String paidFrom = 'cash',
  }) async {
    versements.add((staffId, paidFrom));
  }

  @override
  Future<void> cancelPayout(String payoutId) async => annulations.add(payoutId);
}

void main() {
  group('Ligne de paie', () {
    test('sans versement, tout le solde reste à payer', () {
      final l = PayrollLine.fromJson(const {'staff_id': 'st1', 'balance': 150});
      expect(l.remaining, 150);
      expect(l.canPay, isTrue);
      expect(l.fullyPaid, isFalse);
    });

    test('une paie complète ne laisse rien à verser', () {
      final l = PayrollLine.fromJson(const {
        'staff_id': 'st1',
        'balance': 150,
        'paid': 150,
        'remaining': 0,
        'payouts': [
          {'id': 'p1', 'amount': 150, 'paid_from': 'cash', 'day': '2026-09-15'},
        ],
      });
      expect(l.canPay, isFalse);
      expect(l.fullyPaid, isTrue);
      expect(l.payouts.single.fromDrawer, isTrue);
    });

    test('un coiffeur qui a retravaillé après la paie a encore un reste', () {
      final l = PayrollLine.fromJson(
          const {'staff_id': 'st1', 'balance': 140, 'paid': 100, 'remaining': 40});
      expect(l.canPay, isTrue);
      expect(l.fullyPaid, isFalse);
    });

    test('un virement ne sort pas du tiroir', () {
      expect(
          PayrollPayout.fromJson(const {'id': 'p', 'amount': 10, 'paid_from': 'bank'})
              .fromDrawer,
          isFalse);
    });

    test('un serveur antérieur aux versements reste lisible', () {
      final p = Payroll.fromJson(const {'week_start': 'a', 'week_end': 'b', 'total_to_pay': 90});
      expect(p.totalRemaining, 90, reason: 'rien n’a été versé, tout reste dû');
      expect(p.totalPaid, 0);
    });
  });

  group('Feuille « خلاص الأسبوع »', () {
    Future<_FauxDepot> monter(WidgetTester tester, PayrollLine ligne,
        {VoidCallback? onChanged}) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final depot = _FauxDepot(Payroll(
        weekStart: '2026-09-14',
        weekEnd: '2026-09-21',
        staff: [ligne],
        totalRemaining: ligne.remaining,
        totalPaid: ligne.paid,
      ));
      await tester.pumpWidget(
        Provider<CashRepository>.value(
          value: depot,
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: PayrollSheet(salonId: 's1', onChanged: onChanged),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return depot;
    }

    const aPayer = PayrollLine(
      staffId: 'st1',
      name: 'Ahmed',
      services: 6,
      earned: 150,
      balance: 150,
    );

    testWidgets('le gérant verse la paie depuis le tiroir', (tester) async {
      var rafraichi = false;
      final depot = await monter(tester, aPayer, onChanged: () => rafraichi = true);

      await tester.tap(find.text('خلّص 150.00 DT'));
      await tester.pumpAndSettle();
      expect(find.text('خلّص Ahmed ؟'), findsOneWidget);

      await tester.tap(find.text('من الدرج'));
      await tester.pumpAndSettle();

      expect(depot.versements, [('st1', 'cash')]);
      expect(rafraichi, isTrue, reason: 'la caisse doit voir l’argent sorti');
    });

    testWidgets('ou par virement', (tester) async {
      final depot = await monter(tester, aPayer);

      await tester.tap(find.text('خلّص 150.00 DT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('بتحويل'));
      await tester.pumpAndSettle();

      expect(depot.versements, [('st1', 'bank')]);
    });

    testWidgets('revenir en arrière ne verse rien', (tester) async {
      final depot = await monter(tester, aPayer);

      await tester.tap(find.text('خلّص 150.00 DT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رجوع'));
      await tester.pumpAndSettle();

      expect(depot.versements, isEmpty);
    });

    testWidgets('une semaine payée n’offre plus de bouton, mais son historique',
        (tester) async {
      await monter(
        tester,
        const PayrollLine(
          staffId: 'st1',
          name: 'Ahmed',
          services: 6,
          earned: 150,
          balance: 150,
          paid: 150,
          remaining: 0,
          payouts: [
            PayrollPayout(id: 'p1', amount: 150, paidFrom: 'cash', day: '2026-09-15'),
          ],
        ),
      );

      // Texte exact : l'historique « تخلّص 150.00 DT » contient ces mots.
      expect(find.text('خلّص 150.00 DT'), findsNothing);
      expect(find.text('✅ تخلّص كامل'), findsOneWidget);
      expect(find.textContaining('تخلّص 150.00 DT · من الدرج'), findsOneWidget);
    });

    testWidgets('un reste après un premier versement se paie à part',
        (tester) async {
      await monter(
        tester,
        const PayrollLine(
          staffId: 'st1',
          name: 'Ahmed',
          services: 8,
          earned: 190,
          balance: 190,
          paid: 150,
          remaining: 40,
          payouts: [PayrollPayout(id: 'p1', amount: 150)],
        ),
      );

      expect(find.text('خلّص الباقي 40.00 DT'), findsOneWidget);
    });

    testWidgets('un versement enregistré par erreur s’annule', (tester) async {
      final depot = await monter(
        tester,
        const PayrollLine(
          staffId: 'st1',
          name: 'Ahmed',
          services: 6,
          earned: 150,
          balance: 150,
          paid: 150,
          remaining: 0,
          payouts: [PayrollPayout(id: 'p1', amount: 150)],
        ),
      );

      await tester.tap(find.byTooltip('نحّي هالخلاص'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('نعم'));
      await tester.pumpAndSettle();

      expect(depot.annulations, ['p1']);
    });
  });
}
