/// Erreur remontée par la couche réseau, déjà traduite pour l'utilisateur.
class ApiException implements Exception {
  final int statusCode;
  final String message;

  /// Créneaux de repli renvoyés par le backend sur un conflit de réservation (409).
  final List<String> alternatives;

  const ApiException(this.statusCode, this.message, {this.alternatives = const []});

  bool get isNetwork => statusCode == 0;
  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;

  factory ApiException.network() => const ApiException(
        0,
        'Connexion impossible. Vérifie ta connexion et que le serveur est démarré.',
      );

  factory ApiException.timeout() =>
      const ApiException(0, 'Le serveur met trop de temps à répondre.');

  /// Extrait le message d'un corps d'erreur FastAPI.
  ///
  /// `detail` peut être une chaîne, la liste d'erreurs de validation Pydantic,
  /// ou l'objet `{message, alternatives}` renvoyé sur conflit de créneau.
  factory ApiException.fromBody(int status, dynamic body) {
    if (body is Map && body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) return ApiException(status, detail);
      if (detail is Map) {
        return ApiException(
          status,
          (detail['message'] ?? 'Erreur').toString(),
          alternatives: (detail['alternatives'] as List?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
        );
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) {
          final field = (first['loc'] as List?)?.last?.toString() ?? '';
          final msg = first['msg']?.toString() ?? 'Valeur invalide';
          return ApiException(status, field.isEmpty ? msg : '$field : $msg');
        }
      }
    }
    return ApiException(status, _defaultFor(status));
  }

  static String _defaultFor(int status) {
    switch (status) {
      case 401:
        return 'Session expirée, reconnecte-toi.';
      case 403:
        return "Tu n'as pas les droits pour cette action.";
      case 404:
        return 'Introuvable.';
      case 409:
        return 'Conflit — cette action est déjà faite ou impossible.';
      case 429:
        return 'Trop de tentatives, patiente un instant.';
      default:
        return status >= 500 ? 'Erreur serveur. Réessaie.' : 'Erreur ($status).';
    }
  }

  @override
  String toString() => message;
}
