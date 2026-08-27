import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/notifications_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _unreadOnly = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<NotificationsController>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<NotificationsController>();
    final items = _unreadOnly
        ? controller.items.where((n) => !n.read).toList()
        : controller.items;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(controller),
          _buildFilterRow(),
          Expanded(child: _buildBody(controller, items)),
        ],
      ),
    );
  }

  Widget _buildBody(NotificationsController controller, List<AppNotification> items) {
    if (controller.loading && controller.items.isEmpty) {
      return const AppLoader();
    }
    if (controller.error != null && controller.items.isEmpty) {
      return AppError(message: controller.error!, onRetry: controller.load);
    }
    if (items.isEmpty) {
      return const AppEmpty(emoji: '🔔', title: 'ما كاين إشعارات');
    }
    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: controller.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _NotifCard(
          notif: items[i],
          onTap: () => controller.markRead(items[i]),
        ),
      ),
    );
  }

  Widget _buildHeader(NotificationsController controller) {
    final unread = controller.unread;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 16),
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الإشعارات', style: GoogleFonts.playfairDisplay(
            fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text,
          )),
          if (unread > 0)
            Text('$unread غير مقروء',
                style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.gold)),
        ]),
        const Spacer(),
        if (unread > 0)
          GestureDetector(
            onTap: controller.markAllRead,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: AppColors.border),
              ),
              child: Text('قرأ الكل', style: GoogleFonts.dmSans(
                fontSize: 12, color: AppColors.gold, fontWeight: FontWeight.w600,
              )),
            ),
          ),
      ]),
    );
  }

  Widget _buildFilterRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(children: [
        _filterTab('الكل', !_unreadOnly, () => setState(() => _unreadOnly = false)),
        const SizedBox(width: 10),
        _filterTab('غير مقروء', _unreadOnly, () => setState(() => _unreadOnly = true)),
      ]),
    );
  }

  Widget _filterTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.gold : AppColors.card,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: active ? AppColors.gold : AppColors.border),
        ),
        child: Text(label, style: GoogleFonts.dmSans(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          color: active ? Colors.black : AppColors.sub,
        )),
      ),
    );
  }
}

class _NotifCard extends StatelessWidget {
  final AppNotification notif;
  final VoidCallback onTap;

  const _NotifCard({required this.notif, required this.onTap});

  /// Teinte par famille de notification, pour repérer l'important d'un coup d'œil.
  Color get _accent {
    if (notif.type.startsWith('booking') || notif.type.startsWith('reminder')) {
      return AppColors.green;
    }
    if (notif.type.startsWith('advance') || notif.type == 'closure_ready') {
      return AppColors.gold;
    }
    if (notif.type == 'new_portfolio' || notif.type == 'new_review') {
      return AppColors.pink;
    }
    return AppColors.teal;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notif.read ? AppColors.card : _accent.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notif.read ? AppColors.border : _accent.withValues(alpha: 0.3),
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Text(notif.icon, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notif.message, style: GoogleFonts.dmSans(
                fontSize: 13,
                color: notif.read ? AppColors.sub : AppColors.text,
                fontWeight: notif.read ? FontWeight.w400 : FontWeight.w500,
                height: 1.4,
              )),
              const SizedBox(height: 6),
              Text(notif.time,
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
          ),
          if (!notif.read)
            Container(
              width: 8, height: 8,
              margin: const EdgeInsets.only(top: 4, left: 4),
              decoration:
                  const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            ),
        ]),
      ),
    );
  }
}
