import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/salon_repository.dart';

/// Tunnel de réservation : service → jour → créneau → confirmation.
class BookingController extends ChangeNotifier {
  BookingController(this._salons, this._bookings);

  final SalonRepository _salons;
  final BookingRepository _bookings;

  final List<DaySlot> days = DaySlot.next(14);

  String? _salonId;
  String? _staffId;
  ServiceItem? _service;
  int _dayIndex = 0;
  BookingSlot? _slot;

  List<BookingSlot> _slots = const [];
  bool _loadingSlots = false;
  bool _submitting = false;
  String? _error;
  List<String> _alternatives = const [];

  ServiceItem? get service => _service;
  String? get staffId => _staffId;
  int get dayIndex => _dayIndex;
  DaySlot get selectedDay => days[_dayIndex];
  BookingSlot? get slot => _slot;
  List<BookingSlot> get slots => _slots;
  bool get loadingSlots => _loadingSlots;
  bool get submitting => _submitting;
  String? get error => _error;
  List<String> get alternatives => _alternatives;
  bool get canBook => _service != null && _slot != null && !_submitting;

  /// Prépare un nouveau tunnel. `staffId` null = « peu importe le coiffeur ».
  void start({required String salonId, String? staffId}) {
    _salonId = salonId;
    _staffId = staffId;
    _service = null;
    _slot = null;
    _dayIndex = 0;
    _slots = const [];
    _error = null;
    _alternatives = const [];
  }

  Future<void> selectService(ServiceItem service) async {
    _service = service;
    _slot = null;
    await _loadSlots();
  }

  Future<void> selectStaff(String? staffId) async {
    if (_staffId == staffId) return;
    _staffId = staffId;
    _slot = null;
    await _loadSlots();
  }

  Future<void> selectDay(int index) async {
    if (index < 0 || index >= days.length) return;
    _dayIndex = index;
    _slot = null;
    await _loadSlots();
  }

  void selectSlot(BookingSlot slot) {
    _slot = slot;
    notifyListeners();
  }

  Future<void> _loadSlots() async {
    final staffId = _staffId;
    // Sans coiffeur nommé, le backend choisira au moment de la réservation :
    // on ne peut pas afficher de grille fiable, l'utilisateur en choisit un.
    if (staffId == null || _service == null) {
      _slots = const [];
      notifyListeners();
      return;
    }

    _loadingSlots = true;
    _error = null;
    notifyListeners();
    try {
      _slots = await _salons.slots(
        staffId: staffId,
        isoDate: selectedDay.isoDate,
        serviceIds: [_service!.id],
      );
    } on ApiException catch (e) {
      _error = e.message;
      _slots = const [];
    } finally {
      _loadingSlots = false;
      notifyListeners();
    }
  }

  /// Crée le RDV. Renvoie null en cas d'échec (voir [error]).
  Future<Booking?> confirm({bool payOnline = false}) async {
    final salonId = _salonId;
    if (salonId == null || _service == null || _slot == null) return null;

    _submitting = true;
    _error = null;
    _alternatives = const [];
    notifyListeners();
    try {
      final booking = await _bookings.create(
        salonId: salonId,
        staffId: _staffId,
        serviceIds: [_service!.id],
        startIso: _slot!.start,
      );

      if (payOnline) {
        final checkout = await _bookings.checkout(booking.id);
        // Le provider `mock` du backend de dev n'ouvre pas de page bancaire :
        // on valide directement pour dérouler le tunnel de bout en bout.
        if (checkout.isMock) await _bookings.payMock(checkout.url);
      }
      return booking;
    } on ApiException catch (e) {
      _error = e.message;
      _alternatives = e.alternatives;
      return null;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }
}
