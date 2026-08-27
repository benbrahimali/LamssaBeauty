import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../data/repositories/booking_repository.dart';
import '../data/repositories/style_dna_repository.dart';
import '../state/auth_controller.dart';
import '../state/notifications_controller.dart';
import '../state/salons_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';
import 'my_bookings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(Salon) onGoSalon;
  final Function(Coiffeur) onGoCoiffeur;
  final Function(int) onNav;
  final VoidCallback? onStyleDna;

  const HomeScreen({
    super.key,
    required this.onGoSalon,
    required this.onGoCoiffeur,
    required this.onNav,
    this.onStyleDna,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  Future<List<Booking>>? _upcoming;

  /// Style DNA n'existe que si le serveur a une clé de modèle vision — sinon la
  /// carte enverrait l'utilisateur vers un écran qui ne peut que échouer.
  bool _styleDnaAvailable = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.read<SalonsController>().load();
      _reloadUpcoming();

      final available = await context.read<StyleDnaRepository>().isAvailable();
      if (mounted) setState(() => _styleDnaAvailable = available);
    });
  }

  void _reloadUpcoming() {
    final auth = context.read<AuthController>();
    if (auth.status != AuthStatus.loggedIn) {
      setState(() => _upcoming = null);
      return;
    }
    setState(() {
      _upcoming = context.read<BookingRepository>().mine(upcoming: true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final salons = context.watch<SalonsController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.card,
        onRefresh: () async {
          await salons.refresh();
          _reloadUpcoming();
        },
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildSearch(salons)),
            SliverToBoxAdapter(child: _buildFilters(salons)),
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
              child: SectionHeader(
                title: 'قريب منك 📍',
                actionLabel: 'شوف الكل',
                onAction: () => widget.onNav(1),
              ),
            )),
            SliverToBoxAdapter(child: _buildNearbySalons(salons)),
            if (salons.featuredStaff.isNotEmpty) ...[
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 14),
                child: SectionHeader(title: 'حجامين ترند 🔥'),
              )),
              SliverToBoxAdapter(child: _buildCoiffeurs(salons.featuredStaff)),
            ],
            if (_styleDnaAvailable) SliverToBoxAdapter(child: _buildStyleDNA()),
            SliverToBoxAdapter(child: _buildUpcomingBooking()),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final user = context.watch<AuthController>().user;
    final unread = context.watch<NotificationsController>().unread;
    final name = user?.name.trim().isNotEmpty == true ? user!.name : 'ضيف';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('🌙 مساء النور,',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
              const SizedBox(height: 4),
              Text('$name ✨',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text,
                  )),
            ]),
          ),
          Row(children: [
            GestureDetector(
              onTap: () => widget.onNav(2),
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.card,
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  const Icon(Icons.notifications_rounded, color: AppColors.sub, size: 20),
                  if (unread > 0)
                    Positioned(
                      top: 6, right: 6,
                      child: Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(
                            color: AppColors.red, shape: BoxShape.circle),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 44, height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.goldGradient,
              ),
              alignment: Alignment.center,
              child: Text(initialsOf(name),
                  style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black,
                  )),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildSearch(SalonsController salons) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        height: 50,
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
              onSubmitted: salons.setQuery,
              style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'ابحث صالون، حجام...',
                hintStyle: GoogleFonts.dmSans(color: AppColors.sub, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Icon(Icons.location_on_rounded, color: AppColors.sub, size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _buildFilters(SalonsController salons) {
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
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final filter = filters[i];
          return FilterPill(
            label: filter['label'] as String,
            active: salons.type == filter['id'],
            onTap: () => salons.setType(filter['id'] as SalonType?),
          );
        },
      ),
    );
  }

  Widget _buildNearbySalons(SalonsController salons) {
    if (salons.loading && salons.salons.isEmpty) {
      return const SizedBox(height: 210, child: AppLoader());
    }
    if (salons.error != null && salons.salons.isEmpty) {
      return SizedBox(
        height: 210,
        child: AppError(message: salons.error!, onRetry: salons.refresh),
      );
    }
    if (salons.salons.isEmpty) {
      return const SizedBox(
        height: 210,
        child: AppEmpty(
          emoji: '🔍',
          title: 'Aucun salon trouvé',
          subtitle: 'Change de filtre ou élargis ta recherche.',
        ),
      );
    }

    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: salons.salons.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          final salon = salons.salons[i];
          return GestureDetector(
            onTap: () => widget.onGoSalon(salon),
            child: _SalonCard(salon: salon),
          );
        },
      ),
    );
  }

  Widget _buildCoiffeurs(List<Coiffeur> coiffeurs) {
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        itemCount: coiffeurs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final coiffeur = coiffeurs[i];
          return GestureDetector(
            onTap: () => widget.onGoCoiffeur(coiffeur),
            child: _CoiffeurCard(coiffeur: coiffeur),
          );
        },
      ),
    );
  }

  Widget _buildStyleDNA() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: GestureDetector(
        onTap: widget.onStyleDna,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.gold.withValues(alpha: 0.15),
              AppColors.pink.withValues(alpha: 0.1),
            ]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Text('🧬', style: TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✨ Style DNA — جديد', style: GoogleFonts.dmSans(
                fontSize: 11, letterSpacing: 2, color: AppColors.gold,
                fontWeight: FontWeight.w600,
              )),
              const SizedBox(height: 4),
              Text('شوف ستايلك المناسب', style: GoogleFonts.playfairDisplay(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text,
              )),
              const SizedBox(height: 3),
              Text('حط سيلفي والـ AI يقترحلك أحسن تريند', style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.sub,
              )),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _buildUpcomingBooking() {
    final future = _upcoming;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<List<Booking>>(
      future: future,
      builder: (context, snapshot) {
        final bookings = snapshot.data ?? const <Booking>[];
        if (bookings.isEmpty) return const SizedBox.shrink();

        // Le backend trie du plus récent au plus ancien : le prochain RDV est le dernier.
        final next = bookings.last;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: GestureDetector(
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const MyBookingsScreen(),
              ));
              // Le client a pu annuler depuis la liste : on resynchronise.
              _reloadUpcoming();
            },
            child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.green.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text('📅', style: TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('موعدك القادم', style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.text,
                  )),
                  const SizedBox(height: 2),
                  Text(
                    '${next.date} — ${next.time} · ${next.service}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(next.status.label, style: GoogleFonts.dmSans(
                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.green,
                )),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.sub),
            ]),
            ),
          ),
        );
      },
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────
class _SalonCard extends StatelessWidget {
  final Salon salon;
  const _SalonCard({required this.salon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(children: [
        Container(
          height: 130,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [salon.color, salon.accent.withValues(alpha: 0.13)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Text(salon.initials, style: GoogleFonts.playfairDisplay(
              fontSize: 48, fontWeight: FontWeight.w900, color: salon.accent,
              shadows: [Shadow(color: salon.accent.withValues(alpha: 0.5), blurRadius: 20)],
            )),
            Positioned(
              top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: salon.open
                      ? AppColors.green.withValues(alpha: 0.85)
                      : AppColors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  salon.open ? '🟢 مفتوح' : '🔴 مغلق',
                  style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(salon.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text,
                )),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.star_rounded, size: 13, color: AppColors.gold),
              const SizedBox(width: 4),
              Text(salon.rating.toStringAsFixed(1),
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
              if (salon.distance.isNotEmpty) ...[
                const SizedBox(width: 10),
                const Icon(Icons.location_on_rounded, size: 12, color: AppColors.sub),
                const SizedBox(width: 2),
                Text(salon.distance,
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
              ],
            ]),
            if (salon.price.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(salon.price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _CoiffeurCard extends StatelessWidget {
  final Coiffeur coiffeur;
  const _CoiffeurCard({required this.coiffeur});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        InitialsAvatar(
          initials: coiffeur.initials,
          color: coiffeur.color,
          size: 56,
          showBadge: true,
          available: coiffeur.available,
        ),
        const SizedBox(height: 8),
        Text(
          coiffeur.name.split(' ').first,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(coiffeur.role,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.sub),
            textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('⭐ ${coiffeur.rating.toStringAsFixed(1)} · ${coiffeur.cuts}+',
            style: GoogleFonts.dmSans(
                fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
