import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/salon_repository.dart';

/// Tunnel de réservation : services → jour → créneau → confirmation.
///
/// Le client choisit une ou plusieurs prestations (coupe + barbe, brushing +
/// soin) : la durée s'additionne, et le serveur ne propose que les créneaux où
/// l'ensemble tient.
class BookingController extends ChangeNotifier {
  BookingController(this._salons, this._bookings);

  final SalonRepository _salons;
  final BookingRepository _bookings;

  final List<DaySlot> days = DaySlot.next(14);

  String? _salonId;
  String? _staffId;
  /// Prestations choisies, dans l'ordre où le client les a ajoutées.
  final List<ServiceItem> _selected = [];
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

  List<ServiceItem> get selectedServices => List.unmodifiable(_selected);
  bool get hasServices => _selected.isNotEmpty;
  bool isSelected(ServiceItem service) => _selected.any((s) => s.id == service.id);

  /// Prix affiché avant confirmation. Le serveur refait le calcul : c'est son
  /// prix qui est figé sur le RDV.
  double get totalPrice => _selected.fold(0.0, (total, s) => total + s.price);
  int get totalDuration => _selected.fold(0, (total, s) => total + s.duration);

  List<String> get _serviceIds => [for (final s in _selected) s.id];

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
  bool get canBook => _selected.isNotEmpty && _slot != null && !_submitting;

  /// Prépare un nouveau tunnel. `staffId` null = « peu importe le coiffeur ».
  void start({required String salonId, String? staffId}) {
    _salonId = salonId;
    _staffId = staffId;
    _selected.clear();
    _slot = null;
    _dayIndex = 0;
    _slots = const [];
    _error = null;
    _alternatives = const [];
  }

  /// Ajoute la prestation, ou la retire si elle était déjà choisie.
  ///
  /// La durée change avec la sélection : le créneau choisi n'est plus sûr de
  /// tenir, les jours et les créneaux se recalculent.
  Future<void> toggleService(ServiceItem service) async {
    final index = _selected.indexWhere((s) => s.id == service.id);
    if (index >= 0) {
      _selected.removeAt(index);
    } else {
      _selected.add(service);
    }
    _slot = null;
    await _loadAvailability();
    await _loadSlots();
  }

  /// Remplace la sélection par cette seule prestation.
  Future<void> selectService(ServiceItem service) async {
    _selected
      ..clear()
      ..add(service);
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
    if (staffId == null || _selected.isEmpty) {
      _availability = const {};
      notifyListeners();
      return;
    }

    _loadingDays = true;
    notifyListeners();
    try {
      final jours = await _salons.availability(
        staffId: staffId,
        serviceIds: _serviceIds,
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
    if (staffId == null || _selected.isEmpty) {
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
        serviceIds: _serviceIds,
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
    if (salonId == null || _selected.isEmpty || _slot == null) return null;

    _submitting = true;
    _error = null;
    _alternatives = const [];
    notifyListeners();
    try {
      final booking = await _bookings.create(
        salonId: salonId,
        staffId: _staffId,
        serviceIds: _serviceIds,
        startIso: _slot!.start,
        payOnline: payOnline,
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
