import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/repositories/cash_repository.dart';
import '../state/cash_controller.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// L'état du tiroir, et le comptage du soir (§3.4).
///
/// La caisse du jour dit ce qui a été encaissé ; cette feuille dit ce qui doit
/// physiquement se trouver dans le tiroir. Les deux divergent dès qu'une carte
/// bancaire, un achat de produits ou une tséb9a entre en jeu — c'est cette
/// divergence qu'aucun gérant ne suit correctement de tête.
class TreasurySheet extends StatefulWidget {
  const TreasurySheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const TreasurySheet(),
    );
  }

  @override
  State<TreasurySheet> createState() => _TreasurySheetState();
}

class _TreasurySheetState extends State<TreasurySheet> {
  Treasury? _treasury;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await context.read<CashController>().treasury();
    if (!mounted) return;
    setState(() {
      _treasury = data;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),
        Text('🧾 الصندوق', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 4),
        Text('شنوّة لازم يكون في الدرج توّا',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        const SizedBox(height: 16),
        Flexible(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SizedBox(height: 200, child: AppLoader());

    final t = _treasury;
    if (t == null) {
      return SizedBox(
        height: 200,
        child: AppError(
            message: context.read<CashController>().error ?? 'Trésorerie indisponible',
            onRetry: _load),
      );
    }

    return SingleChildScrollView(
      child: Column(children: [
        _buildDrawer(t),
        const SizedBox(height: 14),
        _buildBank(t),
        if (t.movements.isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildMovements(t),
        ],
        const SizedBox(height: 16),
        _buildActions(t),
      ]),
    );
  }

  // ── Le tiroir ────────────────────────────────────────────────────────────
  Widget _buildDrawer(Treasury t) {
    // Un solde négatif n'est pas ramené à zéro : c'est une anomalie réelle
    // (des sorties sans fond de caisse) et le gérant doit la voir.
    final negatif = t.expectedCash < 0;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: negatif
                ? AppColors.red.withValues(alpha: 0.4)
                : AppColors.border),
      ),
      child: Column(children: [
        _line('فلوس البداية', t.openingFloat),
        _line('مداخيل كاش', t.cashIn, positif: true),
        if (t.deposits > 0) _line('زادة فلوس', t.deposits, positif: true),
        if (t.cashExpenses > 0) _line('مصاريف بالكاش', -t.cashExpenses),
        if (t.cashAdvances > 0) _line('تسبيقات معطية', -t.cashAdvances),
        if (t.withdrawals > 0) _line('مسحوب', -t.withdrawals),
        const Divider(color: AppColors.border, height: 22),
        Row(children: [
          Text('لازم يكون في الدرج',
              style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          const Spacer(),
          Text('${t.expectedCash.toStringAsFixed(2)} DT',
              style: AppTextStyle.dmSans(
                  size: 18,
                  weight: FontWeight.w700,
                  color: negatif ? AppColors.red : AppColors.gold)),
        ]),
        if (t.hasVariance) ...[
          const SizedBox(height: 10),
          _buildVariance(t),
        ],
      ]),
    );
  }

  Widget _buildVariance(Treasury t) {
    final manque = t.cashVariance < 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (manque ? AppColors.red : AppColors.gold).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text(manque ? '⚠️ ناقص' : '⚠️ زايد',
            style: AppTextStyle.dmSans(size: 12, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t.varianceReason.isEmpty ? 'بلا سبب مكتوب' : t.varianceReason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
        ),
        Text('${t.cashVariance.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(
                size: 13,
                weight: FontWeight.w700,
                color: manque ? AppColors.red : AppColors.gold)),
      ]),
    );
  }

  // ── La banque ────────────────────────────────────────────────────────────
  Widget _buildBank(Treasury t) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(children: [
        Row(children: [
          Text('🏦 البنكة',
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w700)),
          const Spacer(),
          Text('${t.bankTotal.toStringAsFixed(2)} DT',
              style: AppTextStyle.dmSans(size: 15, weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        if (t.cardTotal > 0) _line('كارط', t.cardTotal, positif: true, petit: true),
        if (t.onlineTotal > 0)
          _line('أونلاين', t.onlineTotal, positif: true, petit: true),
        if (t.bankExpenses > 0) _line('مصاريف بالتحويل', -t.bankExpenses, petit: true),
        const SizedBox(height: 6),
        Text('هالفلوس ما تدخلش للدرج',
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
      ]),
    );
  }

  // ── Les mouvements du jour ───────────────────────────────────────────────
  Widget _buildMovements(Treasury t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('حركات اليوم',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        const SizedBox(height: 8),
        ...t.movements.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(
                  m.isIncoming ? Icons.south_west : Icons.north_east,
                  size: 14,
                  color: m.isIncoming ? AppColors.gold : AppColors.red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.label.isEmpty ? _movementLabel(m.type) : m.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(size: 12),
                  ),
                ),
                Text(
                  '${m.isIncoming ? '+' : '−'}${m.amount.toStringAsFixed(2)} DT',
                  style: AppTextStyle.dmSans(
                      size: 12,
                      color: m.isIncoming ? AppColors.gold : AppColors.red),
                ),
                if (!t.closed)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _removeMovement(m),
                    icon: const Icon(Icons.close, size: 14, color: AppColors.sub),
                  ),
              ]),
            )),
      ],
    );
  }

  /// Une ligne du détail. Le signe porte le sens : un montant négatif est une
  /// sortie, et il s'affiche comme tel plutôt qu'en valeur absolue.
  Widget _line(String label, double montant,
      {bool positif = false, bool petit = false}) {
    final sortie = montant < 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Text(label,
            style: AppTextStyle.dmSans(
                size: petit ? 11 : 12, color: AppColors.sub)),
        const Spacer(),
        Text(
          '${sortie ? '−' : (positif ? '+' : '')}'
          '${montant.abs().toStringAsFixed(2)} DT',
          style: AppTextStyle.dmSans(
            size: petit ? 11 : 12,
            weight: FontWeight.w700,
            color: sortie ? AppColors.red : AppColors.text,
          ),
        ),
      ]),
    );
  }

  String _movementLabel(String type) => switch (type) {
        'opening_float' => 'فلوس البداية',
        'withdrawal' => 'مسحوب',
        _ => 'زادة فلوس',
      };

  // ── Actions ──────────────────────────────────────────────────────────────
  Widget _buildActions(Treasury t) {
    if (t.closed) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(children: [
          Text('اليوم مسكّر',
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('فلوس غدوة : ${t.closingFloat.toStringAsFixed(2)} DT',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        ]),
      );
    }

    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _addMovement('deposit'),
          icon: const Icon(Icons.add, size: 16),
          label: Text('زيد فلوس', style: AppTextStyle.dmSans(size: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () => _addMovement('withdrawal'),
          icon: const Icon(Icons.remove, size: 16),
          label: Text('اسحب', style: AppTextStyle.dmSans(size: 12)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    ]);
  }

  Future<void> _addMovement(String type) async {
    final montant = TextEditingController();
    final motif = TextEditingController();
    final valide = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text(type == 'withdrawal' ? 'اسحب من الصندوق' : 'زيد فلوس للصندوق',
            style: AppTextStyle.playfair(size: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: montant,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            style: AppTextStyle.dmSans(),
            decoration: InputDecoration(
              hintText: 'القيمة بالدينار',
              hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: motif,
            style: AppTextStyle.dmSans(),
            decoration: InputDecoration(
              hintText: type == 'withdrawal' ? 'وين مشات ؟' : 'منين جات ؟',
              hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('رجوع', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('سجّل',
                style: AppTextStyle.dmSans(
                    color: AppColors.gold, weight: FontWeight.w700)),
          ),
        ],
      ),
    );

    final valeur = double.tryParse(montant.text.trim());
    final label = motif.text.trim();
    montant.dispose();
    motif.dispose();
    if (valide != true || !mounted) return;
    if (valeur == null || valeur <= 0) {
      showAppSnack(context, 'قيمة غالطة');
      return;
    }

    final ok = await context
        .read<CashController>()
        .addMovement(type: type, amount: valeur, label: label);
    if (!mounted) return;
    if (!ok) {
      showAppSnack(context, context.read<CashController>().error ?? 'ما تسجّلش');
      return;
    }
    await _load();
  }

  Future<void> _removeMovement(CashMovement m) async {
    try {
      await context.read<CashController>().removeMovementById(m.id);
    } catch (_) {
      if (!mounted) return;
      showAppSnack(context, 'ما تنحّاش');
      return;
    }
    if (!mounted) return;
    await _load();
  }
}
