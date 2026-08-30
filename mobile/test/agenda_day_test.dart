import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/cash_controller.dart';

/// Navigation entre les jours de l'agenda (§3.3, §3.5).
///
/// Coiffeur et gérant étaient enfermés sur aujourd'hui : un RDV pris pour
/// demain arrivait en notification, puis restait introuvable dans l'app
/// jusqu'au jour même. Le client, lui, avait déjà sa confirmation.
class _FauxBookingRepository extends BookingRepository {
  _FauxBookingRepository() : super(ApiClient(TokenStore()));

  /// Dates demandées au serveur, dans l'ordre. `null` = « aujourd'hui ».
  final List<String?> demandes = [];

  @override
  Future<List<Booking>> myAgenda({String? isoDate}) async {
    demandes.add(isoDate);
    return const [];
  }

  @override
  Future<SalonAgenda> agenda({
    required String salonId,
    String? isoDate,
    Map<String, String> staffNames = const {},
  }) async {
    demandes.add(isoDate);
    return const SalonAgenda();
  }
}

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

void main() {
  group('Agenda du coiffeur', () {
    late _FauxBookingRepository bookings;
    late MyCashController controleur;

    setUp(() {
      bookings = _FauxBookingRepository();
      controleur = MyCashController(
        CashRepository(ApiClient(TokenStore())),
        bookings,
        SalonRepository(ApiClient(TokenStore())),
      );
    });

    test('démarre sur aujourd’hui', () {
      expect(controleur.isToday, isTrue);
    });

    test('demain est consultable', () async {
      await controleur.shiftAgenda(1);

      expect(controleur.isToday, isFalse);
      expect(
        bookings.demandes.last,
        _iso(DateTime.now().add(const Duration(days: 1))),
        reason: 'sans date explicite, le serveur renverrait encore aujourd’hui',
      );
    });

    test('hier aussi : on a besoin de retrouver ce qu’on a fait', () async {
      await controleur.shiftAgenda(-1);

      expect(bookings.demandes.last,
          _iso(DateTime.now().subtract(const Duration(days: 1))));
    });

    test('aujourd’hui n’envoie aucune date', () async {
      await controleur.loadAgenda();

      // Laisser le serveur décider du « jour » évite de lui imposer le fuseau
      // du téléphone, qui peut être faux.
      expect(bookings.demandes.last, isNull);
    });

    test('le retour à aujourd’hui remet la sélection à zéro', () async {
      await controleur.shiftAgenda(3);
      expect(controleur.isToday, isFalse);

      await controleur.resetAgendaToToday();

      expect(controleur.isToday, isTrue);
      expect(bookings.demandes.last, isNull);
    });

    test('déjà sur aujourd’hui, le retour ne relance rien', () async {
      await controleur.resetAgendaToToday();

      // Un rechargement inutile fait clignoter la liste pour rien.
      expect(bookings.demandes, isEmpty);
    });

    test('les déplacements se cumulent', () async {
      await controleur.shiftAgenda(1);
      await controleur.shiftAgenda(1);

      expect(bookings.demandes.last,
          _iso(DateTime.now().add(const Duration(days: 2))));
    });
  });

  group('Agenda du gérant', () {
    late _FauxBookingRepository bookings;
    late CashController controleur;

    setUp(() {
      bookings = _FauxBookingRepository();
      controleur = CashController(
        CashRepository(ApiClient(TokenStore())),
        bookings,
        SalonRepository(ApiClient(TokenStore())),
      );
      controleur.attach('salon1');
    });

    test('démarre sur aujourd’hui', () {
      expect(controleur.isAgendaToday, isTrue);
    });

    test('demain est consultable', () async {
      await controleur.shiftAgenda(1);

      expect(controleur.isAgendaToday, isFalse);
      expect(bookings.demandes.last,
          _iso(DateTime.now().add(const Duration(days: 1))));
    });

    test('le retour à aujourd’hui remet la sélection à zéro', () async {
      await controleur.shiftAgenda(2);
      await controleur.resetAgendaToToday();

      expect(controleur.isAgendaToday, isTrue);
      expect(bookings.demandes.last, isNull);
    });

    test('sans salon rattaché, rien n’est demandé', () async {
      final orphelin = CashController(
        CashRepository(ApiClient(TokenStore())),
        bookings,
        SalonRepository(ApiClient(TokenStore())),
      );

      await orphelin.loadAgenda();

      expect(bookings.demandes, isEmpty);
    });
  });
}
