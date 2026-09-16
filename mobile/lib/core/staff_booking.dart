import '../data/models.dart';
import '../data/repositories/salon_repository.dart';
import 'api_exception.dart';

/// Un coiffeur ouvert depuis un reel ou le fil « En vogue », avec le salon où
/// le réserver.
class StaffForBooking {
  const StaffForBooking({required this.coiffeur, this.salon});

  final Coiffeur coiffeur;

  /// Null quand le salon n'a pas pu être chargé — pas encore validé, réseau…
  /// Le profil s'affiche quand même, mais sans bouton de réservation.
  final Salon? salon;
}

/// Le salon où réserver un coiffeur déjà chargé — carte « حجامين ترند »,
/// par exemple. Null si le salon est inconnu ou indisponible.
///
/// Un rendez-vous se prend toujours dans un salon : horaires, services, prix
/// et caisse sont les siens. Sans lui, le profil n'offre aucun bouton « احجز ».
Future<Salon?> resolveSalonOf(SalonRepository repo, Coiffeur coiffeur) async {
  if (coiffeur.salonId.isEmpty) return null;
  try {
    return (await repo.detail(coiffeur.salonId)).salon;
  } on ApiException {
    // Le portfolio reste consultable : seule la réservation est impossible.
    return null;
  }
}

/// Charge un coiffeur connu par son seul identifiant, **et son salon**.
///
/// Une erreur sur le coiffeur lui-même remonte : il n'y a rien à afficher.
/// Une erreur sur le salon non : le portfolio reste consultable.
Future<StaffForBooking> resolveStaffForBooking(
  SalonRepository repo,
  String staffId,
) async {
  final profil = await repo.staffProfile(staffId);
  return StaffForBooking(
    coiffeur: profil.coiffeur,
    salon: await resolveSalonOf(repo, profil.coiffeur),
  );
}
