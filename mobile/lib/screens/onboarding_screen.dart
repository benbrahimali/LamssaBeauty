import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/breathing.dart';
import '../widgets/common_widgets.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinish;
  const OnboardingScreen({super.key, required this.onFinish});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PageController();
  int _page = 0;

  static const _slides = [
    _Slide(
      emoji: '💈',
      title: 'احجز في ثواني',
      subtitle: 'اختار صالونك المفضل، الحجام، الوقت — وتأكد الحجز فوراً بدون انتظار.',
    ),
    _Slide(
      emoji: '⭐',
      title: 'حجامين ترند',
      subtitle: 'اكتشف أحسن الحجامين في منطقتك مع تقييمات حقيقية وأعمال مباشرة.',
    ),
    _Slide(
      emoji: '🧬',
      title: 'Style DNA بالـ AI',
      subtitle: 'حط سيلفي والذكاء الاصطناعي يقترحلك أحسن ستايل يناسب وجهك.',
    ),
  ];

  /// Même respiration que le splash : l'onboarding le suit immédiatement,
  /// deux traitements différents se verraient comme une rupture.
  late final AnimationController _pulseCtrl =
      AnimationController(vsync: this, duration: breathingCycle);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    syncBreathing(context, _pulseCtrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _ctrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      widget.onFinish();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 24, 0),
                child: GestureDetector(
                  onTap: widget.onFinish,
                  child: Text('تخطى', style: GoogleFonts.dmSans(
                    fontSize: 14, color: AppColors.sub,
                  )),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _buildSlide(_slides[i]),
              ),
            ),
            _buildDots(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GoldButton(
                text: _page < _slides.length - 1 ? 'التالي →' : 'ابدأ الآن ✨',
                onPressed: _next,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlide(_Slide slide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Isolé du reste : seul ce sous-arbre se repeint à chaque image.
          RepaintBoundary(
            child: Stack(alignment: Alignment.center, children: [
              BreathingHalo(controller: _pulseCtrl, size: 210),
              // L'anneau extérieur culmine après l'intérieur : ce retard fait
              // lire une onde partant de l'icône, pas un simple zoom.
              BreathingRing(
                controller: _pulseCtrl,
                phase: -0.09,
                size: 196,
                restOpacity: 0.07,
              ),
              BreathingRing(
                controller: _pulseCtrl,
                size: 140,
                restOpacity: 0.2,
                // L'icône ne change pas de taille avec l'anneau : un emoji mis
                // à l'échelle devient flou.
                child: Text(slide.emoji, style: const TextStyle(fontSize: 60)),
              ),
            ]),
          ),
          const SizedBox(height: 40),
          Text(slide.title, style: GoogleFonts.playfairDisplay(
            fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text,
            height: 1.2,
          ), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(slide.subtitle, style: GoogleFonts.dmSans(
            fontSize: 15, color: AppColors.sub, height: 1.6,
          ), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slides.length, (i) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        width: _page == i ? 24 : 8,
        height: 8,
        decoration: BoxDecoration(
          color: _page == i ? AppColors.gold : AppColors.border,
          borderRadius: BorderRadius.circular(4),
        ),
      )),
    );
  }
}

class _Slide {
  final String emoji;
  final String title;
  final String subtitle;
  const _Slide({required this.emoji, required this.title, required this.subtitle});
}
