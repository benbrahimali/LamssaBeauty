import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../core/env.dart';
import '../data/repositories/style_dna_repository.dart';
import '../theme/app_theme.dart';

/// Voir la coupe conseillée (§2.4) — en illustration, ou sur son propre visage.
///
/// Deux modes volontairement distincts : l'illustration ne fait sortir aucune
/// donnée personnelle, l'essayage envoie le visage du client à un fournisseur
/// externe. Le second exige donc un accord explicite, demandé ici et jamais
/// coché d'avance.
class StylePreviewSheet extends StatefulWidget {
  const StylePreviewSheet({
    super.key,
    required this.styleName,
    required this.styleLabel,
    this.details = '',
    this.selfie,
  });

  final String styleName;
  final String styleLabel;
  final String details;

  /// Le selfie déjà analysé. Sans lui, seul l'aperçu générique est proposé.
  final File? selfie;

  static Future<void> show(
    BuildContext context, {
    required String styleName,
    required String styleLabel,
    String details = '',
    File? selfie,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StylePreviewSheet(
        styleName: styleName,
        styleLabel: styleLabel,
        details: details,
        selfie: selfie,
      ),
    );
  }

  @override
  State<StylePreviewSheet> createState() => _StylePreviewSheetState();
}

class _StylePreviewSheetState extends State<StylePreviewSheet> {
  String? _previewUrl;
  Uint8List? _tryOnImage;
  bool _loading = true;
  bool _tryingOn = false;
  String? _error;
  String _gender = 'male';

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() { _loading = true; _error = null; });
    try {
      final url = await context.read<StyleDnaRepository>().preview(
            style: widget.styleName,
            gender: _gender,
            details: widget.details,
          );
      if (!mounted) return;
      setState(() { _previewUrl = url; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  /// L'essayage n'est lancé qu'après un « oui » explicite : la photo part chez
  /// un tiers, c'est une donnée biométrique.
  Future<void> _askConsentThenTryOn() async {
    final selfie = widget.selfie;
    if (selfie == null) return;

    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('نبعثو تصويرتك ؟', style: AppTextStyle.playfair(size: 18)),
        content: Text(
          'باش نجرّبو القصّة على وجهك، تصويرتك تتبعث لخدمة خارجية. '
          'ما تتحفظش عندنا، وما تترجعش تتبعث مرّة أخرى بلا ما تقبل.',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)
              .copyWith(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('لا', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نقبل',
                style: AppTextStyle.dmSans(
                    color: AppColors.gold, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;

    setState(() { _tryingOn = true; _error = null; });
    try {
      final image = await context.read<StyleDnaRepository>().tryOn(
            selfie: selfie,
            style: widget.styleName,
            details: widget.details,
            consent: true,
          );
      if (!mounted) return;
      setState(() { _tryOnImage = image; _tryingOn = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _tryingOn = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 18),
        Text(widget.styleLabel, style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 14),
        _buildImage(),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: AppTextStyle.dmSans(size: 12, color: AppColors.red)),
        ],
        const SizedBox(height: 16),
        if (_tryOnImage == null) _buildGenderToggle(),
        if (widget.selfie != null && _tryOnImage == null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _tryingOn ? null : _askConsentThenTryOn,
              icon: _tryingOn
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.face_retouching_natural_rounded, size: 18),
              label: Text('جرّبها على وجهي',
                  style: AppTextStyle.dmSans(
                      color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'تصويرتك تتبعث لخدمة خارجية وما تتحفظش',
            textAlign: TextAlign.center,
            style: AppTextStyle.dmSans(size: 11, color: AppColors.sub),
          ),
        ],
      ]),
    );
  }

  Widget _buildImage() {
    if (_tryOnImage != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.memory(_tryOnImage!, height: 300, fit: BoxFit.cover),
      );
    }
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.gold),
        ),
      );
    }
    if (_previewUrl == null || _previewUrl!.isEmpty) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Text('✂️', style: GoogleFonts.dmSans(fontSize: 48)),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: CachedNetworkImage(
        imageUrl: Env.mediaUrl(_previewUrl!),
        height: 300,
        fit: BoxFit.cover,
        placeholder: (_, __) => const SizedBox(
          height: 300,
          child: Center(
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.gold),
          ),
        ),
        errorWidget: (_, __, ___) => const SizedBox(
          height: 300,
          child: Center(child: Text('🖼️', style: TextStyle(fontSize: 40))),
        ),
      ),
    );
  }

  /// L'illustration dépend du genre : une même coupe ne se rend pas pareil.
  Widget _buildGenderToggle() {
    const labels = {'male': 'راجل', 'female': 'مرا'};
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: labels.entries.map((entry) {
        final active = _gender == entry.key;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GestureDetector(
            onTap: active
                ? null
                : () {
                    setState(() => _gender = entry.key);
                    _loadPreview();
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                color: active ? AppColors.gold : AppColors.card2,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(entry.value,
                  style: AppTextStyle.dmSans(
                    size: 13,
                    color: active ? Colors.black : AppColors.sub,
                    weight: active ? FontWeight.w700 : FontWeight.w400,
                  )),
            ),
          ),
        );
      }).toList(),
    );
  }
}
