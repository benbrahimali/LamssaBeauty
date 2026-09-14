import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/salons_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/salon_thumb.dart';
import '../widgets/salon_code_sheet.dart';
import '../core/location.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';
import '../widgets/map_controls.dart';
import '../widgets/salon_search_field.dart';

class ExploreScreen extends StatefulWidget {
  final Function(Salon) onGoSalon;
  const ExploreScreen({super.key, required this.onGoSalon});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  GoogleMapController? _mapController;
  bool _mapView = false;
  bool _locating = false;

  /// Fond de carte choisi : plan, satellite ou mixte.
  MapType _mapType = MapType.normal;

  /// Salon touché sur la carte, dont la fiche s'affiche en bas.
  String? _selectedId;

  static const _tunis = CameraPosition(target: LatLng(36.8190, 10.1658), zoom: 13.5);

  /// Cible de recentrage tant que la carte n'est pas créée.
  LatLng? _centreVoulu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SalonsController>().load();
      _localiserAuDemarrage();
    });
  }

  /// Centre la carte sur l'utilisateur à l'ouverture.
  ///
  /// L'écran s'ouvrait sur un centre Tunis figé et cherchait sans position :
  /// les salons remontaient dans l'ordre du serveur, et la carte montrait un
  /// quartier où l'utilisateur n'était pas. C'est pourtant l'écran où l'on
  /// vient précisément pour trouver ce qui est près de soi.
  ///
  /// La tentative est silencieuse : elle profite d'une permission déjà
  /// accordée, mais n'ouvre aucune boîte système. Une demande sans geste se
  /// fait refuser par réflexe, et un refus définitif ne se rattrape plus — le
  /// bouton « موقعي » reste là pour le geste explicite.
  Future<void> _localiserAuDemarrage() async {
    final salons = context.read<SalonsController>();
    if (salons.hasPosition) {
      await _centrer(LatLng(salons.lat!, salons.lng!));
      return;
    }

    final position = await resolvePosition(context, silencieux: true);
    if (!mounted || position == null) return;

    salons.setPosition(position.position.latitude, position.position.longitude);
    await salons.refresh();
    if (!mounted) return;
    await _centrer(
        LatLng(position.position.latitude, position.position.longitude));
  }

  /// Déplace la caméra, même si la carte n'est pas encore prête.
  ///
  /// La position arrive souvent avant que `onMapCreated` ait été appelé :
  /// sans mémoriser la cible, le recentrage se perdait et la carte restait
  /// sur Tunis.
  Future<void> _centrer(LatLng cible, {double zoom = 14}) async {
    _centreVoulu = cible;
    await _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(cible, zoom));
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  /// Recentre la recherche sur la position réelle (§3.2 « près de moi »).
  Future<void> _locateMe() async {
    setState(() => _locating = true);
    try {
      final position = await resolvePosition(context);
      if (!mounted || position == null) return;

      final salons = context.read<SalonsController>();
      salons.setPosition(position.position.latitude, position.position.longitude);
      await salons.refresh();
      if (!mounted) return;
      await _centrer(
          LatLng(position.position.latitude, position.position.longitude));
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  static bool _placed(Salon s) => s.lat != 0 || s.lng != 0;

  Set<Marker> _markers(List<Salon> salons) => salons.where(_placed).map((s) {
        final choisi = s.id == _selectedId;
        return Marker(
          markerId: MarkerId('salon_${s.id}'),
          position: LatLng(s.lat, s.lng),
          // La fiche en bas de carte remplace la bulle Google : plus lisible,
          // avec la vitrine et un bouton qu'on atteint au pouce.
          consumeTapEvents: true,
          onTap: () {
            setState(() => _selectedId = s.id);
            _mapController?.animateCamera(
                CameraUpdate.newLatLng(LatLng(s.lat, s.lng)));
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            choisi ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueYellow,
          ),
        );
      }).toSet();

  Salon? _selectedIn(List<Salon> salons) {
    for (final s in salons) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  /// Cadre la carte sur tous les salons trouvés.
  Future<void> _fitSalons(List<Salon> salons) async {
    final cadre =
        boundsOf(salons.where(_placed).map((s) => LatLng(s.lat, s.lng)));
    if (cadre == null) return;
    try {
      await _mapController?.animateCamera(CameraUpdate.newLatLngBounds(cadre, 56));
    } catch (_) {
      // Carte pas encore mesurée : le cadrage attendra le prochain geste.
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SalonsController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(controller),
          _buildSearch(controller),
          _buildFilters(controller),
          _buildViewToggle(),
          Expanded(
            child: _mapView
                ? _buildMap(controller)
                : _buildList(controller),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(SalonsController controller) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 16),
      child: Row(
        children: [
          Text('اكتشف', style: GoogleFonts.playfairDisplay(
            fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text,
          )),
          const Spacer(),
          Text('${controller.salons.length} صالون',
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _locating ? null : _locateMe,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: controller.hasPosition
                    ? AppColors.gold.withValues(alpha: 0.15)
                    : AppColors.card,
                border: Border.all(
                  color: controller.hasPosition ? AppColors.gold : AppColors.border,
                ),
              ),
              child: _locating
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold),
                    )
                  : Icon(Icons.my_location_rounded,
                      size: 18,
                      color: controller.hasPosition ? AppColors.gold : AppColors.sub),
            ),
          ),
          const SizedBox(width: 8),
          // Entrée par le code de la vitrine : le client qui vient d'un QR
          // partagé n'a pas à retrouver le salon dans la liste.
          GestureDetector(
            onTap: () => SalonCodeSheet.show(context, widget.onGoSalon),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.card,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.qr_code_scanner_rounded,
                  size: 18, color: AppColors.sub),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearch(SalonsController controller) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      // Pas d'épingle ici : le bouton « موقعي » de l'en-tête s'en charge.
      child: SalonSearchField(
        query: controller.query,
        onSearch: controller.setQuery,
      ),
    );
  }

  Widget _buildFilters(SalonsController controller) {
    final filters = <Map<String, Object?>>[
      {'id': null, 'label': '🏪 الكل'},
      {'id': SalonType.barbershop, 'label': '💈 رجال'},
      {'id': SalonType.femme, 'label': '💅 نساء'},
      {'id': SalonType.mixte, 'label': '✨ Mixte'},
      {'id': SalonType.mariage, 'label': '👰 عرايس'},
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: filters.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == filters.length) {
            return FilterPill(
              label: '🟢 مفتوح الآن',
              active: controller.openNow,
              onTap: () => controller.setOpenNow(!controller.openNow),
            );
          }
          final filter = filters[i];
          return FilterPill(
            label: filter['label'] as String,
            active: controller.type == filter['id'],
            onTap: () => controller.setType(filter['id'] as SalonType?),
          );
        },
      ),
    );
  }

  Widget _buildViewToggle() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          _toggleBtn('📋 قائمة', !_mapView, () => setState(() => _mapView = false)),
          _toggleBtn('🗺️ خريطة', _mapView, () => setState(() => _mapView = true)),
        ]),
      ),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: active ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(label, style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active ? Colors.black : AppColors.sub,
          )),
        ),
      ),
    );
  }

  Widget _buildMap(SalonsController controller) {
    final salons = controller.salons;
    final selected = _selectedIn(salons);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(children: [
          GoogleMap(
            initialCameraPosition: _tunis,
            markers: _markers(salons),
            mapType: _mapType,
            // Le style sombre ne vaut que pour le plan : en mode mixte il
            // assombrirait les noms de rues posés sur l'imagerie.
            style: _mapType == MapType.normal ? kLamssaMapStyle : null,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            // Garde le logo Google hors de la fiche du salon.
            padding: EdgeInsets.only(bottom: selected != null ? 130 : 0),
            onTap: (_) {
              if (_selectedId != null) setState(() => _selectedId = null);
            },
            onMapCreated: (map) {
              _mapController = map;
              // La position peut être arrivée avant la carte : on rattrape.
              final cible = _centreVoulu;
              if (cible != null) {
                map.moveCamera(CameraUpdate.newLatLngZoom(cible, 14));
              } else if (salons.isNotEmpty) {
                // Sans position, montrer les salons vaut mieux qu'un centre
                // de Tunis où il n'y en a peut-être aucun.
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _fitSalons(salons));
              }
            },
          ),

          if (controller.loading)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.gold,
                backgroundColor: Colors.transparent,
              ),
            ),

          PositionedDirectional(
            top: 12,
            start: 12,
            child: MapTypeSelector(
              value: _mapType,
              onChanged: (type) => setState(() => _mapType = type),
            ),
          ),

          // Sous le sélecteur : côte à côte, ils ne tiendraient pas sur un
          // petit téléphone.
          PositionedDirectional(
            top: 64,
            end: 12,
            child: Column(children: [
              MapRoundButton(
                icon: Icons.add_rounded,
                size: 40,
                tooltip: 'قرّب',
                onTap: () => _mapController?.animateCamera(CameraUpdate.zoomIn()),
              ),
              const SizedBox(height: 8),
              MapRoundButton(
                icon: Icons.remove_rounded,
                size: 40,
                tooltip: 'بعّد',
                onTap: () => _mapController?.animateCamera(CameraUpdate.zoomOut()),
              ),
              const SizedBox(height: 16),
              MapRoundButton(
                icon: Icons.my_location_rounded,
                size: 40,
                tooltip: 'موقعي',
                active: controller.hasPosition,
                onTap: () {
                  if (!_locating) _locateMe();
                },
              ),
              if (salons.isNotEmpty) ...[
                const SizedBox(height: 8),
                MapRoundButton(
                  icon: Icons.zoom_out_map_rounded,
                  size: 40,
                  tooltip: 'الصالونات الكل',
                  onTap: () => _fitSalons(salons),
                ),
              ],
            ]),
          ),

          if (selected != null)
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 12,
              child: SalonMapPreview(
                salon: selected,
                onOpen: () => widget.onGoSalon(selected),
                onClose: () => setState(() => _selectedId = null),
              ),
            )
          else if (!controller.loading && salons.isEmpty)
            PositionedDirectional(
              start: 12,
              end: 12,
              bottom: 16,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.card.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(50),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text('ما لقيناش صالونات في هالمنطقة',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildList(SalonsController controller) {
    if (controller.loading && controller.salons.isEmpty) {
      return const AppLoader(label: 'Recherche des salons…');
    }
    if (controller.error != null && controller.salons.isEmpty) {
      return AppError(message: controller.error!, onRetry: controller.refresh);
    }
    if (controller.salons.isEmpty) {
      return const AppEmpty(
        emoji: '🔍',
        title: 'ما لقيناش نتائج',
        subtitle: 'Essaie un autre filtre ou une autre recherche.',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: controller.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 110),
        itemCount: controller.salons.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final salon = controller.salons[i];
          return GestureDetector(
            onTap: () => widget.onGoSalon(salon),
            child: _SalonListCard(salon: salon),
          );
        },
      ),
    );
  }

}

class _SalonListCard extends StatelessWidget {
  final Salon salon;
  const _SalonListCard({required this.salon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        SalonThumb(salon: salon, size: 64, monogramSize: 22),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(salon.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text,
                ))),
            StatusBadge(open: salon.open),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            StarRating(rating: salon.rating),
            const SizedBox(width: 4),
            Text('(${salon.reviews})',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            if (salon.distance.isNotEmpty) ...[
              const Icon(Icons.location_on_rounded, size: 12, color: AppColors.sub),
              const SizedBox(width: 3),
              Text(salon.distance,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(salon.price.isEmpty ? salon.address : salon.price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.gold)),
            ),
          ]),
        ])),
        const Icon(Icons.chevron_right, color: AppColors.sub, size: 20),
      ]),
    );
  }
}
