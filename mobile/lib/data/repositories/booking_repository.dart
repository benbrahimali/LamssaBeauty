import '../../core/api_client.dart';
import '../models.dart';

/// Réservations (§3.3) et paiement en ligne (§3.6).
class BookingRepository {
  BookingRepository(this._api);

  final ApiClient _api;

  /// Crée un RDV. `staffId` à null = option « peu importe ».
  Future<Booking> create({
    required String salonId,
    String? staffId,
    required List<String> serviceIds,
    required String startIso,
    String note = '',
  }) async {
    final data = await _api.post('/bookings', body: {
      'salon_id': salonId,
      if (staffId != null) 'staff_id': staffId,
      'service_ids': serviceIds,
      'start': startIso,
      'source': 'app',
      'note': note,
    }) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  /// RDV walk-in saisi par le salon, pour que la caisse reste exacte.
  Future<Booking> createWalkIn({
    required String salonId,
    required String staffId,
    required List<String> serviceIds,
    required String startIso,
    required String clientName,
    String clientPhone = '',
  }) async {
    final data = await _api.post('/bookings', body: {
      'salon_id': salonId,
      'staff_id': staffId,
      'service_ids': serviceIds,
      'start': startIso,
      'source': 'walkin',
      'client_name': clientName,
      'client_phone': clientPhone,
    }) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  Future<List<Booking>> mine({bool? upcoming}) async {
    final data = await _api.get('/bookings/me', query: {
      if (upcoming != null) 'upcoming': upcoming,
    }) as List;
    return data
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Agenda du jour d'un salon — filtré côté serveur selon le rôle appelant.
  Future<SalonAgenda> agenda({
    required String salonId,
    String? isoDate,
    Map<String, String> staffNames = const {},
  }) async {
    final data = await _api.get('/bookings/salon/$salonId', query: {
      if (isoDate != null) 'date': isoDate,
    }) as Map<String, dynamic>;

    final bookings = ((data['bookings'] as List?) ?? const []).map((e) {
      final raw = Map<String, dynamic>.from(e as Map);
      return Booking.fromJson(
        raw,
        coiffeurName: staffNames[raw['staff_id']?.toString()] ?? '',
      );
    }).toList();

    return SalonAgenda(
      date: data['date']?.toString() ?? '',
      revenueExpected: (data['revenue_expected'] as num?)?.toDouble() ?? 0,
      bookings: bookings,
    );
  }

  /// Planning personnel du coiffeur connecté — il ne voit que ses RDV.
  Future<List<Booking>> myAgenda({String? isoDate}) async {
    final data = await _api.get('/staff/me/agenda', query: {
      if (isoDate != null) 'day': isoDate,
    }) as Map<String, dynamic>;
    return ((data['bookings'] as List?) ?? const [])
        .map((e) => Booking.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Booking> changeStatus(String bookingId, BookingStatus status,
      {String reason = ''}) async {
    final data = await _api.patch('/bookings/$bookingId', body: {
      'status': status.apiValue,
      'reason': reason,
    }) as Map<String, dynamic>;
    return Booking.fromJson(data);
  }

  Future<Booking> cancel(String bookingId, {String reason = ''}) =>
      changeStatus(bookingId, BookingStatus.cancelled, reason: reason);

  /// Termine la prestation et déclenche le split salon/employé.
  Future<CompletedService> complete({
    required String bookingId,
    String method = 'cash',
    double tip = 0,
    double? amountOverride,
  }) async {
    final data = await _api.post('/bookings/$bookingId/complete', body: {
      'method': method,
      'tip': tip,
      if (amountOverride != null) 'amount_override': amountOverride,
    }) as Map<String, dynamic>;

    final split = Map<String, dynamic>.from(data['split'] as Map);
    return CompletedService(
      booking: Booking.fromJson(Map<String, dynamic>.from(data['booking'] as Map)),
      amount: (split['amount'] as num).toDouble(),
      salonShare: (split['salon_share'] as num).toDouble(),
      staffShare: (split['staff_share'] as num).toDouble(),
      tip: (split['tip'] as num).toDouble(),
      staffPayout: (split['staff_payout'] as num).toDouble(),
    );
  }

  /// Ouvre un paiement en ligne et renvoie l'URL de checkout du PSP.
  Future<Checkout> checkout(String bookingId) async {
    final data = await _api.post('/payments/checkout',
        body: {'booking_id': bookingId}) as Map<String, dynamic>;
    return Checkout(
      paymentId: data['payment_id']?.toString() ?? '',
      url: data['checkout_url']?.toString() ?? '',
      provider: data['provider']?.toString() ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Simulation de paiement — disponible uniquement avec `PSP_PROVIDER=mock`.
  Future<void> payMock(String checkoutUrl) async {
    final ref = Uri.parse(checkoutUrl).pathSegments;
    final index = ref.indexOf('mock');
    if (index == -1 || index + 1 >= ref.length) return;
    await _api.post('/payments/mock/${ref[index + 1]}/pay');
  }

  Future<void> review({
    required String bookingId,
    required int rating,
    String comment = '',
  }) =>
      _api.post('/reviews',
          body: {'booking_id': bookingId, 'rating': rating, 'comment': comment});
}

class SalonAgenda {
  final String date;
  final double revenueExpected;
  final List<Booking> bookings;

  const SalonAgenda({
    this.date = '',
    this.revenueExpected = 0,
    this.bookings = const [],
  });
}

class CompletedService {
  final Booking booking;
  final double amount;
  final double salonShare;
  final double staffShare;
  final double tip;
  final double staffPayout;

  const CompletedService({
    required this.booking,
    required this.amount,
    required this.salonShare,
    required this.staffShare,
    required this.tip,
    required this.staffPayout,
  });
}

class Checkout {
  final String paymentId;
  final String url;
  final String provider;
  final double amount;

  const Checkout({
    required this.paymentId,
    required this.url,
    required this.provider,
    required this.amount,
  });

  bool get isMock => provider == 'mock';
}
