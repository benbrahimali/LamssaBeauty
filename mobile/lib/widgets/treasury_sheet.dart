import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/repositories/cash_repository.dart';
import '../state/cash_controller.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';
import 'prompt_dialog.dart';

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
    final media = MediaQuery.of(context);
    // Le clavier recouvre la feuille sans réduire l'écran : plafonner à 88 %
    // de la hauteur totale la ferait déborder sous les touches. On plafonne à
    // ce qui reste réellement visible, et on rend la marge basse au clavier.
    final clavier = media.viewInsets.bottom;
    final disponible = media.size.height - clavier;

    // La marge du clavier va à l'extérieur du plafond de hauteur : à
    // l'intérieur, elle mangerait la place réservée au contenu.
    return Padding(
      padding: EdgeInsets.only(bottom: clavier),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        constraints: BoxConstraints(maxHeight: disponible * 0.88),
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
      ),
    );
  }

  /// Le corps est toujours défilable, y compris pendant le chargement.
  ///
  /// Une hauteur figée pour l'indicateur déborde dès que la place manque —
  /// petit écran, police système agrandie, clavier ouvert — et un débordement
  /// pendant le chargement corrompt l'arbre avant même que les données
  /// arrivent.
  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: AppLoader(),
        ),
      );
    }

    final t = _treasury;
    if (t == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: AppError(
              message: context.read<CashController>().error ??
                  'Trésorerie indisponible',
              onRetry: _load),
        ),
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
        _buildOpening(t),
        _line('مداخيل كاش', t.cashIn, positif: true),
        if (t.deposits > 0) _line('زادة فلوس', t.deposits, positif: true),
        if (t.cashExpenses > 0) _line('مصاريف بالكاش', -t.cashExpenses),
        if (t.cashAdvances > 0) _line('تسبيقات معطية', -t.cashAdvances),
        if (t.withdrawals > 0) _line('مسحوب', -t.withdrawals),
        const Divider(color: AppColors.border, height: 22),
        Row(children: [
          Expanded(
            child: Text('لازم يكون في الدرج',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
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
        color:
            (manque ? AppColors.red : AppColors.gold).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Text(manque ? '⚠️ ناقص' : '⚠️ زايد',
            style: AppTextStyle.dmSans(size: 12, weight: FontWeight.w700)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            t.varianceReason.isEmpty ? 'بلا سبب مكتوب' : t.varianceReason,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
        ),
        const SizedBox(width: 8),
        Text('${t.cashVariance.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(
                size: 13,
                weight: FontWeight.w700,
                color: manque ? AppColors.red : AppColors.gold)),
      ]),
    );
  }

  // ── Le fond de caisse ────────────────────────────────────────────────────
  /// Reporté de la veille, ou corrigé par le gérant.
  ///
  /// Modifiable tant que la journée n'est pas clôturée. Une correction ne
  /// cache jamais l'écart avec la veille : un tiroir qui a changé pendant la
  /// nuit doit se voir, pas se corriger en silence.
  Widget _buildOpening(Treasury t) {
    final ecart = openingGapLabel(t.openingGap);
    final ligne = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Text(
            t.openingDeclared ? 'فلوس البداية (مصرّح بيها)' : 'فلوس البداية',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
          ),
        ),
        const SizedBox(width: 10),
        Text('${t.openingFloat.toStringAsFixed(2)} DT',
            style: AppTextStyle.dmSans(size: 12, weight: FontWeight.w700)),
        if (!t.closed) ...[
          const SizedBox(width: 6),
          const Icon(Icons.edit_rounded, size: 14, color: AppColors.gold),
        ],
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (t.closed)
        ligne
      else
        Semantics(
          button: true,
          label: 'بدّل فلوس البداية',
          child: InkWell(
            onTap: () => _editOpening(t),
            borderRadius: BorderRadius.circular(8),
            child: ligne,
          ),
        ),
      if (ecart.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '⚠️ $ecart',
            style: AppTextStyle.dmSans(
                size: 11,
                color: t.openingGap < 0 ? AppColors.red : AppColors.gold),
          ),
        ),
    ]);
  }

  Future<void> _editOpening(Treasury t) async {
    final saisie = await PromptDialog.show(
      context,
      title: 'فلوس البداية',
      message: t.carriedFloat > 0
          ? 'شحال فمّا في الدرج كي حلّيت ؟ البارح بقات '
              '${t.carriedFloat.toStringAsFixed(2)} DT'
          : 'شحال فمّا في الدرج كي حلّيت ؟',
      fields: [
        PromptField(
          name: 'montant',
          hint: 'القيمة بالدينار',
          initial: t.openingFloat.toStringAsFixed(2),
          numeric: true,
          autofocus: true,
        ),
      ],
      neutralLabel: t.openingDeclared ? 'رجّع مبلغ البارح' : null,
    );
    if (saisie == null || !mounted) return;
    final cash = context.read<CashController>();

    if (saisie.neutral) {
      final id = t.openingMovementId;
      if (id == null) return;
      final ok = await cash.removeMovementById(id);
      if (!mounted) return;
      if (!ok) {
        showAppSnack(context, cash.error ?? 'ما تبدّلش');
        return;
      }
      await _load();
      return;
    }

    final valeur = saisie.number('montant');
    // Zéro est une vraie réponse : le tiroir peut ouvrir vide.
    if (valeur == null || valeur < 0) {
      showAppSnack(context, 'قيمة غالطة');
      return;
    }
    final ok = await cash.addMovement(type: 'opening_float', amount: valeur);
    if (!mounted) return;
    if (!ok) {
      showAppSnack(context, cash.error ?? 'ما تسجّلش');
      return;
    }
    await _load();
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
          Expanded(
            child: Text('🏦 البنكة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text('${t.bankTotal.toStringAsFixed(2)} DT',
              style: AppTextStyle.dmSans(size: 15, weight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        if (t.cardTotal > 0)
          _line('كارط', t.cardTotal, positif: true, petit: true),
        if (t.onlineTotal > 0)
          _line('أونلاين', t.onlineTotal, positif: true, petit: true),
        if (t.bankExpenses > 0)
          _line('مصاريف بالتحويل', -t.bankExpenses, petit: true),
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
                const SizedBox(width: 8),
                Text(
                  '${m.isIncoming ? '+' : '−'}${m.amount.toStringAsFixed(2)} DT',
                  style: AppTextStyle.dmSans(
                      size: 12,
                      color: m.isIncoming ? AppColors.gold : AppColors.red),
                ),
                if (!t.closed)
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _removeMovement(m),
                    icon:
                        const Icon(Icons.close, size: 14, color: AppColors.sub),
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
        // Le libellé cède la place, jamais le montant : un chiffre tronqué
        // serait pire qu'un mot tronqué. Sans cette souplesse la ligne déborde
        // dès qu'un montant atteint quatre chiffres ou que la police système
        // est agrandie.
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(
                  size: petit ? 11 : 12, color: AppColors.sub)),
        ),
        const SizedBox(width: 10),
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
          label: Text('زيد فلوس',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 12)),
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
          label: Text('اسحب',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 12)),
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
    final retrait = type == 'withdrawal';
    final saisie = await PromptDialog.show(
      context,
      title: retrait ? 'اسحب من الصندوق' : 'زيد فلوس للصندوق',
      fields: [
        const PromptField(
          name: 'montant',
          hint: 'القيمة بالدينار',
          numeric: true,
          autofocus: true,
        ),
        PromptField(
          name: 'motif',
          hint: retrait ? 'وين مشات ؟' : 'منين جات ؟',
        ),
      ],
    );
    if (saisie == null || !mounted) return;

    final valeur = saisie.number('montant');
    if (valeur == null || valeur <= 0) {
      showAppSnack(context, 'قيمة غالطة');
      return;
    }

    final ok = await context.read<CashController>().addMovement(
          type: type,
          amount: valeur,
          label: saisie['motif'],
        );
    if (!mounted) return;
    if (!ok) {
      showAppSnack(
          context, context.read<CashController>().error ?? 'ما تسجّلش');
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

/// Écart du fond de caisse avec ce que la veille a laissé, en clair.
/// Vide quand il n'y en a pas.
String openingGapLabel(double gap) {
  if (gap.abs() < 0.01) return '';
  final montant = gap.abs().toStringAsFixed(2);
  return gap < 0
      ? '$montant DT أقل من اللي بقى البارح'
      : '$montant DT أكثر من اللي بقى البارح';
}
