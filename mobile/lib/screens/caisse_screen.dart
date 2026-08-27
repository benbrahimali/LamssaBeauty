import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/auth_controller.dart';
import '../state/cash_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';
import '../widgets/walk_in_sheet.dart';

/// Caisse du salon (§3.4) : encaissement, split par employé, clôture de journée.
class CaisseScreen extends StatefulWidget {
  const CaisseScreen({super.key});

  @override
  State<CaisseScreen> createState() => _CaisseScreenState();
}

class _CaisseScreenState extends State<CaisseScreen> {
  int _tab = 0; // 0 = aujourd'hui, 1 = employés, 2 = historique

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cash = context.read<CashController>();
      cash.attach(context.read<AuthController>().salonId);
      cash.load();
    });
  }

  Future<void> _complete(Booking booking) async {
    final payload = await showModalBottomSheet<_CompletePayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CompleteSheet(booking: booking),
    );
    if (payload == null || !mounted) return;

    final controller = context.read<CashController>();
    final result = await controller.completeBooking(
      booking.id,
      method: payload.method,
      tip: payload.tip,
    );
    if (!mounted) return;

    if (result == null) {
      showAppSnack(context, controller.error ?? 'Encaissement impossible');
      return;
    }
    showAppSnack(
      context,
      'Split : salon ${result.salonShare.toStringAsFixed(2)} DT · '
      'employé ${result.staffPayout.toStringAsFixed(2)} DT',
      success: true,
    );
  }

  Future<void> _closeDay() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('clôturer la journée ?', style: AppTextStyle.playfair(size: 18)),
        content: Text(
          'Les transactions du jour seront verrouillées et les tséb9as approuvées '
          'déduites. Cette action est définitive.',
          style: AppTextStyle.dmSans(size: 13, color: AppColors.sub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Annuler',
                style: AppTextStyle.dmSans(color: AppColors.sub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Clôturer',
                style: AppTextStyle.dmSans(
                    color: AppColors.gold, weight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final controller = context.read<CashController>();
    final closure = await controller.closeDay();
    if (!mounted) return;

    if (closure == null) {
      showAppSnack(context, controller.error ?? 'Clôture impossible');
      return;
    }
    showAppSnack(
      context,
      'Journée clôturée — ${closure.total.toStringAsFixed(0)} DT, '
      'net salon ${closure.netSalon.toStringAsFixed(0)} DT',
      success: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cash = context.watch<CashController>();

    if (!cash.hasSalon) {
      return const Scaffold(
        backgroundColor: AppColors.bg,
        body: AppEmpty(emoji: '🏪', title: 'Aucun salon rattaché'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.card,
        onRefresh: cash.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(cash)),
            SliverToBoxAdapter(child: _buildTotalCard(cash)),
            SliverToBoxAdapter(child: _buildWalkInButton(cash)),
            SliverToBoxAdapter(child: _buildCloseButton(cash)),
            SliverToBoxAdapter(child: _buildTabBar()),
            SliverToBoxAdapter(child: _buildTabContent(cash)),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(CashController cash) {
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 20),
      child: Row(children: [
        Text('الكاسة 💰', style: GoogleFonts.playfairDisplay(
          fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.text,
        )),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            '${now.day.toString().padLeft(2, '0')}/'
            '${now.month.toString().padLeft(2, '0')}/${now.year}',
            style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub),
          ),
        ),
      ]),
    );
  }

  Widget _buildTotalCard(CashController cash) {
    final day = cash.day;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A1200), Color(0xFF0C0C16)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: AppColors.gold.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(children: [
          Text('إجمالي اليوم', style: GoogleFonts.dmSans(
            fontSize: 13, color: AppColors.sub, letterSpacing: 1,
          )),
          const SizedBox(height: 10),
          Text('${day.total.toStringAsFixed(0)} DT',
              style: GoogleFonts.playfairDisplay(
                fontSize: 44, fontWeight: FontWeight.w700, color: AppColors.gold,
                shadows: [
                  Shadow(color: AppColors.gold.withValues(alpha: 0.4), blurRadius: 20)
                ],
              )),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _statBox('🏪 الصالون',
                '${day.salonTotal.toStringAsFixed(0)} DT', AppColors.teal)),
            const SizedBox(width: 12),
            Expanded(child: _statBox('👥 الفريق',
                '${day.staffTotal.toStringAsFixed(0)} DT', AppColors.pink)),
            const SizedBox(width: 12),
            Expanded(child: _statBox('💅 البواقي',
                '+${day.tipsTotal.toStringAsFixed(0)} DT', AppColors.green)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _statBox('💵 كاش',
                '${day.cash.toStringAsFixed(0)} DT', AppColors.gold)),
            const SizedBox(width: 12),
            Expanded(child: _statBox('💳 TPE',
                '${day.card.toStringAsFixed(0)} DT', AppColors.gold)),
            const SizedBox(width: 12),
            Expanded(child: _statBox('🌐 أونلاين',
                '${day.online.toStringAsFixed(0)} DT', AppColors.gold)),
          ]),
        ]),
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.sub)),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(value, style: GoogleFonts.dmSans(
            fontSize: 14, fontWeight: FontWeight.w700, color: color,
          )),
        ),
      ]),
    );
  }

  Future<void> _addWalkIn() async {
    final cash = context.read<CashController>();
    if (cash.services.isEmpty || cash.team.isEmpty) {
      showAppSnack(context, 'Ajoute d’abord un service et un coiffeur au salon');
      return;
    }

    final payload = await showModalBottomSheet<WalkInPayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WalkInSheet(services: cash.services, team: cash.team),
    );
    if (payload == null || !mounted) return;

    final error = await cash.addWalkIn(
      staffId: payload.staffId,
      serviceId: payload.serviceId,
      clientName: payload.clientName,
    );
    if (!mounted) return;
    showAppSnack(
      context,
      error ?? 'زبون طيّاح تزاد للأجندة ✅',
      success: error == null,
    );
  }

  Widget _buildWalkInButton(CashController cash) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: GestureDetector(
        onTap: cash.day.closed ? null : _addWalkIn,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.teal.withValues(alpha: 0.35)),
          ),
          alignment: Alignment.center,
          child: Text('➕ زبون طيّاح (walk-in)', style: AppTextStyle.dmSans(
            size: 14,
            weight: FontWeight.w700,
            color: cash.day.closed ? AppColors.sub : AppColors.teal,
          )),
        ),
      ),
    );
  }

  Widget _buildCloseButton(CashController cash) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: cash.day.closed
          ? const DisabledPlaceholderButton(text: '🔒 اليوم مغلوق', height: 48)
          : GoldButton(
              text: '🔒 سكّر اليوم',
              height: 48,
              enabled: cash.day.transactionCount > 0,
              onPressed: _closeDay,
            ),
    );
  }

  Widget _buildTabBar() {
    const tabs = ['اليوم', 'العمال', 'التاريخ'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final active = _tab == i;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: active ? AppColors.gold : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(tabs[i], style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? Colors.black : AppColors.sub,
                )),
              ),
            ));
          }),
        ),
      ),
    );
  }

  Widget _buildTabContent(CashController cash) {
    if (cash.loading && cash.agenda.bookings.isEmpty && cash.workers.isEmpty) {
      return const SizedBox(height: 200, child: AppLoader());
    }
    if (cash.error != null && cash.workers.isEmpty) {
      return SizedBox(
        height: 200,
        child: AppError(message: cash.error!, onRetry: cash.load),
      );
    }
    switch (_tab) {
      case 0: return _buildToday(cash);
      case 1: return _buildWorkers(cash);
      case 2: return _buildHistory(cash);
      default: return const SizedBox();
    }
  }

  Widget _buildToday(CashController cash) {
    final bookings = cash.agenda.bookings;
    if (bookings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(emoji: '📋', title: 'ما كاين خدمات اليوم'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: bookings.map((booking) {
          final statusColor = switch (booking.status) {
            BookingStatus.confirmed => AppColors.green,
            BookingStatus.inProgress => AppColors.teal,
            BookingStatus.pending => AppColors.gold,
            BookingStatus.done => AppColors.sub,
            _ => AppColors.red,
          };
          final canComplete = booking.status == BookingStatus.confirmed ||
              booking.status == BookingStatus.inProgress;

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(booking.clientName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.text,
                      )),
                  Text('${booking.service} · ${booking.time}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
                ]),
              ),
              const SizedBox(width: 8),
              if (canComplete)
                GestureDetector(
                  onTap: () => _complete(booking),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text('خلّص', style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black,
                    )),
                  ),
                )
              else
                Text('${booking.price.toStringAsFixed(0)} DT',
                    style: GoogleFonts.dmSans(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.gold,
                    )),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWorkers(CashController cash) {
    if (cash.workers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(
          emoji: '👥',
          title: 'Aucun encaissement',
          subtitle: 'Le détail par employé apparaît après la première prestation.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: cash.workers.map((worker) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Row(children: [
              InitialsAvatar(
                  initials: worker.initials, color: worker.color, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(worker.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppColors.text,
                      )),
                  Text('${worker.cuts} خدمات اليوم',
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${worker.total.toStringAsFixed(0)} DT',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.gold,
                    )),
                Text('الإجمالي',
                    style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.sub)),
              ]),
            ]),
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Row(children: [
              _workerStat('نصيبه', '${worker.share.toStringAsFixed(1)} DT',
                  AppColors.green),
              _workerStat('بواقي', '+${worker.tip.toStringAsFixed(1)} DT',
                  AppColors.gold),
              _workerStat('الصافي',
                  '${(worker.share + worker.tip).toStringAsFixed(1)} DT',
                  AppColors.text),
            ]),
          ]),
        )).toList(),
      ),
    );
  }

  Widget _workerStat(String label, String value, Color color) {
    return Expanded(child: Column(children: [
      FittedBox(
        child: Text(value, style: GoogleFonts.dmSans(
          fontSize: 14, fontWeight: FontWeight.w700, color: color,
        )),
      ),
      const SizedBox(height: 2),
      Text(label, style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.sub)),
    ]));
  }

  Widget _buildHistory(CashController cash) {
    if (cash.closures.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(
          emoji: '📅',
          title: 'Aucune clôture',
          subtitle: 'Clôture ta première journée pour démarrer l’historique.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: cash.closures.map((closure) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Text('📅', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(closure.day, style: GoogleFonts.dmSans(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.text,
                )),
                if (closure.advancesDeducted > 0)
                  Text('سلف -${closure.advancesDeducted.toStringAsFixed(0)} DT',
                      style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${closure.total.toStringAsFixed(0)} DT',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.gold,
                  )),
              Text('صافي ${closure.netSalon.toStringAsFixed(0)} DT',
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
          ]),
        )).toList(),
      ),
    );
  }
}

class _CompletePayload {
  final String method;
  final double tip;
  const _CompletePayload(this.method, this.tip);
}

class _CompleteSheet extends StatefulWidget {
  const _CompleteSheet({required this.booking});
  final Booking booking;

  @override
  State<_CompleteSheet> createState() => _CompleteSheetState();
}

class _CompleteSheetState extends State<_CompleteSheet> {
  String _method = 'cash';
  final _tipCtrl = TextEditingController();

  @override
  void dispose() {
    _tipCtrl.dispose();
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
          Text('خلّص الخدمة', style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 4),
          Text(
            '${widget.booking.clientName} · '
            '${widget.booking.price.toStringAsFixed(0)} DT',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
          ),
          const SizedBox(height: 20),
          Row(children: [
            for (final option in const [
              ['cash', '💵 كاش'],
              ['card', '💳 TPE'],
              ['online', '🌐 أونلاين'],
            ])
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _method = option[0]),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _method == option[0]
                          ? AppColors.gold.withValues(alpha: 0.15)
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            _method == option[0] ? AppColors.gold : AppColors.border,
                      ),
                    ),
                    child: Text(option[1], style: AppTextStyle.dmSans(
                      size: 12,
                      color: _method == option[0] ? AppColors.gold : AppColors.sub,
                    )),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          TextField(
            controller: _tipCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTextStyle.dmSans(size: 15),
            decoration: const InputDecoration(
              hintText: 'بقشيش (اختياري)',
              prefixIcon: Icon(Icons.volunteer_activism_rounded,
                  color: AppColors.sub, size: 18),
            ),
          ),
          const SizedBox(height: 20),
          GoldButton(
            text: 'أكد الخلاص',
            onPressed: () => Navigator.pop(
              context,
              _CompletePayload(_method, double.tryParse(_tipCtrl.text.trim()) ?? 0),
            ),
          ),
        ]),
      ),
    );
  }
}
