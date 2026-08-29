import '../../core/api_client.dart';
import '../models.dart';

/// Caisse, tséb9a et clôture (§3.4).
class CashRepository {
  CashRepository(this._api);

  final ApiClient _api;

  // ── Gérant ─────────────────────────────────────────────────────────────
  Future<DayCash> today(String salonId) async {
    final data =
        await _api.get('/cash/today', query: {'salon_id': salonId}) as Map<String, dynamic>;
    return DayCash.fromJson(data);
  }

  Future<DayCash> day(String salonId, String isoDate) async {
    final data = await _api.get('/cash/day',
        query: {'salon_id': salonId, 'date': isoDate}) as Map<String, dynamic>;
    return DayCash.fromJson(data);
  }

  Future<MonthlyReport> monthly(String salonId, int year, int month) async {
    final data = await _api.get('/cash/monthly', query: {
      'salon_id': salonId,
      'year': year,
      'month': month,
    }) as Map<String, dynamic>;
    return MonthlyReport(
      period: data['period']?.toString() ?? '',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      salonTotal: (data['salon_total'] as num?)?.toDouble() ?? 0,
      staffTotal: (data['staff_total'] as num?)?.toDouble() ?? 0,
      expensesTotal: (data['expenses_total'] as num?)?.toDouble() ?? 0,
      result: (data['result'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<void> addExpense({
    required String salonId,
    required String label,
    required double amount,
    String category = 'autre',
  }) =>
      _api.post('/cash/expenses',
          query: {'salon_id': salonId},
          body: {'label': label, 'amount': amount, 'category': category});

  /// Dépenses du salon, les plus récentes d'abord (§3.4).
  ///
  /// Sans cette liste, une dépense saisie de travers restait invisible : le
  /// gérant ne voyait que son effet sur le total de la journée.
  Future<List<Expense>> expenses(String salonId) async {
    final data = await _api.get('/cash/expenses', query: {'salon_id': salonId})
        as List;
    return data
        .map((e) => Expense.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> removeExpense(String expenseId) =>
      _api.delete('/cash/expenses/$expenseId');

  /// Clôture la journée : verrouille les transactions et génère le rapport.
  Future<ClosureResult> closeDay(String salonId, {String? isoDate}) async {
    final data = await _api.post('/cash/closures', body: {
      'salon_id': salonId,
      if (isoDate != null) 'day': isoDate,
    }) as Map<String, dynamic>;

    return ClosureResult(
      id: data['id']?.toString() ?? '',
      day: data['day']?.toString() ?? '',
      total: (data['total'] as num?)?.toDouble() ?? 0,
      salonTotal: (data['salon_total'] as num?)?.toDouble() ?? 0,
      staffTotal: (data['staff_total'] as num?)?.toDouble() ?? 0,
      advancesDeducted: (data['advances_deducted'] as num?)?.toDouble() ?? 0,
      netSalon: (data['net_salon'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<List<ClosureResult>> closures(String salonId, {int limit = 14}) async {
    final data = await _api
        .get('/cash/closures', query: {'salon_id': salonId, 'limit': limit}) as List;
    return data
        .map((e) => ClosureResult.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ── Coiffeur ───────────────────────────────────────────────────────────
  Future<MyCash> mine({String? isoDate}) async {
    final data = await _api.get('/cash/me', query: {
      if (isoDate != null) 'date': isoDate,
    }) as Map<String, dynamic>;
    return MyCash.fromJson(data);
  }

  // ── Tséb9a ─────────────────────────────────────────────────────────────
  Future<List<Advance>> salonAdvances(String salonId, {String? status}) async {
    final data = await _api.get('/advances', query: {
      'salon_id': salonId,
      if (status != null) 'status': status,
    }) as List;
    return data
        .map((e) => Advance.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Advance>> myAdvances() async {
    final data = await _api.get('/advances/me') as Map<String, dynamic>;
    return ((data['advances'] as List?) ?? const [])
        .map((e) => Advance.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<Advance> requestAdvance({
    required String salonId,
    required double amount,
    String reason = '',
  }) async {
    final data = await _api.post('/advances',
            body: {'salon_id': salonId, 'amount': amount, 'reason': reason})
        as Map<String, dynamic>;
    return Advance.fromJson(data);
  }

  Future<Advance> decideAdvance(String advanceId, bool approve,
      {String reason = ''}) async {
    final data = await _api.patch('/advances/$advanceId',
        body: {'approve': approve, 'reason': reason}) as Map<String, dynamic>;
    return Advance.fromJson(data);
  }
}

class MonthlyReport {
  final String period;
  final double total;
  final double salonTotal;
  final double staffTotal;
  final double expensesTotal;
  final double result;

  const MonthlyReport({
    this.period = '',
    this.total = 0,
    this.salonTotal = 0,
    this.staffTotal = 0,
    this.expensesTotal = 0,
    this.result = 0,
  });
}

class ClosureResult {
  final String id;
  final String day;
  final double total;
  final double salonTotal;
  final double staffTotal;
  final double advancesDeducted;
  final double netSalon;

  const ClosureResult({
    required this.id,
    this.day = '',
    this.total = 0,
    this.salonTotal = 0,
    this.staffTotal = 0,
    this.advancesDeducted = 0,
    this.netSalon = 0,
  });

  factory ClosureResult.fromJson(Map<String, dynamic> json) => ClosureResult(
        id: json['id']?.toString() ?? '',
        day: json['day']?.toString() ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        salonTotal: (json['salon_total'] as num?)?.toDouble() ?? 0,
        staffTotal: (json['staff_total'] as num?)?.toDouble() ?? 0,
        advancesDeducted: (json['advances_deducted'] as num?)?.toDouble() ?? 0,
        netSalon: (json['net_salon'] as num?)?.toDouble() ?? 0,
      );
}


/// Une dépense du salon : loyer, produits, électricité…
class Expense {
  const Expense({
    required this.id,
    required this.label,
    required this.amount,
    this.category = 'autre',
    this.spentAt,
  });

  final String id;
  final String label;
  final double amount;
  final String category;
  final DateTime? spentAt;

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category']?.toString() ?? 'autre',
        spentAt: DateTime.tryParse(json['spent_at']?.toString() ?? '')?.toLocal(),
      );
}
