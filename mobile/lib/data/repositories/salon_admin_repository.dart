import '../../core/api_client.dart';
import '../models.dart';

/// Administration d'un salon par son gérant (§3.1 onboarding, §3.5 équipe).
///
/// Toutes ces routes sont réservées au propriétaire du salon : le backend
/// vérifie `salon.owner_id` et renvoie 403 sinon.
class SalonAdminRepository {
  SalonAdminRepository(this._api);

  final ApiClient _api;

  /// Crée le salon et **promeut l'utilisateur au rôle OWNER** côté serveur.
  /// Il faut donc recharger le contexte de session juste après.
  Future<Salon> createSalon({
    required String name,
    required SalonType type,
    required double lat,
    required double lng,
    String address = '',
    String city = '',
    String phone = '',
    String description = '',
    double defaultSplitPct = 50,
    int cancellationWindowH = 2,
  }) async {
    final data = await _api.post('/salons', body: {
      'name': name,
      'type': type.apiValue,
      'lat': lat,
      'lng': lng,
      'address': address,
      'city': city,
      'phone': phone,
      'description': description,
      'default_split_pct': defaultSplitPct,
      'cancellation_window_h': cancellationWindowH,
    }) as Map<String, dynamic>;
    return Salon.fromDetail(data);
  }

  Future<Salon> updateSalon(
    String salonId, {
    String? name,
    String? address,
    String? city,
    String? phone,
    String? description,
    double? defaultSplitPct,
    int? cancellationWindowH,
    /// `false` bascule le salon en « fermé » (congés, §2.4).
    bool? open,
  }) async {
    final data = await _api.patch('/salons/$salonId', body: {
      if (name != null) 'name': name,
      if (address != null) 'address': address,
      if (city != null) 'city': city,
      if (phone != null) 'phone': phone,
      if (description != null) 'description': description,
      if (defaultSplitPct != null) 'default_split_pct': defaultSplitPct,
      if (cancellationWindowH != null)
        'cancellation_window_h': cancellationWindowH,
      if (open != null) 'status': open ? 'open' : 'closed',
    }) as Map<String, dynamic>;
    return Salon.fromDetail(data);
  }

  // ── Catalogue de services ──────────────────────────────────────────────
  Future<List<ServiceItem>> services(String salonId,
      {bool includeInactive = false}) async {
    final data = await _api.get('/salons/$salonId/services', query: {
      if (includeInactive) 'include_inactive': true,
    }) as List;
    return data
        .map((e) => ServiceItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<ServiceItem> createService(
    String salonId, {
    required String name,
    required double price,
    required int durationMin,
    String nameAr = '',
    int bufferMin = 10,
    String description = '',
  }) async {
    final data = await _api.post('/salons/$salonId/services', body: {
      'name': name,
      'name_ar': nameAr,
      'price': price,
      'duration_min': durationMin,
      'buffer_min': bufferMin,
      'description': description,
    }) as Map<String, dynamic>;
    return ServiceItem.fromJson(data);
  }

  Future<ServiceItem> updateService(
    String salonId,
    String serviceId, {
    String? name,
    String? nameAr,
    double? price,
    int? durationMin,
    int? bufferMin,
    bool? active,
  }) async {
    final data = await _api.patch('/salons/$salonId/services/$serviceId', body: {
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (price != null) 'price': price,
      if (durationMin != null) 'duration_min': durationMin,
      if (bufferMin != null) 'buffer_min': bufferMin,
      if (active != null) 'active': active,
    }) as Map<String, dynamic>;
    return ServiceItem.fromJson(data);
  }

  /// Désactivation logique côté serveur : les RDV passés restent lisibles.
  Future<void> deleteService(String salonId, String serviceId) =>
      _api.delete('/salons/$salonId/services/$serviceId');

  // ── Équipe ─────────────────────────────────────────────────────────────
  Future<List<Coiffeur>> staff(String salonId) async {
    final data = await _api.get('/salons/$salonId/staff') as List;
    return data
        .map((e) => Coiffeur.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Rattache un coiffeur par numéro : le compte est créé s'il n'existe pas.
  Future<Coiffeur> addStaff(
    String salonId, {
    required String phone,
    required String displayName,
    int chairNumber = 1,
    double commissionPct = 50,
    List<String> serviceIds = const [],
    List<String> specialties = const [],
    String bio = '',
  }) async {
    final data = await _api.post('/salons/$salonId/staff', body: {
      'phone': phone,
      'display_name': displayName,
      'chair_number': chairNumber,
      'commission_type': 'percent',
      'commission_pct': commissionPct,
      'service_ids': serviceIds,
      'specialties': specialties,
      'bio': bio,
    }) as Map<String, dynamic>;
    return Coiffeur.fromJson(data);
  }

  Future<Coiffeur> updateStaff(
    String salonId,
    String staffId, {
    String? displayName,
    int? chairNumber,
    double? commissionPct,
    List<String>? serviceIds,
    bool? available,
  }) async {
    final data = await _api.patch('/salons/$salonId/staff/$staffId', body: {
      if (displayName != null) 'display_name': displayName,
      if (chairNumber != null) 'chair_number': chairNumber,
      if (commissionPct != null) 'commission_pct': commissionPct,
      if (serviceIds != null) 'service_ids': serviceIds,
      if (available != null) 'available': available,
    }) as Map<String, dynamic>;
    return Coiffeur.fromJson(data);
  }

  /// Refusé en 409 par le serveur tant que le coiffeur a des RDV à venir.
  Future<void> removeStaff(String salonId, String staffId) =>
      _api.delete('/salons/$salonId/staff/$staffId');

  /// Code public et liens de partage du salon (QR vitrine, WhatsApp).
  ///
  /// Le serveur attribue le code au passage si le salon n'en avait pas encore.
  Future<SalonShare> share(String salonId) async {
    final data =
        await _api.get('/salons/$salonId/share') as Map<String, dynamic>;
    return SalonShare.fromJson(data);
  }
}

/// Ce que le gérant imprime en vitrine ou envoie à ses clients.
class SalonShare {
  const SalonShare({
    required this.code,
    required this.url,
    required this.deepLink,
    required this.shareText,
  });

  /// Court et lisible : un client qui n'arrive pas à scanner peut le taper.
  final String code;

  /// Encodé dans le QR — une URL https reste ouvrable par n'importe quel
  /// appareil photo, là où un schéma applicatif ne mène nulle part sans l'app.
  final String url;
  final String deepLink;
  final String shareText;

  /// `BARBIE GV28` — plus facile à relire à voix haute qu'un bloc de 10 signes.
  String get spaced =>
      code.length > 4 ? '${code.substring(0, code.length - 4)} ${code.substring(code.length - 4)}' : code;

  factory SalonShare.fromJson(Map<String, dynamic> json) => SalonShare(
        code: json['code']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        deepLink: json['deep_link']?.toString() ?? '',
        shareText: json['share_text']?.toString() ?? '',
      );
}
