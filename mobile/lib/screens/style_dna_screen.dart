import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/style_dna_repository.dart';
import '../state/salons_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/style_preview_sheet.dart';
import '../widgets/common_widgets.dart';

// ── Step enum ────────────────────────────────────────────────────
enum _DnaStep { intro, upload, scanning, results, error }

/// Style DNA (§2.4 « Could », §8.5) — analyse d'un selfie par un modèle vision.
///
/// Le selfie part vers `POST /style-dna/analyze` ; c'est le backend qui détient
/// la clé du modèle et qui ne conserve pas l'image. L'écran n'invente jamais de
/// résultat : sans visage détecté ou sans réponse, il le dit.
class StyleDnaScreen extends StatefulWidget {
  final VoidCallback onBack;

  /// Ouvre le profil du coiffeur proposé pour une coupe — d'où part la
  /// réservation. Null quand l'écran est ouvert hors du shell principal.
  final void Function(String staffId)? onGoStaff;

  const StyleDnaScreen({super.key, required this.onBack, this.onGoStaff});

  @override
  State<StyleDnaScreen> createState() => _StyleDnaScreenState();
}

class _StyleDnaScreenState extends State<StyleDnaScreen>
    with TickerProviderStateMixin {
  _DnaStep _step = _DnaStep.intro;
  File? _selfie;
  StyleDnaResult? _result;
  String _error = '';

  // Animations
  late AnimationController _pulseCtrl;
  late AnimationController _scanCtrl;
  late AnimationController _revealCtrl;
  late Animation<double> _pulse;
  late Animation<double> _scanLine;
  late Animation<double> _reveal;
  double _scanProgress = 0;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
    _scanCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _revealCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

    _pulse = Tween<double>(begin: 0.96, end: 1.04)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _scanLine = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));
    _reveal = CurvedAnimation(parent: _revealCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _revealCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() { _selfie = File(picked.path); _step = _DnaStep.scanning; });
        _startScan();
      }
    } catch (_) {
      if (mounted) _fail('ما نجمناش نفتحو الصورة. جرب مرة أخرى.');
    }
  }

  void _fail(String message) {
    _scanCtrl.stop();
    setState(() {
      _error = message;
      _step = _DnaStep.error;
      _scanProgress = 0;
    });
  }

  /// Envoie le selfie au backend et attend l'analyse réelle.
  ///
  /// La barre de progression avance pendant l'appel : elle plafonne à 90 % tant
  /// que la réponse n'est pas là, pour ne jamais afficher « terminé » avant de
  /// l'être. La durée de l'analyse n'est pas connue d'avance.
  /// La génération d'images est un second fournisseur, indépendant de
  /// l'analyse : sans sa clé, on n'affiche pas de bouton qui mènerait à un 503.
  bool _imagesAvailable = false;

  Future<void> _loadImageAvailability() async {
    final status = await context.read<StyleDnaRepository>().status();
    if (mounted) setState(() => _imagesAvailable = status.images);
  }

  Future<void> _startScan() async {
    final selfie = _selfie;
    if (selfie == null) return _fail('Aucune photo sélectionnée.');

    _scanCtrl.repeat();
    setState(() => _scanProgress = 0);

    final ticker = Stream.periodic(const Duration(milliseconds: 260)).listen((_) {
      if (!mounted) return;
      setState(() => _scanProgress = (_scanProgress + 0.06).clamp(0.0, 0.9));
    });

    try {
      // Position déjà accordée (écran Explorer) : on la réutilise pour que
      // chaque coupe conseillée pointe vers des coiffeurs joignables. On ne la
      // redemande pas ici — une popup de permission au milieu de l'analyse
      // ferait perdre le fil.
      final salons = context.read<SalonsController>();
      final result = await context.read<StyleDnaRepository>().analyze(
            selfie,
            lat: salons.lat,
            lng: salons.lng,
          );
      if (!mounted) return;

      if (!result.faceDetected || result.styles.isEmpty) {
        _fail('ما لقيناش وجه واضح في الصورة. صوّر وجهك من قدّام في ضوء مليح.');
        return;
      }
      _scanCtrl.stop();
      setState(() {
        _scanProgress = 1;
        _result = result;
        _step = _DnaStep.results;
      });
      unawaited(_loadImageAvailability());
      _revealCtrl.forward();
    } on ApiException catch (e) {
      if (mounted) _fail(e.message);
    } finally {
      await ticker.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: _buildStep(),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _DnaStep.intro:   return _buildIntro();
      case _DnaStep.upload:  return _buildUpload();
      case _DnaStep.scanning: return _buildScanning();
      case _DnaStep.results:  return _buildResults();
      case _DnaStep.error:    return _buildError();
    }
  }

  // ── Échec — on le dit, on n'invente pas de résultat ─────────────
  Widget _buildError() {
    return Column(
      key: const ValueKey('error'),
      children: [
        _buildBackHeader('Style DNA 🧬'),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('😕', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 18),
                Text('التحليل ما نجحش',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text,
                    )),
                const SizedBox(height: 10),
                Text(_error,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmSans(
                      fontSize: 14, color: AppColors.sub, height: 1.6,
                    )),
                const SizedBox(height: 32),
                GoldButton(
                  text: 'جرب صورة أخرى',
                  onPressed: () => setState(() {
                    _step = _DnaStep.upload;
                    _selfie = null;
                    _error = '';
                    _scanProgress = 0;
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 1 — Intro ─────────────────────────────────────────────
  Widget _buildIntro() {
    return Column(
      key: const ValueKey('intro'),
      children: [
        _buildBackHeader('Style DNA 🧬'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [
              const SizedBox(height: 20),
              // Hero DNA visual
              _buildDnaHero(),
              const SizedBox(height: 32),
              Text('شوف ستايلك المناسب', style: GoogleFonts.playfairDisplay(
                fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text,
                height: 1.3,
              ), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'حط سيلفي والذكاء الاصطناعي يحلل شكل وجهك ويقترحلك أحسن الستايلات اللي تناسبك.',
                style: GoogleFonts.dmSans(fontSize: 14, color: AppColors.sub, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 36),
              // Feature list
              ..._introFeatures.map(_buildFeatureRow),
              const SizedBox(height: 36),
              GoldButton(text: 'ابدأ الآن 🧬', onPressed: () => setState(() => _step = _DnaStep.upload)),
              const SizedBox(height: 14),
              Text('✅ خاصوصيتك محمية — الصورة ما تتحفظش',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
          ),
        ),
      ],
    );
  }

  static const _introFeatures = [
    _Feature('🔍', 'تحليل شكل الوجه', 'AI يكشف شكل وجهك: بيضاوي، مربع، مدور...'),
    _Feature('✂️', 'ستايلات مخصصة', '5+ اقتراحات تناسب وجهك مباشرة'),
    _Feature('👨‍🎨', 'حجامين متخصصين', 'تواصل مع الحجام الأمثل لستايلك'),
  ];

  Widget _buildFeatureRow(_Feature f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(f.emoji, style: const TextStyle(fontSize: 22)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(f.title, style: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text,
          )),
          Text(f.desc, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
        ])),
      ]),
    );
  }

  Widget _buildDnaHero() {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: Stack(alignment: Alignment.center, children: [
          // Outer pulse ring
          Container(
            width: 200, height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.gold.withValues(alpha: 0.06),
                Colors.transparent,
              ]),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.1), width: 1),
            ),
          ),
          Container(
            width: 150, height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.gold.withValues(alpha: 0.1),
                Colors.transparent,
              ]),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.2), width: 1),
            ),
          ),
          // Core circle
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.gold.withValues(alpha: 0.3), AppColors.gold.withValues(alpha: 0.08)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.5), width: 1.5),
            ),
            alignment: Alignment.center,
            child: const Text('🧬', style: TextStyle(fontSize: 44)),
          ),
        ]),
      ),
    );
  }

  // ── Step 2 — Upload ────────────────────────────────────────────
  Widget _buildUpload() {
    return Column(
      key: const ValueKey('upload'),
      children: [
        _buildBackHeader('اختار صورتك'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(children: [
              // Face placeholder
              _buildFacePlaceholder(),
              const SizedBox(height: 28),
              Text('اختار طريقة التحميل', style: GoogleFonts.playfairDisplay(
                fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text,
              )),
              const SizedBox(height: 8),
              Text('حط وجهك في المنتصف وتأكد الإضاءة كاملة',
                style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
              const SizedBox(height: 28),
              // Camera button
              _buildUploadOption(
                icon: Icons.camera_alt_rounded,
                label: 'التقاط سيلفي 📸',
                desc: 'استعمل الكاميرا الأمامية مباشرة',
                color: AppColors.gold,
                onTap: () => _pickImage(ImageSource.camera),
              ),
              const SizedBox(height: 12),
              // Gallery button
              _buildUploadOption(
                icon: Icons.photo_library_rounded,
                label: 'من المعرض 🖼️',
                desc: 'اختار صورة موجودة في هاتفك',
                color: AppColors.teal,
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(height: 28),
              // Tips
              _buildPhotoTips(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildFacePlaceholder() {
    return Center(
      child: Container(
        width: 200, height: 240,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(120),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3), width: 2),
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(alignment: Alignment.center, children: [
          // Face outline guide
          CustomPaint(painter: _FaceGuidePainter(), size: const Size(200, 240)),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.face_retouching_natural_rounded,
                size: 64, color: AppColors.gold.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text('وجهك هنا', style: GoogleFonts.dmSans(
              fontSize: 13, color: AppColors.sub.withValues(alpha: 0.6),
            )),
          ]),
        ]),
      ),
    );
  }

  Widget _buildUploadOption({
    required IconData icon,
    required String label,
    required String desc,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25), width: 1.5),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: GoogleFonts.dmSans(
              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text,
            )),
            const SizedBox(height: 3),
            Text(desc, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
          ])),
          Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color),
        ]),
      ),
    );
  }

  Widget _buildPhotoTips() {
    final tips = ['إضاءة كاملة أمام وجهك 💡', 'شكل وجهك يكون واضح 👤', 'بعد 40-60 سم من الشاشة 📏'];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('💡 نصائح للصورة المثالية', style: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold,
        )),
        const SizedBox(height: 10),
        ...tips.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Container(width: 5, height: 5,
              decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(t, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
          ]),
        )),
      ]),
    );
  }

  // ── Step 3 — Scanning ──────────────────────────────────────────
  Widget _buildScanning() {
    return Column(
      key: const ValueKey('scanning'),
      children: [
        SizedBox(height: MediaQuery.of(context).padding.top + 20),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Scanning animation
              _buildScanAnimation(),
              const SizedBox(height: 40),
              Text('يحلل وجهك...', style: GoogleFonts.playfairDisplay(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text,
              )),
              const SizedBox(height: 10),
              Text(_scanStepLabel(), style: GoogleFonts.dmSans(
                fontSize: 13, color: AppColors.gold,
              )),
              const SizedBox(height: 28),
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _scanProgress,
                      backgroundColor: AppColors.card,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${(_scanProgress * 100).toInt()}%', style: GoogleFonts.dmSans(
                    fontSize: 12, color: AppColors.sub,
                  )),
                ]),
              ),
              const SizedBox(height: 36),
              // Analysis steps
              _buildAnalysisSteps(),
            ],
          ),
        ),
      ],
    );
  }

  String _scanStepLabel() {
    if (_scanProgress < 0.3) return 'كشف معالم الوجه...';
    if (_scanProgress < 0.6) return 'تحليل شكل الوجه...';
    if (_scanProgress < 0.85) return 'مقارنة مع قاعدة البيانات...';
    return 'تجهيز الاقتراحات...';
  }

  Widget _buildScanAnimation() {
    return SizedBox(
      width: 220, height: 260,
      child: Stack(alignment: Alignment.center, children: [
        // Face oval
        Container(
          width: 190, height: 240,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(95),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 2),
          ),
          clipBehavior: Clip.hardEdge,
          child: _selfie != null
              ? Image.file(_selfie!, fit: BoxFit.cover)
              : Container(
                  color: AppColors.card,
                  child: Icon(Icons.face_retouching_natural_rounded,
                      size: 80, color: AppColors.gold.withValues(alpha: 0.3)),
                ),
        ),
        // Scanning line overlay
        AnimatedBuilder(
          animation: _scanLine,
          builder: (_, __) => Positioned(
            top: _scanLine.value * 220,
            left: 15, right: 15,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  AppColors.gold.withValues(alpha: 0.9),
                  AppColors.gold,
                  AppColors.gold.withValues(alpha: 0.9),
                  Colors.transparent,
                ]),
                boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.6), blurRadius: 8)],
              ),
            ),
          ),
        ),
        // Corner brackets
        ..._scanCorners(),
      ]),
    );
  }

  List<Widget> _scanCorners() {
    const size = 20.0;
    const w = 3.0;
    const color = AppColors.gold;
    return [
      Positioned(top: 10, left: 15,
          child: _corner(size, w, color, topLeft: true)),
      Positioned(top: 10, right: 15,
          child: _corner(size, w, color, topRight: true)),
      Positioned(bottom: 10, left: 15,
          child: _corner(size, w, color, bottomLeft: true)),
      Positioned(bottom: 10, right: 15,
          child: _corner(size, w, color, bottomRight: true)),
    ];
  }

  Widget _corner(double size, double w, Color color, {
    bool topLeft = false, bool topRight = false,
    bool bottomLeft = false, bool bottomRight = false,
  }) {
    return CustomPaint(
      size: Size(size, size),
      painter: _CornerPainter(
        color: color, strokeWidth: w,
        topLeft: topLeft, topRight: topRight,
        bottomLeft: bottomLeft, bottomRight: bottomRight,
      ),
    );
  }

  Widget _buildAnalysisSteps() {
    final steps = [
      ('معالم الوجه', _scanProgress >= 0.3),
      ('شكل الوجه', _scanProgress >= 0.6),
      ('الستايلات المقترحة', _scanProgress >= 0.85),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: steps.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: s.$2 ? AppColors.gold : AppColors.card,
                border: Border.all(color: s.$2 ? AppColors.gold : AppColors.border),
              ),
              child: s.$2
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(s.$1, style: GoogleFonts.dmSans(
              fontSize: 13,
              color: s.$2 ? AppColors.text : AppColors.sub,
              fontWeight: s.$2 ? FontWeight.w600 : FontWeight.w400,
            )),
          ]),
        )).toList(),
      ),
    );
  }

  // ── Step 4 — Results ───────────────────────────────────────────
  Widget _buildResults() {
    final result = _result!;
    return Column(
      key: const ValueKey('results'),
      children: [
        _buildBackHeader('نتائجك 🎯'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 32),
            child: FadeTransition(
              opacity: _reveal,
              child: Column(children: [
                _buildResultHero(result),
                _buildStyleSuggestions(result),
                if (result.avoidAr.isNotEmpty) _buildAvoid(result),
                _buildRetryButton(),
              ]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultHero(StyleDnaResult result) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.gold.withValues(alpha: 0.15),
          AppColors.gold.withValues(alpha: 0.04),
        ], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        // Selfie preview or emoji
        Container(
          width: 80, height: 96,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.4), width: 1.5),
          ),
          clipBehavior: Clip.hardEdge,
          child: _selfie != null
              ? Image.file(_selfie!, fit: BoxFit.cover)
              : Container(
                  color: AppColors.card,
                  alignment: Alignment.center,
                  child: const Text('🧬', style: TextStyle(fontSize: 36)),
                ),
        ),
        const SizedBox(width: 18),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(
              '✦ تحليل AI · ثقة ${result.confidencePct}%',
              style: GoogleFonts.dmSans(
                fontSize: 10,
                color: AppColors.gold,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            result.shapeLabelAr.isNotEmpty ? result.shapeLabelAr : result.faceShape,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(result.analysisAr, style: GoogleFonts.dmSans(
            fontSize: 12, color: AppColors.sub, height: 1.5,
          )),
        ])),
      ]),
    );
  }

  /// Palette et emoji ne viennent pas du modèle : ce sont des choix visuels,
  /// dérivés du rang de la suggestion pour rester stables d'un rendu à l'autre.
  static const _accents = [
    AppColors.gold, AppColors.pink, AppColors.teal, AppColors.gold2, AppColors.green,
  ];
  static const _emojis = ['✂️', '💈', '🔥', '✨', '🪒'];

  Widget _buildStyleSuggestions(StyleDnaResult result) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '✂️ الستايلات المقترحة'),
        const SizedBox(height: 14),
        ...List.generate(result.styles.length, (i) => _StyleCard(
          style: result.styles[i],
          matches: result.matchesFor(result.styles[i]),
          accent: _accents[i % _accents.length],
          emoji: _emojis[i % _emojis.length],
          onBook: widget.onGoStaff,
          onPreview: _imagesAvailable
              ? () => StylePreviewSheet.show(
                    context,
                    styleName: result.styles[i].name,
                    styleLabel: result.styles[i].nameAr.isNotEmpty
                        ? result.styles[i].nameAr
                        : result.styles[i].name,
                    details: result.styles[i].descriptionAr,
                    selfie: _selfie,
                  )
              : null,
        )),
      ]),
    );
  }

  Widget _buildAvoid(StyleDnaResult result) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚠️ تجنب', style: GoogleFonts.dmSans(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.red,
          )),
          const SizedBox(height: 8),
          ...result.avoidAr.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('• $item', style: GoogleFonts.dmSans(
              fontSize: 12, color: AppColors.sub, height: 1.5,
            )),
          )),
        ]),
      ),
    );
  }

  Widget _buildRetryButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: GestureDetector(
        onTap: () {
          _revealCtrl.reset();
          setState(() {
            _step = _DnaStep.upload;
            _selfie = null;
            _result = null;
            _scanProgress = 0;
          });
        },
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.refresh_rounded, size: 18, color: AppColors.sub),
            const SizedBox(width: 8),
            Text('جرب صورة أخرى', style: GoogleFonts.dmSans(
              fontSize: 14, color: AppColors.sub, fontWeight: FontWeight.w500,
            )),
          ]),
        ),
      ),
    );
  }

  Widget _buildBackHeader(String title) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 14, 16, 16),
      child: Row(children: [
        GestureDetector(
          onTap: _step == _DnaStep.intro ? widget.onBack : () {
            setState(() {
              _step = _step == _DnaStep.results || _step == _DnaStep.scanning
                  ? _DnaStep.upload
                  : _DnaStep.intro;
              _scanProgress = 0;
            });
          },
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.card, shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: AppColors.sub),
          ),
        ),
        const SizedBox(width: 14),
        Text(title, style: GoogleFonts.playfairDisplay(
          fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.text,
        )),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Text('🧬', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 4),
            Text('AI', style: GoogleFonts.dmSans(
              fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700,
            )),
          ]),
        ),
      ]),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────
class _StyleCard extends StatelessWidget {
  final StyleSuggestion style;
  final Color accent;
  final String emoji;

  /// Les coiffeurs qui savent réellement faire cette coupe, autour du client.
  final List<StyleMatch> matches;
  final void Function(String staffId)? onBook;

  /// Null quand le serveur n'a pas de clé de génération d'images.
  final VoidCallback? onPreview;

  const _StyleCard({
    required this.style,
    required this.accent,
    required this.emoji,
    this.matches = const [],
    this.onBook,
    this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: style.recommended ? AppColors.gold.withValues(alpha: 0.4) : AppColors.border,
          width: style.recommended ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        Row(children: [
        Container(
          width: 60, height: 68,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 30)),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(
              child: Text(
                style.nameAr.isNotEmpty ? style.nameAr : style.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.text,
                ),
              ),
            ),
            if (style.recommended) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text('الأمثل', style: GoogleFonts.dmSans(
                  fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black,
                )),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(style.descriptionAr, style: GoogleFonts.dmSans(
            fontSize: 12, color: AppColors.sub, height: 1.4,
          )),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ...style.tags.take(3).map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(t, style: GoogleFonts.dmSans(fontSize: 10, color: accent)),
            )),
          ]),
        ])),
        Column(children: [
          _MatchBar(score: style.matchScore),
          const SizedBox(height: 4),
          Text('${style.matchScore}%', style: GoogleFonts.dmSans(
            fontSize: 11, color: AppColors.gold, fontWeight: FontWeight.w700,
          )),
        ]),
        ]),
        if (onPreview != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.4)),
                minimumSize: const Size.fromHeight(40),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: onPreview,
              icon: const Icon(Icons.image_rounded, size: 16),
              label: Text('شوف القصّة',
                  style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w600, color: accent)),
            ),
          ),
        ],
        // Sans ce bloc, l'analyse resterait un conseil que le client devrait
        // lui-même traduire en salon, coiffeur et prix.
        if (matches.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('وين تلقاها', style: GoogleFonts.dmSans(
              fontSize: 12, color: AppColors.sub, fontWeight: FontWeight.w600,
            )),
          ),
          const SizedBox(height: 8),
          ...matches.map((m) => _MatchRow(match: m, onTap: onBook)),
        ],
      ]),
    );
  }
}

/// Une offre réservable : coiffeur, salon, prix, distance.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match, this.onTap});

  final StyleMatch match;
  final void Function(String staffId)? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(match.staffId),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                match.staffName.isEmpty ? match.salonName : match.staffName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text,
                ),
              ),
              Text(
                [
                  match.label,
                  match.salonName,
                  if (match.distanceKm != null) '${match.distanceKm} كم',
                ].where((e) => e.isNotEmpty).join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Text('${match.price.toStringAsFixed(0)} DT', style: GoogleFonts.dmSans(
            fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold,
          )),
          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.sub),
        ]),
      ),
    );
  }
}

class _MatchBar extends StatelessWidget {
  final int score;
  const _MatchBar({required this.score});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36, height: 68,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FractionallySizedBox(
                heightFactor: score / 100,
                alignment: Alignment.bottomCenter,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.gold, AppColors.gold.withValues(alpha: 0.4)],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────
class _Feature {
  final String emoji, title, desc;
  const _Feature(this.emoji, this.title, this.desc);
}


// ── Custom Painters ───────────────────────────────────────────────
class _FaceGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: size.width * 0.65,
      height: size.height * 0.8,
    );
    canvas.drawOval(rect, paint);
  }
  @override
  bool shouldRepaint(_) => false;
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final bool topLeft, topRight, bottomLeft, bottomRight;

  const _CornerPainter({
    required this.color, required this.strokeWidth,
    this.topLeft = false, this.topRight = false,
    this.bottomLeft = false, this.bottomRight = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final s = size.width;
    if (topLeft) {
      canvas.drawLine(Offset(0, s), const Offset(0, 0), paint);
      canvas.drawLine(const Offset(0, 0), Offset(s, 0), paint);
    }
    if (topRight) {
      canvas.drawLine(Offset(s, s), Offset(s, 0), paint);
      canvas.drawLine(Offset(s, 0), const Offset(0, 0), paint);
    }
    if (bottomLeft) {
      canvas.drawLine(const Offset(0, 0), Offset(0, s), paint);
      canvas.drawLine(Offset(0, s), Offset(s, s), paint);
    }
    if (bottomRight) {
      canvas.drawLine(Offset(s, 0), Offset(s, s), paint);
      canvas.drawLine(Offset(s, s), Offset(0, s), paint);
    }
  }

  @override
  bool shouldRepaint(_CornerPainter old) => old.color != color;
}
