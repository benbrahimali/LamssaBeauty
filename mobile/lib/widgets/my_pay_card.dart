import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/cash_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Ce que le coiffeur touchera cette semaine (§3.4).
///
/// Sa première question en fin de semaine, et jusque-là il n'avait aucune
/// réponse dans l'app : seule la caisse du jour lui était montrée.
class MyPayCard extends StatelessWidget {
  const MyPayCard({super.key, required this.week, this.month, this.onTap});

  final PayrollLine? week;
  final MonthBalance? month;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final w = week;
    if (w == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text('💰 خلاصي هالأسبوع',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_left, size: 18, color: AppColors.sub),
            ]),
            const SizedBox(height: 12),
            PayWeekSummary(week: w),
            if (month != null) ...[
              const SizedBox(height: 10),
              Text(
                'هالشهر : ${month!.earnedWithTips.toStringAsFixed(2)} DT مكسوب'
                ' · ${month!.paid.toStringAsFixed(2)} DT وصلك',
                maxLines: 2,
                style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Le détail d'une semaine de paie, vu par le coiffeur.
class PayWeekSummary extends StatelessWidget {
  const PayWeekSummary({super.key, required this.week});

  final PayrollLine week;

  @override
  Widget build(BuildContext context) {
    final (libelle, montant, couleur) = switch (week) {
      // Il a pris plus d'avance qu'il n'a gagné : il doit au salon, et le
      // masquer laisserait croire que le compte est soldé.
      final w when w.remaining < 0 =>
        ('عليك للصالون', -w.remaining, AppColors.red),
      final w when w.fullyPaid => ('✅ وصلك الخلاص كامل', w.paid, AppColors.green),
      final w => ('باقي ليك', w.remaining, AppColors.gold),
    };

    return Column(children: [
      Row(children: [
        Expanded(
          child: Text(libelle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 13, color: couleur, weight: FontWeight.w600)),
        ),
        const SizedBox(width: 10),
        Text('${montant.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(size: 20, weight: FontWeight.w700, color: couleur)),
      ]),
      const Divider(color: AppColors.border, height: 20),
      _ligne('حصّتي + البقشيش', week.earned + week.tips),
      if (week.advances > 0) _ligne('تسبيقات', -week.advances),
      if (week.paid > 0) _ligne('وصلني', -week.paid),
    ]);
  }

  Widget _ligne(String label, double valeur) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          ),
          const SizedBox(width: 10),
          Text(
            '${valeur < 0 ? '−' : ''}${valeur.abs().toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(
                size: 12,
                weight: FontWeight.w700,
                color: valeur < 0 ? AppColors.red : AppColors.text),
          ),
        ]),
      );
}

/// Ses semaines de paie, une à une, avec les versements reçus et le mois.
class MyPaySheet extends StatefulWidget {
  const MyPaySheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const MyPaySheet(),
      );

  @override
  State<MyPaySheet> createState() => _MyPaySheetState();
}

class _MyPaySheetState extends State<MyPaySheet> {
  /// Semaine consultée : 0 = celle en cours, -1 = la précédente.
  int _offset = 0;
  PayrollLine? _week;
  MonthBalance? _month;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final jour = DateTime.now().add(Duration(days: 7 * _offset));
    final depot = context.read<CashRepository>();
    try {
      final semaine = await depot.myPayroll(weekOf: jour);
      final mois = await depot.myBalance(year: jour.year, month: jour.month);
      if (!mounted) return;
      setState(() {
        _week = semaine;
        _month = mois;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  void _changer(int delta) {
    setState(() => _offset += delta);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
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
        Text('💰 خلاصي', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            tooltip: 'الأسبوع اللي فات',
            onPressed: () => _changer(-1),
            icon: const Icon(Icons.chevron_left, color: AppColors.sub),
          ),
          Flexible(
            child: Text(
              _week == null ? '…' : '${_week!.weekStart} → ${_week!.weekEnd}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
            ),
          ),
          IconButton(
            tooltip: 'الأسبوع اللي بعدو',
            // Pas de semaine future : rien n'y est encore gagné.
            onPressed: _offset >= 0 ? null : () => _changer(1),
            icon: Icon(Icons.chevron_right,
                color: _offset >= 0 ? AppColors.border : AppColors.sub),
          ),
        ]),
        const SizedBox(height: 10),
        Flexible(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(
        child: Padding(padding: EdgeInsets.symmetric(vertical: 50), child: AppLoader()),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(child: AppError(message: _error!, onRetry: _load));
    }
    final w = _week!;
    final m = _month;

    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: PayWeekSummary(week: w),
        ),
        const SizedBox(height: 14),
        Text('الخلاص اللي وصلني',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        const SizedBox(height: 6),
        if (w.payouts.isEmpty)
          Text('مازال ما وصلك شي هالأسبوع',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub))
        else
          for (final p in w.payouts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(p.fromDrawer ? Icons.payments_rounded : Icons.account_balance_rounded,
                    size: 16, color: AppColors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${p.fromDrawer ? 'كاش' : 'تحويل'}'
                    '${p.day.isEmpty ? '' : ' · ${p.day}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(size: 12),
                  ),
                ),
                Text('${p.amount.toStringAsFixed(2)} DT',
                    style: AppTextStyle.dmSans(
                        size: 12, weight: FontWeight.w700, color: AppColors.green)),
              ]),
            ),
        if (m != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              _moisLigne('📅 الشهر ${m.period}', '${m.services} قصّة'),
              _moisLigne('مكسوب (حصّة + بقشيش)', '${m.earnedWithTips.toStringAsFixed(2)} DT'),
              if (m.advances > 0)
                _moisLigne('تسبيقات', '−${m.advances.toStringAsFixed(2)} DT'),
              _moisLigne('وصلني هالشهر', '${m.paid.toStringAsFixed(2)} DT'),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _moisLigne(String label, String valeur) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          ),
          const SizedBox(width: 10),
          Text(valeur, style: AppTextStyle.dmSans(size: 12, weight: FontWeight.w700)),
        ]),
      );
}
