import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Rappelle au gérant que son salon attend la vérification LAMSSA (§2.5).
///
/// Sans ce bandeau, un gérant qui ne reçoit aucune réservation croirait
/// l'application en panne : son salon est simplement encore invisible des
/// clients.
class VerificationBanner extends StatelessWidget {
  const VerificationBanner({super.key, required this.status, this.reason = ''});

  /// `pending` ou `rejected` — un salon `verified` n'affiche rien.
  final String status;

  /// Raison du refus saisie dans la console, éventuellement vide.
  final String reason;

  bool get _refuse => status == 'rejected';

  @override
  Widget build(BuildContext context) {
    if (status == 'verified') return const SizedBox.shrink();

    final couleur = _refuse ? AppColors.red : AppColors.gold;
    final titre = _refuse ? 'صالونك ما تقبلش' : 'صالونك في انتظار التثبّت';
    final texte = _refuse
        ? (reason.isNotEmpty ? reason : 'كلّمنا باش نفهمو السبب ونصلّحوه مع بعض.')
        : 'حضّر الخدمات، الفريق، الأوقات والتصاور. '
            'الحرفاء يشوفوه ويحجزو فيه كي نثبّتوه.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: couleur.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: couleur.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_refuse ? '⚠️' : '⏳', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titre,
                    style: AppTextStyle.dmSans(
                        size: 14, weight: FontWeight.w700, color: couleur),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    texte,
                    style: AppTextStyle.dmSans(size: 12.5, color: AppColors.sub)
                        .copyWith(height: 1.5),
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
