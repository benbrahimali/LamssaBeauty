import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/cash_repository.dart';
import '../data/repositories/salon_repository.dart';

/// Caisse du salon côté gérant : totaux du jour, tséb9as, agenda, clôture.
class CashController extends ChangeNotifier {
  CashController(this._cash, this._bookings, this._salons);

  final CashRepository _cash;
  final BookingRepository _bookings;
  final SalonRepository _salons;

  String? _salonId;
  DayCash _day = const DayCash();
  List<Advance> _advances = const [];
  SalonAgenda _agenda = const SalonAgenda();
  List<ClosureResult> _closures = const [];

  /// Catalogue et équipe du salon — nécessaires pour saisir un walk-in.
  List<ServiceItem> _services = const [];
  List<Coiffeur> _team = const [];
  bool _loading = false;
  String? _error;

  List<ServiceItem> get services => _services;
  List<Coiffeur> get team => _team;

  DayCash get day => _day;
  List<Advance> get advances => _advances;
  List<Advance> get pendingAdvances =>
      _advances.where((a) => a.isPending).toList();
  SalonAgenda get agenda => _agenda;
  List<ClosureResult> get closures => _closures;
  List<CashWorker> get workers => _day.workers;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasSalon => _salonId != null;

  /// Salon actif — nécessaire aux écrans qui interrogent l'API directement
  /// (les dépenses, par exemple).
  String? get salonId => _salonId;

  void attach(String? salonId) {
    if (_salonId == salonId) return;
    _salonId = salonId;
    _day = const DayCash();
    _advances = const [];
    _agenda = const SalonAgenda();
    _closures = const [];
  }

  Future<void> load() async {
    final salonId = _salonId;
    if (salonId == null || _loading) return;

    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _cash.today(salonId),
        _cash.salonAdvances(salonId),
        _bookings.agenda(salonId: salonId),
        _cash.closures(salonId),
      ]);
      _day = results[0] as DayCash;
      _advances = results[1] as List<Advance>;
      _agenda = results[2] as SalonAgenda;
      _closures = results[3] as List<ClosureResult>;

      // Catalogue et équipe : rechargés une seule fois, ils bougent rarement.
      if (_services.isEmpty || _team.isEmpty) {
        final detail = await _salons.detail(salonId);
        _services = detail.services;
        _team = detail.staff;
      }
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Saisit un client de passage (§3.3, §8.4).
  ///
  /// Sans ça la caisse est fausse dès qu'un client entre sans avoir réservé —
  /// et c'est précisément ce qui pousse le gérant à adopter l'outil.
  Future<String?> addWalkIn({
    required String staffId,
    required String serviceId,
    required String clientName,
    DateTime? start,
  }) async {
    final salonId = _salonId;
    if (salonId == null) return 'Aucun salon sélectionné';
    try {
      await _bookings.createWalkIn(
        salonId: salonId,
        staffId: staffId,
        serviceIds: [serviceId],
        // Un walk-in décrit un client déjà sur place : par défaut, maintenant.
        startIso: (start ?? DateTime.now()).toUtc().toIso8601String(),
        clientName: clientName,
      );
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> decideAdvance(String advanceId, bool approve) async {
    try {
      await _cash.decideAdvance(advanceId, approve);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Saisit une dépense.
  ///
  /// [paidFrom] dit si l'argent sort du tiroir ou de la banque : une charge
  /// réglée par virement ne doit pas faire baisser le solde de caisse.
  Future<String?> addExpense(String label, double amount,
      {String category = 'autre', String paidFrom = 'cash'}) async {
    final salonId = _salonId;
    if (salonId == null) return 'Aucun salon sélectionné';
    try {
      await _cash.addExpense(
          salonId: salonId,
          label: label,
          amount: amount,
          category: category,
          paidFrom: paidFrom);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Encaisse une prestation : crée la transaction et son split.
  Future<CompletedService?> completeBooking(
    String bookingId, {
    String method = 'cash',
    double tip = 0,
  }) async {
    try {
      final result = await _bookings.complete(
          bookingId: bookingId, method: method, tip: tip);
      await load();
      return result;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Clôture la journée.
  ///
  /// [countedCash] null = le gérant n'a pas compté son tiroir ; l'écart n'est
  /// alors pas calculé plutôt qu'affiché à zéro.
  Future<ClosureResult?> closeDay({
    double? countedCash,
    double withdrawal = 0,
    String varianceReason = '',
  }) async {
    final salonId = _salonId;
    if (salonId == null) return null;
    try {
      final closure = await _cash.closeDay(
        salonId,
        countedCash: countedCash,
        withdrawal: withdrawal,
        varianceReason: varianceReason,
      );
      await load();
      return closure;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Retire un mouvement saisi par erreur. Refusé côté serveur si la journée
  /// est déjà clôturée : le rapport signé ne doit pas bouger.
  Future<bool> removeMovementById(String movementId) async {
    try {
      await _cash.removeMovement(movementId);
      await load();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }

  /// État du tiroir aujourd'hui, pour le comparer à ce qu'on y compte.
  Future<Treasury?> treasury() async {
    final salonId = _salonId;
    if (salonId == null) return null;
    try {
      return await _cash.treasury(salonId);
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  /// Fond de caisse, apport ou prélèvement.
  Future<bool> addMovement({
    required String type,
    required double amount,
    String label = '',
  }) async {
    final salonId = _salonId;
    if (salonId == null) return false;
    try {
      await _cash.addMovement(
          salonId: salonId, type: type, amount: amount, label: label);
      await load();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    }
  }
}

/// Caisse personnelle d'un coiffeur — ne voit jamais celle du salon.
class MyCashController extends ChangeNotifier {
  MyCashController(this._cash, this._bookings, this._salons);

  final CashRepository _cash;
  final BookingRepository _bookings;
  final SalonRepository _salons;

  MyCash _cashDay = const MyCash();
  List<Advance> _advances = const [];
  List<Booking> _agenda = const [];
  List<ServiceItem> _services = const [];
  bool _loading = false;
  String? _error;

  MyCash get cash => _cashDay;
  List<Advance> get advances => _advances;
  List<Booking> get agenda => _agenda;
  List<ServiceItem> get services => _services;

  /// Catalogue du salon — chargé à la demande, uniquement pour le walk-in.
  Future<void> loadCatalogue(String salonId) async {
    if (_services.isNotEmpty) return;
    try {
      _services = (await _salons.detail(salonId)).services;
      notifyListeners();
    } on ApiException {
      // Le walk-in restera indisponible ; le reste du tableau de bord marche.
    }
  }

  /// Le coiffeur saisit lui-même le client de passage qu'il vient de servir.
  Future<String?> addWalkIn({
    required String salonId,
    required String staffId,
    required String serviceId,
    required String clientName,
  }) async {
    try {
      await _bookings.createWalkIn(
        salonId: salonId,
        staffId: staffId,
        serviceIds: [serviceId],
        startIso: DateTime.now().toUtc().toIso8601String(),
        clientName: clientName,
      );
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _cashDay = await _cash.mine();
      _advances = await _cash.myAdvances();
      _agenda = await _bookings.myAgenda();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Le coiffeur clôture lui-même la prestation qu'il vient de terminer.
  Future<CompletedService?> completeBooking(
    String bookingId, {
    String method = 'cash',
    double tip = 0,
  }) async {
    try {
      final result =
          await _bookings.complete(bookingId: bookingId, method: method, tip: tip);
      await load();
      return result;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<String?> requestAdvance(String salonId, double amount, String reason) async {
    try {
      await _cash.requestAdvance(salonId: salonId, amount: amount, reason: reason);
      await load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
}
