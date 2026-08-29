import '../data/models.dart';

/// Où mène une notification.
///
/// Séparé de la navigation elle-même pour être vérifiable : c'est une règle
/// métier — « une tséb9a mène à la caisse » — et pas une affaire de widgets.
enum NotificationTarget {
  /// Les rendez-vous du client.
  myBookings,

  /// L'agenda du coiffeur ou le tableau de bord du gérant.
  agenda,

  /// Caisse : tséb9a, clôture.
  cash,

  /// Modération des avis, réservée au gérant du salon.
  reviews,

  /// Fil des réalisations.
  trending,

  /// Rien de mieux à proposer : on reste sur la liste.
  none,
}

/// Destination d'une notification selon son type et le rôle actif.
///
/// Le même type mène à des endroits différents : un rappel de rendez-vous
/// renvoie le client à ses réservations, et le professionnel à son agenda —
/// ce n'est pas le même objet vu des deux côtés.
NotificationTarget targetFor(String type, AppRole role) {
  switch (type) {
    case 'booking_confirmed':
    case 'booking_cancelled':
    case 'reminder_j1':
    case 'reminder_h2':
    case 'your_turn':
      return role == AppRole.client
          ? NotificationTarget.myBookings
          : NotificationTarget.agenda;

    case 'advance_requested':
    case 'advance_decided':
    case 'closure_ready':
      // Un client ne reçoit jamais ces notifications ; s'il en recevait une
      // par erreur, l'envoyer vers une caisse qu'il ne peut pas lire ne
      // ferait qu'un 403.
      return role == AppRole.client
          ? NotificationTarget.none
          : NotificationTarget.cash;

    case 'new_review':
      // Le gérant modère ; le coiffeur et le client n'ont rien à décider.
      return role == AppRole.owner
          ? NotificationTarget.reviews
          : NotificationTarget.none;

    case 'new_portfolio':
      return NotificationTarget.trending;

    default:
      // Type inconnu — un serveur plus récent, par exemple. Mieux vaut ne
      // rien faire que d'envoyer l'utilisateur au hasard.
      return NotificationTarget.none;
  }
}

/// Vrai si toucher cette notification mène quelque part.
///
/// Sert à n'afficher le chevron que sur les cartes réellement actionnables :
/// un indicateur qui ment est pire que pas d'indicateur.
bool isActionable(String type, AppRole role) =>
    targetFor(type, role) != NotificationTarget.none;
