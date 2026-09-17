import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/api_exception.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/cash_controller.dart';

/// Caisse du gérant : les chiffres suivent les actions (§3.4).
class _FausseCaisse extends CashRepository {
  _FausseCaisse() : super(ApiClient(TokenStore()));

  /// Retient chaque lecture jusqu'à ce que le test la libère.
  bool bloquer = true;
  int lectures = 0;
  double recette = 15;
  final attentes = <Completer<void>>[];

  @override
  Future<DayCash> today(String salonId) async {
    lectures++;
    final valeur = recette;
    if (bloquer) {
      final c = Completer<void>();
      attentes.add(c);
      await c.future;
    }
    // La valeur lue au moment où le serveur répond.
    return DayCash(total: bloquer ? recette : valeur);
  }

  @override
  Future<List<Advance>> salonAdvances(String salonId, {String? status}) async => const [];

  @override
  Future<List<ClosureResult>> closures(String salonId, {int limit = 14}) async => const [];
}

class _FauxRdv extends BookingRepository {
  _FauxRdv() : super(ApiClient(TokenStore()));

  bool refuserEncaissement = false;
  int crees = 0;
  List<String> prestations = const [];
  final encaissements = <(String, String)>[];

  @override
  Future<SalonAgenda> agenda({
    required String salonId,
    String? isoDate,
    Map<String, String> staffNames = const {},
  }) async =>
      const SalonAgenda();

  @override
  Future<Booking> createWalkIn({
    required String salonId,
    required String staffId,
    required List<String> serviceIds,
    required String startIso,
    required String clientName,
    String clientPhone = '',
  }) async {
    crees++;
    prestations = serviceIds;
    return const Booking(id: 'w1');
  }

  @override
  Future<CompletedService> complete({
    required String bookingId,
    String method = 'cash',
    double tip = 0,
    double? amountOverride,
    List<String>? serviceIds,
  }) async {
    if (refuserEncaissement) throw const ApiException(409, 'Journée clôturée');
    encaissements.add((bookingId, method));
    return const CompletedService(
      booking: Booking(id: 'w1'),
      amount: 25,
      salonShare: 12.5,
      staffShare: 12.5,
      tip: 0,
      staffPayout: 12.5,
    );
  }
}

class _FauxSalons extends SalonRepository {
  _FauxSalons() : super(ApiClient(TokenStore()));

  @override
  Future<SalonDetail> detail(String salonId) async => const SalonDetail(
        salon: Salon(id: 's1', name: 'Barbier', type: SalonType.barbershop),
        services: [ServiceItem(id: 'coupe', name: 'Coupe', price: 25, duration: 30)],
        staff: [Coiffeur(id: 'st1', name: 'Ahmed', salonId: 's1')],
      );
}

void main() {
  group('Rechargement', () {
    test('une demande pendant un chargement n’est pas perdue', () async {
      final caisse = _FausseCaisse();
      final c = CashController(caisse, _FauxRdv(), _FauxSalons())..attach('s1');

      final premier = c.load();
      await pumpEventQueue();
      expect(caisse.lectures, 1);

      // Un encaissement arrive pendant le rafraîchissement, puis l'action
      // redemande les chiffres.
      caisse.recette = 40;
      final second = c.load();

      caisse.attentes[0].complete();
      await pumpEventQueue();
      expect(caisse.lectures, 2, reason: 'le second passage relit la caisse');

      caisse.attentes[1].complete();
      await second;
      await premier;
      expect(c.day.total, 40, reason: 'l’écran montre l’état d’après l’action');
    });

    test('sans appel concurrent, une seule lecture', () async {
      final caisse = _FausseCaisse()..bloquer = false;
      final c = CashController(caisse, _FauxRdv(), _FauxSalons())..attach('s1');

      await c.load();

      expect(caisse.lectures, 1);
      expect(c.day.total, 15);
    });

    test('après un premier chargement terminé, le suivant relit', () async {
      final caisse = _FausseCaisse()..bloquer = false;
      final c = CashController(caisse, _FauxRdv(), _FauxSalons())..attach('s1');

      await c.load();
      caisse.recette = 60;
      await c.load();

      expect(caisse.lectures, 2);
      expect(c.day.total, 60);
    });
  });

  group('Walk-in', () {
    Future<(CashController, _FauxRdv)> pret() async {
      final rdv = _FauxRdv();
      final c = CashController(_FausseCaisse()..bloquer = false, rdv, _FauxSalons())
        ..attach('s1');
      return (c, rdv);
    }

    test('« خلّص توّا » encaisse le client dans la foulée', () async {
      final (c, rdv) = await pret();

      final erreur = await c.addWalkIn(
          staffId: 'st1', serviceIds: ['coupe'], clientName: 'Mehdi', payNow: true, method: 'card');

      expect(erreur, isNull);
      expect(rdv.encaissements, [('w1', 'card')]);
    });

    test('un walk-in peut porter plusieurs prestations', () async {
      final (c, rdv) = await pret();

      await c.addWalkIn(
          staffId: 'st1', serviceIds: ['coupe', 'barbe'], clientName: 'Mehdi', payNow: true);

      expect(rdv.prestations, ['coupe', 'barbe']);
      expect(rdv.encaissements, [('w1', 'cash')], reason: 'encaissé en une fois');
    });

    test('sans « خلّص توّا », le rendez-vous attend son encaissement', () async {
      final (c, rdv) = await pret();

      await c.addWalkIn(staffId: 'st1', serviceIds: ['coupe'], clientName: 'Mehdi');

      expect(rdv.crees, 1);
      expect(rdv.encaissements, isEmpty);
    });

    test('un encaissement refusé est signalé, sans recréer le rendez-vous', () async {
      final (c, rdv) = await pret();
      rdv.refuserEncaissement = true;

      final erreur = await c.addWalkIn(
          staffId: 'st1', serviceIds: ['coupe'], clientName: 'Mehdi', payNow: true);

      expect(erreur, contains('تزاد'), reason: 'il existe : ne pas le ressaisir');
      expect(rdv.crees, 1);
    });
  });
}
