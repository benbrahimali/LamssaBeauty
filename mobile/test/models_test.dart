/// Désérialisation des modèles — sans réseau ni backend.
///
/// Les fixtures reproduisent les réponses réelles de l'API (vérifiées par
/// `test/api_integration_test.dart`), pour attraper en CI toute régression de
/// contrat sans avoir à démarrer MongoDB.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_exception.dart';
import 'package:lamssa/data/models.dart';

void main() {
  group('Salon', () {
    test('carte de recherche : distance et prix formatés', () {
      final salon = Salon.fromCard(const {
        'id': '6a6f',
        'name': 'Barbier El Menzah',
        'type': 'barbershop',
        'address': 'Rue du Lac',
        'city': 'Tunis',
        'lat': 36.8412,
        'lng': 10.1795,
        'photos': <String>[],
        'rating_avg': 4.75,
        'rating_count': 12,
        'status': 'open',
        'is_open_now': true,
        'distance_km': 2.345,
        'price_from': 10.0,
        'staff_count': 2,
      });

      expect(salon.type, SalonType.barbershop);
      expect(salon.distance, '2.3 km');
      expect(salon.price, 'à partir de 10 DT');
      expect(salon.address, 'Rue du Lac, Tunis');
      expect(salon.open, isTrue);
      expect(salon.workers, 2);
      expect(salon.initials, 'BE');
    });

    test('sans distance ni prix, les champs restent vides plutôt que faux', () {
      final salon = Salon.fromCard(const {
        'id': 'x', 'name': 'Salon', 'type': 'mixte', 'is_open_now': false,
      });
      expect(salon.distance, isEmpty);
      expect(salon.price, isEmpty);
      expect(salon.rating, 0);
    });

    test('détail : coordonnées GeoJSON lues dans le bon ordre', () {
      final salon = Salon.fromDetail(const {
        'id': 'x',
        'name': 'Studio Carthage',
        'type': 'mariees',
        'location': {'type': 'Point', 'coordinates': [10.3236, 36.8525]},
        'hours': {
          'mon': {'closed': true, 'open': '09:00', 'close': '19:00'},
          'tue': {'closed': false, 'open': '10:00', 'close': '20:00'},
        },
      });

      // MongoDB stocke [lng, lat] — l'inverser placerait tous les salons en mer.
      expect(salon.lng, 10.3236);
      expect(salon.lat, 36.8525);
      expect(salon.type, SalonType.mariage);
      expect(salon.hours, '10:00 – 20:00', reason: 'le lundi fermé est ignoré');
    });

    test('un salon fermé toute la semaine est signalé', () {
      final salon = Salon.fromDetail(const {
        'id': 'x', 'name': 'S', 'type': 'mixte',
        'hours': {'mon': {'closed': true}, 'sun': {'closed': true}},
      });
      expect(salon.hours, 'Fermé');
    });

    test('le type inconnu retombe sur mixte au lieu de planter', () {
      expect(SalonTypeExt.parse('inconnu'), SalonType.mixte);
      expect(SalonTypeExt.parse(null), SalonType.mixte);
      expect(SalonType.mariage.apiValue, 'mariees');
    });
  });

  group('Coiffeur', () {
    test('display_name prime, spécialités deviennent le rôle', () {
      final coiffeur = Coiffeur.fromJson(const {
        'id': 'c1',
        'salon_id': 's1',
        'display_name': 'Ahmed Trabelsi',
        'chair_number': 2,
        'commission_pct': 55.0,
        'service_ids': ['sv1', 'sv2'],
        'specialties': ['fade', 'barbe'],
        'available': true,
        'rating_avg': 4.8,
        'cuts_count': 120,
        'bio': 'Spécialiste maison.',
      }, salonName: 'Barbier El Menzah');

      expect(coiffeur.name, 'Ahmed Trabelsi');
      expect(coiffeur.initials, 'AT');
      expect(coiffeur.role, 'fade');
      expect(coiffeur.salon, 'Barbier El Menzah');
      expect(coiffeur.serviceIds, ['sv1', 'sv2']);
      expect(coiffeur.chairNumber, 2);
      expect(coiffeur.commissionPct, 55.0);
    });

    test('sans display_name ni spécialité, des valeurs de repli sensées', () {
      final coiffeur = Coiffeur.fromJson(const {'id': 'c2', 'display_name': ''});
      expect(coiffeur.name, 'Coiffeur');
      expect(coiffeur.role, 'Coiffeur');
      expect(coiffeur.available, isTrue);
    });
  });

  group('Booking', () {
    test('heure locale, prix et services concaténés', () {
      final booking = Booking.fromJson({
        'id': 'b1',
        'salon_id': 's1',
        'staff_id': 'c1',
        'client_name': 'Mehdi',
        'service_names': ['Brushing', 'Soin'],
        'price_total': 90.0,
        'status': 'CONFIRMED',
        'source': 'app',
        'start': DateTime(2026, 9, 15, 14, 30).toUtc().toIso8601String(),
      });

      expect(booking.service, 'Brushing + Soin');
      expect(booking.time, '14:30');
      expect(booking.date, '15/9');
      expect(booking.status, BookingStatus.confirmed);
      expect(booking.isActive, isTrue);
      expect(booking.isWalkIn, isFalse);
    });

    test('un walk-in sans nom affiche « Client »', () {
      final booking = Booking.fromJson(const {
        'id': 'b2', 'client_name': '  ', 'source': 'walkin', 'status': 'DONE',
      });
      expect(booking.clientName, 'Client');
      expect(booking.isWalkIn, isTrue);
      expect(booking.isActive, isFalse);
    });

    test('les statuts terminaux ne sont pas actifs', () {
      for (final raw in ['DONE', 'CANCELLED', 'NO_SHOW']) {
        final booking = Booking.fromJson({'id': 'b', 'status': raw});
        expect(booking.isActive, isFalse, reason: raw);
      }
    });
  });

  group('Caisse', () {
    const payload = {
      'day': '2026-08-02',
      'transaction_count': 4,
      'total': 72.0,
      'salon_total': 34.4,
      'staff_total': 37.6,
      'tips_total': 5.0,
      'expenses_total': 4.0,
      'net_salon': 30.4,
      'advances_pending': 8.0,
      'advances_pending_count': 1,
      'by_method': {'cash': 37.0, 'card': 25.0, 'online': 10.0},
      'by_staff': {
        'st1': {'name': 'Ahmed', 'chair': 1, 'count': 2, 'gross': 40.0,
                'staff_share': 20.0, 'salon_share': 20.0, 'tips': 3.0},
        'st2': {'name': 'Youssef', 'count': 2, 'gross': 32.0,
                'staff_share': 17.6, 'salon_share': 14.4, 'tips': 2.0},
      },
      'closed': false,
    };

    test('les totaux et la ventilation sont lus intégralement', () {
      final day = DayCash.fromJson(payload);

      expect(day.total, 72.0);
      expect(day.cash, 37.0);
      expect(day.card, 25.0);
      expect(day.online, 10.0);
      expect(day.workers, hasLength(2));
      expect(day.closed, isFalse);
    });

    test('part salon + part équipe reconstituent le total', () {
      final day = DayCash.fromJson(payload);
      expect(day.salonTotal + day.staffTotal, closeTo(day.total, 0.01));
    });

    test('chaque employé garde son nom et sa chaise', () {
      final day = DayCash.fromJson(payload);
      final ahmed = day.workers.firstWhere((w) => w.name == 'Ahmed');
      expect(ahmed.cuts, 2);
      expect(ahmed.share, 20.0);
      expect(ahmed.tip, 3.0);
      expect(ahmed.chair, 1);
      expect(ahmed.initials, 'AH');

      final youssef = day.workers.firstWhere((w) => w.name == 'Youssef');
      expect(youssef.chair, isNull, reason: 'chaise absente = null, pas 0');
    });

    test('une journée vide ne casse rien', () {
      final day = DayCash.fromJson(const {});
      expect(day.total, 0);
      expect(day.workers, isEmpty);
      expect(day.byMethod, isEmpty);
    });

    test('la caisse personnelle expose le net à percevoir', () {
      final mine = MyCash.fromJson(const {
        'count': 3, 'gross': 60.0, 'my_share': 33.0, 'tips': 5.0,
        'payout': 38.0, 'advances_outstanding': 8.0, 'advances_pending': 0.0,
      });
      expect(mine.payout, 38.0);
      expect(mine.advancesOutstanding, 8.0);
    });
  });

  group('Créneaux et jours', () {
    test('la grille des 14 prochains jours commence aujourd’hui', () {
      final days = DaySlot.next(14);
      final today = DateTime.now();

      expect(days, hasLength(14));
      expect(days.first.date.day, today.day);
      expect(days.first.isoDate, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect(days.last.date.difference(days.first.date).inDays, 13);
    });

    test('le format ISO est zéro-paddé — l’API refuse 2026-9-5', () {
      final slot = DaySlot.fromDate(DateTime(2026, 9, 5));
      expect(slot.isoDate, '2026-09-05');
      expect(slot.dayNum, '5');
      expect(slot.dayShort, 'Sam');
    });

    test('un créneau porte l’heure affichable et l’instant exact', () {
      final slot = BookingSlot.fromJson(const {
        'time': '14:30', 'start': '2026-09-15T13:30:00+00:00',
      });
      expect(slot.time, '14:30');
      expect(DateTime.tryParse(slot.start), isNotNull);
    });
  });

  group('Notifications', () {
    test('titre et corps sont fusionnés, l’icône dérive du type', () {
      final notif = AppNotification.fromJson({
        'id': 'n1',
        'type': 'advance_decided',
        'title': 'Tséb9a approuvée',
        'body': '8 DT',
        'read': false,
        'created_at':
            DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
      });

      expect(notif.message, 'Tséb9a approuvée — 8 DT');
      expect(notif.icon, '💸');
      expect(notif.read, isFalse);
      expect(notif.time, 'il y a 5 min');
    });

    test('un type inconnu garde une icône neutre', () {
      final notif = AppNotification.fromJson(const {'id': 'n', 'type': 'zzz'});
      expect(notif.icon, '🔔');
    });
  });

  group('Utilitaires', () {
    test('les initiales gèrent un mot seul, plusieurs mots, ou rien', () {
      expect(initialsOf('Rania Gharbi'), 'RG');
      expect(initialsOf('Rania'), 'RA');
      expect(initialsOf('   '), '?');
    });

    test('le temps relatif se lit en français', () {
      final now = DateTime.now();
      expect(relativeTime(now.toIso8601String()), "à l'instant");
      expect(relativeTime(now.subtract(const Duration(hours: 3)).toIso8601String()),
          'il y a 3 h');
      expect(relativeTime(now.subtract(const Duration(days: 1)).toIso8601String()),
          'hier');
      expect(relativeTime(null), isEmpty);
      expect(relativeTime('pas une date'), isEmpty);
    });

    test('les couleurs dérivées sont stables pour un même identifiant', () {
      expect(TypePalette.forId('abc'), TypePalette.forId('abc'));
      expect(TypePalette.surface(SalonType.barbershop),
          isNot(TypePalette.surface(SalonType.femme)));
    });
  });

  group('ApiException', () {
    test('un détail texte de FastAPI est repris tel quel', () {
      final error = ApiException.fromBody(409, {'detail': 'Créneau déjà réservé'});
      expect(error.message, 'Créneau déjà réservé');
      expect(error.isConflict, isTrue);
    });

    test('un conflit de créneau expose les alternatives', () {
      final error = ApiException.fromBody(409, {
        'detail': {
          'message': 'Créneau indisponible',
          'alternatives': ['2026-09-15T09:00:00Z', '2026-09-15T09:15:00Z'],
        }
      });
      expect(error.message, 'Créneau indisponible');
      expect(error.alternatives, hasLength(2));
    });

    test('une erreur de validation Pydantic devient lisible', () {
      final error = ApiException.fromBody(422, {
        'detail': [
          {'loc': ['body', 'phone'], 'msg': 'Numéro de téléphone invalide'}
        ]
      });
      expect(error.message, 'phone : Numéro de téléphone invalide');
    });

    test('un corps inattendu retombe sur un message générique', () {
      expect(ApiException.fromBody(401, null).isUnauthorized, isTrue);
      expect(ApiException.fromBody(500, 'boom').message, contains('serveur'));
      expect(ApiException.network().isNetwork, isTrue);
    });
  });
}
