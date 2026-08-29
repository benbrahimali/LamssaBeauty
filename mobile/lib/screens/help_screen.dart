import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Aide (§2.5).
///
/// Les questions listées sont celles qui feront revenir un client vers le
/// support si personne n'y répond ici : annuler, être remboursé, ne pas voir
/// de créneau. Le contact WhatsApp est en tête parce que c'est le canal que
/// les salons tunisiens utilisent déjà.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  /// Numéro du support. À remplacer par la ligne réelle avant le pilote.
  static const supportPhone = '+21699000000';

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  static const _faq = [
    (
      'كيفاش نحجز ؟',
      'اختار الصالون، الخدمة، الحجّام والوقت. الحجز يتأكّد ديركت كان الصالون '
          'يقبل بلا خلاص، وإلا بعد ما تخلّص.',
    ),
    (
      'نجّم نلغي موعدي ؟',
      'إيه، من « مواعيدي ». كل صالون يحدّد المهلة — عادة ساعتين قبل الموعد. '
          'بعد المهلة، كلّم الصالون ديركت.',
    ),
    (
      'خلّصت وما جاش الموعد، شنوّة نعمل ؟',
      'صاحب الصالون ينجّم يرجّعلك الفلوس من التطبيق. الترجيع يوصلك بنفس '
          'الطريقة اللي خلّصت بيها.',
    ),
    (
      'علاش ما فماش أوقات فارغة ؟',
      'يعني الحجّام معمّر، ولا الصالون مسكّر هالنهار، ولا هو في عطلة. '
          'جرّب نهار آخر ولا حجّام آخر.',
    ),
    (
      'شنوّة هو Style DNA ؟',
      'تحطّ سيلفي، والذكاء الاصطناعي يقترحلك قصّات تناسب شكل وجهك، ويوريك '
          'الحجّامة اللي يعرفو يعملوها قريب منك. التصويرة ما تتحفظش.',
    ),
    (
      'عندي صالون، كيفاش نسجّلو ؟',
      'من « حسابي » → « أنشئ صالون ». ديما تزيد خدماتك وفريقك، وتلقى كود QR '
          'تحطّو في الفيترينة.',
    ),
  ];

  int? _open;

  Future<void> _openUrl(Uri uri, String repli) async {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      showAppSnack(context, repli);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text('المساعدة', style: AppTextStyle.playfair(size: 20)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Row(children: [
            Expanded(
              child: _ContactCard(
                emoji: '💬',
                label: 'WhatsApp',
                color: AppColors.green,
                onTap: () => _openUrl(
                  Uri.parse('https://wa.me/'
                      '${HelpScreen.supportPhone.replaceAll(RegExp(r"[^0-9]"), "")}'),
                  'ما لقيناش WhatsApp في هالجهاز',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ContactCard(
                emoji: '📞',
                label: 'تليفون',
                color: AppColors.gold,
                onTap: () => _openUrl(
                  Uri.parse('tel:${HelpScreen.supportPhone}'),
                  HelpScreen.supportPhone,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Text('أسئلة متداولة',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 10),
          ...List.generate(_faq.length, (i) {
            final (question, reponse) = _faq[i];
            final open = _open == i;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                GestureDetector(
                  // Une seule réponse ouverte à la fois : la liste reste
                  // parcourable au pouce.
                  onTap: () => setState(() => _open = open ? null : i),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: Text(question,
                            style: AppTextStyle.dmSans(
                                size: 13, weight: FontWeight.w600)),
                      ),
                      Icon(
                        open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        size: 20,
                        color: AppColors.sub,
                      ),
                    ]),
                  ),
                ),
                if (open)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(reponse,
                          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)
                              .copyWith(height: 1.7)),
                    ),
                  ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.emoji,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 6),
          Text(label,
              style: AppTextStyle.dmSans(
                  size: 13, color: color, weight: FontWeight.w700)),
        ]),
      ),
    );
  }
}
