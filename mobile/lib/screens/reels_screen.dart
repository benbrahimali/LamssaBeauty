import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../data/repositories/reel_repository.dart';
import '../state/auth_controller.dart';
import '../state/reels_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Fil des reels (§3.8) — vidéos courtes de coiffeurs et de salons.
///
/// Volontairement public : un visiteur sans compte voit les vidéos, et c'est ce
/// qui doit lui donner envie de réserver. Seuls publier et aimer exigent un
/// compte.
class ReelsScreen extends StatefulWidget {
  const ReelsScreen({super.key, this.onGoStaff, this.onGoSalon});

  final void Function(String staffId)? onGoStaff;
  final void Function(String salonId)? onGoSalon;

  @override
  State<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends State<ReelsScreen> {
  final _pages = PageController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ReelsController>().load(),
    );
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Publier exige un profil pro : le serveur refuse les autres en 403.
  bool get _canPublish {
    final auth = context.read<AuthController>();
    return auth.status == AuthStatus.loggedIn &&
        (auth.context?.staffId != null || auth.context?.ownedSalonId != null);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReelsController>();

    return Scaffold(
      backgroundColor: Colors.black,
      floatingActionButton: _canPublish
          ? FloatingActionButton(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              onPressed: controller.publishing ? null : _pickAndPublish,
              child: controller.publishing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.black),
                    )
                  : const Icon(Icons.videocam_rounded),
            )
          : null,
      body: _buildBody(controller),
    );
  }

  Widget _buildBody(ReelsController controller) {
    if (controller.loading && controller.reels.isEmpty) return const AppLoader();
    if (controller.error != null && controller.reels.isEmpty) {
      return AppError(
        message: controller.error!,
        onRetry: () => controller.load(force: true),
      );
    }
    if (controller.reels.isEmpty) {
      return const AppEmpty(
        emoji: '🎬',
        title: 'ما فماش فيديوهات توّا',
        subtitle: 'الصالونات باش يبدأوا ينشروا خدمتهم قريب',
      );
    }

    return Stack(children: [
      PageView.builder(
        controller: _pages,
        scrollDirection: Axis.vertical,
        itemCount: controller.reels.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => _ReelPage(
          reel: controller.reels[i],
          // Une seule vidéo joue à la fois : lire tout le fil en parallèle
          // épuiserait la batterie et le forfait data.
          active: i == _current,
          onVisible: () => controller.markViewed(controller.reels[i]),
          onLike: () => _like(controller, controller.reels[i]),
          onOpenAuthor: () => _openAuthor(controller.reels[i]),
        ),
      ),
      Positioned(
        top: MediaQuery.of(context).padding.top + 16,
        right: 20,
        child: Text('ريلز', style: AppTextStyle.playfair(size: 22, color: Colors.white)),
      ),
    ]);
  }

  void _like(ReelsController controller, Reel reel) {
    if (context.read<AuthController>().status != AuthStatus.loggedIn) {
      showAppSnack(context, 'لازم تسجّل دخول باش تعمل إعجاب');
      return;
    }
    controller.toggleLike(reel);
  }

  /// Ouvre l'auteur du reel — le coiffeur s'il y en a un, le salon sinon.
  ///
  /// Le lecteur est une route posée AU-DESSUS de la coquille de l'app. Les
  /// callbacks changent bien l'écran de la coquille, mais elle reste cachée
  /// dessous : le bouton semblait mort alors qu'il agissait. On referme donc
  /// le lecteur d'abord, et on navigue ensuite.
  ///
  /// Le repli existe pour l'autre cas : un hôte qui n'aurait fourni aucun
  /// chemin laisserait un bouton inerte sans le moindre signe. On le dit.
  void _openAuthor(Reel reel) {
    final staffId = reel.staffId;
    final versCoiffeur = staffId != null ? widget.onGoStaff : null;
    final versSalon = widget.onGoSalon;

    if (versCoiffeur == null && versSalon == null) {
      showAppSnack(context, 'ما نجّمناش نحلّو الصالون من هنا');
      return;
    }

    final navigateur = Navigator.of(context);
    if (navigateur.canPop()) navigateur.pop();

    if (versCoiffeur != null && staffId != null) {
      versCoiffeur(staffId);
    } else {
      versSalon!(reel.salonId);
    }
  }

  Future<void> _pickAndPublish() async {
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.gallery,
      // Le serveur refuse au-delà : autant l'annoncer au sélecteur.
      maxDuration: const Duration(seconds: 90),
    );
    if (picked == null || !mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PublishReelSheet(video: File(picked.path)),
    );
  }
}

/// Une vidéo plein écran, avec ses actions.
class _ReelPage extends StatefulWidget {
  const _ReelPage({
    required this.reel,
    required this.active,
    required this.onVisible,
    required this.onLike,
    required this.onOpenAuthor,
  });

  final Reel reel;
  final bool active;
  final VoidCallback onVisible;
  final VoidCallback onLike;
  final VoidCallback onOpenAuthor;

  @override
  State<_ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends State<_ReelPage> {
  VideoPlayerController? _video;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(_ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _start();
    } else if (!widget.active && old.active) {
      // Libère le décodeur : Android n'en offre qu'un nombre limité, et les
      // garder ouverts fait échouer la lecture des vidéos suivantes.
      _video?.pause();
      _video?.dispose();
      _video = null;
      if (mounted) setState(() => _ready = false);
    }
  }

  Future<void> _start() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.reel.videoUrl));
    _video = controller;
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setLooping(true);
      await controller.play();
      setState(() => _ready = true);
      widget.onVisible();
    } catch (_) {
      // Une vidéo illisible ne doit pas bloquer le fil : on affiche la
      // vignette et l'utilisateur passe à la suivante.
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;

    return GestureDetector(
      onTap: () {
        final video = _video;
        if (video == null || !_ready) return;
        setState(() {
          video.value.isPlaying ? video.pause() : video.play();
        });
      },
      child: Stack(fit: StackFit.expand, children: [
        if (_ready && _video != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _video!.value.size.width,
              height: _video!.value.size.height,
              child: VideoPlayer(_video!),
            ),
          )
        else
          _buildPoster(reel),

        // Dégradé bas : sans lui, le texte blanc devient illisible sur une
        // vidéo claire.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.center,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
            ),
          ),
        ),

        Positioned(
          left: 20, right: 80, bottom: 110,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(
              onTap: widget.onOpenAuthor,
              child: Text(
                reel.authorLabel,
                style: AppTextStyle.dmSans(
                    color: Colors.white, weight: FontWeight.w700, size: 15),
              ),
            ),
            if (reel.salonName.isNotEmpty && reel.staffName.isNotEmpty)
              Text(reel.salonName,
                  style: AppTextStyle.dmSans(size: 12, color: Colors.white70)),
            if (reel.caption.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reel.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.dmSans(size: 13, color: Colors.white)),
            ],
            if (reel.tags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(reel.tags.map((t) => '#$t').join(' '),
                  style: AppTextStyle.dmSans(size: 12, color: AppColors.gold)),
            ],
          ]),
        ),

        Positioned(
          right: 16, bottom: 120,
          child: Column(children: [
            _Action(
              icon: reel.likedByMe
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: reel.likedByMe ? AppColors.red : Colors.white,
              label: '${reel.likes}',
              onTap: widget.onLike,
            ),
            const SizedBox(height: 18),
            _Action(
              icon: Icons.visibility_rounded,
              color: Colors.white,
              label: '${reel.views}',
            ),
            const SizedBox(height: 18),
            _Action(
              icon: Icons.calendar_month_rounded,
              color: AppColors.gold,
              label: 'احجز',
              onTap: widget.onOpenAuthor,
            ),
          ]),
        ),

        if (!_ready && !_failed)
          const Center(
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.gold),
          ),
      ]),
    );
  }

  Widget _buildPoster(Reel reel) {
    if (reel.thumbnailUrl.isEmpty) return const ColoredBox(color: Colors.black);
    return CachedNetworkImage(
      imageUrl: reel.thumbnailUrl,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      // La colonne se réduisait à la largeur de son texte : une cible d'une
      // trentaine de pixels, sous le minimum tactile. Un doigt qui vise
      // l'icône tombait à côté, et le bouton passait pour inerte.
      child: Container(
        constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        alignment: Alignment.center,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: AppTextStyle.dmSans(size: 11, color: Colors.white)),
        ]),
      ),
    );
  }
}

class _PublishReelSheet extends StatefulWidget {
  const _PublishReelSheet({required this.video});

  final File video;

  @override
  State<_PublishReelSheet> createState() => _PublishReelSheetState();
}

class _PublishReelSheetState extends State<_PublishReelSheet> {
  final _caption = TextEditingController();
  final _tags = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final error = await context.read<ReelsController>().publish(
          video: widget.video,
          caption: _caption.text.trim(),
          tags: _tags.text
              .split(RegExp(r'[,\s]+'))
              .map((t) => t.trim())
              .where((t) => t.isNotEmpty)
              .toList(),
        );
    if (!mounted) return;
    Navigator.pop(context);
    showAppSnack(context, error ?? 'تنشر الفيديو', success: error == null);
  }

  @override
  Widget build(BuildContext context) {
    final publishing = context.watch<ReelsController>().publishing;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
          const SizedBox(height: 20),
          Text('انشر فيديو', style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 6),
          Text('أقصى مدة: دقيقة ونصف',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 18),
          TextField(
            controller: _caption,
            maxLines: 2,
            style: AppTextStyle.dmSans(),
            decoration: _decoration('وصف قصير'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            style: AppTextStyle.dmSans(),
            decoration: _decoration('fade, dégradé, barbe'),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(52),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: publishing ? null : _submit,
              child: publishing
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.black),
                    )
                  : Text('انشر',
                      style: AppTextStyle.dmSans(
                          color: Colors.black, weight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        filled: true,
        fillColor: AppColors.card2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}
