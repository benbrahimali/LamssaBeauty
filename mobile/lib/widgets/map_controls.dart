import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';
import 'salon_thumb.dart';

/// Style sombre du plan, accordé au thème de l'app.
///
/// Arrêts de bus, commerces et leurs pictogrammes sont masqués : sur la carte
/// des salons ils recouvraient les épingles et noyaient ce qu'on vient
/// chercher. Les parcs et les grands axes restent, pour se repérer.
const String kLamssaMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0f0f1c"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8a8aa6"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#0b0b16"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"color":"#2a2a40"}]},
  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c9a84c"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"visibility":"on"},{"color":"#12241c"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1e1e33"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#15152a"}]},
  {"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#26263f"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#3a3320"}]},
  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#c9a84c"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#070714"}]},
  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#3d3d5c"}]}
]''';

/// Plus petit cadre contenant tous les points, ou null s'il n'y en a aucun.
///
/// Un point seul donne un cadre d'environ un kilomètre : un cadre nul ferait
/// zoomer la caméra au maximum, sur un pâté de maisons.
LatLngBounds? boundsOf(Iterable<LatLng> points, {double minSpan = 0.01}) {
  if (points.isEmpty) return null;

  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final p in points) {
    south = math.min(south, p.latitude);
    north = math.max(north, p.latitude);
    west = math.min(west, p.longitude);
    east = math.max(east, p.longitude);
  }
  if (north - south < minSpan) {
    final milieu = (north + south) / 2;
    south = milieu - minSpan / 2;
    north = milieu + minSpan / 2;
  }
  if (east - west < minSpan) {
    final milieu = (east + west) / 2;
    west = milieu - minSpan / 2;
    east = milieu + minSpan / 2;
  }
  return LatLngBounds(
    southwest: LatLng(south, west),
    northeast: LatLng(north, east),
  );
}

/// Choix du fond de carte : plan, satellite ou mixte.
///
/// Le satellite aide à reconnaître un bâtiment ou un coin de rue ; le mixte y
/// ajoute les noms des rues, sans quoi on se perd dans l'imagerie.
class MapTypeSelector extends StatelessWidget {
  const MapTypeSelector({super.key, required this.value, required this.onChanged});

  final MapType value;
  final ValueChanged<MapType> onChanged;

  static const options = <(MapType, IconData, String)>[
    (MapType.normal, Icons.map_rounded, 'خريطة'),
    (MapType.satellite, Icons.satellite_alt_rounded, 'ساتليت'),
    (MapType.hybrid, Icons.layers_rounded, 'مختلطة'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (type, icon, label) in options)
            Semantics(
              button: true,
              selected: type == value,
              label: label,
              child: GestureDetector(
                onTap: () => onChanged(type),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: type == value ? AppColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // Seul le fond actif est nommé : trois libellés côte à côte
                  // débordaient d'une carte de 328 dp, celle d'un téléphone
                  // courant. Les autres restent nommés pour le lecteur d'écran.
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: type == value ? Colors.black : AppColors.sub),
                      if (type == value) ...[
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: AppTextStyle.dmSans(
                            size: 12,
                            weight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bouton rond posé sur une carte (zoom, position, fond de carte…).
class MapRoundButton extends StatelessWidget {
  const MapRoundButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.size = 44,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final bouton = GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: active ? AppColors.gold : AppColors.card,
          shape: BoxShape.circle,
          border: Border.all(color: active ? AppColors.gold : AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon,
            size: size * 0.45, color: active ? Colors.black : AppColors.text),
      ),
    );
    return tooltip == null ? bouton : Tooltip(message: tooltip!, child: bouton);
  }
}

/// Fiche du salon touché sur la carte.
///
/// Remplace la bulle Google, minuscule et sans photo : ici le client voit la
/// vitrine, la note, s'il est ouvert, et atteint le bouton au pouce.
class SalonMapPreview extends StatelessWidget {
  const SalonMapPreview({
    super.key,
    required this.salon,
    required this.onOpen,
    required this.onClose,
    this.onDirections,
  });

  final Salon salon;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  /// Itinéraire jusqu'au salon. Sans lui — salon sans position — pas de bouton.
  final VoidCallback? onDirections;

  @override
  Widget build(BuildContext context) {
    final details = [
      if (salon.distance.isNotEmpty) salon.distance,
      if (salon.price.isNotEmpty) salon.price else if (salon.address.isNotEmpty) salon.address,
    ].join(' · ');

    return GestureDetector(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SalonThumb(salon: salon, size: 72, monogramSize: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        salon.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyle.dmSans(size: 15, weight: FontWeight.w700),
                      ),
                    ),
                    GestureDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close_rounded, size: 18, color: AppColors.sub),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StarRating(rating: salon.rating),
                      Text('(${salon.reviews})',
                          style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
                      StatusBadge(open: salon.open),
                    ],
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.dmSans(size: 12, color: AppColors.gold),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 34,
                    child: Row(children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onOpen,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('شوف الصالون',
                                style: AppTextStyle.dmSans(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: Colors.black)),
                          ),
                        ),
                      ),
                      if (onDirections != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDirections,
                            icon: const Icon(Icons.directions_rounded, size: 16),
                            label: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text('الطريق',
                                  style: AppTextStyle.dmSans(
                                      size: 13,
                                      weight: FontWeight.w700,
                                      color: AppColors.gold)),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.gold,
                              side: BorderSide(
                                  color: AppColors.gold.withValues(alpha: 0.6)),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
