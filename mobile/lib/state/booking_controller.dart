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

  /// Disponibilité de chaque jour, indexée par date ISO. Vide tant que le
  /// coiffeur et la prestation ne sont pas choisis : la durée du service
  /// change ce qui rentre dans la journée.
  Map<String, DayAvailability> _availability = const {};
  bool _loadingDays = false;
  bool _loadingSlots = false;
  bool _submitting = false;
  String? _error;
  List<String> _alternatives = const [];

  ServiceItem? get service => _service;

  bool get loadingDays => _loadingDays;

  /// Ce qu'on sait d'un jour. Null tant que la disponibilité n'est pas
  /// chargée — le calendrier reste alors neutre plutôt que faussement fermé.
  DayAvailability? availabilityFor(DaySlot day) => _availability[day.isoDate];

  /// Vrai quand on sait que le jour est réservable, ou qu'on ne sait rien
  /// encore. On ne grise que sur une information confirmée.
  bool isDayOpen(DaySlot day) => _availability[day.isoDate]?.available ?? true;
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
    await _loadAvailability();
    await _loadSlots();
  }

  Future<void> selectStaff(String? staffId) async {
    if (_staffId == staffId) return;
    _staffId = staffId;
    _slot = null;
    await _loadAvailability();
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

  /// Charge l'état des 14 jours et recale la sélection si besoin.
  ///
  /// Sans ce recalage, le tunnel s'ouvre sur aujourd'hui — souvent le jour de
  /// repos du coiffeur — et le client voit « complet » avant même d'avoir
  /// choisi quoi que ce soit.
  Future<void> _loadAvailability() async {
    final staffId = _staffId;
    if (staffId == null || _service == null) {
      _availability = const {};
      notifyListeners();
      return;
    }

    _loadingDays = true;
    notifyListeners();
    try {
      final jours = await _salons.availability(
        staffId: staffId,
        serviceIds: [_service!.id],
        days: days.length,
      );
      _availability = {for (final j in jours) j.isoDate: j};

      if (!isDayOpen(days[_dayIndex])) {
        final premier = days.indexWhere(isDayOpen);
        // Aucun jour ouvert sur la quinzaine : on ne bouge pas, l'écran dira
        // pourquoi. Déplacer la sélection n'y changerait rien.
        if (premier >= 0) _dayIndex = premier;
      }
    } on ApiException {
      // La disponibilité n'est qu'un confort : sans elle le calendrier reste
      // ouvert et l'utilisateur découvre au clic, comme avant.
      _availability = const {};
    } finally {
      _loadingDays = false;
      notifyListeners();
    }
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
