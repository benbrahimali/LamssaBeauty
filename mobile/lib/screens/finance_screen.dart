import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/cash_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Gestion financière du salon (§3.4).
///
/// La caisse dit ce qui est entré ; cet écran dit ce qu'il reste. Un salon peut
/// encaisser 3 000 DT dans le mois et perdre de l'argent une fois le loyer
/// payé — c'est précisément ce que le gérant ne voyait nulle part.
///
/// Chaque salon décrit ses propres charges, avec ses propres libellés et son
/// propre rythme : rien n'est imposé.
class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key, required this.salonId});

  final String salonId;

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> {
  Pnl? _pnl;
  List<RecurringCharge> _charges = const [];
  double _monthlyCharges = 0;
  bool _loading = true;
  String? _error;

  /// Mois consulté : 0 = en cours, -1 = le précédent.
  int _offset = 0;

  CashRepository get _repo => context.read<CashRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({DateTime start, DateTime end}) get _period {
    final now = DateTime.now();
    final first = DateTime(now.year, now.month + _offset, 1);
    // Jour 0 du mois suivant = dernier jour du mois visé.
    final last = DateTime(first.year, first.month + 1, 0);
    return (start: first, end: last);
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final p = _period;
      final results = await Future.wait([
        _repo.pnl(widget.salonId, start: p.start, end: p.end),
        _repo.charges(widget.salonId),
      ]);
      if (!mounted) return;
      final charges = results[1] as ({
        List<RecurringCharge> charges,
        double monthlyEquivalent
      });
      setState(() {
        _pnl = results[0] as Pnl;
        _charges = charges.charges;
        _monthlyCharges = charges.monthlyEquivalent;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text('الميزانية', style: AppTextStyle.playfair(size: 20)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        onPressed: _addCharge,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('مصروف قار',
            style: AppTextStyle.dmSans(
                color: Colors.black, weight: FontWeight.w700)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoader();
    if (_error != null) return AppError(message: _error!, onRetry: _load);

    final pnl = _pnl!;
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          _buildMonthPicker(),
          const SizedBox(height: 14),
          _buildResultCard(pnl),
          const SizedBox(height: 16),
          _buildBreakdown(pnl),
          if (pnl.byCategory.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('وين تمشي الفلوس'),
            const SizedBox(height: 10),
            ...pnl.byCategory.entries.map((e) => _categoryRow(e.key, e.value, pnl)),
          ],
          const SizedBox(height: 20),
          _sectionTitle('المصاريف القارة'),
          const SizedBox(height: 4),
          Text(
            'ما يلزمك كل شهر قبل ما تربح حتّى مليم : '
            '${_monthlyCharges.toStringAsFixed(0)} DT',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
          ),
          const SizedBox(height: 10),
          if (_charges.isEmpty)
            Text('ما زلت ما سجّلت حتّى مصروف قار',
                style: AppTextStyle.dmSans(size: 13, color: AppColors.sub))
          else
            ..._charges.map(_chargeRow),
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    final p = _period;
    const mois = [
      'جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان',
      'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
    ];
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        onPressed: () {
          setState(() => _offset -= 1);
          _load();
        },
        icon: const Icon(Icons.chevron_left, color: AppColors.sub),
      ),
      Text('${mois[p.start.month - 1]} ${p.start.year}',
          style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
      IconButton(
        // Pas de mois futur : il n'y a rien à y lire.
        onPressed: _offset >= 0
            ? null
            : () {
                setState(() => _offset += 1);
                _load();
              },
        icon: Icon(Icons.chevron_right,
            color: _offset >= 0 ? AppColors.border : AppColors.sub),
      ),
    ]);
  }

  Widget _buildResultCard(Pnl pnl) {
    final couleur = pnl.isLoss ? AppColors.red : AppColors.green;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        Text(pnl.isLoss ? 'الخسارة' : 'الربح الصافي',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
        const SizedBox(height: 6),
        Text('${pnl.result.toStringAsFixed(2)} DT',
            style: AppTextStyle.playfair(size: 32, color: couleur)),
        const SizedBox(height: 4),
        Text(
          '${pnl.marginPct.toStringAsFixed(1)} % من رقم المعاملات · '
          '${pnl.transactionCount} خدمة',
          style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
        ),
      ]),
    );
  }

  /// Le détail ligne à ligne : c'est ce qui rend le résultat vérifiable.
  Widget _buildBreakdown(Pnl pnl) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        _line('رقم المعاملات', pnl.revenue, AppColors.text),
        _line('حصّة الفريق', -pnl.staffShare, AppColors.sub),
        const Divider(color: AppColors.border, height: 20),
        _line('الهامش الخام', pnl.grossMargin, AppColors.text, fort: true),
        const SizedBox(height: 8),
        _line('مصاريف عرضية', -pnl.expenses, AppColors.sub),
        _line('مصاريف قارة', -pnl.recurringCharges, AppColors.sub),
        const Divider(color: AppColors.border, height: 20),
        _line('الباقي', pnl.result,
            pnl.isLoss ? AppColors.red : AppColors.gold, fort: true),
        if (pnl.tipsCollected > 0) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.sub),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                // Ils passent par la caisse mais ne sont pas au salon : les
                // compter en revenu gonflerait le résultat.
                'بقشيش ${pnl.tipsCollected.toStringAsFixed(0)} DT محسوب للفريق، '
                'ماهوش من مدخول الصالون',
                style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _line(String label, double valeur, Color couleur, {bool fort = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: AppTextStyle.dmSans(
                size: fort ? 14 : 13,
                color: fort ? AppColors.text : AppColors.sub,
                weight: fort ? FontWeight.w700 : FontWeight.w400)),
        const Spacer(),
        Text('${valeur.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(
                size: fort ? 15 : 13,
                color: couleur,
                weight: fort ? FontWeight.w700 : FontWeight.w500)),
      ]),
    );
  }

  Widget _categoryRow(String categorie, double montant, Pnl pnl) {
    final total = pnl.expenses + pnl.recurringCharges;
    final part = total > 0 ? montant / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(children: [
        Row(children: [
          Text(categorie, style: AppTextStyle.dmSans(size: 13)),
          const Spacer(),
          Text('${montant.toStringAsFixed(0)} DT',
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: part.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppColors.card2,
            valueColor: const AlwaysStoppedAnimation(AppColors.gold),
          ),
        ),
      ]),
    );
  }

  Widget _chargeRow(RecurringCharge charge) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(charge.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w600)),
            Text('${charge.category} · ${charge.periodLabel}',
                style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
          ]),
        ),
        Text('${charge.amount.toStringAsFixed(0)} DT',
            style: AppTextStyle.dmSans(
                size: 14, weight: FontWeight.w700, color: AppColors.gold)),
        GestureDetector(
          onTap: () => _deactivate(charge),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.sub),
          ),
        ),
      ]),
    );
  }

  Widget _sectionTitle(String texte) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(texte, style: AppTextStyle.playfair(size: 17)),
      );

  Future<void> _deactivate(RecurringCharge charge) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('تنحّي « ${charge.label} » ؟',
            style: AppTextStyle.playfair(size: 17)),
        content: Text(
          // Désactiver plutôt que supprimer : les mois passés gardent leurs
          // comptes justes.
          'ما تبقاش محسوبة في الشهور الجايّة. الشهور اللي فاتت ما يتبدّلوش.',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)
              .copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('رجوع', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نحّي',
                style: AppTextStyle.dmSans(
                    color: AppColors.red, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await _repo.setChargeActive(charge.id, false);
      await _load();
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }

  Future<void> _addCharge() async {
    final payload = await showModalBottomSheet<_ChargePayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ChargeSheet(),
    );
    if (payload == null || !mounted) return;

    try {
      await _repo.addCharge(
        widget.salonId,
        label: payload.label,
        amount: payload.amount,
        period: payload.period,
        category: payload.category,
      );
      await _load();
      if (mounted) showAppSnack(context, 'تسجّل ✅', success: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }
}

class _ChargePayload {
  const _ChargePayload({
    required this.label,
    required this.amount,
    required this.period,
    required this.category,
  });

  final String label;
  final double amount;
  final String period;
  final String category;
}

class _ChargeSheet extends StatefulWidget {
  const _ChargeSheet();

  @override
  State<_ChargeSheet> createState() => _ChargeSheetState();
}

class _ChargeSheetState extends State<_ChargeSheet> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  String _period = 'monthly';
  String _category = 'loyer';

  static const _categories = [
    'loyer', 'produits', 'électricité', 'eau', 'entretien', 'taxes', 'autre',
  ];

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text('مصروف قار', style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 4),
          Text('كراء، خلاص، فاتورة، أداء…',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 18),
          TextField(
            controller: _label,
            style: AppTextStyle.dmSans(),
            decoration: _decoration('الوصف'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            style: AppTextStyle.dmSans(),
            decoration: _decoration('المبلغ (DT)'),
          ),
          const SizedBox(height: 14),
          _chips(
            const {'weekly': 'كل جمعة', 'monthly': 'كل شهر', 'yearly': 'كل عام'},
            _period,
            (v) => setState(() => _period = v),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _categories
                .map((c) => GestureDetector(
                      onTap: () => setState(() => _category = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: _category == c ? AppColors.gold : AppColors.card2,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(c,
                            style: AppTextStyle.dmSans(
                              size: 12,
                              color: _category == c ? Colors.black : AppColors.sub,
                            )),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                final montant =
                    double.tryParse(_amount.text.replaceAll(',', '.'));
                if (_label.text.trim().length < 2 ||
                    montant == null ||
                    montant <= 0) {
                  showAppSnack(context, 'اكتب الوصف والمبلغ');
                  return;
                }
                Navigator.pop(
                  context,
                  _ChargePayload(
                    label: _label.text.trim(),
                    amount: montant,
                    period: _period,
                    category: _category,
                  ),
                );
              },
              child: Text('سجّل',
                  style: AppTextStyle.dmSans(
                      color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chips(
    Map<String, String> options,
    String actif,
    void Function(String) onTap,
  ) {
    return Row(
      children: options.entries.map((e) {
        final active = e.key == actif;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onTap(e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: active ? AppColors.gold : AppColors.card2,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(e.value,
                    style: AppTextStyle.dmSans(
                      size: 12,
                      color: active ? Colors.black : AppColors.sub,
                      weight: active ? FontWeight.w700 : FontWeight.w400,
                    )),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        filled: true,
        fillColor: AppColors.card2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}
