import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../core/api_exception.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// QR et code public du salon (§3.2, §8.3).
///
/// Le gérant l'imprime pour sa vitrine ou l'envoie sur WhatsApp : le client
/// arrive directement sur la fiche — services, prix, prise de RDV — sans avoir
/// à chercher le salon dans l'app.
class SalonQrScreen extends StatefulWidget {
  const SalonQrScreen({super.key, required this.salonId, required this.salonName});

  final String salonId;
  final String salonName;

  @override
  State<SalonQrScreen> createState() => _SalonQrScreenState();
}

class _SalonQrScreenState extends State<SalonQrScreen> {
  SalonShare? _share;
  String? _error;
  bool _loading = true;

  /// Délimite ce qui est capturé quand le gérant partage le QR en image.
  final GlobalKey _qrKey = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final share = await context.read<SalonAdminRepository>().share(widget.salonId);
      if (!mounted) return;
      setState(() { _share = share; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  /// Partage le QR en image, avec le lien et le code en légende.
  ///
  /// Un gérant envoie une photo sur WhatsApp, pas une URL : l'image se
  /// réaffiche dans la conversation et s'imprime telle quelle.
  Future<void> _shareImage(SalonShare share) async {
    setState(() => _sharing = true);
    try {
      final boundary =
          _qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('QR non rendu');

      // 3× : lisible à l'impression, là où la densité de l'écran ne suffit pas.
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Capture vide');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lamssa-${share.code}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);

      await Share.shareXFiles([XFile(file.path)], text: share.shareText);
    } catch (_) {
      // Le partage d'image dépend de la plateforme : on retombe sur le texte
      // plutôt que de laisser le gérant sans rien.
      await Share.share(share.shareText);
    } finally {
      if (mounted) setState(() => _sharing = false);
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
        title: Text('كود الصالون', style: AppTextStyle.playfair(size: 20)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoader();
    if (_error != null) return AppError(message: _error!, onRetry: _load);

    final share = _share!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
      child: Column(children: [
        Text(
          widget.salonName,
          textAlign: TextAlign.center,
          style: AppTextStyle.playfair(size: 22),
        ),
        const SizedBox(height: 6),
        Text(
          'صوّر الكود وتفرّج على الخدمات واحجز',
          textAlign: TextAlign.center,
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        ),
        const SizedBox(height: 24),

        // Fond blanc obligatoire : un QR clair sur fond sombre n'est pas
        // reconnu par la plupart des appareils photo.
        RepaintBoundary(
          key: _qrKey,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: QrImageView(
              data: share.url,
              size: 240,
              backgroundColor: Colors.white,
              // Niveau H : le QR reste lisible même sali ou partiellement
              // masqué sur une vitrine.
              errorCorrectionLevel: QrErrorCorrectLevel.H,
            ),
          ),
        ),
        const SizedBox(height: 24),

        _CodeBox(share: share),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _sharing ? null : () => _shareImage(share),
            icon: _sharing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Colors.black),
                  )
                : const Icon(Icons.share_rounded, size: 20),
            label: Text('شارك مع الحرفاء',
                style: AppTextStyle.dmSans(
                    color: Colors.black, weight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.text,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: share.url));
              if (!mounted) return;
              showAppSnack(context, 'تنسخ اللينك');
            },
            icon: const Icon(Icons.link_rounded, size: 20),
            label: Text('انسخ اللينك', style: AppTextStyle.dmSans()),
          ),
        ),

        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💡', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'اطبع الكود وحطّو في الفيترينة. الحريف يصوّرو، يشوف الخدمات '
                'والأثمنة، ويحجز مباشرة.',
                style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)
                    .copyWith(height: 1.6),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Le code en clair : un client qui n'arrive pas à scanner doit pouvoir le taper.
class _CodeBox extends StatelessWidget {
  const _CodeBox({required this.share});

  final SalonShare share;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: share.code));
        if (context.mounted) showAppSnack(context, 'تنسخ الكود');
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        ),
        child: Column(children: [
          Text('الكود', style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 6),
          Text(
            share.spaced,
            style: AppTextStyle.playfair(size: 26, color: AppColors.gold)
                .copyWith(letterSpacing: 3),
          ),
        ]),
      ),
    );
  }
}
