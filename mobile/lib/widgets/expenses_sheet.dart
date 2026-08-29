import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/cash_repository.dart';
import '../state/cash_controller.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Dépenses du salon (§3.4).
///
/// Elles pèsent sur le net du gérant — c'est `net_salon` dans la caisse du
/// jour. Les saisir sans pouvoir les relire ni corriger une faute laissait un
/// chiffre faux dans le P&L, sans moyen de le rattraper.
class ExpensesSheet extends StatefulWidget {
  const ExpensesSheet({super.key, required this.salonId});

  final String salonId;

  static Future<void> show(BuildContext context, String salonId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExpensesSheet(salonId: salonId),
    );
  }

  @override
  State<ExpensesSheet> createState() => _ExpensesSheetState();
}

class _ExpensesSheetState extends State<ExpensesSheet> {
  final _label = TextEditingController();
  final _amount = TextEditingController();

  List<Expense> _expenses = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await context.read<CashRepository>().expenses(widget.salonId);
      if (!mounted) return;
      setState(() { _expenses = rows; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _add() async {
    final label = _label.text.trim();
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (label.isEmpty || amount == null || amount <= 0) {
      showAppSnack(context, 'اكتب الوصف والمبلغ');
      return;
    }

    setState(() => _saving = true);
    // Passe par le contrôleur : la caisse du jour doit se recalculer, sinon le
    // net affiché ne tient pas compte de la dépense qu'on vient de saisir.
    final error = await context.read<CashController>().addExpense(label, amount);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      showAppSnack(context, error);
      return;
    }
    _label.clear();
    _amount.clear();
    await _load();
  }

  Future<void> _remove(Expense expense) async {
    final before = _expenses;
    setState(() => _expenses = _expenses.where((e) => e.id != expense.id).toList());
    try {
      await context.read<CashRepository>().removeExpense(expense.id);
      if (!mounted) return;
      await context.read<CashController>().load();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _expenses = before);
      showAppSnack(context, e.message);
    }
  }

  double get _total => _expenses.fold(0.0, (sum, e) => sum + e.amount);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
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
          Row(children: [
            Text('المصاريف', style: AppTextStyle.playfair(size: 20)),
            const Spacer(),
            if (!_loading && _expenses.isNotEmpty)
              Text('${_total.toStringAsFixed(0)} DT',
                  style: AppTextStyle.dmSans(
                      weight: FontWeight.w700, color: AppColors.red)),
          ]),
          const SizedBox(height: 14),
          _buildForm(),
          const SizedBox(height: 14),
          Flexible(child: _buildList()),
        ]),
      ),
    );
  }

  Widget _buildForm() {
    return Row(children: [
      Expanded(
        flex: 3,
        child: TextField(
          controller: _label,
          style: AppTextStyle.dmSans(size: 13),
          decoration: _decoration('كراء، مواد…'),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          style: AppTextStyle.dmSans(size: 13),
          decoration: _decoration('DT'),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _saving ? null : _add,
        child: Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: _saving
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.black),
                )
              : const Icon(Icons.add_rounded, color: Colors.black),
        ),
      ),
    ]);
  }

  Widget _buildList() {
    if (_loading) return const SizedBox(height: 120, child: AppLoader());
    if (_error != null) {
      return SizedBox(height: 140, child: AppError(message: _error!, onRetry: _load));
    }
    if (_expenses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('ما فماش مصاريف مسجّلة',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _expenses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final expense = _expenses[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(expense.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(weight: FontWeight.w600)),
                if (expense.spentAt != null)
                  Text(
                    '${expense.spentAt!.day.toString().padLeft(2, '0')}/'
                    '${expense.spentAt!.month.toString().padLeft(2, '0')}',
                    style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
                  ),
              ]),
            ),
            Text('-${expense.amount.toStringAsFixed(0)} DT',
                style: AppTextStyle.dmSans(
                    size: 13, weight: FontWeight.w700, color: AppColors.red)),
            GestureDetector(
              onTap: () => _remove(expense),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Icon(Icons.close_rounded, size: 18, color: AppColors.sub),
              ),
            ),
          ]),
        );
      },
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
        filled: true,
        fillColor: AppColors.card2,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}
