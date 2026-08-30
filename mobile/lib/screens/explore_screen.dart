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
  final _searchCtrl = TextEditingController();

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
    _searchCtrl.dispose();
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

  Set<Marker> _markers(List<Salon> salons) => salons
      .where((s) => s.lat != 0 || s.lng != 0)
      .map((s) => Marker(
            markerId: MarkerId('salon_${s.id}'),
            position: LatLng(s.lat, s.lng),
            infoWindow: InfoWindow(
              title: s.name,
              snippet: '${s.rating.toStringAsFixed(1)}⭐'
                  '${s.distance.isEmpty ? '' : ' · ${s.distance}'}',
              onTap: () => widget.onGoSalon(s),
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow),
          ))
      .toSet();

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
                ? _buildMap(controller.salons)
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
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.search_rounded, color: AppColors.sub, size: 18),
          ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: controller.setQuery,
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'ابحث...',
                hintStyle: GoogleFonts.dmSans(color: AppColors.sub, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
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

  Widget _buildMap(List<Salon> salons) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GoogleMap(
          initialCameraPosition: _tunis,
          markers: _markers(salons),
          mapType: MapType.normal,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            // La position peut être arrivée avant la carte : on rattrape.
            final cible = _centreVoulu;
            if (cible != null) {
              controller.moveCamera(CameraUpdate.newLatLngZoom(cible, 14));
            }
          },
          style: _mapDarkStyle,
        ),
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

  static const String _mapDarkStyle = '''[
    {"elementType":"geometry","stylers":[{"color":"#0c0c18"}]},
    {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
    {"elementType":"labels.text.stroke","stylers":[{"color":"#0c0c18"}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a2e"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#050510"}]},
    {"featureType":"poi","stylers":[{"visibility":"off"}]}
  ]''';
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
