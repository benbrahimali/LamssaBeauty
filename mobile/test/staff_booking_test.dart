import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/api_exception.dart';
import 'package:lamssa/core/staff_booking.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';

/// Réserver un coiffeur découvert dans un reel (§3.8).
///
/// Le profil ouvert depuis un reel n'avait aucun bouton « احجز » : le salon du
/// coiffeur n'était jamais chargé, et un rendez-vous se prend dans un salon.
class _FauxDepot extends SalonRepository {
  _FauxDepot({this.salonId = 's1', this.salonDisponible = true, this.coiffeurExiste = true})
      : super(ApiClient(TokenStore()));

  final String salonId;
  final bool salonDisponible;
  final bool coiffeurExiste;
  final salonsDemandes = <String>[];

  @override
  Future<StaffProfile> staffProfile(String staffId) async {
    if (!coiffeurExiste) throw const ApiException(404, 'Coiffeur introuvable');
    return StaffProfile(
      coiffeur: Coiffeur(id: staffId, name: 'Ahmed', salonId: salonId),
    );
  }

  @override
  Future<SalonDetail> detail(String salonId) async {
    salonsDemandes.add(salonId);
    // Salon pas encore validé : le serveur répond 404 au public.
    if (!salonDisponible) throw const ApiException(404, 'Salon introuvable');
    return SalonDetail(
      salon: Salon(id: salonId, name: 'Barbier El Menzah', type: SalonType.barbershop),
    );
  }
}

void main() {
  test('le coiffeur arrive avec son salon : la réservation est possible', () async {
    final depot = _FauxDepot();

    final cible = await resolveStaffForBooking(depot, 'st1');

    expect(cible.coiffeur.id, 'st1');
    expect(cible.salon?.id, 's1',
        reason: 'sans le salon, le bouton « احجز » ne s’affiche pas');
    expect(depot.salonsDemandes, ['s1'], reason: 'le salon du coiffeur, pas un autre');
  });

  test('un salon indisponible laisse le portfolio consultable', () async {
    final cible =
        await resolveStaffForBooking(_FauxDepot(salonDisponible: false), 'st1');

    expect(cible.coiffeur.name, 'Ahmed');
    expect(cible.salon, isNull, reason: 'pas de bouton qui mènerait nulle part');
  });

  test('un coiffeur sans salon connu ne déclenche aucune requête inutile', () async {
    final depot = _FauxDepot(salonId: '');

    final cible = await resolveStaffForBooking(depot, 'st1');

    expect(cible.salon, isNull);
    expect(depot.salonsDemandes, isEmpty);
  });

  group('Coiffeur de « حجامين ترند »', () {
    const ahmed = Coiffeur(id: 'st1', name: 'Ahmed', salonId: 's1');

    test('son salon est retrouvé pour pouvoir le réserver', () async {
      final depot = _FauxDepot();

      final salon = await resolveSalonOf(depot, ahmed);

      expect(salon?.id, 's1');
      expect(depot.salonsDemandes, ['s1']);
    });

    test('un salon indisponible ne bloque pas le profil', () async {
      expect(await resolveSalonOf(_FauxDepot(salonDisponible: false), ahmed), isNull);
    });

    test('sans salon connu, aucune requête', () async {
      final depot = _FauxDepot();

      final salon = await resolveSalonOf(
          depot, const Coiffeur(id: 'st1', name: 'Ahmed'));

      expect(salon, isNull);
      expect(depot.salonsDemandes, isEmpty);
    });
  });

  test('un coiffeur introuvable remonte l’erreur : il n’y a rien à montrer', () async {
    expect(
      () => resolveStaffForBooking(_FauxDepot(coiffeurExiste: false), 'st1'),
      throwsA(isA<ApiException>()),
    );
  });
}
