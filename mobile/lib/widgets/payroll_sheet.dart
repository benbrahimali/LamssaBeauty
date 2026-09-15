import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/cash_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Paie de la semaine, coiffeur par coiffeur (§3.4).
///
/// C'est la feuille que le gérant a en main le jour de la paie. Le chiffre qui
/// compte n'est pas ce qui a été gagné mais ce qui reste à donner : les
/// tséb9as accordées dans la semaine sont déjà déduites.
class PayrollSheet extends StatefulWidget {
  const PayrollSheet({super.key, required this.salonId, this.onChanged});

  final String salonId;

  /// Appelé après un versement ou une annulation : la caisse du jour doit
  /// refléter l'argent sorti du tiroir.
  final VoidCallback? onChanged;

  static Future<void> show(BuildContext context, String salonId,
      {VoidCallback? onChanged}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PayrollSheet(salonId: salonId, onChanged: onChanged),
    );
  }

  @override
  State<PayrollSheet> createState() => _PayrollSheetState();
}

class _PayrollSheetState extends State<PayrollSheet> {
  Payroll? _payroll;
  bool _loading = true;
  String? _error;

  /// Semaine consultée : 0 = celle en cours, -1 = la précédente.
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await context.read<CashRepository>().payroll(
            widget.salonId,
            weekOf: DateTime.now().add(Duration(days: 7 * _offset)),
          );
      if (!mounted) return;
      setState(() { _payroll = data; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
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
        Text('💰 خلاص الأسبوع', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 10),
        _buildWeekPicker(),
        const SizedBox(height: 14),
        Flexible(child: _buildBody()),
      ]),
    );
  }

  Widget _buildWeekPicker() {
    final p = _payroll;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      IconButton(
        onPressed: () {
          setState(() => _offset -= 1);
          _load();
        },
        icon: const Icon(Icons.chevron_left, color: AppColors.sub),
      ),
      // Les dates cèdent la place, jamais les flèches : sans cela la ligne
      // déborde avec une police agrandie.
      Flexible(
        child: Text(
          p == null ? '…' : '${p.weekStart} → ${p.weekEnd}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
        ),
      ),
      IconButton(
        // Pas de semaine future : il n'y a rien à y payer.
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

  Widget _buildBody() {
    if (_loading) return const SizedBox(height: 160, child: AppLoader());
    if (_error != null) {
      return SizedBox(height: 180, child: AppError(message: _error!, onRetry: _load));
    }

    final payroll = _payroll!;
    final lignes = payroll.active;
    if (lignes.isEmpty) {
      return const AppEmpty(
        emoji: '📭',
        title: 'ما فماش خدمة هالأسبوع',
        subtitle: 'لا قصّات، لا تسبيقات',
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: lignes.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _PayrollRow(
            line: lignes[i],
            onPay: () => _pay(lignes[i]),
            onCancel: _cancel,
          ),
        ),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          _total('مجموع المكاسب', payroll.totalEarned, AppColors.text),
          const SizedBox(height: 6),
          _total('التسبيقات المعطاة', -payroll.totalAdvances, AppColors.red),
          if (payroll.totalPaid > 0) ...[
            const SizedBox(height: 6),
            _total('تخلّص', -payroll.totalPaid, AppColors.green),
          ],
          const Divider(color: AppColors.border, height: 18),
          _total('الباقي للخلاص', payroll.totalRemaining, AppColors.gold, fort: true),
        ]),
      ),
    ]);
  }

  DateTime get _weekOf => DateTime.now().add(Duration(days: 7 * _offset));

  /// Remet à un coiffeur ce qui lui reste dû, en choisissant d'où sort
  /// l'argent : le tiroir se vide, un virement non.
  Future<void> _pay(PayrollLine line) async {
    final nom = line.name.isEmpty ? 'الحجّام' : line.name;
    final source = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('خلّص $nom ؟', style: AppTextStyle.playfair(size: 18)),
        content: Text(
          '${line.remaining.toStringAsFixed(2)} DT — منين تخرج الفلوس ؟',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('رجوع', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'bank'),
            child: Text('بتحويل', style: AppTextStyle.dmSans(color: AppColors.text)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cash'),
            child: Text('من الدرج',
                style: AppTextStyle.dmSans(
                    color: AppColors.gold, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (source == null || !mounted) return;

    try {
      await context.read<CashRepository>().payStaff(
            salonId: widget.salonId,
            staffId: line.staffId,
            weekOf: _weekOf,
            paidFrom: source,
          );
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
      return;
    }
    if (!mounted) return;
    showAppSnack(context, 'تخلّص $nom ✅', success: true);
    widget.onChanged?.call();
    await _load();
  }

  Future<void> _cancel(PayrollPayout payout) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('نحّي هالخلاص ؟', style: AppTextStyle.playfair(size: 18)),
        content: Text(
          '${payout.amount.toStringAsFixed(2)} DT'
          '${payout.fromDrawer ? ' يرجعو للدرج' : ''}',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('لا', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم',
                style: AppTextStyle.dmSans(
                    color: AppColors.red, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await context.read<CashRepository>().cancelPayout(payout.id);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
      return;
    }
    if (!mounted) return;
    widget.onChanged?.call();
    await _load();
  }

  Widget _total(String label, double valeur, Color couleur, {bool fort = false}) {
    return Row(children: [
      // Le libellé cède la place, jamais le montant : sans élément flexible,
      // un `Spacer` tombe à zéro et les deux textes débordent dès que la
      // police système est agrandie.
      Expanded(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.dmSans(
                size: fort ? 14 : 12,
                color: fort ? AppColors.text : AppColors.sub,
                weight: fort ? FontWeight.w700 : FontWeight.w400)),
      ),
      const SizedBox(width: 10),
      Text('${valeur.toStringAsFixed(2)} DT',
          style: AppTextStyle.dmSans(
              size: fort ? 16 : 13, color: couleur, weight: FontWeight.w700)),
    ]);
  }
}

class _PayrollRow extends StatelessWidget {
  const _PayrollRow({required this.line, this.onPay, this.onCancel});

  final PayrollLine line;
  final VoidCallback? onPay;
  final void Function(PayrollPayout)? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text(line.name.isEmpty ? 'حجّام' : line.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          ),
          Text(
            '${line.balance.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(
              size: 15,
              weight: FontWeight.w700,
              // Un solde négatif se lit d'un coup d'œil : l'employé doit encore
              // au salon, il n'y a rien à lui remettre cette semaine.
              color: line.owesSalon ? AppColors.red : AppColors.gold,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Passe à la ligne au lieu de déborder : quatre détails ne tiennent
        // pas sur un petit écran ou avec une police agrandie.
        Wrap(runSpacing: 4, children: [
          _detail('${line.services} قصّة'),
          _detail('حصّتو ${line.earned.toStringAsFixed(0)}'),
          if (line.tips > 0) _detail('بقشيش ${line.tips.toStringAsFixed(0)}'),
          if (line.advances > 0)
            _detail('تسبيق ${line.advances.toStringAsFixed(0)}', rouge: true),
        ]),
        // L'historique des versements : sans lui, rien ne dit qui a déjà été
        // payé, et la même semaine se paie deux fois.
        for (final p in line.payouts)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Icon(
                p.fromDrawer
                    ? Icons.payments_rounded
                    : Icons.account_balance_rounded,
                size: 14,
                color: AppColors.green,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'تخلّص ${p.amount.toStringAsFixed(2)} DT · '
                  '${p.fromDrawer ? 'من الدرج' : 'بتحويل'}'
                  '${p.day.isEmpty ? '' : ' · ${p.day}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.dmSans(size: 11, color: AppColors.green),
                ),
              ),
              if (onCancel != null)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'نحّي هالخلاص',
                  onPressed: () => onCancel!(p),
                  icon: const Icon(Icons.close, size: 14, color: AppColors.sub),
                ),
            ]),
          ),
        if (line.canPay && onPay != null) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton.icon(
              onPressed: onPay,
              icon: const Icon(Icons.payments_rounded, size: 16),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  line.paid > 0
                      ? 'خلّص الباقي ${line.remaining.toStringAsFixed(2)} DT'
                      : 'خلّص ${line.remaining.toStringAsFixed(2)} DT',
                  style: AppTextStyle.dmSans(
                      size: 13, weight: FontWeight.w700, color: Colors.black),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ] else if (line.fullyPaid) ...[
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('✅ تخلّص كامل',
                style: AppTextStyle.dmSans(
                    size: 12, weight: FontWeight.w700, color: AppColors.green)),
          ),
        ],
      ]),
    );
  }

  Widget _detail(String texte, {bool rouge = false}) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 10),
        child: Text(texte,
            style: AppTextStyle.dmSans(
                size: 11, color: rouge ? AppColors.red : AppColors.sub)),
      );
}
