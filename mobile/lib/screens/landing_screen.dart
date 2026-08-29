import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

class LandingScreen extends StatefulWidget {
  final VoidCallback onSignIn;
  final VoidCallback onSignUp;
  final VoidCallback onGuest;

  /// Inscription d'un professionnel : même compte, même OTP, mais on enchaîne
  /// sur la création du salon. Le rôle vient du serveur — on ne devient gérant
  /// qu'en ayant un salon, pas en le déclarant.
  final VoidCallback onSignUpPro;

  const LandingScreen({
    super.key,
    required this.onSignIn,
    required this.onSignUp,
    required this.onGuest,
    required this.onSignUpPro,
  });

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _contentCtrl;
  late Animation<double> _ring1;
  late Animation<double> _ring2;
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _taglineFade;
  late Animation<double> _statsFade;
  late Animation<double> _btnFade;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat(reverse: true);
    _contentCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..forward();

    _ring1 = Tween<double>(begin: 0.9, end: 1.05)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut));
    _ring2 = Tween<double>(begin: 1.05, end: 0.95)
        .animate(CurvedAnimation(parent: _bgCtrl, curve: Curves.easeInOut));

    _logoFade = CurvedAnimation(
        parent: _contentCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut));
    _logoSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
        CurvedAnimation(parent: _contentCtrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _taglineFade = CurvedAnimation(
        parent: _contentCtrl, curve: const Interval(0.25, 0.6, curve: Curves.easeOut));
    _statsFade = CurvedAnimation(
        parent: _contentCtrl, curve: const Interval(0.5, 0.8, curve: Curves.easeOut));
    _btnFade = CurvedAnimation(
        parent: _contentCtrl, curve: const Interval(0.7, 1.0, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Animated background gradient
          _buildAnimatedBg(size),
          // Rings
          _buildRings(size),
          // Content
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 2),
                _buildLogo(),
                const SizedBox(height: 24),
                _buildTagline(),
                const SizedBox(height: 32),
                _buildStats(),
                const Spacer(flex: 3),
                _buildButtons(),
                _buildGuest(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBg(Size size) {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (_, __) => Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0.0, -0.3),
            radius: 0.9 + (_bgCtrl.value * 0.2),
            colors: [
              AppColors.gold.withValues(alpha: 0.06 + (_bgCtrl.value * 0.04)),
              const Color(0xFF0A0A18).withValues(alpha: 0.8),
              AppColors.bg,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildRings(Size size) {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (_, __) => Center(
        child: Stack(alignment: Alignment.center, children: [
          // Outer ring
          Transform.scale(
            scale: _ring1.value,
            child: Container(
              width: size.width * 0.85,
              height: size.width * 0.85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
            ),
          ),
          // Middle ring
          Transform.scale(
            scale: _ring2.value,
            child: Container(
              width: size.width * 0.62,
              height: size.width * 0.62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.gold.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
          ),
          // Inner glow
          Container(
            width: size.width * 0.38,
            height: size.width * 0.38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.gold.withValues(alpha: 0.08),
                Colors.transparent,
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildLogo() {
    return FadeTransition(
      opacity: _logoFade,
      child: SlideTransition(
        position: _logoSlide,
        child: Column(children: [
          // Icon mark
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.gold, Color(0xFF8B6914)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 40, spreadRadius: 2),
              ],
            ),
            alignment: Alignment.center,
            child: Text('L', style: GoogleFonts.playfairDisplay(
              fontSize: 38, fontWeight: FontWeight.w900, color: Colors.black,
            )),
          ),
          const SizedBox(height: 18),
          // Brand name
          Text('LAMSSA', style: GoogleFonts.playfairDisplay(
            fontSize: 52, fontWeight: FontWeight.w900, color: AppColors.gold,
            letterSpacing: -1.5,
            shadows: [Shadow(color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 30)],
          )),
          const SizedBox(height: 10),
          // Divider line
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 32, height: 1, color: AppColors.gold.withValues(alpha: 0.4)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('✦', style: TextStyle(fontSize: 10, color: AppColors.gold.withValues(alpha: 0.6))),
            ),
            Container(width: 32, height: 1, color: AppColors.gold.withValues(alpha: 0.4)),
          ]),
        ]),
      ),
    );
  }

  Widget _buildTagline() {
    return FadeTransition(
      opacity: _taglineFade,
      child: Column(children: [
        Text('صالونات البيوتي في يدك', style: GoogleFonts.playfairDisplay(
          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text,
          height: 1.3,
        )),
        const SizedBox(height: 8),
        Text('احجز موعدك مع أحسن الحجامين في تونس', style: GoogleFonts.dmSans(
          fontSize: 14, color: AppColors.sub, height: 1.5,
        )),
      ]),
    );
  }

  Widget _buildStats() {
    final stats = [
      {'value': '2K+', 'label': 'عميل'},
      {'value': '120+', 'label': 'صالون'},
      {'value': '4.9', 'label': 'تقييم'},
    ];
    return FadeTransition(
      opacity: _statsFade,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: stats.asMap().entries.map((e) {
          final isLast = e.key == stats.length - 1;
          return Row(children: [
            Column(children: [
              Text(e.value['value']!, style: GoogleFonts.playfairDisplay(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.gold,
              )),
              Text(e.value['label']!, style: GoogleFonts.dmSans(
                fontSize: 11, color: AppColors.sub,
              )),
            ]),
            if (!isLast)
              Container(
                height: 32, width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                color: AppColors.border,
              ),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildButtons() {
    return FadeTransition(
      opacity: _btnFade,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(children: [
          // Sign Up — primary
          GestureDetector(
            onTap: widget.onSignUp,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.gold, Color(0xFF8B6914)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(color: AppColors.gold.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 8)),
                ],
              ),
              alignment: Alignment.center,
              child: Text('نحجز كحريف ✨', style: GoogleFonts.dmSans(
                fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black,
              )),
            ),
          ),
          const SizedBox(height: 12),
          // Parcours professionnel : distinct dès l'entrée, parce qu'un gérant
          // qui télécharge l'app veut inscrire son salon, pas réserver.
          GestureDetector(
            onTap: widget.onSignUpPro,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('💈', style: TextStyle(fontSize: 17)),
                  const SizedBox(width: 8),
                  Text('عندي صالون', style: GoogleFonts.dmSans(
                    fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text,
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Sign In — outlined
          GestureDetector(
            onTap: widget.onSignIn,
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text('تسجيل الدخول', style: GoogleFonts.dmSans(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold,
              )),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildGuest() {
    return FadeTransition(
      opacity: _btnFade,
      child: GestureDetector(
        onTap: widget.onGuest,
        child: Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('متابعة كضيف', style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.sub,
            )),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, size: 11, color: AppColors.sub),
          ]),
        ),
      ),
    );
  }
}
