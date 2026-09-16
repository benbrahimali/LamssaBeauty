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

/// Charge un coiffeur connu par son seul identifiant, **et son salon**.
///
/// Un rendez-vous se prend toujours dans un salon : horaires, services, prix
/// et caisse sont les siens. Sans le salon, le profil ouvert depuis un reel
/// n'offrait aucun bouton « احجز » — le client restait bloqué sur le portfolio.
///
/// Une erreur sur le coiffeur lui-même remonte : il n'y a rien à afficher.
/// Une erreur sur le salon non : le portfolio reste consultable.
Future<StaffForBooking> resolveStaffForBooking(
  SalonRepository repo,
  String staffId,
) async {
  final profil = await repo.staffProfile(staffId);
  final salonId = profil.coiffeur.salonId;
  if (salonId.isEmpty) return StaffForBooking(coiffeur: profil.coiffeur);

  try {
    final detail = await repo.detail(salonId);
    return StaffForBooking(coiffeur: profil.coiffeur, salon: detail.salon);
  } on ApiException {
    return StaffForBooking(coiffeur: profil.coiffeur);
  }
}
