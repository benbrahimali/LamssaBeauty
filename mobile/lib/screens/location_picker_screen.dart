import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/location.dart';
import '../theme/app_theme.dart';

/// Choisir l'emplacement exact d'un salon sur la carte (§3.1, §3.2).
///
/// Le GPS place le salon là où se tient le gérant — pas forcément devant sa
/// vitrine, et parfois à cinquante mètres près en ville. Or cette position
/// décide de son apparition dans les recherches « près de moi » : elle mérite
/// d'être ajustée à la main.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initial});

  /// Point de départ : la position GPS déjà obtenue, si elle existe.
  final LatLng? initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  /// Centre de Tunis — repli quand on n'a aucune position.
  static const _tunis = LatLng(36.8190, 10.1658);

  GoogleMapController? _map;
  late LatLng _target = widget.initial ?? _tunis;
  MapType _type = MapType.normal;
  String _address = '';
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void dispose() {
    _map?.dispose();
    super.dispose();
  }

  /// Adresse approximative du point visé.
  ///
  /// Sert de contrôle : « Rue du Lac, El Menzah » confirme qu'on ne s'est pas
  /// trompé de quartier, ce qu'un couple de coordonnées ne dira jamais.
  Future<void> _resolveAddress() async {
    setState(() => _resolving = true);
    try {
      // Même géocodeur que la création : deux rendus différents pour le même
      // point donneraient l'impression que l'un des deux se trompe.
      final adresse =
          await resolveAddress(_target.latitude, _target.longitude);
      if (!mounted) return;
      setState(() {
        _address = adresse.full;
        _resolving = false;
      });
    } catch (_) {
      // Le géocodage inverse dépend des services Google : son échec ne doit
      // pas empêcher de valider un point, qui reste parfaitement utilisable.
      if (mounted) setState(() { _address = ''; _resolving = false; });
    }
  }

  Future<void> _goToMyPosition() async {
    final position = await resolvePosition(context);
    if (position == null || !mounted) return;
    final cible = LatLng(position.position.latitude, position.position.longitude);
    setState(() => _target = cible);
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(cible, 17));
    await _resolveAddress();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _target, zoom: 16),
          onMapCreated: (c) => _map = c,
          mapType: _type,
          // Pincer, zoomer, faire pivoter : les gestes attendus d'une carte.
          zoomGesturesEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: true,
          myLocationEnabled: true,
          // Bouton maison masqué : le nôtre gère les permissions et recentre
          // aussi l'épingle, ce que celui de Google ne fait pas.
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onCameraMove: (position) => _target = position.target,
          // L'adresse n'est résolue qu'à l'arrêt : la recalculer à chaque
          // image ferait un appel de géocodage par pixel parcouru.
          onCameraIdle: _resolveAddress,
        ),

        // Épingle fixe au centre : c'est la carte qui bouge sous elle. Plus
        // précis au pouce qu'un marqueur à faire glisser, qui se retrouve
        // caché par le doigt au moment de le lâcher.
        const IgnorePointer(
          child: Center(
            child: Padding(
              // Décale la pointe de l'épingle sur le centre exact.
              padding: EdgeInsets.only(bottom: 42),
              child: Icon(Icons.location_on, size: 46, color: AppColors.gold),
            ),
          ),
        ),

        _buildTopBar(),
        _buildConfirmPanel(),
      ]),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 12,
      left: 16,
      right: 16,
      child: Row(children: [
        _RoundButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
        const Spacer(),
        // Le satellite sert vraiment ici : on reconnaît un bâtiment, un coin
        // de rue — pas un plan schématique.
        _RoundButton(
          icon: _type == MapType.normal
              ? Icons.satellite_alt_rounded
              : Icons.map_rounded,
          active: _type != MapType.normal,
          onTap: () => setState(() {
            _type = switch (_type) {
              MapType.normal => MapType.hybrid,
              MapType.hybrid => MapType.satellite,
              _ => MapType.normal,
            };
          }),
        ),
        const SizedBox(width: 10),
        _RoundButton(icon: Icons.my_location_rounded, onTap: _goToMyPosition),
      ]),
    );
  }

  Widget _buildConfirmPanel() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(
            20, 18, 20, MediaQuery.of(context).padding.bottom + 20),
        decoration: const BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.place_rounded, size: 18, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _address.isNotEmpty
                      ? _address
                      : (_resolving ? 'نقرا العنوان…' : 'الموقع المختار'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600),
                ),
                Text(
                  '${_target.latitude.toStringAsFixed(5)}, '
                  '${_target.longitude.toStringAsFixed(5)}',
                  style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Text(
            'حرّك الخريطة باش تحطّ الدبوس على باب الصالون',
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.of(context).pop(
                PickedLocation(
                  lat: _target.latitude,
                  lng: _target.longitude,
                  address: _address,
                ),
              ),
              child: Text('أكّد الموقع',
                  style: AppTextStyle.dmSans(
                      color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ce que le sélecteur rend : un point, et l'adresse lue au passage.
class PickedLocation {
  const PickedLocation({
    required this.lat,
    required this.lng,
    this.address = '',
  });

  final double lat;
  final double lng;
  final String address;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
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
            size: 20, color: active ? Colors.black : AppColors.text),
      ),
    );
  }
}
