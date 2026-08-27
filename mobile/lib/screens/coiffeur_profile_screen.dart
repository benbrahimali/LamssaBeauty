import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

class CoiffeurProfileScreen extends StatefulWidget {
  final Coiffeur coiffeur;
  final VoidCallback onBack;

  /// Null quand on arrive ici sans contexte de salon (onglet « mon profil »).
  final VoidCallback? onBook;

  const CoiffeurProfileScreen({
    super.key,
    required this.coiffeur,
    required this.onBack,
    this.onBook,
  });

  @override
  State<CoiffeurProfileScreen> createState() => _CoiffeurProfileScreenState();
}

class _CoiffeurProfileScreenState extends State<CoiffeurProfileScreen> {
  StaffProfile? _profile;
  bool _loading = true;
  String? _error;

  Coiffeur get _coiffeur => _profile?.coiffeur ?? widget.coiffeur;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile =
          await context.read<SalonRepository>().staffProfile(widget.coiffeur.id);
      if (!mounted) return;
      setState(() {
        _profile = profile;
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHero(context)),
              SliverToBoxAdapter(child: _buildStats()),
              if (_loading)
                const SliverToBoxAdapter(
                  child: SizedBox(height: 180, child: AppLoader()),
                )
              else if (_error != null)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: AppError(message: _error!, onRetry: _load),
                  ),
                )
              else ...[
                if (_coiffeur.trending.isNotEmpty)
                  SliverToBoxAdapter(child: _buildTrending()),
                SliverToBoxAdapter(child: _buildServices()),
                SliverToBoxAdapter(child: _buildPortfolio()),
                SliverToBoxAdapter(child: _buildReviews()),
              ],
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
          if (widget.onBook != null)
            Positioned(
              left: 20, right: 20,
              bottom: MediaQuery.of(context).padding.bottom + 20,
              child: GoldButton(
                text: 'احجز مع ${_coiffeur.name.split(' ').first} ✨',
                enabled: _coiffeur.available,
                onPressed: widget.onBook,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final coiffeur = _coiffeur;
    return Container(
      padding:
          EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 60, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [coiffeur.color.withValues(alpha: 0.15), AppColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(children: [
        InitialsAvatar(
          initials: coiffeur.initials,
          color: coiffeur.color,
          size: 90,
          showBadge: true,
          available: coiffeur.available,
        ),
        const SizedBox(height: 16),
        Text(coiffeur.name, style: GoogleFonts.playfairDisplay(
          fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text,
        )),
        const SizedBox(height: 4),
        Text(coiffeur.role,
            style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.sub)),
        if (coiffeur.salon.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.store_rounded, size: 14, color: AppColors.gold),
            const SizedBox(width: 6),
            Text(coiffeur.salon, style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.gold, fontWeight: FontWeight.w600,
            )),
          ]),
        ],
        if (coiffeur.bio.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(coiffeur.bio,
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.sub, height: 1.5,
              )),
        ],
      ]),
    );
  }

  Widget _buildStats() {
    final coiffeur = _coiffeur;
    final stats = <Map<String, String>>[
      {'label': 'تقييم', 'value': '${coiffeur.rating.toStringAsFixed(1)}⭐'},
      {'label': 'قطعة', 'value': '${coiffeur.cuts}+'},
      {'label': 'كرسي', 'value': '#${coiffeur.chairNumber}'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Row(
        children: stats.map((stat) {
          final isLast = stat == stats.last;
          return Expanded(child: Container(
            margin: EdgeInsets.only(right: isLast ? 0 : 10),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(children: [
              Text(stat['value']!, style: GoogleFonts.playfairDisplay(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text,
              )),
              const SizedBox(height: 4),
              Text(stat['label']!,
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
          ));
        }).toList(),
      ),
    );
  }

  Widget _buildTrending() {
    final coiffeur = _coiffeur;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '🔥 ترند الأسبوع'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: coiffeur.trending.map((tag) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: coiffeur.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: coiffeur.color.withValues(alpha: 0.3)),
            ),
            child: Text(tag, style: GoogleFonts.dmSans(
              fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text,
            )),
          )).toList(),
        ),
      ]),
    );
  }

  Widget _buildServices() {
    final services = _profile?.services ?? const <ServiceItem>[];
    if (services.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '✂️ الخدمات'),
        const SizedBox(height: 12),
        ...services.map((service) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Text(service.icon, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  service.nameAr.trim().isNotEmpty ? service.nameAr : service.name,
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text,
                  ),
                ),
                Text('${service.duration} دقيقة',
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
              ]),
            ),
            Text('${service.price.toStringAsFixed(0)} DT',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold,
                )),
          ]),
        )),
      ]),
    );
  }

  Widget _buildPortfolio() {
    final items = _profile?.portfolio ?? const <PortfolioEntry>[];
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: AppEmpty(
          emoji: '📸',
          title: 'Pas encore de réalisation',
          subtitle: 'Ce coiffeur n’a rien publié pour le moment.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '📸 البورتفوليو'),
        const SizedBox(height: 12),
        GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) => _PortfolioTile(
            entry: items[i],
            fallbackColor: _coiffeur.color,
          ),
        ),
      ]),
    );
  }

  Widget _buildReviews() {
    final reviews = _profile?.reviews ?? const <ReviewEntry>[];
    if (reviews.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '⭐ آراء الحرفاء'),
        const SizedBox(height: 12),
        ...reviews.map((review) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              StarRating(rating: review.rating.toDouble()),
              const Spacer(),
              Text(review.createdAt,
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
            if (review.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(review.comment, style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.text, height: 1.4,
              )),
            ],
          ]),
        )),
      ]),
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({required this.entry, required this.fallbackColor});

  final PortfolioEntry entry;
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    // Les images de démonstration ne sont pas de vrais fichiers : on retombe
    // proprement sur une tuile colorée plutôt qu'un carré cassé.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: fallbackColor.withValues(alpha: 0.25)),
          if (entry.imageUrl.startsWith('http'))
            Image.network(
              entry.imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (entry.likes > 0)
            Positioned(
              bottom: 6, right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text('❤️ ${entry.likes}',
                    style: GoogleFonts.dmSans(fontSize: 10, color: Colors.white)),
              ),
            ),
        ],
      ),
    );
  }
}
