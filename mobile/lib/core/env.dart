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

  /// URL de l'API. Sur émulateur Android, `localhost` désigne l'émulateur
  /// lui-même : la machine hôte est joignable via 10.0.2.2.
  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (kIsWeb) return 'http://localhost:8000';
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
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

  static const Duration requestTimeout = Duration(seconds: 20);

  /// En dev le backend accepte ce code pour tout numéro (`OTP_DEV_CODE`).
  static const bool showDevOtpHint = !kReleaseMode;
}
