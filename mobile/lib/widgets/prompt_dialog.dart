import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Un champ de saisie d'un [PromptDialog].
class PromptField {
  const PromptField({
    required this.name,
    this.hint = '',
    this.label = '',
    this.helper = '',
    this.initial = '',
    this.numeric = false,
    this.autofocus = false,
  });

  /// Clé de lecture dans le [PromptResult].
  final String name;
  final String hint;
  final String label;
  final String helper;
  final String initial;

  /// Chiffres et séparateur décimal uniquement.
  final bool numeric;
  final bool autofocus;
}

/// Ce que l'utilisateur a saisi, ou l'action neutre s'il l'a choisie.
class PromptResult {
  const PromptResult(this.values, {this.neutral = false});

  final Map<String, String> values;

  /// Vrai quand l'action secondaire a été utilisée (« retirer l'objectif »…).
  final bool neutral;

  String operator [](String name) => (values[name] ?? '').trim();

  /// Le champ lu comme un nombre, virgule tunisienne tolérée. Null si vide ou
  /// illisible — l'appelant décide si c'est une erreur ou une absence.
  double? number(String name) {
    final brut = this[name].replaceAll(',', '.');
    return brut.isEmpty ? null : double.tryParse(brut);
  }
}

/// Boîte de saisie courte, qui possède ses propres contrôleurs.
///
/// C'est tout l'intérêt : un `TextEditingController` créé dans une méthode
/// puis libéré juste après `await showDialog` est encore utilisé pendant
/// l'animation de fermeture. Le résultat est un « TextEditingController was
/// used after being disposed », suivi d'un arbre de widgets corrompu —
/// GlobalKeys dupliquées, overflow aberrant, écran rouge. En confiant les
/// contrôleurs à l'état d'un widget de la route, le framework les libère
/// seulement quand la route a réellement disparu.
class PromptDialog extends StatefulWidget {
  const PromptDialog({
    super.key,
    required this.title,
    required this.fields,
    this.message = '',
    this.confirmLabel = 'سجّل',
    this.cancelLabel = 'رجوع',
    this.neutralLabel,
  });

  final String title;
  final List<PromptField> fields;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final String? neutralLabel;

  static Future<PromptResult?> show(
    BuildContext context, {
    required String title,
    required List<PromptField> fields,
    String message = '',
    String confirmLabel = 'سجّل',
    String cancelLabel = 'رجوع',
    String? neutralLabel,
  }) {
    return showDialog<PromptResult>(
      context: context,
      builder: (_) => PromptDialog(
        title: title,
        fields: fields,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        neutralLabel: neutralLabel,
      ),
    );
  }

  @override
  State<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      f.name: TextEditingController(text: f.initial),
  };

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  PromptResult _collect({bool neutral = false}) => PromptResult(
        {for (final e in _controllers.entries) e.key: e.value.text},
        neutral: neutral,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title, style: AppTextStyle.playfair(size: 17)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (widget.message.isNotEmpty) ...[
            Text(widget.message,
                style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
            const SizedBox(height: 12),
          ],
          for (final f in widget.fields) ...[
            TextField(
              controller: _controllers[f.name],
              autofocus: f.autofocus,
              keyboardType: f.numeric
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              inputFormatters: f.numeric
                  ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]
                  : null,
              style: AppTextStyle.dmSans(),
              decoration: InputDecoration(
                labelText: f.label.isEmpty ? null : f.label,
                labelStyle: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
                hintText: f.hint.isEmpty ? null : f.hint,
                hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
                helperText: f.helper.isEmpty ? null : f.helper,
                helperStyle: AppTextStyle.dmSans(size: 10, color: AppColors.sub),
              ),
            ),
            if (f != widget.fields.last) const SizedBox(height: 10),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel,
              style: AppTextStyle.dmSans(color: AppColors.sub)),
        ),
        if (widget.neutralLabel != null)
          TextButton(
            onPressed: () => Navigator.pop(context, _collect(neutral: true)),
            child: Text(widget.neutralLabel!,
                style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, _collect()),
          child: Text(widget.confirmLabel,
              style: AppTextStyle.dmSans(
                  color: AppColors.gold, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}
