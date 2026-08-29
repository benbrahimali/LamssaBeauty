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

  /// Compte de résultat du salon (§3.4).
  ///
  /// Sans période, le mois en cours : c'est la maille sur laquelle un loyer et
  /// des salaires ont un sens.
  Future<Pnl> pnl(String salonId, {DateTime? start, DateTime? end}) async {
    final data = await _api.get('/cash/pnl', query: {
      'salon_id': salonId,
      if (start != null) 'start': _isoDay(start),
      if (end != null) 'end': _isoDay(end),
    }) as Map<String, dynamic>;
    return Pnl.fromJson(data);
  }

  /// Charges fixes du salon, avec leur équivalent mensuel.
  Future<({List<RecurringCharge> charges, double monthlyEquivalent})> charges(
    String salonId, {
    bool includeInactive = false,
  }) async {
    final data = await _api.get('/cash/charges', query: {
      'salon_id': salonId,
      if (includeInactive) 'include_inactive': true,
    }) as Map<String, dynamic>;
    return (
      charges: ((data['charges'] as List?) ?? const [])
          .map((e) => RecurringCharge.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      monthlyEquivalent: (data['monthly_equivalent'] as num?)?.toDouble() ?? 0,
    );
  }

  Future<RecurringCharge> addCharge(
    String salonId, {
    required String label,
    required double amount,
    required String period,
    String category = 'autre',
  }) async {
    final data = await _api.post('/cash/charges',
        query: {'salon_id': salonId},
        body: {
          'label': label,
          'amount': amount,
          'period': period,
          'category': category,
        }) as Map<String, dynamic>;
    return RecurringCharge.fromJson(data);
  }

  /// Désactive plutôt que supprimer : les mois déjà analysés gardent leurs
  /// comptes justes.
  Future<RecurringCharge> setChargeActive(String chargeId, bool active) async {
    final data = await _api.patch('/cash/charges/$chargeId',
        body: {'active': active}) as Map<String, dynamic>;
    return RecurringCharge.fromJson(data);
  }

  /// À réserver aux saisies erronées — une charge réelle se désactive.
  Future<void> deleteCharge(String chargeId) =>
      _api.delete('/cash/charges/$chargeId');

  /// Paie de la semaine, par coiffeur (§3.4).
  ///
  /// Le montant qui compte est `balance` : ce qui reste à remettre en main
  /// propre une fois les tséb9as déduites, pas le brut gagné.
  Future<Payroll> payroll(String salonId, {DateTime? weekOf}) async {
    final data = await _api.get('/cash/payroll', query: {
      'salon_id': salonId,
      if (weekOf != null) 'week_of': _isoDay(weekOf),
    }) as Map<String, dynamic>;
    return Payroll.fromJson(data);
  }

  /// La même semaine, vue par le coiffeur : ce qu'il touchera.
  Future<PayrollLine> myPayroll({DateTime? weekOf}) async {
    final data = await _api.get('/cash/me/payroll', query: {
      if (weekOf != null) 'week_of': _isoDay(weekOf),
    }) as Map<String, dynamic>;
    return PayrollLine.fromJson(data);
  }

  static String _isoDay(DateTime d) => '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

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


/// Ce que le gérant doit à son équipe pour la semaine.
class Payroll {
  const Payroll({
    required this.weekStart,
    required this.weekEnd,
    this.staff = const [],
    this.totalEarned = 0,
    this.totalAdvances = 0,
    this.totalToPay = 0,
  });

  final String weekStart;
  final String weekEnd;
  final List<PayrollLine> staff;
  final double totalEarned;
  final double totalAdvances;
  final double totalToPay;

  /// Les lignes sans activité ni avance encombrent la fiche d'un salon qui a
  /// beaucoup de chaises : on ne montre que ceux qui ont quelque chose.
  List<PayrollLine> get active =>
      staff.where((l) => l.services > 0 || l.advances > 0).toList();

  factory Payroll.fromJson(Map<String, dynamic> json) => Payroll(
        weekStart: json['week_start']?.toString() ?? '',
        weekEnd: json['week_end']?.toString() ?? '',
        staff: ((json['staff'] as List?) ?? const [])
            .map((e) => PayrollLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0,
        totalAdvances: (json['total_advances'] as num?)?.toDouble() ?? 0,
        totalToPay: (json['total_to_pay'] as num?)?.toDouble() ?? 0,
      );
}

/// La ligne de paie d'un coiffeur.
class PayrollLine {
  const PayrollLine({
    required this.staffId,
    this.name = '',
    this.services = 0,
    this.gross = 0,
    this.earned = 0,
    this.tips = 0,
    this.advances = 0,
    this.balance = 0,
    this.weekStart = '',
    this.weekEnd = '',
  });

  final String staffId;
  final String name;
  final int services;
  final double gross;
  final double earned;
  final double tips;
  final double advances;

  /// Peut être négatif : l'employé a pris plus d'avance qu'il n'a gagné.
  /// Le masquer laisserait croire que le compte est soldé.
  final double balance;

  final String weekStart;
  final String weekEnd;

  bool get owesSalon => balance < 0;

  factory PayrollLine.fromJson(Map<String, dynamic> json) => PayrollLine(
        staffId: json['staff_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        services: (json['services'] as num?)?.toInt() ?? 0,
        gross: (json['gross'] as num?)?.toDouble() ?? 0,
        earned: (json['earned'] as num?)?.toDouble() ?? 0,
        tips: (json['tips'] as num?)?.toDouble() ?? 0,
        advances: (json['advances'] as num?)?.toDouble() ?? 0,
        balance: (json['balance'] as num?)?.toDouble() ?? 0,
        weekStart: json['week_start']?.toString() ?? '',
        weekEnd: json['week_end']?.toString() ?? '',
      );
}


/// Une charge fixe du salon : loyer, salaire, abonnement, taxe.
class RecurringCharge {
  const RecurringCharge({
    required this.id,
    required this.label,
    required this.amount,
    this.category = 'autre',
    this.period = 'monthly',
    this.active = true,
  });

  final String id;
  final String label;
  final double amount;
  final String category;
  final String period;
  final bool active;

  String get periodLabel => switch (period) {
        'weekly' => 'كل جمعة',
        'yearly' => 'كل عام',
        _ => 'كل شهر',
      };

  factory RecurringCharge.fromJson(Map<String, dynamic> json) => RecurringCharge(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        label: json['label']?.toString() ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        category: json['category']?.toString() ?? 'autre',
        period: json['period']?.toString() ?? 'monthly',
        active: json['active'] != false,
      );
}

/// Compte de résultat : ce qu'il reste au salon une fois tout payé.
class Pnl {
  const Pnl({
    this.days = 0,
    this.revenue = 0,
    this.staffShare = 0,
    this.grossMargin = 0,
    this.expenses = 0,
    this.recurringCharges = 0,
    this.result = 0,
    this.marginPct = 0,
    this.tipsCollected = 0,
    this.byCategory = const {},
    this.transactionCount = 0,
  });

  final double days;
  final double revenue;
  final double staffShare;
  final double grossMargin;
  final double expenses;
  final double recurringCharges;

  /// Peut être négatif : c'est tout l'intérêt de le calculer.
  final double result;
  final double marginPct;

  /// Encaissés pour l'équipe, jamais comptés en revenu du salon.
  final double tipsCollected;
  final Map<String, double> byCategory;
  final int transactionCount;

  bool get isLoss => result < 0;

  factory Pnl.fromJson(Map<String, dynamic> json) => Pnl(
        days: (json['days'] as num?)?.toDouble() ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
        staffShare: (json['staff_share'] as num?)?.toDouble() ?? 0,
        grossMargin: (json['gross_margin'] as num?)?.toDouble() ?? 0,
        expenses: (json['expenses'] as num?)?.toDouble() ?? 0,
        recurringCharges: (json['recurring_charges'] as num?)?.toDouble() ?? 0,
        result: (json['result'] as num?)?.toDouble() ?? 0,
        marginPct: (json['margin_pct'] as num?)?.toDouble() ?? 0,
        tipsCollected: (json['tips_collected'] as num?)?.toDouble() ?? 0,
        byCategory: ((json['by_category'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0),
        ),
        transactionCount: (json['transaction_count'] as num?)?.toInt() ?? 0,
      );
}
