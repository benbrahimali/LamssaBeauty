import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/cash_controller.dart';
import 'package:lamssa/widgets/treasury_sheet.dart';
import 'package:provider/provider.dart';

/// Fond de caisse déclaré par le gérant dans « الصندوق » (§3.4).
class _FauxCash extends CashController {
  _FauxCash(this._tresor)
      : super(
          CashRepository(ApiClient(TokenStore())),
          BookingRepository(ApiClient(TokenStore())),
          SalonRepository(ApiClient(TokenStore())),
        );

  final Treasury _tresor;
  final ajouts = <(String, double)>[];
  final suppressions = <String>[];

  @override
  Future<Treasury?> treasury() async => _tresor;

  @override
  Future<bool> addMovement({
    required String type,
    required double amount,
    String label = '',
  }) async {
    ajouts.add((type, amount));
    return true;
  }

  @override
  Future<bool> removeMovementById(String movementId) async {
    suppressions.add(movementId);
    return true;
  }
}

void main() {
  group('Écart avec la veille', () {
    test('aucun écart, aucun message', () {
      expect(openingGapLabel(0), isEmpty);
      expect(openingGapLabel(0.004), isEmpty);
    });

    test('il manque de l’argent depuis la veille', () {
      expect(openingGapLabel(-20), '20.00 DT أقل من اللي بقى البارح');
    });

    test('il y en a plus que la veille', () {
      expect(openingGapLabel(80), '80.00 DT أكثر من اللي بقى البارح');
    });
  });

  test('la trésorerie reçue du serveur porte le fond déclaré et l’écart', () {
    final t = Treasury.fromJson(const {
      'opening_float': 200,
      'carried_float': 220,
      'opening_declared': true,
      'opening_gap': -20,
      'opening_movement_id': 'm1',
    });
    expect(t.openingFloat, 200);
    expect(t.carriedFloat, 220);
    expect(t.openingDeclared, isTrue);
    expect(t.openingGap, -20);
    expect(t.openingMovementId, 'm1');
  });

  test('une réponse ancienne, sans ces champs, reste lisible', () {
    final t = Treasury.fromJson(const {'opening_float': 150});
    expect(t.openingDeclared, isFalse);
    expect(t.openingGap, 0);
    expect(t.openingMovementId, isNull);
  });

  group('Feuille « الصندوق »', () {
    Future<_FauxCash> monter(WidgetTester tester, Treasury tresor) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final cash = _FauxCash(tresor);
      await tester.pumpWidget(
        ChangeNotifierProvider<CashController>.value(
          value: cash,
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: TreasurySheet(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return cash;
    }

    testWidgets('le gérant déclare le fond de caisse du jour', (tester) async {
      final cash = await monter(
          tester, const Treasury(openingFloat: 220, carriedFloat: 220));

      await tester.tap(find.text('فلوس البداية'));
      await tester.pumpAndSettle();

      // Le montant de la veille est proposé, pas un champ vide.
      expect(find.widgetWithText(TextField, '220.00'), findsOneWidget);
      expect(find.textContaining('البارح بقات 220.00 DT'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '180');
      await tester.tap(find.text('سجّل'));
      await tester.pumpAndSettle();

      expect(cash.ajouts, [('opening_float', 180.0)]);
    });

    testWidgets('un tiroir vide peut être déclaré à zéro', (tester) async {
      final cash = await monter(tester, const Treasury(openingFloat: 50));

      await tester.tap(find.text('فلوس البداية'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0');
      await tester.tap(find.text('سجّل'));
      await tester.pumpAndSettle();

      expect(cash.ajouts, [('opening_float', 0.0)]);
    });

    testWidgets('l’écart avec la veille reste visible', (tester) async {
      await monter(
        tester,
        const Treasury(
          openingFloat: 200,
          carriedFloat: 220,
          openingDeclared: true,
          openingGap: -20,
          openingMovementId: 'm1',
        ),
      );

      expect(find.text('فلوس البداية (مصرّح بيها)'), findsOneWidget);
      expect(find.textContaining('20.00 DT أقل من اللي بقى البارح'), findsOneWidget);
    });

    testWidgets('revenir au montant de la veille retire la déclaration',
        (tester) async {
      final cash = await monter(
        tester,
        const Treasury(
          openingFloat: 200,
          carriedFloat: 220,
          openingDeclared: true,
          openingGap: -20,
          openingMovementId: 'm1',
        ),
      );

      await tester.tap(find.text('فلوس البداية (مصرّح بيها)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('رجّع مبلغ البارح'));
      await tester.pumpAndSettle();

      expect(cash.suppressions, ['m1']);
      expect(cash.ajouts, isEmpty);
    });

    testWidgets('sans déclaration, pas de retour à proposer', (tester) async {
      await monter(tester, const Treasury(openingFloat: 220, carriedFloat: 220));

      await tester.tap(find.text('فلوس البداية'));
      await tester.pumpAndSettle();

      expect(find.text('رجّع مبلغ البارح'), findsNothing);
    });

    testWidgets('une journée clôturée ne se modifie plus', (tester) async {
      final cash = await monter(
          tester, const Treasury(openingFloat: 220, closed: true));

      expect(find.byIcon(Icons.edit_rounded), findsNothing);
      await tester.tap(find.text('فلوس البداية'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(cash.ajouts, isEmpty);
    });
  });
}
