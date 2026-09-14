import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Barre de recherche des salons, partagée par l'accueil et « اكتشف ».
///
/// Chaque icône agit : la loupe lance la recherche, la croix l'efface, et
/// l'épingle — quand l'écran la propose — récupère la position pour trier par
/// distance. Des icônes décoratives dans un champ se font toucher, et un geste
/// qui ne fait rien passe pour une panne.
class SalonSearchField extends StatefulWidget {
  const SalonSearchField({
    super.key,
    required this.query,
    required this.onSearch,
    this.hint = 'ابحث على صالون ولا حجّام...',
    this.onLocate,
    this.locating = false,
    this.located = false,
  });

  /// Recherche en cours, partagée entre les écrans.
  final String query;
  final ValueChanged<String> onSearch;
  final String hint;

  /// Récupérer la position. Sans lui, l'épingle n'est pas affichée.
  final VoidCallback? onLocate;
  final bool locating;

  /// La position est connue : l'épingle passe en doré.
  final bool located;

  @override
  State<SalonSearchField> createState() => _SalonSearchFieldState();
}

class _SalonSearchFieldState extends State<SalonSearchField> {
  late final _ctrl = TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(SalonSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recherche lancée depuis l'autre écran : le champ doit l'afficher, sinon
    // la liste est filtrée par un texte que personne ne voit.
    if (widget.query != oldWidget.query && widget.query != _ctrl.text.trim()) {
      _ctrl.text = widget.query;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    widget.onSearch(_ctrl.text.trim());
  }

  void _clear() {
    _ctrl.clear();
    widget.onSearch('');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        _FieldIcon(
          icon: Icons.search_rounded,
          label: 'ابحث',
          onTap: _submit,
        ),
        Expanded(
          child: TextField(
            controller: _ctrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _submit(),
            style: AppTextStyle.dmSans(size: 14),
            cursorColor: AppColors.gold,
            // Toutes les bordures à zéro : le thème en pose une par défaut, qui
            // dessinait un second cadre à l'intérieur de la barre.
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: AppTextStyle.dmSans(size: 14, color: AppColors.sub),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _ctrl,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : _FieldIcon(
                  icon: Icons.close_rounded,
                  label: 'امسح',
                  onTap: _clear,
                ),
        ),
        if (widget.onLocate != null)
          widget.locating
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.gold),
                  ),
                )
              : _FieldIcon(
                  icon: widget.located
                      ? Icons.my_location_rounded
                      : Icons.location_on_rounded,
                  label: 'موقعي',
                  color: widget.located ? AppColors.gold : AppColors.sub,
                  onTap: widget.onLocate!,
                ),
      ]),
    );
  }
}

/// Icône touchable du champ, avec une zone de 46 px : l'icône seule, 18 px,
/// se rate au pouce.
class _FieldIcon extends StatelessWidget {
  const _FieldIcon({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.sub,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 46,
          height: 50,
          child: Icon(icon, size: 19, color: color),
        ),
      ),
    );
  }
}
