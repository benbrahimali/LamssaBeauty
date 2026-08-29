import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Modération des avis (§3.8).
///
/// Masquer n'efface pas : l'avis reste visible du gérant et peut être
/// republié. Une suppression définitive transformerait l'outil de modération
/// en outil de censure, et les avis d'une plateforme n'ont de valeur que si on
/// ne peut pas faire disparaître les mauvais.
class ReviewsModerationSheet extends StatefulWidget {
  const ReviewsModerationSheet({super.key, required this.salonId});

  final String salonId;

  static Future<void> show(BuildContext context, String salonId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReviewsModerationSheet(salonId: salonId),
    );
  }

  @override
  State<ReviewsModerationSheet> createState() => _ReviewsModerationSheetState();
}

class _ReviewsModerationSheetState extends State<ReviewsModerationSheet> {
  List<SalonReview> _reviews = const [];
  bool _loading = true;
  String? _error;

  SalonAdminRepository get _repo => context.read<SalonAdminRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repo.reviews(widget.salonId);
      if (!mounted) return;
      setState(() { _reviews = rows; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _toggle(SalonReview review) async {
    final index = _reviews.indexWhere((r) => r.id == review.id);
    if (index < 0) return;

    final before = _reviews[index];
    setState(() {
      _reviews = [..._reviews]..[index] = before.copyWith(hidden: !before.hidden);
    });

    try {
      await _repo.moderateReview(review.id, hide: !before.hidden);
      if (!mounted) return;
      // La note du salon est recalculée côté serveur : masquer un avis doit
      // aussi le retirer de la moyenne.
      showAppSnack(
        context,
        before.hidden ? 'التقييم رجع ظاهر' : 'التقييم تخبّى',
        success: true,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _reviews = [..._reviews]..[index] = before);
      showAppSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),
        Text('التقييمات', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 4),
        Text('تنجّم تخبّي تقييم مسيء — يرجع وقت ما تحب',
            textAlign: TextAlign.center,
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        const SizedBox(height: 18),
        Flexible(child: _buildList()),
      ]),
    );
  }

  Widget _buildList() {
    if (_loading) return const SizedBox(height: 160, child: AppLoader());
    if (_error != null) {
      return SizedBox(height: 180, child: AppError(message: _error!, onRetry: _load));
    }
    if (_reviews.isEmpty) {
      return const AppEmpty(
        emoji: '⭐',
        title: 'ما فماش تقييمات',
        subtitle: 'الحرفاء ينقّطو بعد ما يكمّلو موعدهم',
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _reviews.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final review = _reviews[i];
        return Opacity(
          // Un avis masqué reste lisible, en retrait : le gérant doit voir ce
          // qu'il a caché, sinon il ne le republiera jamais.
          opacity: review.hidden ? 0.45 : 1,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ...List.generate(5, (s) => Icon(
                      s < review.rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 15,
                      color: AppColors.gold,
                    )),
                const Spacer(),
                if (review.hidden)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text('مخبّي',
                        style: AppTextStyle.dmSans(size: 10, color: AppColors.red)),
                  ),
              ]),
              if (review.comment.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(review.comment,
                    style: AppTextStyle.dmSans(size: 13).copyWith(height: 1.5)),
              ],
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _toggle(review),
                behavior: HitTestBehavior.opaque,
                child: Row(children: [
                  Icon(
                    review.hidden
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                    color: review.hidden ? AppColors.green : AppColors.sub,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    review.hidden ? 'رجّعو' : 'خبّيه',
                    style: AppTextStyle.dmSans(
                      size: 12,
                      color: review.hidden ? AppColors.green : AppColors.sub,
                      weight: FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}
