import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';

/// Quel rendez-vous propose « صلّح الخلاص » dans la caisse (§3.4).
void main() {
  Booking rdv({
    BookingStatus status = BookingStatus.done,
    bool paid = true,
    String? paymentId,
  }) =>
      Booking(
        id: 'b1',
        clientName: 'Mehdi',
        service: 'Fade',
        coiffeur: 'Ahmed',
        coiffeurId: 'st1',
        salonId: 's1',
        date: '2026-09-15',
        time: '10:00',
        price: 25,
        status: status,
        paid: paid,
        paymentId: paymentId,
      );

  test('un encaissement en espèces ou par carte se corrige', () {
    expect(rdv().voidable, isTrue);
  });

  test('un paiement en ligne se rembourse, il ne s’annule pas', () {
    final enLigne = rdv(paymentId: 'pay1');
    expect(enLigne.voidable, isFalse);
    expect(enLigne.refundable, isTrue,
        reason: 'le geste proposé est le remboursement');
  });

  test('un rendez-vous pas encore encaissé n’a rien à corriger', () {
    expect(rdv(status: BookingStatus.inProgress, paid: false).voidable, isFalse);
    expect(rdv(status: BookingStatus.confirmed, paid: false).voidable, isFalse);
  });

  test('un rendez-vous terminé mais non payé non plus', () {
    expect(rdv(paid: false).voidable, isFalse);
  });

  test('un rendez-vous annulé ou manqué non plus', () {
    expect(rdv(status: BookingStatus.cancelled, paid: false).voidable, isFalse);
    expect(rdv(status: BookingStatus.noShow, paid: false).voidable, isFalse);
  });
}
