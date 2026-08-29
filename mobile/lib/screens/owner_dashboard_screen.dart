import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../data/models.dart';
import '../state/auth_controller.dart';
import '../state/cash_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/revenue_bar.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';
import 'create_salon_screen.dart';
import 'manage_salon_screen.dart';

/// Tableau de bord gérant : caisse du jour, agenda, équipe, tséb9as à valider.
class OwnerDashboardScreen extends StatefulWidget {
  final Function(int) onNav;
  const OwnerDashboardScreen({super.key, required this.onNav});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthController>();
      final cash = context.read<CashController>();
      cash.attach(auth.salonId);
      cash.load();
    });
  }

  Future<void> _decide(Advance advance, bool approve) async {
    final controller = context.read<CashController>();
    final error = await controller.decideAdvance(advance.id, approve);
    if (!mounted) return;
    showAppSnack(
      context,
      error ?? (approve ? 'Tséb9a approuvée ✅' : 'Tséb9a refusée'),
      success: error == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final cash = context.watch<CashController>();

    if (!cash.hasSalon) return _buildNoSalon();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.card,
        onRefresh: cash.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(auth, cash)),
            if (cash.loading && cash.day.transactionCount == 0 && cash.agenda.bookings.isEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 300, child: AppLoader()))
            else if (cash.error != null && cash.day.transactionCount == 0)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 300,
                  child: AppError(message: cash.error!, onRetry: cash.load),
                ),
              )
            else ...[
              SliverToBoxAdapter(child: _buildKpiGrid(cash)),
              if (cash.pendingAdvances.isNotEmpty)
                SliverToBoxAdapter(child: _buildPendingAdvances(cash)),
              SliverToBoxAdapter(child: _buildChart(cash)),
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 14),
                child: SectionHeader(title: '📋 حجوزات اليوم'),
              )),
              SliverToBoxAdapter(child: _buildBookingsList(cash)),
              const SliverToBoxAdapter(child: Padding(
                padding: EdgeInsets.fromLTRB(24, 24, 24, 14),
                child: SectionHeader(title: '👥 الفريق'),
              )),
              SliverToBoxAdapter(child: _buildTeam(cash)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  /// Sans salon rattaché, le tableau de bord n'a rien à montrer : on propose
  /// directement l'onboarding (§3.1) au lieu d'une impasse.
  Widget _buildNoSalon() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🏪', style: TextStyle(fontSize: 52)),
              const SizedBox(height: 18),
              Text('ما عندكش صالون', style: AppTextStyle.playfair(size: 22)),
              const SizedBox(height: 10),
              Text(
                'أنشئ صالونك في دقيقة : الاسم، الموقع، الخدمات والفريق.',
                textAlign: TextAlign.center,
                style: AppTextStyle.dmSans(size: 14, color: AppColors.sub)
                    .copyWith(height: 1.6),
              ),
              const SizedBox(height: 32),
              GoldButton(text: 'أنشئ صالوني 🏪', onPressed: _createSalon),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createSalon() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateSalonScreen()),
    );
    if (!mounted) return;
    // Le rôle et le salon actif viennent de changer : on rebranche la caisse.
    final auth = context.read<AuthController>();
    final cash = context.read<CashController>();
    cash.attach(auth.salonId);
    cash.load();
  }

  Future<void> _manageSalon() async {
    final auth = context.read<AuthController>();
    final salonId = auth.salonId;
    if (salonId == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ManageSalonScreen(
        salonId: salonId,
        salonName: auth.context?.ownedSalonName ?? 'Mon salon',
      ),
    ));
    if (mounted) context.read<CashController>().load();
  }

  Widget _buildHeader(AuthController auth, CashController cash) {
    final salonName = auth.context?.ownedSalonName ?? 'Mon salon';
    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('👑 لوحة التحكم',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
              const SizedBox(height: 4),
              Text(salonName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text,
                  )),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: (cash.day.closed ? AppColors.sub : AppColors.green)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(50),
              border: Border.all(
                color: (cash.day.closed ? AppColors.sub : AppColors.green)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Text(
              cash.day.closed ? '🔒 مغلوق' : '🟢 مفتوح',
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: cash.day.closed ? AppColors.sub : AppColors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _manageSalon,
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.card,
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.settings_rounded,
                  size: 18, color: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(CashController cash) {
    final day = cash.day;
    final confirmed = cash.agenda.bookings
        .where((b) => b.status == BookingStatus.confirmed)
        .length;
    final pending =
        cash.agenda.bookings.where((b) => b.status == BookingStatus.pending).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Row(children: [
          Expanded(child: KpiCard(
            icon: Icons.monetization_on_rounded,
            iconColor: AppColors.gold,
            value: '${day.total.toStringAsFixed(0)} DT',
            label: 'إيرادات اليوم',
            change: '${day.transactionCount} خدمة',
            gold: true,
          )),
          const SizedBox(width: 12),
          Expanded(child: KpiCard(
            icon: Icons.calendar_today_rounded,
            iconColor: AppColors.green,
            value: '$confirmed',
            label: 'حجوزات مؤكدة',
            change: pending > 0 ? '$pending معلقة' : null,
            changeColor: AppColors.gold,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: KpiCard(
            icon: Icons.store_rounded,
            iconColor: AppColors.teal,
            value: '${day.salonTotal.toStringAsFixed(0)} DT',
            label: 'نصيب الصالون',
            change: day.expensesTotal > 0
                ? 'صافي ${day.netSalon.toStringAsFixed(0)} DT'
                : null,
            changeColor: AppColors.sub,
          )),
          const SizedBox(width: 12),
          Expanded(child: KpiCard(
            icon: Icons.people_rounded,
            iconColor: AppColors.pink,
            value: '${day.staffTotal.toStringAsFixed(0)} DT',
            label: 'نصيب الفريق',
            change: day.tipsTotal > 0
                ? '+${day.tipsTotal.toStringAsFixed(0)} بقشيش'
                : null,
          )),
        ]),
      ]),
    );
  }

  /// Les tséb9as en attente bloquent la paie : on les met en haut, pas dans un onglet.
  Widget _buildPendingAdvances(CashController cash) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('💸 طلبات سلفة (${cash.pendingAdvances.length})',
              style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...cash.pendingAdvances.map((advance) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    '${advance.staffName} — ${advance.amount.toStringAsFixed(0)} DT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600),
                  ),
                  if (advance.reason.isNotEmpty)
                    Text(advance.reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
                ]),
              ),
              _decisionButton('✓', AppColors.green, () => _decide(advance, true)),
              const SizedBox(width: 8),
              _decisionButton('✕', AppColors.red, () => _decide(advance, false)),
            ]),
          )),
        ]),
      ),
    );
  }

  Widget _decisionButton(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: AppTextStyle.dmSans(
                size: 15, weight: FontWeight.w700, color: color)),
      ),
    );
  }

  /// Historique réel des clôtures — pas de courbe inventée.
  Widget _buildChart(CashController cash) {
    final closures = cash.closures.take(7).toList().reversed.toList();
    if (closures.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('📊 الإيرادات الأسبوعية', style: GoogleFonts.playfairDisplay(
              fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text,
            )),
            const SizedBox(height: 12),
            Text(
              'L’historique apparaîtra après ta première clôture de journée.',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
            ),
          ]),
        ),
      );
    }

    final maxValue = closures
        .map((c) => c.total)
        .reduce((a, b) => a > b ? a : b);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📊 الإيرادات الأسبوعية', style: GoogleFonts.playfairDisplay(
            fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text,
          )),
          const SizedBox(height: 20),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: closures.map((closure) {
                final ratio = maxValue > 0 ? closure.total / maxValue : 0.0;
                final label = closure.day.length >= 10
                    ? closure.day.substring(8, 10)
                    : closure.day;
                return RevenueBar(
                  value: closure.total,
                  ratio: ratio,
                  label: label,
                );
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBookingsList(CashController cash) {
    final bookings = cash.agenda.bookings;
    if (bookings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(emoji: '📋', title: 'ما كاين حجوزات اليوم'),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: bookings.map((b) => _BookingRow(booking: b)).toList(),
      ),
    );
  }

  Widget _buildTeam(CashController cash) {
    final workers = cash.workers;
    if (workers.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(
          emoji: '👥',
          title: 'Aucune prestation encaissée',
          subtitle: 'Le détail par employé apparaît dès le premier encaissement.',
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: workers.map((worker) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(children: [
            InitialsAvatar(
              initials: worker.initials, color: worker.color, size: 46,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(worker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text,
                    )),
                Text(
                  '${worker.cuts} خدمة'
                  '${worker.chair == null ? '' : ' · كرسي ${worker.chair}'}',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${worker.total.toStringAsFixed(0)} DT',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.gold)),
              Text('نصيبه ${worker.share.toStringAsFixed(0)} DT',
                  style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
            ]),
          ]),
        )).toList(),
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Booking booking;
  const _BookingRow({required this.booking});

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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
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
            Text(booking.clientName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.text,
                )),
            Text(booking.service,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
            Text('${booking.date} — ${booking.time}',
                style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.sub)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${booking.price.toStringAsFixed(0)} DT',
              style: GoogleFonts.playfairDisplay(
                fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.gold,
              )),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text(booking.status.label, style: GoogleFonts.dmSans(
              fontSize: 10, fontWeight: FontWeight.w600, color: _statusColor,
            )),
          ),
        ]),
      ]),
    );
  }
}
