import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/booking_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

/// Mes réservations — à venir et historique (§3.3, §3.8).
///
/// C'est d'ici que le client annule un RDV (dans la fenêtre autorisée par le
/// salon) et qu'il note une prestation terminée.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<Booking> _bookings = const [];
  bool _loading = true;
  String? _error;
  int _tab = 0;

  /// Avis déjà déposés pendant cette session : l'API refuse le second en 409,
  /// autant retirer le bouton tout de suite.
  final _reviewed = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bookings = await context.read<BookingRepository>().mine();
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<Booking> get _upcoming => _bookings.where((b) => b.isActive).toList()
    ..sort((a, b) =>
        (a.start ?? DateTime.now()).compareTo(b.start ?? DateTime.now()));

  List<Booking> get _past => _bookings.where((b) => !b.isActive).toList();

  Future<void> _cancel(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('إلغاء الموعد ؟', style: AppTextStyle.playfair(size: 18)),
        content: Text(
          'موعدك ${booking.date} على ${booking.time} باش يتلغى.',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('رجوع', style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('ألغي',
                style: AppTextStyle.dmSans(
                    color: AppColors.red, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await context.read<BookingRepository>().cancel(booking.id);
      if (!mounted) return;
      showAppSnack(context, 'الموعد تلغى', success: true);
      await _load();
    } on ApiException catch (e) {
      // Hors fenêtre d'annulation, le serveur renvoie 409 avec le délai exact.
      if (mounted) showAppSnack(context, e.message);
    }
  }

  Future<void> _review(Booking booking) async {
    final payload = await showModalBottomSheet<_ReviewPayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(booking: booking),
    );
    if (payload == null || !mounted) return;

    try {
      await context.read<BookingRepository>().review(
            bookingId: booking.id,
            rating: payload.rating,
            comment: payload.comment,
          );
      if (!mounted) return;
      setState(() => _reviewed.add(booking.id));
      showAppSnack(context, 'شكرا على رأيك ⭐', success: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabs(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding:
          EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 20, 12),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_rounded,
                size: 20, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 14),
        Text('مواعيدي 📅', style: AppTextStyle.playfair(size: 24)),
      ]),
    );
  }

  Widget _buildTabs() {
    const labels = ['الجاية', 'السابقة'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: List.generate(labels.length, (i) {
            final active = _tab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: active ? AppColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(labels[i], style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? Colors.black : AppColors.sub,
                  )),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const AppLoader();
    if (_error != null) return AppError(message: _error!, onRetry: _load);

    final items = _tab == 0 ? _upcoming : _past;
    if (items.isEmpty) {
      return AppEmpty(
        emoji: _tab == 0 ? '📅' : '🗂️',
        title: _tab == 0 ? 'ما عندك حتى موعد جاي' : 'ما عندك حتى موعد سابق',
        subtitle: _tab == 0 ? 'احجز من الصفحة الرئيسية.' : null,
      );
    }

    return RefreshIndicator(
      color: AppColors.gold,
      backgroundColor: AppColors.card,
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 110),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _BookingCard(
          booking: items[i],
          onCancel: items[i].isActive ? () => _cancel(items[i]) : null,
          onReview: items[i].status == BookingStatus.done &&
                  !_reviewed.contains(items[i].id)
              ? () => _review(items[i])
              : null,
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking, this.onCancel, this.onReview});

  final Booking booking;
  final VoidCallback? onCancel;
  final VoidCallback? onReview;

  Color get _statusColor => switch (booking.status) {
        BookingStatus.confirmed => AppColors.green,
        BookingStatus.inProgress => AppColors.teal,
        BookingStatus.pending => AppColors.gold,
        BookingStatus.done => AppColors.sub,
        _ => AppColors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.calendar_today_rounded, color: _statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                booking.service.isEmpty ? 'خدمة' : booking.service,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.dmSans(size: 15, weight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              Text('${booking.date} · ${booking.time}',
                  style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${booking.price.toStringAsFixed(0)} DT',
                style: AppTextStyle.playfair(size: 16, color: AppColors.gold)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(booking.status.label, style: AppTextStyle.dmSans(
                size: 10, weight: FontWeight.w600, color: _statusColor,
              )),
            ),
          ]),
        ]),
        if (onCancel != null || onReview != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            if (onReview != null)
              Expanded(
                child: GestureDetector(
                  onTap: onReview,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: AppColors.gold.withValues(alpha: 0.4)),
                    ),
                    child: Text('⭐ نقّم', style: AppTextStyle.dmSans(
                      size: 13, weight: FontWeight.w700, color: AppColors.gold,
                    )),
                  ),
                ),
              ),
            if (onReview != null && onCancel != null) const SizedBox(width: 10),
            if (onCancel != null)
              Expanded(
                child: GestureDetector(
                  onTap: onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text('ألغي', style: AppTextStyle.dmSans(
                      size: 13, weight: FontWeight.w600, color: AppColors.red,
                    )),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _ReviewPayload {
  final int rating;
  final String comment;
  const _ReviewPayload(this.rating, this.comment);
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.booking});
  final Booking booking;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          const SizedBox(height: 18),
          Text('كيفاش كانت الخدمة ؟', style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 4),
          Text(widget.booking.service,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final value = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    value <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 38,
                    color: value <= _rating ? AppColors.gold : AppColors.border,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            maxLength: 500,
            style: AppTextStyle.dmSans(size: 14),
            decoration: const InputDecoration(
              hintText: 'زيد كلمة (اختياري)',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          GoldButton(
            text: 'ابعث التقييم',
            onPressed: () => Navigator.pop(
              context,
              _ReviewPayload(_rating, _commentCtrl.text.trim()),
            ),
          ),
        ]),
      ),
    );
  }
}
