import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lamssa/core/location.dart';

/// Qualité de la position rendue à l'appelant (§3.1, §3.2).
///
/// Un point de GPS met parfois plus de quinze secondes à venir en intérieur —
/// et c'est justement là que se tient un gérant qui crée son salon. L'app se
/// rabattait alors en silence sur la dernière position connue de l'appareil,
/// qui peut dater d'hier et d'un autre quartier. Suffisant pour trier des
/// salons par distance ; pas pour figer l'adresse d'un salon, que personne ne
/// pourrait vérifier sur des coordonnées brutes.
void main() {
  Position point({double lat = 36.8, double lng = 10.18}) => Position(
        latitude: lat,
        longitude: lng,
        timestamp: DateTime.now(),
        accuracy: 10,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

  test('une mesure fraîche n’est pas signalée approximative', () {
    final r = ResolvedPosition(point());

    expect(r.approximate, isFalse,
        reason: 'c’est le cas normal : rien à signaler à l’utilisateur');
  });

  test('le repli sur le dernier point connu est signalé', () {
    final r = ResolvedPosition(point(), approximate: true);

    // Sans ce drapeau, la création de salon ne pouvait pas distinguer un
    // point mesuré maintenant d'un point périmé.
    expect(r.approximate, isTrue);
  });

  test('la position reste accessible dans les deux cas', () {
    for (final approximatif in [false, true]) {
      final r = ResolvedPosition(point(lat: 35.5, lng: 11.0),
          approximate: approximatif);

      expect(r.position.latitude, 35.5);
      expect(r.position.longitude, 11.0);
    }
  });

  test('le drapeau ne modifie pas les coordonnées', () {
    final brut = point(lat: 36.8065, lng: 10.1815);
    final r = ResolvedPosition(brut, approximate: true);

    // Un point approximatif reste utilisable tel quel : on le signale, on ne
    // le corrige pas.
    expect(r.position.latitude, brut.latitude);
    expect(r.position.longitude, brut.longitude);
  });
}
