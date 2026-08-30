import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/env.dart';
import '../data/models.dart';

/// Vignette d'un salon : sa photo, ou son monogramme à défaut.
///
/// Trois écrans la dessinaient chacun de leur côté, et deux avaient oublié la
/// photo : la recherche et le tunnel de réservation affichaient les initiales
/// même quand le gérant avait mis une vitrine. Un seul widget évite que le cas
/// diverge à nouveau — c'est la photo qui fait cliquer.
class SalonThumb extends StatelessWidget {
  const SalonThumb({
    super.key,
    required this.salon,
    required this.size,
    this.radius = 14,
    this.monogramSize,
  });

  final Salon salon;
  final double size;
  final double radius;

  /// Taille du monogramme quand il n'y a pas de photo. Proportionnelle par
  /// défaut : un chiffre figé rend la vignette illisible en petit.
  final double? monogramSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [salon.color, salon.accent.withValues(alpha: 0.2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      clipBehavior: Clip.hardEdge,
      alignment: Alignment.center,
      child: salon.photos.isEmpty
          ? Text(salon.initials,
              style: GoogleFonts.playfairDisplay(
                fontSize: monogramSize ?? size * 0.34,
                fontWeight: FontWeight.w900,
                color: salon.accent,
              ))
          : CachedNetworkImage(
              imageUrl: Env.mediaUrl(salon.photos.first),
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => const SizedBox.shrink(),
              // En cas d'échec, le dégradé reste visible : mieux qu'une icône
              // cassée au milieu d'une liste.
              errorWidget: (_, __, ___) => Center(
                child: Text(salon.initials,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: monogramSize ?? size * 0.34,
                      fontWeight: FontWeight.w900,
                      color: salon.accent,
                    )),
              ),
            ),
    );
  }
}
