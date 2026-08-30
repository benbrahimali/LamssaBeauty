import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/api_exception.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/booking_controller.dart';

/// Choix du jour dans le tunnel de réservation (§3.3, §3.5).
///
/// Le calendrier proposait quatorze jours identiques : il fallait taper chacun
/// pour découvrir qu'il était vide. Le tunnel s'ouvrait de surcroît sur
/// aujourd'hui — souvent le jour de repos du coiffeur — et le client lisait
/// « complet » avant d'avoir rien choisi.
class _FauxSalonRepository extends SalonRepository {
  _FauxSalonRepository(this._jours, {this.echoue = false})
      : super(ApiClient(TokenStore()));

  /// Décalages (en jours à partir d'aujourd'hui) où le coiffeur travaille.
  final Set<int> _jours;
  final bool echoue;

  @override
  Future<List<DayAvailability>> availability({
    required String staffId,
    List<String> serviceIds = const [],
    int days = 14,
  }) async {
    if (echoue) throw const ApiException(503, 'serveur indisponible');
    final aujourdhui = DateTime.now();
    return List.generate(days, (i) {
      final d = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day + i);
      final ouvert = _jours.contains(i);
      return DayAvailability(
        isoDate: '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-'
            '${d.day.toString().padLeft(2, '0')}',
        available: ouvert,
        slotCount: ouvert ? 12 : 0,
        reason: ouvert ? null : DayUnavailability.dayOff,
      );
    });
  }

  @override
  Future<List<BookingSlot>> slots({
    required String staffId,
    required String isoDate,
    List<String> serviceIds = const [],
  }) async =>
      const [];
}

void main() {
  const service =
      ServiceItem(id: 's1', name: 'Coupe', price: 25, duration: 30);

  BookingController controleur(Set<int> joursOuverts, {bool echoue = false}) {
    return BookingController(
      _FauxSalonRepository(joursOuverts, echoue: echoue),
      BookingRepository(ApiClient(TokenStore())),
    );
  }

  /// Le tunnel ne charge la disponibilité qu'une fois coiffeur ET service
  /// choisis : la durée du service change ce qui rentre dans la journée.
  Future<BookingController> pret(Set<int> joursOuverts,
      {bool echoue = false}) async {
    final c = controleur(joursOuverts, echoue: echoue);
    await c.selectService(service);
    await c.selectStaff('staff1');
    return c;
  }

  group('Jours fermés', () {
    test('un jour de repos est signalé fermé', () async {
      final c = await pret({1, 2, 3});

      expect(c.isDayOpen(c.days[0]), isFalse);
      expect(c.availabilityFor(c.days[0])!.reason, DayUnavailability.dayOff);
      expect(c.isDayOpen(c.days[1]), isTrue);
    });

    test('le motif remonte pour que l’écran dise quoi faire', () async {
      final c = await pret({5});

      // « Complet » invite à revenir demain ; un repos invite à changer de
      // coiffeur. Confondre les deux fait tourner le client en rond.
      expect(c.availabilityFor(c.days[0])!.reason, DayUnavailability.dayOff);
      expect(c.availabilityFor(c.days[5])!.reason, isNull);
    });
  });

  group('Recalage automatique', () {
    test('le tunnel s’ouvre sur le premier jour travaillé', () async {
      final c = await pret({3, 4, 5});

      expect(c.dayIndex, 3,
          reason: 'aujourd’hui est un jour de repos : rester dessus '
              'afficherait « complet » avant tout choix');
    });

    test('un jour déjà ouvert n’est pas déplacé', () async {
      final c = await pret({0, 1, 2});

      expect(c.dayIndex, 0, reason: 'aucune raison de bouger la sélection');
    });

    test('aucun jour libre : la sélection ne bouge pas', () async {
      final c = await pret(const {});

      // Déplacer la sélection n'y changerait rien ; l'écran affiche le
      // message « ce coiffeur n'a aucun jour libre ».
      expect(c.dayIndex, 0);
      expect(c.days.every((d) => !c.isDayOpen(d)), isTrue);
    });
  });

  group('Dégradation', () {
    test('sans disponibilité chargée, le calendrier reste ouvert', () async {
      final c = controleur({1});

      // Griser sur une information qu'on n'a pas empêcherait de réserver.
      expect(c.isDayOpen(c.days[0]), isTrue);
      expect(c.availabilityFor(c.days[0]), isNull);
    });

    test('une panne serveur ne ferme pas le calendrier', () async {
      final c = await pret({1}, echoue: true);

      // L'utilisateur découvre au clic, comme avant : c'est un confort perdu,
      // pas une réservation perdue.
      expect(c.days.every(c.isDayOpen), isTrue);
      expect(c.dayIndex, 0);
    });
  });
}
