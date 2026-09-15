import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';
import 'common_widgets.dart';

/// Avatar du profil, modifiable par les coiffeurs et les gérants.
///
/// Ce sont eux qu'on voit dans les cartes. Pour un client l'avatar reste les
/// initiales, sans pastille appareil photo : proposer un geste que le serveur
/// refuserait serait pire que de ne rien proposer.
class EditableAvatar extends StatefulWidget {
  const EditableAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.editable = false,
    this.size = 90,
  });

  final String name;
  final String? imageUrl;
  final bool editable;
  final double size;

  @override
  State<EditableAvatar> createState() => _EditableAvatarState();
}

class _EditableAvatarState extends State<EditableAvatar> {
  bool _envoi = false;

  bool get _aUnePhoto => (widget.imageUrl ?? '').trim().isNotEmpty;

  Future<void> _choisir() async {
    final source = await showModalBottomSheet<_Choix>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _option(context, Icons.photo_library_rounded, 'اختار من الغاليري',
                _Choix.galerie),
            _option(context, Icons.photo_camera_rounded, 'صوّر توّا', _Choix.camera),
            if (_aUnePhoto)
              _option(context, Icons.delete_outline_rounded, 'نحّي التصويرة',
                  _Choix.retirer,
                  couleur: AppColors.red),
          ]),
        ),
      ),
    );
    if (source == null || !mounted) return;

    final auth = context.read<AuthController>();
    if (source == _Choix.retirer) {
      await _envoyer(() => auth.removeAvatar(), 'تنحّات التصويرة');
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: source == _Choix.camera ? ImageSource.camera : ImageSource.gallery,
      // Un avatar s'affiche au plus en 90 px : inutile d'envoyer une photo de
      // 8 Mo, lente en 3G et refusée au-delà de MAX_UPLOAD_MB.
      maxWidth: 800,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    await _envoyer(() => auth.updateAvatar(File(picked.path)), 'تبدّلت التصويرة ✅');
  }

  Future<void> _envoyer(Future<String?> Function() action, String succes) async {
    setState(() => _envoi = true);
    final erreur = await action();
    if (!mounted) return;
    setState(() => _envoi = false);
    showAppSnack(context, erreur ?? succes, success: erreur == null);
  }

  Widget _option(BuildContext context, IconData icon, String label, _Choix choix,
      {Color couleur = AppColors.text}) {
    return ListTile(
      leading: Icon(icon, color: couleur),
      title: Text(label, style: AppTextStyle.dmSans(size: 15, color: couleur)),
      onTap: () => Navigator.of(context).pop(choix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = InitialsAvatar(
      initials: initialsOf(widget.name),
      color: AppColors.gold,
      size: widget.size,
      imageUrl: widget.imageUrl,
    );
    if (!widget.editable) return avatar;

    return Semantics(
      button: true,
      label: 'بدّل تصويرة البروفيل',
      child: GestureDetector(
        onTap: _envoi ? null : _choisir,
        child: Stack(clipBehavior: Clip.none, children: [
          avatar,
          if (_envoi)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.gold),
                ),
              ),
            ),
          PositionedDirectional(
            bottom: 0,
            end: 0,
            child: Container(
              width: widget.size * 0.32,
              height: widget.size * 0.32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold,
                border: Border.all(color: AppColors.bg, width: 2.5),
              ),
              child: Icon(Icons.photo_camera_rounded,
                  size: widget.size * 0.16, color: Colors.black),
            ),
          ),
        ]),
      ),
    );
  }
}

enum _Choix { galerie, camera, retirer }
