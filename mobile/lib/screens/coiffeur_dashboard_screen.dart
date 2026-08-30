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

/// Espace coiffeur : SON planning, SA caisse, SES tséb9as (§3.4).
/// Aucune donnée du salon n'est visible ici — le backend le refuse d'ailleurs.
class CoiffeurDashboardScreen extends StatefulWidget {
  const CoiffeurDashboardScreen({super.key, this.showAgendaOnly = false});

  final bool showAgendaOnly;

  @override
  State<CoiffeurDashboardScreen> createState() => _CoiffeurDashboardScreenState();
}

class _CoiffeurDashboardScreenState extends State<CoiffeurDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MyCashController>().load();
      final salonId = context.read<AuthController>().salonId;
      if (salonId != null) {
        context.read<MyCashController>().loadCatalogue(salonId);
      }
    });
  }

  /// Titre de l'agenda, avec la navigation entre les jours.
  ///
  /// Le coiffeur était enfermé sur aujourd'hui : un RDV pris pour demain lui
  /// arrivait en notification, puis restait introuvable dans l'app jusqu'au
  /// jour même. Le passé reste consultable — on a souvent besoin de retrouver
  /// ce qu'on a fait hier.
  Widget _buildAgendaHeader(MyCashController controller) {
    final jour = controller.agendaDay;
    final titre = controller.isToday
        ? '📅 جدول اليوم'
        : '📅 ${jour.day}/${jour.month}';

    return Row(children: [
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () => controller.shiftAgenda(-1),
        icon: const Icon(Icons.chevron_left, color: AppColors.sub, size: 22),
      ),
      Flexible(
        child: GestureDetector(
          // Un retour direct à aujourd'hui évite de tapoter la flèche autant
          // de fois qu'on s'est éloigné.
          onTap: controller.resetAgendaToToday,
          child: Text(titre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.playfair(size: 17)),
        ),
      ),
      IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        onPressed: () => controller.shiftAgenda(1),
        icon: const Icon(Icons.chevron_right, color: AppColors.sub, size: 22),
      ),
    ]);
  }

  Future<void> _addWalkIn() async {
    final auth = context.read<AuthController>();
    final controller = context.read<MyCashController>();
    final salonId = auth.salonId;
    final staffId = auth.staffId;

    if (salonId == null || staffId == null || controller.services.isEmpty) {
      showAppSnack(context, 'Catalogue du salon indisponible');
      return;
    }

    final payload = await showModalBottomSheet<WalkInPayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WalkInSheet(
        services: controller.services,
        // Le coiffeur ne saisit que pour lui-même.
        team: const [],
        lockedStaffId: staffId,
      ),
    );
    if (payload == null || !mounted) return;

    final error = await controller.addWalkIn(
      salonId: salonId,
      staffId: staffId,
      serviceId: payload.serviceId,
      clientName: payload.clientName,
    );
    if (!mounted) return;
    showAppSnack(
      context,
      error ?? 'زبون طيّاح تزاد ✅',
      success: error == null,
    );
  }

  Future<void> _completeBooking(Booking booking) async {
    final result = await showModalBottomSheet<_CompletePayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _CompleteSheet(booking: booking),
    );
    if (result == null || !mounted) return;

    final controller = context.read<MyCashController>();
    final completed = await controller.completeBooking(
      booking.id,
      method: result.method,
      tip: result.tip,
    );
    if (!mounted) return;

    if (completed == null) {
      showAppSnack(context, controller.error ?? 'Encaissement impossible');
      return;
    }
    showAppSnack(
      context,
      'Encaissé : ${completed.amount.toStringAsFixed(0)} DT — '
      'ta part ${completed.staffPayout.toStringAsFixed(2)} DT',
      success: true,
    );
  }

  Future<void> _requestAdvance() async {
    final salonId = context.read<AuthController>().salonId;
    if (salonId == null) {
      showAppSnack(context, "Tu n'es rattaché à aucun salon");
      return;
    }
    final payload = await showModalBottomSheet<_AdvancePayload>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _AdvanceSheet(),
    );
    if (payload == null || !mounted) return;

    final error = await context
        .read<MyCashController>()
        .requestAdvance(salonId, payload.amount, payload.reason);
    if (!mounted) return;
    showAppSnack(
      context,
      error ?? 'Demande envoyée au gérant ✅',
      success: error == null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MyCashController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.gold,
        backgroundColor: AppColors.card,
        onRefresh: controller.load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            if (controller.loading && controller.agenda.isEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 260, child: AppLoader()))
            else if (controller.error != null && controller.agenda.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 260,
                  child: AppError(message: controller.error!, onRetry: controller.load),
                ),
              )
            else ...[
              if (!widget.showAgendaOnly)
                SliverToBoxAdapter(child: _buildKpis(controller)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: _buildAgendaHeader(controller)),
                      GestureDetector(
                        onTap: _addWalkIn,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.teal.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(50),
                            border: Border.all(
                                color: AppColors.teal.withValues(alpha: 0.35)),
                          ),
                          child: Text('➕ طيّاح', style: AppTextStyle.dmSans(
                            size: 12,
                            weight: FontWeight.w700,
                            color: AppColors.teal,
                          )),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _buildSchedule(controller)),
              if (!widget.showAgendaOnly) ...[
                SliverToBoxAdapter(child: _buildAdvanceCard(controller)),
                SliverToBoxAdapter(child: _buildAdvanceHistory(controller)),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final user = context.watch<AuthController>().user;
    final name = user?.name.trim().isNotEmpty == true ? user!.name : 'حجام';

    return Padding(
      padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 20, 24, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مرحبا 👋',
                  style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub)),
              const SizedBox(height: 4),
              Text(name.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.text,
                  )),
            ]),
          ),
          InitialsAvatar(
            initials: initialsOf(name),
            color: TypePalette.forId(user?.id ?? ''),
            size: 52,
            showBadge: true,
          ),
        ],
      ),
    );
  }

  Widget _buildKpis(MyCashController controller) {
    final cash = controller.cash;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: [
        Expanded(child: KpiCard(
          icon: Icons.content_cut_rounded,
          iconColor: AppColors.gold,
          value: '${cash.count}',
          label: 'قطعات اليوم',
          gold: true,
        )),
        const SizedBox(width: 12),
        Expanded(child: KpiCard(
          icon: Icons.monetization_on_rounded,
          iconColor: AppColors.green,
          value: '${cash.myShare.toStringAsFixed(0)} DT',
          label: 'نصيبي اليوم',
        )),
        const SizedBox(width: 12),
        Expanded(child: KpiCard(
          icon: Icons.volunteer_activism_rounded,
          iconColor: AppColors.pink,
          value: '${cash.tips.toStringAsFixed(0)} DT',
          label: 'بقشيش',
        )),
      ]),
    );
  }

  Widget _buildSchedule(MyCashController controller) {
    final bookings = controller.agenda;
    if (bookings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AppEmpty(emoji: '📅', title: 'ما كاين مواعيد اليوم'),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: bookings.map((booking) {
          final color = switch (booking.status) {
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
              SizedBox(
                width: 46,
                child: Text(booking.time, style: GoogleFonts.dmSans(
                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.gold,
                )),
              ),
              Container(
                width: 2, height: 40,
                color: color.withValues(alpha: 0.35),
                margin: const EdgeInsets.symmetric(horizontal: 12),
              ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(booking.clientName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.dmSans(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.text,
                          )),
                    ),
                    if (booking.isWalkIn) ...[
                      const SizedBox(width: 6),
                      Text('walk-in',
                          style: GoogleFonts.dmSans(
                              fontSize: 10, color: AppColors.teal)),
                    ],
                  ]),
                  Text(booking.service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
                ]),
              ),
              const SizedBox(width: 8),
              canComplete
                  ? GestureDetector(
                      onTap: () => _completeBooking(booking),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.gold,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text('خلّص',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            )),
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(booking.status.label,
                          style: GoogleFonts.dmSans(
                            fontSize: 11, fontWeight: FontWeight.w600, color: color,
                          )),
                    ),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAdvanceCard(MyCashController controller) {
    final pending = controller.cash.advancesPending;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.gold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Text('💸', style: TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('طلب سلفة (تسبقة)', style: GoogleFonts.dmSans(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text,
              )),
              Text(
                pending > 0
                    ? 'طلب في الانتظار : ${pending.toStringAsFixed(0)} DT'
                    : 'اطلب تقدم على راتبك مع صاحب الصالون',
                style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub),
              ),
            ]),
          ),
          GestureDetector(
            onTap: pending > 0 ? null : _requestAdvance,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: pending > 0 ? AppColors.border : AppColors.gold,
                borderRadius: BorderRadius.circular(50),
              ),
              child: Text(pending > 0 ? 'في الانتظار' : 'اطلب',
                  style: GoogleFonts.dmSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: pending > 0 ? AppColors.sub : Colors.black,
                  )),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAdvanceHistory(MyCashController controller) {
    if (controller.advances.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SectionHeader(title: '💸 تاريخ السلف'),
        const SizedBox(height: 12),
        ...controller.advances.take(5).map((advance) {
          final color = switch (advance.status) {
            'approved' => AppColors.green,
            'rejected' => AppColors.red,
            'settled' => AppColors.sub,
            _ => AppColors.gold,
          };
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Text('${advance.amount.toStringAsFixed(0)} DT',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.gold,
                  )),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  advance.reason.isEmpty ? advance.requestedAt : advance.reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(advance.status,
                    style: GoogleFonts.dmSans(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color,
                    )),
              ),
            ]),
          );
        }),
      ]),
    );
  }
}

// ── Feuilles modales ──────────────────────────────────────────────
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
    return _SheetShell(
      title: 'خلّص الخدمة',
      subtitle: '${widget.booking.clientName} · '
          '${widget.booking.price.toStringAsFixed(0)} DT',
      children: [
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
                      color: _method == option[0] ? AppColors.gold : AppColors.border,
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
      ],
    );
  }
}

class _AdvancePayload {
  final double amount;
  final String reason;
  const _AdvancePayload(this.amount, this.reason);
}

class _AdvanceSheet extends StatefulWidget {
  const _AdvanceSheet();

  @override
  State<_AdvanceSheet> createState() => _AdvanceSheetState();
}

class _AdvanceSheetState extends State<_AdvanceSheet> {
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'طلب تسبقة',
      subtitle: 'صاحب الصالون يوافق ولا يرفض',
      children: [
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyle.dmSans(size: 15),
          decoration: const InputDecoration(hintText: 'المبلغ (DT)'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _reasonCtrl,
          style: AppTextStyle.dmSans(size: 15),
          decoration: const InputDecoration(hintText: 'السبب (اختياري)'),
        ),
        const SizedBox(height: 20),
        GoldButton(
          text: 'ابعث الطلب',
          onPressed: () {
            final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
            if (amount <= 0) {
              showAppSnack(context, 'Montant invalide');
              return;
            }
            Navigator.pop(
                context, _AdvancePayload(amount, _reasonCtrl.text.trim()));
          },
        ),
      ],
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

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
          Text(title, style: AppTextStyle.playfair(size: 20)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
          const SizedBox(height: 20),
          ...children,
        ]),
      ),
    );
  }
}
