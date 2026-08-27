import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onContinue;
  const SplashScreen({super.key, required this.onContinue});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _subFade;
  late Animation<double> _btnFade;
  bool _showBtn = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));

    _logoFade  = CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut));
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _subFade   = CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.65, curve: Curves.easeOut));
    _btnFade   = CurvedAnimation(parent: _ctrl, curve: const Interval(0.65, 1.0, curve: Curves.easeOut));

    _ctrl.forward();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _showBtn = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF1A1200), AppColors.bg],
            stops: [0.0, 0.7],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Decorative rings
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 280, height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.08), width: 1),
                    ),
                  ),
                  Container(
                    width: 200, height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.gold.withValues(alpha: 0.12), width: 1),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      FadeTransition(
                        opacity: _logoFade,
                        child: SlideTransition(
                          position: _logoSlide,
                          child: Text(
                            'LAMSSA',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: AppColors.gold,
                              letterSpacing: -2,
                              shadows: [
                                Shadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 40),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Divider line
                      FadeTransition(
                        opacity: _subFade,
                        child: Container(
                          width: 60, height: 2,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              Colors.transparent,
                              AppColors.gold,
                              Colors.transparent,
                            ]),
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Subtitle
                      FadeTransition(
                        opacity: _subFade,
                        child: Text(
                          'SALONS & BEAUTÉ',
                          style: GoogleFonts.dmSans(
                            fontSize: 11,
                            letterSpacing: 6,
                            color: AppColors.sub,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Emoji row
              FadeTransition(
                opacity: _subFade,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: ['💈', '✂️', '💅', '✨'].map((e) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 48),
              // CTA Button
              if (_showBtn)
                FadeTransition(
                  opacity: _btnFade,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: GestureDetector(
                      onTap: widget.onContinue,
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gold.withValues(alpha: 0.4),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'ابدأ الآن ✨',
                          style: GoogleFonts.dmSans(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
