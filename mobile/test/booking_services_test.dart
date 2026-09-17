import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/booking_controller.dart';

/// Réserver une ou plusieurs prestations (§3.3) : coupe + barbe, brushing + soin.
class _FauxSalons extends SalonRepository {
  _FauxSalons() : super(ApiClient(TokenStore()));

  final prestationsDemandees = <List<String>>[];

  @override
  Future<List<DayAvailability>> availability({
    required String staffId,
    List<String> serviceIds = const [],
    int days = 14,
  }) async =>
      const [];

  @override
  Future<List<BookingSlot>> slots({
    required String staffId,
    required String isoDate,
    List<String> serviceIds = const [],
  }) async {
    prestationsDemandees.add(List.of(serviceIds));
    return const [BookingSlot(time: '10:00', start: '2026-09-20T09:00:00Z')];
  }
}

class _FausseReservation extends BookingRepository {
  _FausseReservation() : super(ApiClient(TokenStore()));

  List<String>? prestationsReservees;

  @override
  Future<Booking> create({
    required String salonId,
    String? staffId,
    required List<String> serviceIds,
    required String startIso,
    String note = '',
    bool payOnline = false,
  }) async {
    prestationsReservees = serviceIds;
    return const Booking(id: 'b1');
  }
}

void main() {
  const coupe = ServiceItem(id: 'coupe', name: 'Coupe', price: 25, duration: 30);
  const barbe = ServiceItem(id: 'barbe', name: 'Barbe', price: 10, duration: 15);

  late _FauxSalons salons;
  late _FausseReservation reservations;
  late BookingController tunnel;

  setUp(() async {
    salons = _FauxSalons();
    reservations = _FausseReservation();
    tunnel = BookingController(salons, reservations)
      ..start(salonId: 's1', staffId: 'st1');
  });

  test('deux prestations s’additionnent en prix et en durée', () async {
    await tunnel.toggleService(coupe);
    await tunnel.toggleService(barbe);

    expect(tunnel.selectedServices.map((s) => s.id), ['coupe', 'barbe']);
    expect(tunnel.totalPrice, 35);
    expect(tunnel.totalDuration, 45);
  });

  test('les créneaux sont calculés pour l’ensemble des prestations', () async {
    await tunnel.toggleService(coupe);
    await tunnel.toggleService(barbe);

    expect(salons.prestationsDemandees.last, ['coupe', 'barbe'],
        reason: 'une grille calculée pour la coupe seule ne laisserait pas le temps de la barbe');
  });

  test('retoucher une prestation la retire', () async {
    await tunnel.toggleService(coupe);
    await tunnel.toggleService(barbe);
    await tunnel.toggleService(coupe);

    expect(tunnel.selectedServices.map((s) => s.id), ['barbe']);
    expect(tunnel.totalPrice, 10);
  });

  test('changer de prestation oublie le créneau choisi', () async {
    await tunnel.toggleService(coupe);
    tunnel.selectSlot(tunnel.slots.first);
    expect(tunnel.canBook, isTrue);

    await tunnel.toggleService(barbe);

    expect(tunnel.slot, isNull, reason: 'la durée a changé, le créneau peut ne plus tenir');
    expect(tunnel.canBook, isFalse);
  });

  test('sans prestation, rien ne se réserve', () async {
    await tunnel.toggleService(coupe);
    await tunnel.toggleService(coupe);

    expect(tunnel.hasServices, isFalse);
    expect(tunnel.canBook, isFalse);
  });

  test('la réservation envoie toutes les prestations choisies', () async {
    await tunnel.toggleService(coupe);
    await tunnel.toggleService(barbe);
    tunnel.selectSlot(tunnel.slots.first);

    final rdv = await tunnel.confirm();

    expect(rdv?.id, 'b1');
    expect(reservations.prestationsReservees, ['coupe', 'barbe']);
  });

  test('un nouveau tunnel repart sans prestation', () async {
    await tunnel.toggleService(coupe);

    tunnel.start(salonId: 's2', staffId: 'st2');

    expect(tunnel.selectedServices, isEmpty);
  });

  group('Avis du client', () {
    test('un rendez-vous déjà noté le dit', () {
      expect(Booking.fromJson(const {'id': 'b1', 'reviewed': true}).reviewed, isTrue);
    });

    test('sans l’information, il reste notable', () {
      expect(Booking.fromJson(const {'id': 'b1'}).reviewed, isFalse);
    });
  });
}
