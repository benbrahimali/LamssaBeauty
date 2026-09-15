import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/widgets/expense_edit_sheet.dart';
import 'package:provider/provider.dart';

/// Corriger une dépense et joindre son ticket (§3.4).
class _FauxDepot extends CashRepository {
  _FauxDepot() : super(ApiClient(TokenStore()));

  final corrections = <Map<String, Object?>>[];
  final ticketsRetires = <String>[];

  @override
  Future<Expense> updateExpense(
    String expenseId, {
    String? label,
    double? amount,
    String? category,
    String? paidFrom,
  }) async {
    corrections.add({'label': label, 'amount': amount, 'paid_from': paidFrom});
    return Expense(id: expenseId, label: label ?? '', amount: amount ?? 0);
  }

  @override
  Future<void> removeReceipt(String expenseId) async => ticketsRetires.add(expenseId);

  @override
  Future<Expense> uploadReceipt(String expenseId, File image) =>
      throw UnimplementedError('le sélecteur de photos n’existe pas en test');
}

void main() {
  group('Dépense reçue du serveur', () {
    test('porte son mode de paiement et son ticket', () {
      final e = Expense.fromJson(const {
        'id': 'e1',
        'label': 'Produits',
        'amount': 45,
        'paid_from': 'bank',
        'receipt_url': 'https://res.cloudinary.com/demo/image/upload/ticket.jpg',
      });
      expect(e.fromDrawer, isFalse);
      expect(e.hasReceipt, isTrue);
    });

    test('sans ticket, rien à charger', () {
      expect(Expense.fromJson(const {'id': 'e1'}).hasReceipt, isFalse);
      expect(Expense.fromJson(const {'id': 'e1', 'receipt_url': ''}).receiptUrl, isNull);
    });

    test('une dépense ancienne, sans mode de paiement, est sortie du tiroir', () {
      expect(Expense.fromJson(const {'id': 'e1'}).fromDrawer, isTrue);
    });
  });

  group('Feuille « تبديل المصروف »', () {
    Future<_FauxDepot> monter(WidgetTester tester, Expense depense) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final depot = _FauxDepot();
      await tester.pumpWidget(Provider<CashRepository>.value(
        value: depot,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ExpenseEditSheet(expense: depense),
            ),
          ),
        ),
      ));
      // Pas `pumpAndSettle` : l'image d'un ticket ne se charge jamais en test,
      // son indicateur tournerait sans fin.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      return depot;
    }

    const produits = Expense(id: 'e1', label: 'Produits', amount: 45);

    testWidgets('la dépense s’ouvre avec ses valeurs', (tester) async {
      await monter(tester, produits);

      expect(find.widgetWithText(TextField, 'Produits'), findsOneWidget);
      expect(find.widgetWithText(TextField, '45'), findsOneWidget);
      expect(find.textContaining('ما فماش تيكيه'), findsOneWidget);
    });

    testWidgets('corriger le montant et passer au virement', (tester) async {
      final depot = await monter(tester, produits);

      await tester.enterText(find.widgetWithText(TextField, '45'), '54');
      await tester.tap(find.text('تحويل'));
      await tester.tap(find.text('سجّل التبديل'));
      await tester.pumpAndSettle();

      expect(depot.corrections, [
        {'label': 'Produits', 'amount': 54.0, 'paid_from': 'bank'},
      ]);
    });

    testWidgets('un montant vide n’est pas envoyé', (tester) async {
      final depot = await monter(tester, produits);

      await tester.enterText(find.widgetWithText(TextField, '45'), '');
      await tester.tap(find.text('سجّل التبديل'));
      await tester.pumpAndSettle();

      expect(depot.corrections, isEmpty);
    });

    testWidgets('un ticket joint se retire', (tester) async {
      final depot = await monter(
        tester,
        const Expense(
          id: 'e1',
          label: 'Produits',
          amount: 45,
          receiptUrl: 'https://res.cloudinary.com/demo/image/upload/ticket.jpg',
        ),
      );

      expect(find.text('صوّر من جديد'), findsOneWidget);
      await tester.tap(find.text('نحّي التيكيه'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(depot.ticketsRetires, ['e1']);
      expect(find.textContaining('ما فماش تيكيه'), findsOneWidget);
    });
  });
}
