import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/env.dart';

/// Adresse de l'API selon la version de l'app.
///
/// Un APK de release construit sans `--dart-define` visait 10.0.2.2 — l'adresse
/// de l'émulateur — et ne joignait aucun serveur sur un vrai téléphone.
void main() {
  String adresse({
    String override = '',
    bool release = false,
    bool web = false,
    bool android = false,
  }) =>
      Env.resolveApiBaseUrl(
        override: override,
        isRelease: release,
        isWeb: web,
        isAndroid: android,
      );

  group('Version publiée', () {
    test('vise la production par défaut', () {
      expect(adresse(release: true, android: true), Env.productionUrl);
    });

    test('vise la production sur toutes les plateformes', () {
      for (final web in [true, false]) {
        for (final android in [true, false]) {
          expect(adresse(release: true, web: web, android: android),
              Env.productionUrl);
        }
      }
    });

    test('ne vise jamais une adresse de développement', () {
      final url = adresse(release: true, android: true);
      expect(url, isNot(contains('10.0.2.2')));
      expect(url, isNot(contains('localhost')));
    });

    test('la production est en HTTPS', () {
      // Android refuse le trafic en clair hors débogage : une adresse http
      // échouerait en silence sur les téléphones des clients.
      expect(Env.productionUrl, startsWith('https://'));
    });

    test('une adresse forcée au build garde la priorité', () {
      // Pour pointer une version de test vers un autre serveur.
      expect(
        adresse(override: 'https://staging.example.com', release: true),
        'https://staging.example.com',
      );
    });
  });

  group('Développement', () {
    test('l’émulateur Android joint la machine hôte par 10.0.2.2', () {
      expect(adresse(android: true), 'http://10.0.2.2:8000');
    });

    test('le web et le bureau visent localhost', () {
      expect(adresse(web: true), 'http://localhost:8000');
      expect(adresse(), 'http://localhost:8000');
    });

    test('une adresse forcée remplace le défaut', () {
      // Le cas du téléphone réel branché sur le Wi-Fi du PC.
      expect(adresse(override: 'http://192.168.1.17:8000', android: true),
          'http://192.168.1.17:8000');
    });
  });

  test('le délai d’attente couvre le réveil du serveur gratuit', () {
    // Render endort le service après 15 minutes et met près d'une minute à le
    // réveiller : en dessous, la première requête après une pause échoue.
    expect(Env.requestTimeout.inSeconds, greaterThanOrEqualTo(55));
  });
}
