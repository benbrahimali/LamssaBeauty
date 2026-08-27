import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/env.dart';
import '../data/repositories/portfolio_repository.dart';
import '../state/auth_controller.dart';
import '../state/portfolio_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Fil « En vogue » (§3.8, §8.3).
///
/// Le client découvre des coupes réelles, faites par des coiffeurs joignables,
/// et passe de l'image à la réservation. C'est le levier d'acquisition décrit
/// au §8.3 : on ne vend pas un salon, on montre son travail.
class TrendingScreen extends StatefulWidget {
  const TrendingScreen({super.key, required this.onGoStaff});

  /// Ouvre le profil du coiffeur — d'où part la réservation.
  final void Function(String staffId) onGoStaff;

  @override
  State<TrendingScreen> createState() => _TrendingScreenState();
}

class _TrendingScreenState extends State<TrendingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<PortfolioController>().load(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PortfolioController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(children: [
        _buildHeader(),
        if (controller.tags.isNotEmpty) _buildTags(controller),
        Expanded(child: _buildFeed(controller)),
      ]),
    );
  }

  Widget _buildHeader() => Padding(
        padding:
            EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 12),
        child: Row(children: [
          Text('في الموضة', style: AppTextStyle.playfair(size: 28)),
          const SizedBox(width: 8),
          const Text('🔥', style: TextStyle(fontSize: 22)),
        ]),
      );

  Widget _buildTags(PortfolioController controller) {
    final tags = <String?>[null, ...controller.tags];
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: tags.length,
        itemBuilder: (_, i) {
          final tag = tags[i];
          final active = controller.activeTag == tag;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => controller.filterByTag(tag),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.gold : AppColors.card,
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                      color: active ? AppColors.gold : AppColors.border),
                ),
                child: Text(
                  tag == null ? 'الكل' : '#$tag',
                  style: AppTextStyle.dmSans(
                    size: 13,
                    color: active ? Colors.black : AppColors.sub,
                    weight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeed(PortfolioController controller) {
    if (controller.loading && controller.posts.isEmpty) return const AppLoader();
    if (controller.error != null && controller.posts.isEmpty) {
      return AppError(
        message: controller.error!,
        onRetry: () => controller.load(force: true),
      );
    }
    if (controller.posts.isEmpty) {
      return const AppEmpty(
        emoji: '📸',
        title: 'ما فماش تصاور توّا',
        subtitle: 'الحجامة باش يبدأوا ينشروا خدمتهم قريب',
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: () => controller.load(force: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
        itemCount: controller.posts.length,
        itemBuilder: (_, i) => _PostCard(
          post: controller.posts[i],
          onLike: () => _like(controller, controller.posts[i]),
          onOpenStaff: () => widget.onGoStaff(controller.posts[i].staffId),
        ),
      ),
    );
  }

  void _like(PortfolioController controller, PortfolioPost post) {
    // Aimer exige un compte : sans ce garde-fou l'appel repart en 401 et le
    // cœur se rallume tout seul, ce qui est incompréhensible pour l'utilisateur.
    if (context.read<AuthController>().status != AuthStatus.loggedIn) {
      showAppSnack(context, 'لازم تسجّل دخول باش تعمل إعجاب');
      return;
    }
    controller.toggleLike(post);
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({
    required this.post,
    required this.onLike,
    required this.onOpenStaff,
  });

  final PortfolioPost post;
  final VoidCallback onLike;
  final VoidCallback onOpenStaff;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 1,
          child: CachedNetworkImage(
            imageUrl: Env.mediaUrl(post.imageUrl),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: AppColors.card2,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.gold),
            ),
            // Une photo manquante ne doit pas casser le fil : le reste de la
            // carte (coiffeur, salon, tags) garde sa valeur.
            errorWidget: (_, __, ___) => Container(
              color: AppColors.card2,
              alignment: Alignment.center,
              child: const Text('🖼️', style: TextStyle(fontSize: 32)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: onOpenStaff,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.staffName.isEmpty ? 'حجّام' : post.staffName,
                          style: AppTextStyle.dmSans(weight: FontWeight.w700)),
                      if (post.salonName.isNotEmpty)
                        Text(post.salonName,
                            style: AppTextStyle.dmSans(
                                size: 12, color: AppColors.sub)),
                    ],
                  ),
                ),
              ),
              GestureDetector(
                onTap: onLike,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(children: [
                    Icon(
                      post.likedByMe
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 20,
                      color: post.likedByMe ? AppColors.red : AppColors.sub,
                    ),
                    const SizedBox(width: 6),
                    Text('${post.likes}',
                        style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
                  ]),
                ),
              ),
            ]),
            if (post.caption.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(post.caption,
                  style: AppTextStyle.dmSans(size: 13).copyWith(height: 1.5)),
            ],
            if (post.tags.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: post.tags
                    .map((t) => Text('#$t',
                        style: AppTextStyle.dmSans(size: 12, color: AppColors.gold)))
                    .toList(),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.gold,
                  side: BorderSide(color: AppColors.gold.withValues(alpha: 0.4)),
                  minimumSize: const Size.fromHeight(44),
                  shape:
                      RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: onOpenStaff,
                child: Text('احجز مع هالحجّام',
                    style: AppTextStyle.dmSans(
                        color: AppColors.gold, weight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
