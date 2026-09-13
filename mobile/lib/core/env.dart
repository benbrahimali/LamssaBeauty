import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Configuration d'exécution.
///
/// Surchargeable au lancement sans toucher au code :
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000`
class Env {
  const Env._();

  static const String _override =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// L'API hébergée, que vise toute version publiée de l'app.
  static const String productionUrl = 'https://lamssabeauty.onrender.com';

  /// URL de l'API.
  static String get apiBaseUrl => resolveApiBaseUrl(
        override: _override,
        isRelease: kReleaseMode,
        isWeb: kIsWeb,
        // `Platform` n'existe pas sur le web : on ne l'interroge qu'ailleurs.
        isAndroid: !kIsWeb && Platform.isAndroid,
      );

  /// Choix de l'adresse, isolé pour être testable.
  ///
  /// Une version publiée vise la production par défaut. Elle visait
  /// l'adresse de développement : un APK construit sans `--dart-define`
  /// cherchait l'API sur 10.0.2.2 — l'émulateur — et ne joignait rien sur un
  /// vrai téléphone. `--dart-define=API_BASE_URL` garde la priorité, pour
  /// pointer une version de test vers un autre serveur.
  ///
  /// En développement, sur émulateur Android, `localhost` désigne l'émulateur
  /// lui-même : la machine hôte est joignable via 10.0.2.2.
  @visibleForTesting
  static String resolveApiBaseUrl({
    required String override,
    required bool isRelease,
    required bool isWeb,
    required bool isAndroid,
  }) {
    if (override.isNotEmpty) return override;
    if (isRelease) return productionUrl;
    if (isWeb) return 'http://localhost:8000';
    if (isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }

  static const String apiPrefix = '/api/v1';

  /// Résout l'URL d'un média servi par l'API.
  ///
  /// En dev les images sont enregistrées sur disque et renvoyées en chemin
  /// relatif (`/media/…`) ; avec S3 configuré, le backend renvoie une URL
  /// absolue. L'app doit gérer les deux sans savoir laquelle est active.
  static String mediaUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '$apiBaseUrl$url';
  }

  /// Délai d'attente d'une requête.
  ///
  /// L'hébergement gratuit endort le serveur après un quart d'heure sans
  /// visite, et le réveil prend près d'une minute. À 20 secondes, la première
  /// requête après chaque pause échouait à coup sûr : l'app affichait une
  /// erreur alors que le serveur était simplement en train de démarrer.
  /// Un réseau réellement coupé échoue bien plus tôt, sur une erreur de
  /// connexion et non sur ce délai.
  static const Duration requestTimeout = Duration(seconds: 60);

  /// En dev le backend accepte ce code pour tout numéro (`OTP_DEV_CODE`).
  static const bool showDevOtpHint = !kReleaseMode;
}
