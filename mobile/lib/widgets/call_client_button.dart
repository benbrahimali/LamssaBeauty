import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'async_states.dart';

/// Appeler le client d'un rendez-vous en un toucher (§3.3).
///
/// Un client en retard, un créneau à déplacer : le salon doit pouvoir le
/// joindre sans chercher son numéro. Rien ne s'affiche sans numéro.
class CallClientButton extends StatelessWidget {
  const CallClientButton({super.key, required this.phone});

  final String phone;

  Future<void> _appeler(BuildContext context) async {
    final ouvert = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (!ouvert && context.mounted) showAppSnack(context, 'ما نجمناش نعيّطو : $phone');
  }

  @override
  Widget build(BuildContext context) {
    if (phone.trim().isEmpty) return const SizedBox.shrink();
    return IconButton(
      tooltip: phone,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: () => _appeler(context),
      icon: const Icon(Icons.phone_rounded, size: 18, color: AppColors.green),
    );
  }
}
