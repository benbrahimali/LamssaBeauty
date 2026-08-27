import 'dart:io';
import 'dart:typed_data';

import '../../core/api_client.dart';

/// Style DNA (§2.4, §8.5) — le selfie est analysé côté serveur.
///
/// L'analyse ne tourne pas dans l'app : la clé du modèle vision resterait
/// extractible depuis l'APK. L'image part vers le backend, qui ne la conserve pas.
class StyleDnaRepository {
  StyleDnaRepository(this._api);

  final ApiClient _api;

  /// L'analyse vision dépasse largement le timeout HTTP par défaut.
  static const _analysisTimeout = Duration(seconds: 90);

  /// La génération d'image est plus lente encore que l'analyse.
  static const _imageTimeout = Duration(seconds: 120);

  /// Vrai si le serveur a une clé configurée — sinon l'app masque la fonctionnalité.
  Future<bool> isAvailable() async => (await status()).analysis;

  /// Les deux fournisseurs sont indépendants : l'analyse peut marcher sans la
  /// génération d'images, et l'app ne doit proposer que ce qui existe.
  Future<StyleDnaStatus> status() async {
    try {
      final data = await _api.get('/style-dna/status') as Map<String, dynamic>;
      return StyleDnaStatus(
        analysis: data['available'] == true,
        images: data['images_available'] == true,
      );
    } catch (_) {
      return const StyleDnaStatus(analysis: false, images: false);
    }
  }

  /// Illustration de référence d'une coupe, sur un visage générique.
  ///
  /// Aucune donnée personnelle n'est envoyée : c'est le rendu que l'on peut
  /// montrer sans rien demander au client.
  Future<String> preview({
    required String style,
    String gender = 'male',
    String details = '',
  }) async {
    final data = await _api.postForm(
      '/style-dna/preview',
      fields: {'style': style, 'gender': gender, 'details': details},
      timeout: _imageTimeout,
    ) as Map<String, dynamic>;
    return data['url']?.toString() ?? '';
  }

  /// Applique la coupe sur le selfie du client.
  ///
  /// [consent] doit traduire un accord explicite : la photo part chez un
  /// fournisseur externe, c'est une donnée biométrique. Le serveur refuse en
  /// 403 sans cet accord, et ne conserve ni la photo ni le rendu.
  Future<Uint8List> tryOn({
    required File selfie,
    required String style,
    required bool consent,
    String details = '',
  }) async =>
      _api.postMultipartBytes(
        '/style-dna/tryon',
        field: 'file',
        bytes: await selfie.readAsBytes(),
        filename: 'selfie.jpg',
        contentType: _contentTypeOf(selfie.path),
        fields: {
          'style': style,
          'details': details,
          'consent': consent.toString(),
        },
        timeout: _imageTimeout,
      );

  /// Avec [lat]/[lng], le serveur relie chaque coupe aux coiffeurs qui savent
  /// la faire autour du client. Sans position, l'analyse reste un conseil.
  Future<StyleDnaResult> analyze(
    File selfie, {
    String hint = '',
    double? lat,
    double? lng,
  }) async {
    final bytes = await selfie.readAsBytes();
    final data = await _api.postMultipart(
      '/style-dna/analyze',
      field: 'file',
      bytes: bytes,
      filename: 'selfie.jpg',
      contentType: _contentTypeOf(selfie.path),
      fields: {
        if (hint.trim().isNotEmpty) 'hint': hint.trim(),
        if (lat != null && lng != null) 'lat': '$lat',
        if (lat != null && lng != null) 'lng': '$lng',
      },
      timeout: _analysisTimeout,
    ) as Map<String, dynamic>;
    return StyleDnaResult.fromJson(data);
  }

  /// `image_picker` conserve l'extension d'origine ; le backend n'accepte que
  /// JPEG, PNG et WebP.
  ///
  /// Un type inconnu n'est pas déguisé en JPEG : le fichier part en
  /// `application/octet-stream` et le serveur le refuse en 415, plutôt que de
  /// facturer un appel au modèle sur un fichier qui n'est pas une image.
  static String _contentTypeOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}

/// Ce que le serveur sait faire — chaque fournisseur est optionnel.
class StyleDnaStatus {
  final bool analysis;
  final bool images;
  const StyleDnaStatus({required this.analysis, required this.images});
}

class StyleSuggestion {
  final String name;
  final String nameAr;
  final String descriptionAr;
  final int matchScore;
  final List<String> tags;
  final bool recommended;

  const StyleSuggestion({
    required this.name,
    this.nameAr = '',
    this.descriptionAr = '',
    this.matchScore = 0,
    this.tags = const [],
    this.recommended = false,
  });

  factory StyleSuggestion.fromJson(Map<String, dynamic> json) => StyleSuggestion(
        name: json['name']?.toString() ?? '',
        nameAr: json['name_ar']?.toString() ?? '',
        descriptionAr: json['description_ar']?.toString() ?? '',
        matchScore: (json['match_score'] as num?)?.toInt() ?? 0,
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        recommended: json['recommended'] == true,
      );
}

/// Un endroit concret où obtenir la coupe conseillée (§2.4).
///
/// Ces données ne viennent pas du modèle mais du catalogue en base : le coiffeur
/// et le prix affichés existent réellement et sont réservables.
class StyleMatch {
  final String staffId;
  final String staffName;
  final String salonId;
  final String salonName;
  final String serviceId;
  final String serviceName;
  final String serviceNameAr;
  final double price;
  final int durationMin;
  final double ratingAvg;
  final double? distanceKm;

  /// Ce qui a motivé la proposition — « fade », « Skin fade »…
  final List<String> matchedOn;

  const StyleMatch({
    required this.staffId,
    required this.salonId,
    required this.serviceId,
    this.staffName = '',
    this.salonName = '',
    this.serviceName = '',
    this.serviceNameAr = '',
    this.price = 0,
    this.durationMin = 0,
    this.ratingAvg = 0,
    this.distanceKm,
    this.matchedOn = const [],
  });

  String get label => serviceNameAr.trim().isNotEmpty ? serviceNameAr : serviceName;

  factory StyleMatch.fromJson(Map<String, dynamic> json) => StyleMatch(
        staffId: json['staff_id']?.toString() ?? '',
        staffName: json['staff_name']?.toString() ?? '',
        salonId: json['salon_id']?.toString() ?? '',
        salonName: json['salon_name']?.toString() ?? '',
        serviceId: json['service_id']?.toString() ?? '',
        serviceName: json['service_name']?.toString() ?? '',
        serviceNameAr: json['service_name_ar']?.toString() ?? '',
        price: (json['price'] as num?)?.toDouble() ?? 0,
        durationMin: (json['duration_min'] as num?)?.toInt() ?? 0,
        ratingAvg: (json['rating_avg'] as num?)?.toDouble() ?? 0,
        distanceKm: (json['distance_km'] as num?)?.toDouble(),
        matchedOn: ((json['matched_on'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class StyleDnaResult {
  /// False quand l'image ne montre pas un visage exploitable — l'app doit alors
  /// demander une autre photo plutôt qu'afficher un résultat inventé.
  final bool faceDetected;
  final String faceShape;
  final String shapeLabelAr;
  final double confidence;
  final String analysisAr;
  final List<StyleSuggestion> styles;
  final List<String> avoidAr;
  final String model;

  /// Offres réelles par nom de coupe. Vide si le client n'a pas partagé sa
  /// position — le serveur préfère ne rien proposer qu'orienter à l'aveugle.
  final Map<String, List<StyleMatch>> matches;

  const StyleDnaResult({
    this.faceDetected = false,
    this.faceShape = '',
    this.shapeLabelAr = '',
    this.confidence = 0,
    this.analysisAr = '',
    this.styles = const [],
    this.avoidAr = const [],
    this.model = '',
    this.matches = const {},
  });

  List<StyleMatch> matchesFor(StyleSuggestion style) => matches[style.name] ?? const [];

  int get confidencePct => (confidence * 100).round().clamp(0, 100);

  factory StyleDnaResult.fromJson(Map<String, dynamic> json) => StyleDnaResult(
        faceDetected: json['face_detected'] == true,
        faceShape: json['face_shape']?.toString() ?? '',
        shapeLabelAr: json['shape_label_ar']?.toString() ?? '',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        analysisAr: json['analysis_ar']?.toString() ?? '',
        styles: (json['styles'] as List?)
                ?.map((e) => StyleSuggestion.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            const [],
        avoidAr:
            (json['avoid_ar'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        model: json['model']?.toString() ?? '',
        matches: ((json['matches'] as Map?) ?? const {}).map(
          (key, value) => MapEntry(
            key.toString(),
            ((value as List?) ?? const [])
                .map((e) => StyleMatch.fromJson(Map<String, dynamic>.from(e as Map)))
                .toList(),
          ),
        ),
      );
}
