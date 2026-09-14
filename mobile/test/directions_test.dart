import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/directions.dart';

/// Itinéraire vers un salon : le lien ouvert dans Google Maps.
void main() {
  test('vise le salon par ses coordonnées', () {
    final uri = directionsUri(36.8065, 10.1815);

    expect(uri.scheme, 'https');
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/dir/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['destination'], '36.806500,10.181500');
  });

  test('le point décimal ne dépend pas de la langue du téléphone', () {
    // Une virgule décimale (« 36,8 ») se confondrait avec le séparateur
    // latitude,longitude et enverrait le client ailleurs.
    final destination = directionsUri(36.8, 10.1).queryParameters['destination']!;
    expect(destination.split(','), ['36.800000', '10.100000']);
  });

  test('les coordonnées négatives sont conservées', () {
    expect(directionsUri(-33.9, -18.4).queryParameters['destination'],
        '-33.900000,-18.400000');
  });

  test('un salon sans position n’a pas d’itinéraire', () {
    expect(hasCoordinates(0, 0), isFalse);
  });

  test('un salon placé en a un', () {
    expect(hasCoordinates(36.8065, 10.1815), isTrue);
  });
}
