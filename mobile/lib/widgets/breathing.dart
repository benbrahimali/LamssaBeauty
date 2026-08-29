import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Respiration partagée par le splash et l'onboarding.
///
/// Un `Interval` sur un contrôleur en aller-retour retarde le *départ* d'un
/// anneau mais le fait culminer en même temps que les autres : un zoom
/// retardé, pas une onde. Une phase sur une sinusoïde décale réellement le
/// sommet, et la fonction se referme sur elle-même — aucun à-coup au bouclage.
double breath(double t, {double phase = 0}) =>
    0.5 - 0.5 * math.cos(2 * math.pi * (t + phase));

/// Durée d'un cycle : le rythme d'une respiration calme. Plus rapide, l'écran
/// devient nerveux au lieu d'être accueillant.
const breathingCycle = Duration(milliseconds: 3200);

/// Amplitude maximale. Au-delà, l'œil lit un rebond plutôt qu'un souffle — et
/// un écran d'accueil qui rebondit fait bon marché.
const breathingAmplitude = 0.055;

/// Un anneau qui respire : il grandit un peu, et sa lumière monte avec lui.
class BreathingRing extends StatelessWidget {
  const BreathingRing({
    super.key,
    required this.controller,
    required this.size,
    required this.restOpacity,
    this.phase = 0,
    this.amplitude = breathingAmplitude,
    this.child,
  });

  final AnimationController controller;
  final double size;

  /// Opacité du trait au repos, quand l'anneau est à son plus petit.
  final double restOpacity;

  /// Décalage dans le cycle, en fraction de tour. Négatif = culmine plus tard.
  final double phase;
  final double amplitude;

  /// Contenu centré dans l'anneau — une icône, par exemple.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = breath(controller.value, phase: phase);
        return Transform.scale(
          // Repère stable pour les tests : Material insère ses propres
          // Transform dans l'arbre, impossible de distinguer les anneaux sans.
          key: ValueKey('breathing-ring-${size.toInt()}'),
          scale: 1 + amplitude * t,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                // Le trait s'éclaircit en même temps qu'il s'élargit : c'est ce
                // couplage qui donne l'impression d'une lumière qui enfle,
                // plutôt que d'un cercle qu'on redimensionne.
                color: AppColors.gold.withValues(alpha: restOpacity * (1 + 1.6 * t)),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.gold.withValues(alpha: 0.10 * t),
                  blurRadius: 8 + 26 * t,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

/// Halo diffus. Il ne dessine aucun contour : il ne fait que réchauffer le fond
/// au moment où les anneaux s'ouvrent.
class BreathingHalo extends StatelessWidget {
  const BreathingHalo({
    super.key,
    required this.controller,
    this.size = 300,
    this.phase = 0,
  });

  final AnimationController controller;
  final double size;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = breath(controller.value, phase: phase);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.gold.withValues(alpha: 0.06 + 0.06 * t),
                AppColors.gold.withValues(alpha: 0.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Contrôleur de respiration respectant « réduire les animations ».
///
/// Ce réglage est une exigence d'accessibilité, pas une préférence esthétique :
/// le mouvement continu donne des vertiges à certains utilisateurs. Les écrans
/// qui respirent appellent [syncBreathing] depuis `didChangeDependencies`.
void syncBreathing(BuildContext context, AnimationController controller) {
  final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  if (reduceMotion) {
    controller.stop();
    controller.value = 0;
  } else if (!controller.isAnimating) {
    // `repeat()` sans `reverse` : la sinusoïde redescend d'elle-même et se
    // referme, donc aucune rupture à la boucle.
    controller.repeat();
  }
}
