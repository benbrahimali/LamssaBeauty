import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/notification_route.dart';
import 'package:lamssa/data/models.dart';

/// Destination d'une notification (§3.7).
///
/// Toucher une notification ne faisait que la marquer comme lue : rien ne
/// s'ouvrait. Pire, la même notification touchée dans le volet Android menait
/// quelque part. Ces tests fixent une règle unique pour les deux entrées.
void main() {
  group('Rendez-vous', () {
    const types = [
      'booking_confirmed',
      'booking_cancelled',
      'reminder_j1',
      'reminder_h2',
      'your_turn',
    ];

    test('le client va à ses réservations', () {
      for (final type in types) {
        expect(targetFor(type, AppRole.client), NotificationTarget.myBookings,
            reason: type);
      }
    });

    test('le professionnel va à son agenda', () {
      // Le même événement n'est pas le même objet des deux côtés : le client
      // pense « mon rendez-vous », le coiffeur pense « ma journée ».
      for (final type in types) {
        expect(targetFor(type, AppRole.coiffeur), NotificationTarget.agenda,
            reason: type);
        expect(targetFor(type, AppRole.owner), NotificationTarget.agenda,
            reason: type);
      }
    });
  });

  group('Caisse', () {
    test('tséb9a et clôture mènent à la caisse côté pro', () {
      for (final type in ['advance_requested', 'advance_decided', 'closure_ready']) {
        expect(targetFor(type, AppRole.owner), NotificationTarget.cash,
            reason: type);
        expect(targetFor(type, AppRole.coiffeur), NotificationTarget.cash,
            reason: type);
      }
    });

    test('un client n’est jamais envoyé vers une caisse', () {
      // Il n'en reçoit pas ; s'il en recevait une, l'y envoyer ne produirait
      // qu'un 403.
      for (final type in ['advance_requested', 'closure_ready']) {
        expect(targetFor(type, AppRole.client), NotificationTarget.none,
            reason: type);
      }
    });
  });

  group('Avis et publications', () {
    test('seul le gérant est envoyé vers la modération', () {
      expect(targetFor('new_review', AppRole.owner), NotificationTarget.reviews);
      expect(targetFor('new_review', AppRole.coiffeur), NotificationTarget.none);
      expect(targetFor('new_review', AppRole.client), NotificationTarget.none);
    });

    test('une nouvelle réalisation mène au fil', () {
      for (final role in AppRole.values) {
        expect(targetFor('new_portfolio', role), NotificationTarget.trending);
      }
    });
  });

  group('Robustesse', () {
    test('un type inconnu ne mène nulle part', () {
      // Un serveur plus récent peut inventer un type : mieux vaut ne rien
      // faire que d'envoyer l'utilisateur au hasard.
      for (final role in AppRole.values) {
        expect(targetFor('type_du_futur', role), NotificationTarget.none);
        expect(targetFor('', role), NotificationTarget.none);
      }
    });

    test('le chevron n’apparaît que si la carte mène quelque part', () {
      // Un indicateur qui ment est pire que pas d'indicateur.
      expect(isActionable('booking_confirmed', AppRole.client), isTrue);
      expect(isActionable('new_review', AppRole.client), isFalse);
      expect(isActionable('type_du_futur', AppRole.owner), isFalse);
    });
  });
}
