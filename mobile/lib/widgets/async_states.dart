import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Indicateur de chargement discret, aux couleurs de l'app.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.gold),
          ),
          if (label != null) ...[
            const SizedBox(height: 14),
            Text(label!, style: AppTextStyle.dmSans(color: AppColors.sub, size: 13)),
          ],
        ],
      ),
    );
  }
}

/// Écran d'erreur avec action de réessai — jamais de page blanche muette.
class AppError extends StatelessWidget {
  const AppError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('📡', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyle.dmSans(color: AppColors.sub, size: 14),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.gold),
                label: Text('Réessayer',
                    style: AppTextStyle.dmSans(
                        color: AppColors.gold, weight: FontWeight.w600)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// État vide explicite (aucun salon, aucun RDV…).
class AppEmpty extends StatelessWidget {
  const AppEmpty({super.key, required this.emoji, required this.title, this.subtitle});

  final String emoji;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: AppTextStyle.playfair(size: 18)),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.dmSans(color: AppColors.sub, size: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Affiche un message d'erreur en bas d'écran, sans casser la navigation.
void showAppSnack(BuildContext context, String message, {bool success = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message, style: AppTextStyle.dmSans(color: Colors.black)),
      backgroundColor: success ? AppColors.green : AppColors.gold,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
}
