import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/salon_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';
import 'common_widgets.dart';

/// La note du coiffeur sur son tableau de bord (§3.8).
///
/// Il recevait « Nouvel avis 2/5 » sans pouvoir le lire, et ne voyait nulle
/// part la note que les clients voient sur sa carte.
class MyRatingCard extends StatelessWidget {
  const MyRatingCard({super.key, required this.reviews, this.onTap});

  final MyReviews? reviews;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = reviews;
    if (r == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: GestureDetector(
        onTap: r.hasReviews ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: r.hasReviews
              ? Row(children: [
                  Text(r.ratingAvg.toStringAsFixed(1),
                      style: AppTextStyle.playfair(size: 30, color: AppColors.gold)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('⭐ تقييمي',
                          style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(children: [
                        // Une étoile seule : `StarRating` réécrirait la note
                        // déjà affichée en grand juste à côté.
                        const Icon(Icons.star_rounded, size: 14, color: AppColors.gold),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('${r.ratingCount} رأي',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
                        ),
                      ]),
                    ]),
                  ),
                  const Icon(Icons.chevron_left, size: 18, color: AppColors.sub),
                ])
              : Row(children: [
                  const Text('⭐', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'مازال ما عندك حتى تقييم — كل زبون تخدمو ينجم يقيّمك بعد الخدمة',
                      style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)
                          .copyWith(height: 1.5),
                    ),
                  ),
                ]),
        ),
      ),
    );
  }
}

/// Les avis reçus par le coiffeur, anonymes, du plus récent au plus ancien.
class MyReviewsSheet extends StatefulWidget {
  const MyReviewsSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const MyReviewsSheet(),
      );

  @override
  State<MyReviewsSheet> createState() => _MyReviewsSheetState();
}

class _MyReviewsSheetState extends State<MyReviewsSheet> {
  MyReviews? _reviews;
  String? _error;
  bool _loading = true;

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
      final r = await context.read<SalonRepository>().myReviews();
      if (!mounted) return;
      setState(() {
        _reviews = r;
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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),
        Text('آراء الحرفاء', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 14),
        Flexible(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SingleChildScrollView(
        child: Padding(padding: EdgeInsets.symmetric(vertical: 50), child: AppLoader()),
      );
    }
    if (_error != null) {
      return SingleChildScrollView(child: AppError(message: _error!, onRetry: _load));
    }
    final r = _reviews!;
    if (r.reviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Text('مازال ما عندك حتى رأي',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(r.ratingAvg.toStringAsFixed(1),
            style: AppTextStyle.playfair(size: 36, color: AppColors.gold)),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.star_rounded, size: 18, color: AppColors.gold),
          const SizedBox(height: 4),
          Text('${r.ratingCount} رأي',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        ]),
      ]),
      const SizedBox(height: 6),
      // Dit pourquoi aucun nom n'apparaît, avant qu'on le demande.
      Text('الآراء ما فيهاش أسامي الحرفاء',
          style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
      const SizedBox(height: 14),
      Flexible(
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: r.reviews.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final avis = r.reviews[i];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.card2,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  StarRating(rating: avis.rating.toDouble()),
                  const Spacer(),
                  Text(avis.createdAt,
                      style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
                ]),
                if (avis.comment.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(avis.comment,
                      style: AppTextStyle.dmSans(size: 13).copyWith(height: 1.5)),
                ],
              ]),
            );
          },
        ),
      ),
    ]);
  }
}
