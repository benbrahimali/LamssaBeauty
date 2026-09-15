import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/env.dart';
import '../data/repositories/cash_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Corriger une dépense et joindre la photo de son ticket (§3.4).
///
/// Une faute de frappe obligeait à supprimer puis ressaisir la dépense, en
/// perdant sa date. Et sans le ticket, personne ne retrouvait ce qu'une
/// dépense « produits » de 45 DT contenait vraiment.
class ExpenseEditSheet extends StatefulWidget {
  const ExpenseEditSheet({super.key, required this.expense});

  final Expense expense;

  static Future<void> show(BuildContext context, Expense expense) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ExpenseEditSheet(expense: expense),
      );

  @override
  State<ExpenseEditSheet> createState() => _ExpenseEditSheetState();
}

class _ExpenseEditSheetState extends State<ExpenseEditSheet> {
  late final _label = TextEditingController(text: widget.expense.label);
  late final _amount = TextEditingController(text: _montant(widget.expense.amount));
  late String _paidFrom = widget.expense.fromDrawer ? 'cash' : 'bank';
  late String? _receipt = widget.expense.receiptUrl;
  bool _saving = false;
  bool _uploading = false;

  static String _montant(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  CashRepository get _repo => context.read<CashRepository>();

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final label = _label.text.trim();
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    if (label.length < 2 || amount == null || amount <= 0) {
      showAppSnack(context, 'اكتب الوصف والمبلغ');
      return;
    }

    setState(() => _saving = true);
    try {
      await _repo.updateExpense(
        widget.expense.id,
        label: label,
        amount: amount,
        paidFrom: _paidFrom,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Journée clôturée, par exemple : le serveur explique pourquoi.
      showAppSnack(context, e.message);
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    showAppSnack(context, 'تبدّل المصروف ✅', success: true);
  }

  Future<void> _attach(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      // Assez pour lire un ticket, sans envoyer 8 Mo en 3G.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final maj = await _repo.uploadReceipt(widget.expense.id, File(picked.path));
      if (mounted) setState(() => _receipt = maj.receiptUrl);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeReceipt() async {
    try {
      await _repo.removeReceipt(widget.expense.id);
      if (mounted) setState(() => _receipt = null);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }

  void _view() {
    final url = _receipt;
    if (url == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          // Pincer pour lire un total écrit en petit.
          InteractiveViewer(
            maxScale: 5,
            child: CachedNetworkImage(
              imageUrl: Env.mediaUrl(url),
              fit: BoxFit.contain,
              placeholder: (_, __) =>
                  const SizedBox(height: 240, child: AppLoader()),
              errorWidget: (_, __, ___) => const SizedBox(
                height: 200,
                child: Icon(Icons.broken_image_outlined, color: AppColors.sub),
              ),
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: IconButton(
              tooltip: 'سكّر',
              onPressed: () => Navigator.of(ctx).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
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
            Text('تبديل المصروف', style: AppTextStyle.playfair(size: 20)),
            const SizedBox(height: 18),
            TextField(
              controller: _label,
              style: AppTextStyle.dmSans(),
              decoration: _decoration('الوصف'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              style: AppTextStyle.dmSans(),
              decoration: _decoration('المبلغ (DT)'),
            ),
            const SizedBox(height: 12),
            _buildSource(),
            const SizedBox(height: 18),
            _buildReceipt(),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text('سجّل التبديل',
                        style: AppTextStyle.dmSans(
                            color: Colors.black, weight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildSource() {
    return Row(children: [
      Text('خلّصت بـ', style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
      const SizedBox(width: 10),
      for (final (code, label) in const [('cash', 'كاش'), ('bank', 'تحويل')])
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: GestureDetector(
            onTap: () => setState(() => _paidFrom = code),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: _paidFrom == code
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _paidFrom == code ? AppColors.gold : AppColors.border),
              ),
              child: Text(label,
                  style: AppTextStyle.dmSans(
                      size: 12,
                      color: _paidFrom == code ? AppColors.gold : AppColors.sub,
                      weight: _paidFrom == code ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
        ),
    ]);
  }

  Widget _buildReceipt() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('🧾 التيكيه', style: AppTextStyle.dmSans(weight: FontWeight.w700)),
        const SizedBox(height: 10),
        if (_receipt != null) ...[
          GestureDetector(
            onTap: _view,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: Env.mediaUrl(_receipt!),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => const SizedBox(height: 150, child: AppLoader()),
                errorWidget: (_, __, ___) => const SizedBox(
                  height: 150,
                  child: Icon(Icons.broken_image_outlined, color: AppColors.sub),
                ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _removeReceipt,
              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.red),
              label: Text('نحّي التيكيه',
                  style: AppTextStyle.dmSans(size: 12, color: AppColors.red)),
            ),
          ),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('ما فماش تيكيه — صوّرو باش يبقى أثر للمحاسب',
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          ),
        if (_uploading)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: LinearProgressIndicator(color: AppColors.gold, backgroundColor: AppColors.card),
          ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : () => _attach(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_rounded, size: 16),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_receipt == null ? 'صوّر التيكيه' : 'صوّر من جديد',
                    style: AppTextStyle.dmSans(size: 12)),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _uploading ? null : () => _attach(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_rounded, size: 16),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('من الغاليري', style: AppTextStyle.dmSans(size: 12)),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.text,
                side: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ]),
      ]),
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
