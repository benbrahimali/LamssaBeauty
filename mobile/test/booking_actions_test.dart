import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/booking_actions.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/booking_actions_menu.dart';

/// Ce que le salon peut faire d'un rendez-vous (§3.3) : c'est par ces gestes
/// que l'app sait si le client est venu.
void main() {
  final maintenant = DateTime(2026, 9, 17, 14);

  Booking rdv(BookingStatus status, {DateTime? start}) =>
      Booking(id: 'b1', status: status, start: start ?? DateTime(2026, 9, 17, 13));

  group('Actions', () {
    test('un rendez-vous confirmé passé : خلّص, ما جاش, بطّل', () {
      expect(bookingActions(rdv(BookingStatus.confirmed), maintenant),
          [BookingAction.complete, BookingAction.noShow, BookingAction.cancel]);
    });

    test('avant l’heure, pas de « ما جاش »', () {
      final plusTard = rdv(BookingStatus.confirmed, start: DateTime(2026, 9, 17, 16));
      expect(bookingActions(plusTard, maintenant), isNot(contains(BookingAction.noShow)));
      expect(bookingActions(plusTard, maintenant), contains(BookingAction.complete),
          reason: 'un client arrivé en avance s’encaisse');
    });

    test('un client marqué absent peut encore être encaissé', () {
      expect(bookingActions(rdv(BookingStatus.noShow), maintenant), [BookingAction.complete]);
    });

    test('un paiement en ligne en attente peut être annulé, pas encaissé', () {
      expect(bookingActions(rdv(BookingStatus.pending), maintenant), [BookingAction.cancel]);
    });

    test('un rendez-vous terminé ou annulé n’a plus d’action', () {
      expect(bookingActions(rdv(BookingStatus.done), maintenant), isEmpty);
      expect(bookingActions(rdv(BookingStatus.cancelled), maintenant), isEmpty);
    });
  });

  group('Menu', () {
    Future<List<BookingAction>> monter(WidgetTester tester, List<BookingAction> actions) async {
      final choisies = <BookingAction>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: BookingActionsMenu(actions: actions, onSelected: choisies.add),
          ),
        ),
      ));
      await tester.tap(find.byTooltip('خيارات الموعد'));
      await tester.pumpAndSettle();
      return choisies;
    }

    testWidgets('propose ما جاش et بطّل الموعد', (tester) async {
      final choisies = await monter(
          tester, [BookingAction.complete, BookingAction.noShow, BookingAction.cancel]);

      expect(find.text('ما جاش'), findsOneWidget);
      await tester.tap(find.text('بطّل الموعد'));
      await tester.pumpAndSettle();

      expect(choisies, [BookingAction.cancel]);
    });

    test('sans absent ni annulation, pas de menu', () {
      expect(BookingActionsMenu.hasItems([BookingAction.complete]), isFalse);
      expect(BookingActionsMenu.hasItems([BookingAction.cancel]), isTrue);
    });
  });

  group('Confirmation', () {
    Future<bool?> demander(WidgetTester tester, BookingAction action, String reponse) async {
      bool? resultat;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async => resultat = await confirmBookingAction(context, action),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(reponse));
      await tester.pumpAndSettle();
      return resultat;
    }

    testWidgets('« نعم » confirme', (tester) async {
      expect(await demander(tester, BookingAction.noShow, 'نعم'), isTrue);
    });

    testWidgets('« لا » ne fait rien', (tester) async {
      expect(await demander(tester, BookingAction.cancel, 'لا'), isFalse);
    });
  });
}
