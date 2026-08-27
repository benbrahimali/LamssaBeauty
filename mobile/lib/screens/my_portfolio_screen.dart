import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../core/env.dart';
import '../data/repositories/portfolio_repository.dart';
import '../state/portfolio_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

/// Le mur du coiffeur (§3.8) : ce qu'il publie alimente le fil « En vogue »
/// et son propre profil, donc ses réservations.
class MyPortfolioScreen extends StatefulWidget {
  const MyPortfolioScreen({super.key, required this.staffId});

  final String staffId;

  @override
  State<MyPortfolioScreen> createState() => _MyPortfolioScreenState();
}

class _MyPortfolioScreenState extends State<MyPortfolioScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<MyPortfolioController>().load(widget.staffId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyPortfolioController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        foregroundColor: AppColors.text,
        title: Text('خدمتي', style: AppTextStyle.playfair(size: 20)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        onPressed: controller.publishing ? null : _pickAndPublish,
        icon: const Icon(Icons.add_a_photo_rounded, size: 20),
        label: Text('انشر',
            style: AppTextStyle.dmSans(
                color: Colors.black, weight: FontWeight.w700)),
      ),
      body: _buildBody(controller),
    );
  }

  Widget _buildBody(MyPortfolioController controller) {
    if (controller.loading && controller.posts.isEmpty) return const AppLoader();
    if (controller.error != null && controller.posts.isEmpty) {
      return AppError(
        message: controller.error!,
        onRetry: () => controller.load(widget.staffId),
      );
    }
    if (controller.posts.isEmpty) {
      return const AppEmpty(
        emoji: '✂️',
        title: 'ما نشرت حتّى صورة',
        subtitle: 'صوّر خدمتك — الحرفاء يلقاوك من التصاور',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: controller.posts.length,
      itemBuilder: (_, i) {
        final post = controller.posts[i];
        return GestureDetector(
          onLongPress: () => _confirmDelete(controller, post),
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: CachedNetworkImage(
                imageUrl: Env.mediaUrl(post.imageUrl),
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.card2),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.card2,
                  alignment: Alignment.center,
                  child: const Text('🖼️', style: TextStyle(fontSize: 24)),
                ),
              ),
            ),
            Positioned(
              left: 8, bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.favorite_rounded, size: 12, color: AppColors.red),
                  const SizedBox(width: 4),
                  Text('${post.likes}',
                      style: AppTextStyle.dmSans(size: 11, color: Colors.white)),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }

  Future<void> _pickAndPublish() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Le backend refuse au-delà de MAX_UPLOAD_MB : mieux vaut réduire ici que
      // faire monter 8 Mo pour se prendre un 413.
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PublishSheet(image: File(picked.path)),
    );
  }

  Future<void> _confirmDelete(
      MyPortfolioController controller, PortfolioPost post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('تنحّي الصورة ؟', style: AppTextStyle.playfair(size: 18)),
        content: Text('ما تنجّمش ترجّعها بعد.',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('لا', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('نعم', style: AppTextStyle.dmSans(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await controller.remove(post);
    if (!mounted) return;
    showAppSnack(context, error ?? 'تنحّات', success: error == null);
  }
}

class _PublishSheet extends StatefulWidget {
  const _PublishSheet({required this.image});

  final File image;

  @override
  State<_PublishSheet> createState() => _PublishSheetState();
}

class _PublishSheetState extends State<_PublishSheet> {
  final _caption = TextEditingController();
  final _tags = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = context.read<MyPortfolioController>();
    final error = await controller.publish(
      image: widget.image,
      caption: _caption.text.trim(),
      // Le serveur retire déjà les « # » et met en minuscules ; on se contente
      // de découper ce que le coiffeur a tapé.
      tags: _tags.text
          .split(RegExp(r'[,\s]+'))
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );
    if (!mounted) return;
    Navigator.pop(context);
    showAppSnack(context, error ?? 'تنشرت', success: error == null);
  }

  @override
  Widget build(BuildContext context) {
    final publishing = context.watch<MyPortfolioController>().publishing;

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
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(widget.image, height: 180, fit: BoxFit.cover),
          ),
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
