// ─────────────────────────────────────────────────────────────────────────────
// LAMSSA — Modèles de données
//
// Ces classes sont alimentées par l'API (`fromJson`) et consommées telles quelles
// par les écrans. Les identifiants sont des chaînes : MongoDB émet des ObjectId.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum SalonType { barbershop, femme, mixte, mariage }

extension SalonTypeExt on SalonType {
  String get label {
    switch (this) {
      case SalonType.barbershop: return 'Barbershop 💈';
      case SalonType.femme:      return 'Salon Femme 💅';
      case SalonType.mixte:      return 'Mixte ✨';
      case SalonType.mariage:    return 'Mariées 👰';
    }
  }
  String get emoji {
    switch (this) {
      case SalonType.barbershop: return '💈';
      case SalonType.femme:      return '💅';
      case SalonType.mixte:      return '✨';
      case SalonType.mariage:    return '👰';
    }
  }

  /// Valeur attendue par l'API (`barbershop | femme | mixte | mariees`).
  String get apiValue => this == SalonType.mariage ? 'mariees' : name;

  static SalonType parse(String? raw) {
    switch (raw) {
      case 'barbershop': return SalonType.barbershop;
      case 'femme':      return SalonType.femme;
      case 'mariees':    return SalonType.mariage;
      default:           return SalonType.mixte;
    }
  }
}

/// Couleurs dérivées du type de salon — l'API ne transporte pas de thème.
class TypePalette {
  const TypePalette._();

  static const _surfaces = {
    SalonType.barbershop: Color(0xFF1A1A2E),
    SalonType.femme:      Color(0xFF1A0A1E),
    SalonType.mixte:      Color(0xFF0A1E1A),
    SalonType.mariage:    Color(0xFF1E1A0A),
  };
  static const _accents = {
    SalonType.barbershop: Color(0xFFC9A84C),
    SalonType.femme:      Color(0xFFE8A0BF),
    SalonType.mixte:      Color(0xFF84CFC9),
    SalonType.mariage:    Color(0xFFF4D03F),
  };

  static Color surface(SalonType type) => _surfaces[type]!;
  static Color accent(SalonType type) => _accents[type]!;

  /// Couleur stable pour une personne, dérivée de son identifiant.
  static Color forId(String id) {
    const palette = [
      Color(0xFFC9A84C), Color(0xFFE8A0BF), Color(0xFF84CFC9),
      Color(0xFFF4D03F), Color(0xFF9B8AFB), Color(0xFF6FCF97),
    ];
    if (id.isEmpty) return palette.first;
    return palette[id.hashCode.abs() % palette.length];
  }
}

/// Deux premières lettres significatives d'un nom, pour les avatars.
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final letters = parts.first.characters.take(2).toString();
    return letters.toUpperCase();
  }
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

double _toDouble(dynamic value, [double fallback = 0]) =>
    value is num ? value.toDouble() : fallback;

int _toInt(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : fallback;

// ─────────────────────────────────────────────────────────────────────────────
// Salon
// ─────────────────────────────────────────────────────────────────────────────
class Salon {
  final String id;
  final String name;
  final SalonType type;
  final double rating;
  final int reviews;
  final String distance;
  final String address;
  final String price;
  final bool open;
  final int workers;
  final String phone;
  final String hours;
  final double lat;
  final double lng;
  final List<String> photos;

  const Salon({
    required this.id,
    required this.name,
    required this.type,
    this.rating = 0,
    this.reviews = 0,
    this.distance = '',
    this.address = '',
    this.price = '',
    this.open = true,
    this.workers = 0,
    this.phone = '',
    this.hours = '',
    this.lat = 0,
    this.lng = 0,
    this.photos = const [],
  });

  String get initials => initialsOf(name);
  Color get color => TypePalette.surface(type);
  Color get accent => TypePalette.accent(type);

  /// Depuis `GET /salons` (carte de résultat de recherche).
  factory Salon.fromCard(Map<String, dynamic> json) {
    final km = json['distance_km'];
    final from = json['price_from'];
    return Salon(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: SalonTypeExt.parse(json['type']?.toString()),
      rating: _toDouble(json['rating_avg']),
      reviews: _toInt(json['rating_count']),
      distance: km is num ? '${km.toStringAsFixed(1)} km' : '',
      address: [json['address'], json['city']]
          .where((v) => v != null && v.toString().isNotEmpty)
          .join(', '),
      price: from is num ? 'à partir de ${from.toStringAsFixed(0)} DT' : '',
      open: json['is_open_now'] == true,
      workers: _toInt(json['staff_count']),
      lat: _toDouble(json['lat']),
      lng: _toDouble(json['lng']),
      photos: (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  /// Depuis `GET /salons/{id}` (objet salon complet).
  factory Salon.fromDetail(
    Map<String, dynamic> json, {
    bool? isOpenNow,
    int workers = 0,
    double? priceFrom,
  }) {
    final coords = (json['location']?['coordinates'] as List?) ?? const [0, 0];
    return Salon(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      type: SalonTypeExt.parse(json['type']?.toString()),
      rating: _toDouble(json['rating_avg']),
      reviews: _toInt(json['rating_count']),
      address: [json['address'], json['city']]
          .where((v) => v != null && v.toString().isNotEmpty)
          .join(', '),
      price: priceFrom == null ? '' : 'à partir de ${priceFrom.toStringAsFixed(0)} DT',
      open: isOpenNow ?? json['status'] == 'open',
      workers: workers,
      phone: json['phone']?.toString() ?? '',
      hours: _formatHours(json['hours']),
      lng: _toDouble(coords.isNotEmpty ? coords[0] : 0),
      lat: _toDouble(coords.length > 1 ? coords[1] : 0),
      photos: (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }

  /// Résume les horaires hebdomadaires en une plage lisible.
  static String _formatHours(dynamic hours) {
    if (hours is! Map) return '';
    for (final day in const ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']) {
      final entry = hours[day];
      if (entry is Map && entry['closed'] != true) {
        return '${entry['open']} – ${entry['close']}';
      }
    }
    return 'Fermé';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Coiffeur (StaffMember côté API)
// ─────────────────────────────────────────────────────────────────────────────
class Coiffeur {
  final String id;
  final String name;
  final String role;
  final String salon;
  final String salonId;
  final double rating;
  final int cuts;
  final List<String> serviceIds;
  final bool available;
  final List<String> trending;
  final String bio;
  final String experience;
  final int chairNumber;
  final double commissionPct;

  /// Jours de repos hebdomadaires ('mon'..'sun'). Le salon peut ouvrir 6j/7
  /// pendant qu'un coiffeur se repose le lundi.
  final List<String> daysOff;

  const Coiffeur({
    required this.id,
    required this.name,
    this.role = '',
    this.salon = '',
    this.salonId = '',
    this.rating = 0,
    this.cuts = 0,
    this.serviceIds = const [],
    this.available = true,
    this.trending = const [],
    this.bio = '',
    this.experience = '',
    this.chairNumber = 1,
    this.commissionPct = 50,
    this.daysOff = const [],
  });

  String get initials => initialsOf(name);
  Color get color => TypePalette.forId(id);

  factory Coiffeur.fromJson(Map<String, dynamic> json, {String salonName = ''}) {
    final specialties =
        (json['specialties'] as List?)?.map((e) => e.toString()).toList() ??
            const <String>[];
    final display = json['display_name']?.toString() ?? '';
    return Coiffeur(
      id: json['id']?.toString() ?? '',
      name: display.trim().isNotEmpty
          ? display
          : (json['name']?.toString() ?? 'Coiffeur'),
      role: specialties.isNotEmpty ? specialties.first : 'Coiffeur',
      salon: salonName,
      salonId: json['salon_id']?.toString() ?? '',
      rating: _toDouble(json['rating_avg']),
      cuts: _toInt(json['cuts_count']),
      serviceIds:
          (json['service_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      available: json['available'] != false,
      trending: specialties,
      bio: json['bio']?.toString() ?? '',
      chairNumber: _toInt(json['chair_number'], 1),
      commissionPct: _toDouble(json['commission_pct'], 50),
      daysOff:
          (json['days_off'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
    );
  }
}

/// Jours de la semaine, dans l'ordre et avec la clé attendue par l'API.
///
/// La semaine commence lundi : c'est la convention du backend, et un décalage
/// ici ferait poser le repos du dimanche sur le lundi.
const kWeekdays = <({String key, String label})>[
  (key: 'mon', label: 'ثنين'),
  (key: 'tue', label: 'ثلاث'),
  (key: 'wed', label: 'ربعا'),
  (key: 'thu', label: 'خميس'),
  (key: 'fri', label: 'جمعة'),
  (key: 'sat', label: 'سبت'),
  (key: 'sun', label: 'حدّ'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────
class ServiceItem {
  final String id;
  final String name;
  final String nameAr;

  /// Commission propre à cette prestation. Null = le taux du coiffeur
  /// s'applique — une couleur laisse moins de marge qu'une coupe.
  final double? commissionPct;

  /// Coût du produit, retenu par le salon avant partage.
  final double productCost;
  final double price;
  final int duration;
  final String icon;
  final SalonType category;
  final String description;
  final int bufferMin;

  const ServiceItem({
    required this.id,
    required this.name,
    this.nameAr = '',
    this.commissionPct,
    this.productCost = 0,
    required this.price,
    required this.duration,
    this.icon = '✂️',
    this.category = SalonType.mixte,
    this.description = '',
    this.bufferMin = 10,
  });

  factory ServiceItem.fromJson(Map<String, dynamic> json) {
    final category = SalonTypeExt.parse(json['category']?.toString());
    return ServiceItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      nameAr: json['name_ar']?.toString() ?? '',
      commissionPct: (json['commission_pct'] as num?)?.toDouble(),
      productCost: (json['product_cost'] as num?)?.toDouble() ?? 0,
      price: _toDouble(json['price']),
      duration: _toInt(json['duration_min']),
      icon: category.emoji,
      category: category,
      description: json['description']?.toString() ?? '',
      bufferMin: _toInt(json['buffer_min'], 10),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Créneaux
// ─────────────────────────────────────────────────────────────────────────────
class BookingSlot {
  /// Heure locale affichable, ex. « 14:30 ».
  final String time;

  /// Instant exact (ISO 8601) à renvoyer au backend.
  final String start;
  final bool available;

  const BookingSlot({required this.time, this.start = '', this.available = true});

  factory BookingSlot.fromJson(Map<String, dynamic> json) => BookingSlot(
        time: json['time']?.toString() ?? '',
        start: json['start']?.toString() ?? '',
      );
}

class DaySlot {
  final String dayShort;
  final String dayNum;
  final String fullDate;
  final bool available;
  final DateTime date;

  const DaySlot({
    required this.dayShort,
    required this.dayNum,
    required this.fullDate,
    required this.date,
    this.available = true,
  });

  static const _short = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  static const _long = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'
  ];
  static const _months = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre'
  ];

  factory DaySlot.fromDate(DateTime date) => DaySlot(
        dayShort: _short[date.weekday - 1],
        dayNum: date.day.toString(),
        fullDate: '${_long[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}',
        date: date,
      );

  /// Les `count` prochains jours à partir d'aujourd'hui.
  static List<DaySlot> next(int count) {
    final today = DateTime.now();
    return List.generate(
      count,
      (i) => DaySlot.fromDate(DateTime(today.year, today.month, today.day + i)),
    );
  }

  /// Format attendu par l'API : `YYYY-MM-DD`.
  String get isoDate => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  DaySlot copyWith({bool? available}) => DaySlot(
        dayShort: dayShort,
        dayNum: dayNum,
        fullDate: fullDate,
        date: date,
        available: available ?? this.available,
      );
}

/// Pourquoi un jour n'est pas réservable.
///
/// « Complet » et « le coiffeur est en congé » demandent deux réactions
/// opposées — réessayer plus tard, ou changer de coiffeur. Les confondre fait
/// perdre le client.
enum DayUnavailability {
  salonClosed,
  dayOff,
  staffUnavailable,
  full;

  static DayUnavailability? fromApi(String? code) => switch (code) {
        'salon_closed' => DayUnavailability.salonClosed,
        'day_off' => DayUnavailability.dayOff,
        'staff_unavailable' => DayUnavailability.staffUnavailable,
        'full' => DayUnavailability.full,
        _ => null,
      };

  /// Ce qu'on affiche sous le jour grisé, en tunisien.
  String get label => switch (this) {
        DayUnavailability.salonClosed => 'مسكّر',
        DayUnavailability.dayOff => 'راحة',
        DayUnavailability.staffUnavailable => 'غايب',
        DayUnavailability.full => 'كامل',
      };
}

/// Disponibilité d'un coiffeur pour une journée donnée.
class DayAvailability {
  const DayAvailability({
    required this.isoDate,
    this.available = false,
    this.slotCount = 0,
    this.reason,
  });

  final String isoDate;
  final bool available;
  final int slotCount;
  final DayUnavailability? reason;

  factory DayAvailability.fromJson(Map<String, dynamic> json) => DayAvailability(
        isoDate: json['date']?.toString() ?? '',
        available: json['available'] == true,
        slotCount: (json['slot_count'] as num?)?.toInt() ?? 0,
        reason: DayUnavailability.fromApi(json['reason']?.toString()),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifications
// ─────────────────────────────────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String type;
  final String message;
  final String time;
  bool read;
  final String icon;

  /// Charge utile du serveur — `booking_id`, `salon_id`… C'est elle qui permet
  /// d'ouvrir l'écran concerné au lieu de se contenter de marquer comme lu.
  final Map<String, String> data;

  AppNotification({
    required this.id,
    required this.type,
    required this.message,
    required this.time,
    this.read = false,
    this.icon = '🔔',
    this.data = const {},
  });

  static const _icons = {
    'booking_confirmed': '✅',
    'booking_cancelled': '❌',
    'reminder_j1': '⏰',
    'reminder_h2': '⏰',
    'your_turn': '💈',
    'advance_requested': '💸',
    'advance_decided': '💸',
    'closure_ready': '📊',
    'new_portfolio': '🔥',
    'new_review': '⭐',
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString() ?? '';
    final title = json['title']?.toString() ?? '';
    final body = json['body']?.toString() ?? '';
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: type,
      message: [title, body].where((s) => s.isNotEmpty).join(' — '),
      time: relativeTime(json['created_at']?.toString()),
      read: json['read'] == true,
      icon: _icons[type] ?? '🔔',
      data: ((json['data'] as Map?) ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      ),
    );
  }
}

/// « il y a 5 min », « hier »… à partir d'un timestamp ISO.
String relativeTime(String? iso) {
  final parsed = DateTime.tryParse(iso ?? '');
  if (parsed == null) return '';
  final delta = DateTime.now().difference(parsed.toLocal());
  if (delta.inMinutes < 1) return "à l'instant";
  if (delta.inMinutes < 60) return 'il y a ${delta.inMinutes} min';
  if (delta.inHours < 24) return 'il y a ${delta.inHours} h';
  if (delta.inDays == 1) return 'hier';
  return 'il y a ${delta.inDays} j';
}

// ─────────────────────────────────────────────────────────────────────────────
// Caisse
// ─────────────────────────────────────────────────────────────────────────────
class CashWorker {
  final String id;
  final String name;
  final int cuts;
  final double total;
  final double share;
  final double tip;
  final int? chair;

  const CashWorker({
    required this.id,
    required this.name,
    this.cuts = 0,
    this.total = 0,
    this.share = 0,
    this.tip = 0,
    this.chair,
  });

  String get initials => initialsOf(name);
  Color get color => TypePalette.forId(id);

  factory CashWorker.fromEntry(String staffId, Map<String, dynamic> row) => CashWorker(
        id: staffId,
        name: row['name']?.toString() ?? '—',
        cuts: _toInt(row['count']),
        total: _toDouble(row['gross']),
        share: _toDouble(row['staff_share']),
        tip: _toDouble(row['tips']),
        chair: row['chair'] is num ? _toInt(row['chair']) : null,
      );
}

/// Réponse de `GET /cash/today` (vue gérant).
class DayCash {
  final double total;
  final double salonTotal;
  final double staffTotal;
  final double tipsTotal;
  final double expensesTotal;
  final double netSalon;
  final double advancesPending;
  final int advancesPendingCount;
  final int transactionCount;
  final Map<String, double> byMethod;
  final List<CashWorker> workers;
  final bool closed;

  const DayCash({
    this.total = 0,
    this.salonTotal = 0,
    this.staffTotal = 0,
    this.tipsTotal = 0,
    this.expensesTotal = 0,
    this.netSalon = 0,
    this.advancesPending = 0,
    this.advancesPendingCount = 0,
    this.transactionCount = 0,
    this.byMethod = const {},
    this.workers = const [],
    this.closed = false,
  });

  double get cash => byMethod['cash'] ?? 0;
  double get card => byMethod['card'] ?? 0;
  double get online => byMethod['online'] ?? 0;

  factory DayCash.fromJson(Map<String, dynamic> json) {
    final staff = (json['by_staff'] as Map?) ?? const {};
    return DayCash(
      total: _toDouble(json['total']),
      salonTotal: _toDouble(json['salon_total']),
      staffTotal: _toDouble(json['staff_total']),
      tipsTotal: _toDouble(json['tips_total']),
      expensesTotal: _toDouble(json['expenses_total']),
      netSalon: _toDouble(json['net_salon']),
      advancesPending: _toDouble(json['advances_pending']),
      advancesPendingCount: _toInt(json['advances_pending_count']),
      transactionCount: _toInt(json['transaction_count']),
      byMethod: ((json['by_method'] as Map?) ?? const {})
          .map((key, value) => MapEntry(key.toString(), _toDouble(value))),
      workers: staff.entries
          .map((e) => CashWorker.fromEntry(
              e.key.toString(), Map<String, dynamic>.from(e.value as Map)))
          .toList(),
      closed: json['closed'] == true,
    );
  }
}

/// Réponse de `GET /cash/me` (vue coiffeur, strictement personnelle).
class MyCash {
  final int count;
  final double gross;
  final double myShare;
  final double tips;
  final double payout;
  final double advancesOutstanding;
  final double advancesPending;

  const MyCash({
    this.count = 0,
    this.gross = 0,
    this.myShare = 0,
    this.tips = 0,
    this.payout = 0,
    this.advancesOutstanding = 0,
    this.advancesPending = 0,
  });

  factory MyCash.fromJson(Map<String, dynamic> json) => MyCash(
        count: _toInt(json['count']),
        gross: _toDouble(json['gross']),
        myShare: _toDouble(json['my_share']),
        tips: _toDouble(json['tips']),
        payout: _toDouble(json['payout']),
        advancesOutstanding: _toDouble(json['advances_outstanding']),
        advancesPending: _toDouble(json['advances_pending']),
      );
}

class Advance {
  final String id;
  final String staffName;
  final double amount;
  final String reason;
  final String status;
  final String requestedAt;

  const Advance({
    required this.id,
    this.staffName = '',
    this.amount = 0,
    this.reason = '',
    this.status = 'pending',
    this.requestedAt = '',
  });

  bool get isPending => status == 'pending';

  factory Advance.fromJson(Map<String, dynamic> json) => Advance(
        id: json['id']?.toString() ?? '',
        staffName: json['staff_name']?.toString() ?? '',
        amount: _toDouble(json['amount']),
        reason: json['reason']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        requestedAt: relativeTime(json['requested_at']?.toString()),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Réservations
// ─────────────────────────────────────────────────────────────────────────────
enum BookingStatus { pending, confirmed, inProgress, done, cancelled, noShow }

extension BookingStatusExt on BookingStatus {
  String get label {
    switch (this) {
      case BookingStatus.pending:    return 'En attente';
      case BookingStatus.confirmed:  return 'Confirmé';
      case BookingStatus.inProgress: return 'En cours';
      case BookingStatus.done:       return 'Terminé';
      case BookingStatus.cancelled:  return 'Annulé';
      case BookingStatus.noShow:     return 'Absent';
    }
  }

  String get apiValue {
    switch (this) {
      case BookingStatus.pending:    return 'PENDING';
      case BookingStatus.confirmed:  return 'CONFIRMED';
      case BookingStatus.inProgress: return 'IN_PROGRESS';
      case BookingStatus.done:       return 'DONE';
      case BookingStatus.cancelled:  return 'CANCELLED';
      case BookingStatus.noShow:     return 'NO_SHOW';
    }
  }

  static BookingStatus parse(String? raw) {
    switch (raw) {
      case 'CONFIRMED':   return BookingStatus.confirmed;
      case 'IN_PROGRESS': return BookingStatus.inProgress;
      case 'DONE':        return BookingStatus.done;
      case 'CANCELLED':   return BookingStatus.cancelled;
      case 'NO_SHOW':     return BookingStatus.noShow;
      default:            return BookingStatus.pending;
    }
  }
}

class Booking {
  final String id;
  final String clientName;
  final String service;
  final String coiffeur;
  final String coiffeurId;
  final String salonId;
  final String date;
  final String time;
  final double price;
  final BookingStatus status;
  final DateTime? start;
  final bool isWalkIn;

  /// Paiement en ligne rattaché, s'il y en a un (§3.6). Nécessaire pour
  /// proposer un remboursement : on ne rembourse pas un RDV réglé en espèces.
  final String? paymentId;
  final bool paid;

  const Booking({
    required this.id,
    this.clientName = '',
    this.service = '',
    this.coiffeur = '',
    this.coiffeurId = '',
    this.salonId = '',
    this.date = '',
    this.time = '',
    this.price = 0,
    this.status = BookingStatus.pending,
    this.start,
    this.isWalkIn = false,
    this.paymentId,
    this.paid = false,
  });

  /// Seul un paiement en ligne encaissé est remboursable — le serveur refuse
  /// le reste en 409.
  bool get refundable => paid && paymentId != null && paymentId!.isNotEmpty;

  bool get isActive =>
      status == BookingStatus.pending ||
      status == BookingStatus.confirmed ||
      status == BookingStatus.inProgress;

  factory Booking.fromJson(Map<String, dynamic> json, {String coiffeurName = ''}) {
    final start = DateTime.tryParse(json['start']?.toString() ?? '')?.toLocal();
    final names =
        (json['service_names'] as List?)?.map((e) => e.toString()).toList() ?? const [];
    final client = json['client_name']?.toString() ?? '';
    return Booking(
      id: json['id']?.toString() ?? '',
      clientName: client.trim().isNotEmpty ? client : 'Client',
      service: names.join(' + '),
      coiffeur: coiffeurName,
      coiffeurId: json['staff_id']?.toString() ?? '',
      salonId: json['salon_id']?.toString() ?? '',
      date: start == null ? '' : '${start.day}/${start.month}',
      time: start == null
          ? ''
          : '${start.hour.toString().padLeft(2, '0')}:'
              '${start.minute.toString().padLeft(2, '0')}',
      price: _toDouble(json['price_total']),
      status: BookingStatusExt.parse(json['status']?.toString()),
      start: start,
      isWalkIn: json['source'] == 'walkin',
      paymentId: json['payment_id']?.toString(),
      paid: json['payment_status'] == 'paid',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session
// ─────────────────────────────────────────────────────────────────────────────
enum AppRole { client, owner, coiffeur }

extension AppRoleExt on AppRole {
  String get apiValue {
    switch (this) {
      case AppRole.client:   return 'CLIENT';
      case AppRole.owner:    return 'OWNER';
      case AppRole.coiffeur: return 'STAFF';
    }
  }

  static AppRole parse(String? raw) {
    switch (raw) {
      case 'OWNER': return AppRole.owner;
      case 'STAFF': return AppRole.coiffeur;
      default:      return AppRole.client;
    }
  }
}

class AppUser {
  final String id;
  final String phone;
  final String name;
  final AppRole role;
  final String locale;

  const AppUser({
    required this.id,
    this.phone = '',
    this.name = '',
    this.role = AppRole.client,
    this.locale = 'fr',
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id']?.toString() ?? '',
        phone: json['phone']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        role: AppRoleExt.parse(json['role']?.toString()),
        locale: json['locale']?.toString() ?? 'fr',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'phone': phone,
        'name': name,
        'role': role.apiValue,
        'locale': locale,
      };
}
