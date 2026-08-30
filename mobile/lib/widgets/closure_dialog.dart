import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Ce que le gérant a déclaré au moment de fermer sa journée.
class ClosureInput {
  const ClosureInput({this.countedCash, this.withdrawal = 0, this.reason = ''});

  /// Null quand le tiroir n'a pas été compté — l'app n'affiche alors aucun
  /// écart plutôt qu'un zéro inventé.
  final double? countedCash;
  final double withdrawal;
  final String reason;
}

/// Comptage du tiroir avant clôture (§3.4).
///
/// Possède ses contrôleurs : ils sont libérés par le framework quand la route
/// disparaît, et non pendant l'animation de fermeture où les champs sont
/// encore reconstruits.
class ClosureDialog extends StatefulWidget {
  const ClosureDialog({super.key, required this.expectedCash});

  final double expectedCash;

  static Future<ClosureInput?> show(BuildContext context, double expectedCash) {
    return showDialog<ClosureInput>(
      context: context,
      builder: (_) => ClosureDialog(expectedCash: expectedCash),
    );
  }

  @override
  State<ClosureDialog> createState() => _ClosureDialogState();
}

class _ClosureDialogState extends State<ClosureDialog> {
  final _compte = TextEditingController();
  final _preleve = TextEditingController();
  final _motif = TextEditingController();

  @override
  void dispose() {
    _compte.dispose();
    _preleve.dispose();
    _motif.dispose();
    super.dispose();
  }

  double? get _saisi {
    final brut = _compte.text.trim().replaceAll(',', '.');
    return brut.isEmpty ? null : double.tryParse(brut);
  }

  @override
  Widget build(BuildContext context) {
    final compte = _saisi;
    final ecart = compte == null ? null : compte - widget.expectedCash;

    return AlertDialog(
      backgroundColor: AppColors.card2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('سكّر اليوم ؟', style: AppTextStyle.playfair(size: 18)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Text('لازم يكون في الدرج',
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
            const Spacer(),
            Text('${widget.expectedCash.toStringAsFixed(2)} DT',
                style: AppTextStyle.dmSans(
                    size: 14,
                    weight: FontWeight.w700,
                    color: AppColors.gold)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _compte,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            onChanged: (_) => setState(() {}),
            style: AppTextStyle.dmSans(),
            decoration: InputDecoration(
              labelText: 'عدّيت قدّاش ؟ (اختياري)',
              labelStyle: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
            ),
          ),
          if (ecart != null && ecart.abs() >= 0.01) ...[
            const SizedBox(height: 8),
            Row(children: [
              Text(ecart < 0 ? '⚠️ ناقص' : '⚠️ زايد',
                  style:
                      AppTextStyle.dmSans(size: 12, weight: FontWeight.w700)),
              const Spacer(),
              Text('${ecart.toStringAsFixed(2)} DT',
                  style: AppTextStyle.dmSans(
                      size: 13,
                      weight: FontWeight.w700,
                      color: ecart < 0 ? AppColors.red : AppColors.gold)),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: _motif,
              style: AppTextStyle.dmSans(),
              decoration: InputDecoration(
                labelText: 'علاش ؟',
                labelStyle: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _preleve,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            style: AppTextStyle.dmSans(),
            decoration: InputDecoration(
              labelText: 'شنوّة باش تاخذ معاك ؟ (اختياري)',
              labelStyle: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
              helperText: 'الباقي يولّي فلوس البداية متاع غدوة',
              helperStyle: AppTextStyle.dmSans(size: 10, color: AppColors.sub),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'الخدمة متاع اليوم باش تتقفل والتسبيقات باش تتنقّص. ما فماش رجوع.',
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('رجوع', style: AppTextStyle.dmSans(color: AppColors.sub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            ClosureInput(
              countedCash: _saisi,
              withdrawal:
                  double.tryParse(_preleve.text.trim().replaceAll(',', '.')) ??
                      0,
              reason: _motif.text.trim(),
            ),
          ),
          child: Text('سكّر',
              style: AppTextStyle.dmSans(
                  color: AppColors.gold, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}
