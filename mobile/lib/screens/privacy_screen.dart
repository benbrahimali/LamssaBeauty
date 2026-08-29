import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/env.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Sécurité et confidentialité (§2.5, loi tunisienne 2004-63).
///
/// Ce n'est pas une page d'habillage : le Play Store refuse une app qui touche
/// à la caméra et à la position sans dire ce qu'elle en fait. Le texte décrit
/// donc le comportement réel du code — notamment que le selfie de Style DNA
/// n'est ni stocké ni rattaché au compte.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    (
      '🔐',
      'كيفاش نأمّنو حسابك',
      'ما فماش كلمة سر. تدخل بكود يوصلك في SMS، والجلسة تتجدّد أوتوماتيك. '
          'كي تخرج، الجهاز يتشطب من قائمة الإشعارات.',
    ),
    (
      '📍',
      'الموقع',
      'نستعملوه وقت تدوّر على صالونات قريبة، ووقت صاحب الصالون يسجّل صالونو. '
          'ما نتبعوش موقعك في الخلفية.',
    ),
    (
      '🤳',
      'تصويرة Style DNA',
      'التصويرة تتبعث للتحليل وما تتحفظش: لا في السيرفر، لا في حسابك، لا في '
          'السجلّات. كي تحب تجرّب القصّة على وجهك، نسألوك صراحة قبل.',
    ),
    (
      '💳',
      'الخلاص',
      'ما نحفظوش معطيات بطاقتك. الخلاص يصير عند مزوّد معتمد، وإحنا نعرفو كان '
          'النتيجة: خلّص ولا لا.',
    ),
    (
      '📊',
      'شنوّة نحفظو',
      'رقم تليفونك، اسمك، مواعيدك وتقييماتك. هاذم ضروريين باش التطبيق يخدم.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text('الأمان والخصوصية', style: AppTextStyle.playfair(size: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          ..._sections.map((s) => _Section(emoji: s.$1, title: s.$2, body: s.$3)),
          const SizedBox(height: 8),

          if (auth.status == AuthStatus.loggedIn) ...[
            _DangerTile(
              icon: Icons.logout_rounded,
              label: 'اخرج من هالجهاز',
              // Le retrait du token FCM se fait dans `logout()`, tant que le
              // JWT est encore valide : sinon l'appareil continuerait de
              // recevoir les notifications du compte.
              onTap: () async {
                await auth.logout();
                if (context.mounted) Navigator.of(context).maybePop();
              },
            ),
            const SizedBox(height: 10),
            _DangerTile(
              icon: Icons.delete_forever_rounded,
              label: 'تحب تمسح حسابك ؟',
              onTap: () => _contactForDeletion(context),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'خادم: ${Env.apiBaseUrl}',
            textAlign: TextAlign.center,
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
        ],
      ),
    );
  }

  /// La suppression de compte n'existe pas encore côté serveur : on ouvre un
  /// canal humain plutôt que d'afficher un bouton qui ne ferait rien.
  Future<void> _contactForDeletion(BuildContext context) async {
    final uri = Uri.parse(
      'mailto:contact@lamssa.tn?subject=${Uri.encodeComponent('طلب مسح حساب')}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (context.mounted) {
      showAppSnack(context, 'ابعثلنا على contact@lamssa.tn');
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.emoji, required this.title, required this.body});

  final String emoji;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 8),
        Text(body,
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)
                .copyWith(height: 1.7)),
      ]),
    );
  }
}

class _DangerTile extends StatelessWidget {
  const _DangerTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: AppTextStyle.dmSans(size: 13, color: AppColors.red)),
          ),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.red),
        ]),
      ),
    );
  }
}
