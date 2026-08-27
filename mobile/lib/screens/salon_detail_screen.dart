import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

class SalonDetailScreen extends StatefulWidget {
  final Salon salon;
  final VoidCallback onBack;
  final Function(Salon, Coiffeur?) onBook;
  final Function(Coiffeur) onGoCoiffeur;

  const SalonDetailScreen({
    super.key,
    required this.salon,
    required this.onBack,
    required this.onBook,
    required this.onGoCoiffeur,
  });

  @override
  State<SalonDetailScreen> createState() => _SalonDetailScreenState();
}

class _SalonDetailScreenState extends State<SalonDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  static const _tabs = ['الخدمات', 'الفريق', 'معلومات'];

  SalonDetail? _detail;
  bool _loading = true;
  String? _error;

  /// La carte de recherche est déjà affichable : on l'utilise en attendant le détail.
  Salon get _salon => _detail?.salon ?? widget.salon;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await context.read<SalonRepository>().detail(widget.salon.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHero()),
              SliverToBoxAdapter(child: _buildTabBar()),
              SliverToBoxAdapter(child: _buildTabContent()),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            child: GestureDetector(
              onTap: widget.onBack,
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.8),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: AppColors.text),
              ),
            ),
          ),
          Positioned(
            left: 20, right: 20,
            bottom: MediaQuery.of(context).padding.bottom + 20,
            child: GoldButton(
              text: 'احجز الآن ✨',
              enabled: (_detail?.services.isNotEmpty ?? false),
              onPressed: () => widget.onBook(_salon, null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final salon = _salon;
    return Container(
      height: 240,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [salon.color, salon.accent.withValues(alpha: 0.15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(alignment: Alignment.center, children: [
        Text(salon.initials, style: GoogleFonts.playfairDisplay(
          fontSize: 80, fontWeight: FontWeight.w900, color: salon.accent,
          shadows: [Shadow(color: salon.accent.withValues(alpha: 0.4), blurRadius: 40)],
        )),
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, AppColors.bg.withValues(alpha: 0.95)],
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(salon.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text,
                    ))),
                StatusBadge(open: salon.open),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                StarRating(rating: salon.rating),
                const SizedBox(width: 6),
                Text('(${salon.reviews} تقييم)',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
                if (salon.distance.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.location_on_rounded, size: 12, color: AppColors.sub),
                  const SizedBox(width: 3),
                  Text(salon.distance,
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
                ],
              ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: TabBar(
        controller: _tabCtrl,
        labelStyle: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w400),
        labelColor: Colors.black,
        unselectedLabelColor: AppColors.sub,
        indicator: BoxDecoration(
          color: AppColors.gold,
          borderRadius: BorderRadius.circular(10),
        ),
        indicatorPadding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        tabs: _tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    if (_loading) {
      return const SizedBox(height: 220, child: AppLoader());
    }
    if (_error != null) {
      return SizedBox(
        height: 220,
        child: AppError(message: _error!, onRetry: _load),
      );
    }
    switch (_tabCtrl.index) {
      case 0: return _buildServices();
      case 1: return _buildTeam();
      case 2: return _buildInfo();
      default: return const SizedBox();
    }
  }

  Widget _buildServices() {
    final services = _detail?.services ?? const <ServiceItem>[];
    if (services.isEmpty) {
      return const AppEmpty(
        emoji: '✂️',
        title: 'Aucun service publié',
        subtitle: "Ce salon n'a pas encore renseigné son catalogue.",
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: services
            .map((service) => _ServiceRow(
                  service: service,
                  onBook: () => widget.onBook(_salon, null),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildTeam() {
    final team = _detail?.staff ?? const <Coiffeur>[];
    if (team.isEmpty) {
      return const AppEmpty(emoji: '💈', title: 'ما كاين فريق متسجل');
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: team
            .map((coiffeur) => GestureDetector(
                  onTap: () => widget.onGoCoiffeur(coiffeur),
                  child: _TeamMemberRow(
                    coiffeur: coiffeur,
                    onBook: () => widget.onBook(_salon, coiffeur),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildInfo() {
    final salon = _salon;
    final rows = <Map<String, Object>>[
      {'icon': Icons.location_on_rounded, 'label': 'العنوان', 'value': salon.address},
      {'icon': Icons.access_time_rounded, 'label': 'أوقات العمل', 'value': salon.hours},
      {'icon': Icons.phone_rounded, 'label': 'الهاتف', 'value': salon.phone},
      {'icon': Icons.attach_money_rounded, 'label': 'الأسعار', 'value': salon.price},
      {
        'icon': Icons.people_rounded,
        'label': 'عدد الحجامين',
        'value': '${salon.workers} حجام'
      },
    ].where((row) => (row['value'] as String).trim().isNotEmpty).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        children: rows.map((row) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Icon(row['icon'] as IconData, size: 18, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row['label'] as String,
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
                const SizedBox(height: 2),
                Text(row['value'] as String, style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text,
                )),
              ]),
            ),
          ]),
        )).toList(),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  final ServiceItem service;
  final VoidCallback onBook;
  const _ServiceRow({required this.service, required this.onBook});

  @override
  Widget build(BuildContext context) {
    final title = service.nameAr.trim().isNotEmpty ? service.nameAr : service.name;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Text(service.icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: GoogleFonts.dmSans(
            fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text,
          )),
          if (service.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(service.description,
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
          ],
          const SizedBox(height: 4),
          Text('⏱ ${service.duration} دقيقة',
              style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${service.price.toStringAsFixed(0)} DT',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold,
              )),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: onBook,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text('احجز', style: GoogleFonts.dmSans(
                fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black,
              )),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  final Coiffeur coiffeur;
  final VoidCallback onBook;
  const _TeamMemberRow({required this.coiffeur, required this.onBook});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        InitialsAvatar(
          initials: coiffeur.initials,
          color: coiffeur.color,
          size: 50,
          showBadge: true,
          available: coiffeur.available,
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(coiffeur.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text,
              )),
          const SizedBox(height: 3),
          Text('${coiffeur.role} · chaise ${coiffeur.chairNumber}',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
          const SizedBox(height: 5),
          Row(children: [
            StarRating(rating: coiffeur.rating),
            const SizedBox(width: 8),
            Text('${coiffeur.cuts}+ قطعة',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
          ]),
        ])),
        GestureDetector(
          onTap: coiffeur.available ? onBook : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: coiffeur.available
                  ? AppColors.gold.withValues(alpha: 0.15)
                  : AppColors.border,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: coiffeur.available
                    ? AppColors.gold.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            child: Text(
              coiffeur.available ? 'احجز معاه' : 'غير متاح',
              style: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: coiffeur.available ? AppColors.gold : AppColors.sub,
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
