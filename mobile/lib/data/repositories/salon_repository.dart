import '../../core/api_client.dart';
import '../models.dart';

/// Recherche & découverte (§3.2).
class SalonRepository {
  SalonRepository(this._api);

  final ApiClient _api;

  Future<List<Salon>> search({
    double? lat,
    double? lng,
    SalonType? type,
    double maxKm = 10,
    bool openNow = false,
    double minRating = 0,
    String? query,
  }) async {
    final data = await _api.get('/salons', query: {
      if (lat != null && lng != null) 'near': '$lat,$lng',
      if (type != null) 'type': type.apiValue,
      'max_km': maxKm,
      if (openNow) 'open_now': true,
      if (minRating > 0) 'min_rating': minRating,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
    }) as List;

    return data
        .map((e) => Salon.fromCard(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<SalonDetail> detail(String salonId) =>
      _detailFrom('/salons/$salonId');

  /// Fiche salon depuis le code imprimé sur le QR ou saisi à la main.
  ///
  /// Le serveur normalise la casse, les espaces et les tirets : on lui envoie
  /// la saisie telle quelle plutôt que de dupliquer la règle ici.
  Future<SalonDetail> detailByCode(String code) =>
      _detailFrom('/salons/code/${Uri.encodeComponent(code.trim())}');

  Future<SalonDetail> _detailFrom(String path) async {
    final data = await _api.get(path) as Map<String, dynamic>;

    final services = ((data['services'] as List?) ?? const [])
        .map((e) => ServiceItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final raw = Map<String, dynamic>.from(data['salon'] as Map);
    final salon = Salon.fromDetail(
      raw,
      isOpenNow: data['is_open_now'] == true,
      workers: ((data['staff'] as List?) ?? const []).length,
      priceFrom: services.isEmpty
          ? null
          : services.map((s) => s.price).reduce((a, b) => a < b ? a : b),
    );
    final semaine = parseWeekHours(raw['hours']);
    final staff = ((data['staff'] as List?) ?? const [])
        .map((e) => Coiffeur.fromJson(
              Map<String, dynamic>.from(e as Map),
              salonName: salon.name,
            ))
        .toList();

    return SalonDetail(
        salon: salon, staff: staff, services: services, hours: semaine);
  }

  /// Profil public d'un coiffeur : identité, services, portfolio, avis (§3.2).
  Future<StaffProfile> staffProfile(String staffId) async {
    final data = await _api.get('/staff/$staffId') as Map<String, dynamic>;
    final raw = Map<String, dynamic>.from(data['staff'] as Map);

    return StaffProfile(
      coiffeur: Coiffeur.fromJson(
        {...raw, 'name': data['name']},
        salonName: data['salon']?['name']?.toString() ?? '',
      ),
      services: ((data['services'] as List?) ?? const [])
          .map((e) => ServiceItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      portfolio: ((data['portfolio'] as List?) ?? const [])
          .map((e) => PortfolioEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      reviews: ((data['reviews'] as List?) ?? const [])
          .map((e) => ReviewEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  /// Créneaux libres d'un coiffeur pour un jour donné.
  Future<List<BookingSlot>> slots({
    required String staffId,
    required String isoDate,
    List<String> serviceIds = const [],
  }) async {
    final data = await _api.get('/staff/$staffId/slots', query: {
      'date': isoDate,
      if (serviceIds.isNotEmpty) 'service_ids': serviceIds,
    }) as Map<String, dynamic>;

    return ((data['slots'] as List?) ?? const [])
        .map((e) => BookingSlot.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Disponibilité jour par jour, pour griser le calendrier avant que le
  /// client tape un jour au hasard.
  Future<List<DayAvailability>> availability({
    required String staffId,
    List<String> serviceIds = const [],
    int days = 14,
  }) async {
    final data = await _api.get('/staff/$staffId/availability', query: {
      'days': days,
      if (serviceIds.isNotEmpty) 'service_ids': serviceIds,
    }) as Map<String, dynamic>;

    return ((data['days'] as List?) ?? const [])
        .map((e) => DayAvailability.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

class SalonDetail {
  final Salon salon;
  final List<Coiffeur> staff;
  final List<ServiceItem> services;

  /// Semaine complète, un [DayHours] par clé de jour. Toujours les sept jours,
  /// même si le serveur n'en renvoie qu'une partie : l'éditeur du gérant doit
  /// pouvoir les proposer tous.
  final Map<String, DayHours> hours;

  const SalonDetail({
    required this.salon,
    this.staff = const [],
    this.services = const [],
    this.hours = const {},
  });
}

class StaffProfile {
  final Coiffeur coiffeur;
  final List<ServiceItem> services;
  final List<PortfolioEntry> portfolio;
  final List<ReviewEntry> reviews;

  const StaffProfile({
    required this.coiffeur,
    this.services = const [],
    this.portfolio = const [],
    this.reviews = const [],
  });
}

/// Une réalisation publiée par le coiffeur (fil « En vogue », §3.8).
class PortfolioEntry {
  final String id;
  final String imageUrl;
  final String caption;
  final List<String> tags;
  final int likes;

  const PortfolioEntry({
    required this.id,
    this.imageUrl = '',
    this.caption = '',
    this.tags = const [],
    this.likes = 0,
  });

  factory PortfolioEntry.fromJson(Map<String, dynamic> json) => PortfolioEntry(
        id: json['id']?.toString() ?? '',
        imageUrl: json['image_url']?.toString() ?? '',
        caption: json['caption']?.toString() ?? '',
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        likes: (json['likes'] as num?)?.toInt() ?? 0,
      );
}

class ReviewEntry {
  final String id;
  final int rating;
  final String comment;
  final String createdAt;

  const ReviewEntry({
    required this.id,
    this.rating = 5,
    this.comment = '',
    this.createdAt = '',
  });

  factory ReviewEntry.fromJson(Map<String, dynamic> json) => ReviewEntry(
        id: json['id']?.toString() ?? '',
        rating: (json['rating'] as num?)?.toInt() ?? 5,
        comment: json['comment']?.toString() ?? '',
        createdAt: relativeTime(json['created_at']?.toString()),
      );
}
