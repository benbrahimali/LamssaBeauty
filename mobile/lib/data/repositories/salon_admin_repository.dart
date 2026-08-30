import 'dart:io';

import '../../core/api_client.dart';
import '../models.dart';
import 'portfolio_repository.dart';

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
    /// Objectif de chiffre d'affaires mensuel. 0 retire l'objectif.
    double? monthlyRevenueTarget,
    /// Part du pourboire revenant à l'employé. 100 = tout pour lui.
    double? tipStaffPct,
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
      if (monthlyRevenueTarget != null)
        'monthly_revenue_target': monthlyRevenueTarget,
      if (tipStaffPct != null) 'tip_staff_pct': tipStaffPct,
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
    /// Null = le taux du coiffeur s'applique.
    double? commissionPct,
    double productCost = 0,
  }) async {
    final data = await _api.post('/salons/$salonId/services', body: {
      'name': name,
      'name_ar': nameAr,
      'price': price,
      'duration_min': durationMin,
      'buffer_min': bufferMin,
      'description': description,
      if (commissionPct != null) 'commission_pct': commissionPct,
      'product_cost': productCost,
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
    double? commissionPct,
    double? productCost,
  }) async {
    final data = await _api.patch('/salons/$salonId/services/$serviceId', body: {
      if (name != null) 'name': name,
      if (nameAr != null) 'name_ar': nameAr,
      if (price != null) 'price': price,
      if (durationMin != null) 'duration_min': durationMin,
      if (bufferMin != null) 'buffer_min': bufferMin,
      if (active != null) 'active': active,
      if (commissionPct != null) 'commission_pct': commissionPct,
      if (productCost != null) 'product_cost': productCost,
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
    List<String> daysOff = const [],
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
      'days_off': daysOff,
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
    List<String>? daysOff,
    bool? available,
  }) async {
    final data = await _api.patch('/salons/$salonId/staff/$staffId', body: {
      if (displayName != null) 'display_name': displayName,
      if (chairNumber != null) 'chair_number': chairNumber,
      if (commissionPct != null) 'commission_pct': commissionPct,
      if (serviceIds != null) 'service_ids': serviceIds,
      if (daysOff != null) 'days_off': daysOff,
      if (available != null) 'available': available,
    }) as Map<String, dynamic>;
    return Coiffeur.fromJson(data);
  }

  /// Refusé en 409 par le serveur tant que le coiffeur a des RDV à venir.
  Future<void> removeStaff(String salonId, String staffId) =>
      _api.delete('/salons/$salonId/staff/$staffId');

  /// Avis du salon, masqués compris — réservé au gérant.
  Future<List<SalonReview>> reviews(String salonId) async {
    final data = await _api.get('/reviews/salon/$salonId',
        query: {'include_hidden': true, 'limit': 50}) as List;
    return data
        .map((e) => SalonReview.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Masque ou republie un avis (§3.8).
  ///
  /// Masquer recalcule la note du salon côté serveur : un avis injurieux ne
  /// doit pas continuer à peser sur la moyenne une fois retiré.
  Future<void> moderateReview(String reviewId, {required bool hide}) =>
      _api.patch('/reviews/$reviewId/moderate', query: {'hide': hide});

  /// Rembourse un paiement encaissé (§3.6).
  ///
  /// Le mouvement d'argent réel se fait chez le PSP ; l'API trace l'état pour
  /// que la caisse et le RDV restent cohérents.
  Future<void> refund(String paymentId) =>
      _api.post('/payments/$paymentId/refund');

  /// Classement interne de l'équipe (§3.5) — coupes puis note.
  ///
  /// Réservé au gérant : un classement public exposerait les coiffeurs les
  /// moins bien notés aux yeux des clients.
  Future<List<RankedStaff>> ranking(String salonId) async {
    final data = await _api.get('/salons/$salonId/ranking') as List;
    return data
        .map((e) => RankedStaff.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Congés à venir de l'équipe (§3.5). Bloquent automatiquement les créneaux.
  Future<List<TimeOff>> timeOff(String salonId) async {
    final data = await _api.get('/salons/$salonId/timeoff') as List;
    return data
        .map((e) => TimeOff.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Pose un congé et renvoie le nombre de RDV déjà pris sur la période.
  ///
  /// Ce compte n'est pas décoratif : sans lui, un gérant bloque une semaine
  /// sans voir qu'il vient de poser des lapins à ses clients.
  Future<({TimeOff timeOff, int toReschedule})> addTimeOff({
    required String salonId,
    required String staffId,
    required DateTime start,
    required DateTime end,
    String reason = '',
  }) async {
    final data = await _api.post('/salons/$salonId/timeoff', body: {
      'staff_id': staffId,
      // Le serveur raisonne en UTC ; l'app saisit en heure locale.
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
      'reason': reason,
    }) as Map<String, dynamic>;
    return (
      timeOff: TimeOff.fromJson(Map<String, dynamic>.from(data['time_off'] as Map)),
      toReschedule: (data['bookings_to_reschedule'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> removeTimeOff(String salonId, String offId) =>
      _api.delete('/salons/$salonId/timeoff/$offId');

  /// Ajoute une photo à la vitrine du salon. Renvoie la liste à jour.
  ///
  /// Le serveur refuse au-delà de 10 photos : une fiche plus longue ne se fait
  /// plus défiler.
  Future<List<String>> addPhoto(String salonId, File image) async {
    final data = await _api.postMultipart(
      '/salons/$salonId/photos',
      field: 'file',
      bytes: await image.readAsBytes(),
      filename: image.path.split(RegExp(r'[/\\]')).last,
      contentType: PortfolioRepository.contentTypeOf(image.path),
      timeout: const Duration(seconds: 60),
    ) as Map<String, dynamic>;
    return ((data['photos'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  /// La photo est désignée par son URL, pas par sa position : deux
  /// suppressions concurrentes effaceraient la mauvaise.
  Future<List<String>> removePhoto(String salonId, String url) async {
    final data = await _api.delete('/salons/$salonId/photos', query: {'url': url})
        as Map<String, dynamic>;
    return ((data['photos'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  /// Code public et liens de partage du salon (QR vitrine, WhatsApp).
  ///
  /// Le serveur attribue le code au passage si le salon n'en avait pas encore.
  Future<SalonShare> share(String salonId) async {
    final data =
        await _api.get('/salons/$salonId/share') as Map<String, dynamic>;
    return SalonShare.fromJson(data);
  }
}

/// Un avis client, tel que le gérant le voit — y compris masqué.
class SalonReview {
  const SalonReview({
    required this.id,
    this.rating = 5,
    this.comment = '',
    this.hidden = false,
    this.createdAt,
  });

  final String id;
  final int rating;
  final String comment;
  final bool hidden;
  final DateTime? createdAt;

  SalonReview copyWith({bool? hidden}) => SalonReview(
        id: id,
        rating: rating,
        comment: comment,
        hidden: hidden ?? this.hidden,
        createdAt: createdAt,
      );

  factory SalonReview.fromJson(Map<String, dynamic> json) => SalonReview(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 5,
        comment: json['comment']?.toString() ?? '',
        hidden: json['status']?.toString() == 'hidden',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal(),
      );
}

/// Une ligne du classement interne de l'équipe.
class RankedStaff {
  const RankedStaff({
    required this.rank,
    required this.staffId,
    required this.name,
    this.chair = 1,
    this.cuts = 0,
    this.rating = 0,
  });

  final int rank;
  final String staffId;
  final String name;
  final int chair;
  final int cuts;
  final double rating;

  /// Podium : au-delà, un numéro suffit.
  String get medal => switch (rank) {
        1 => '🥇',
        2 => '🥈',
        3 => '🥉',
        _ => '$rank',
      };

  factory RankedStaff.fromJson(Map<String, dynamic> json) => RankedStaff(
        rank: (json['rank'] as num?)?.toInt() ?? 0,
        staffId: json['staff_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        chair: (json['chair'] as num?)?.toInt() ?? 1,
        cuts: (json['cuts'] as num?)?.toInt() ?? 0,
        rating: (json['rating'] as num?)?.toDouble() ?? 0,
      );
}

/// Une absence de coiffeur : ses créneaux disparaissent automatiquement.
class TimeOff {
  const TimeOff({
    required this.id,
    required this.staffId,
    required this.start,
    required this.end,
    this.reason = '',
  });

  final String id;
  final String staffId;
  final DateTime start;
  final DateTime end;
  final String reason;

  /// Affiché en heure locale : le serveur stocke en UTC.
  String get range {
    String day(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
    final from = start.toLocal();
    final to = end.toLocal();
    return day(from) == day(to) ? day(from) : '${day(from)} → ${day(to)}';
  }

  factory TimeOff.fromJson(Map<String, dynamic> json) => TimeOff(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        staffId: json['staff_id']?.toString() ?? '',
        start: DateTime.tryParse(json['start']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        end: DateTime.tryParse(json['end']?.toString() ?? '')?.toUtc() ??
            DateTime.now().toUtc(),
        reason: json['reason']?.toString() ?? '',
      );
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
