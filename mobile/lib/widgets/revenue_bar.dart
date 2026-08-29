import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Une barre du graphique de recettes hebdomadaires (§3.4).
///
/// La barre prend ce qui reste après les deux libellés, au lieu d'une hauteur
/// figée : deux lignes de texte plus 90 px de barre réclamaient 131 px dans
/// une boîte de 130 — d'où « A RenderFlex overflowed by 1.00 pixels » — et le
/// moindre agrandissement de police aggravait l'écart.
class RevenueBar extends StatelessWidget {
  const RevenueBar({
    super.key,
    required this.value,
    required this.ratio,
    required this.label,
  });

  /// Montant du jour, affiché au-dessus de la barre.
  final double value;

  /// Part du plus haut montant de la semaine, entre 0 et 1.
  final double ratio;

  /// Jour du mois, sous la barre.
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text(value.toStringAsFixed(0),
          style: GoogleFonts.dmSans(
            fontSize: 9,
            color: AppColors.gold,
            fontWeight: FontWeight.w700,
          )),
      const SizedBox(height: 4),
      Expanded(
        child: FractionallySizedBox(
          alignment: Alignment.bottomCenter,
          // Un plancher visible : une journée à zéro doit rester lisible
          // comme une barre, pas disparaître.
          heightFactor: ratio.clamp(0.05, 1.0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 600),
            width: 24,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(label,
          style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
    ]);
  }
}
