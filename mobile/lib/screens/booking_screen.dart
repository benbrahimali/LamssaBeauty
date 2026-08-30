import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_repository.dart';
import '../state/booking_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import '../widgets/common_widgets.dart';

/// Tunnel de réservation (§3.3) : coiffeur → service → jour → créneau.
/// Les créneaux viennent du moteur serveur ; aucun horaire n'est deviné ici.
class BookingScreen extends StatefulWidget {
  final Salon salon;
  final Coiffeur? coiffeur;
  final VoidCallback onBack;
  final void Function(Booking booking) onConfirm;

  const BookingScreen({
    super.key,
    required this.salon,
    this.coiffeur,
    required this.onBack,
    required this.onConfirm,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  List<ServiceItem> _services = const [];
  List<Coiffeur> _team = const [];
  bool _loading = true;
  String? _loadError;
  String _paymentMethod = 'cash';

  @override
  void initState() {
    super.initState();
    _loadCatalogue();
  }

  Future<void> _loadCatalogue() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final detail = await context.read<SalonRepository>().detail(widget.salon.id);
      if (!mounted) return;

      final controller = context.read<BookingController>();
      final available = detail.staff.where((c) => c.available).toList();
      setState(() {
        _services = detail.services;
        _team = detail.staff;
        _loading = false;
      });

      // Sans coiffeur choisi, on en présélectionne un : la grille de créneaux
      // dépend d'une personne précise, on ne peut pas l'afficher autrement.
      if (controller.staffId == null && available.isNotEmpty) {
        await controller.selectStaff(available.first.id);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    final controller = context.read<BookingController>();
    final booking = await controller.confirm(payOnline: _paymentMethod == 'online');
    if (!mounted) return;

    if (booking == null) {
      showAppSnack(context, controller.error ?? 'Réservation impossible');
      return;
    }
    widget.onConfirm(booking);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BookingController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _loading
                    ? const AppLoader(label: 'Chargement du catalogue…')
                    : _loadError != null
                        ? AppError(message: _loadError!, onRetry: _loadCatalogue)
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 210),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSalonInfo(),
                                if (_team.isNotEmpty) _buildStaffSection(controller),
                                _buildServiceSection(controller),
                                if (controller.service != null) ...[
                                  _buildDaySection(controller),
                                  _buildSlotsSection(controller),
                                  _buildPaymentSection(),
                                  _buildSummary(controller),
                                ],
                              ],
                            ),
                          ),
              ),
            ],
          ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomBar(controller),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: widget.onBack,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.arrow_back_rounded, size: 20, color: AppColors.text),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text('احجز موعدك', style: AppTextStyle.playfair(size: 20)),
        ),
      ]),
    );
  }

  Widget _buildSalonInfo() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                widget.salon.color,
                widget.salon.accent.withValues(alpha: 0.2),
              ]),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(widget.salon.initials, style: GoogleFonts.playfairDisplay(
              fontSize: 18, fontWeight: FontWeight.w900, color: widget.salon.accent,
            )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.salon.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.dmSans(size: 15, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(widget.salon.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildStaffSection(BookingController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('اختار الحجام 💈'),
      SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _team.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final member = _team[i];
            final selected = controller.staffId == member.id;
            return GestureDetector(
              onTap: member.available ? () => controller.selectStaff(member.id) : null,
              child: Opacity(
                opacity: member.available ? 1 : 0.4,
                child: Container(
                  width: 88,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.gold.withValues(alpha: 0.12)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    InitialsAvatar(
                      initials: member.initials,
                      color: member.color,
                      size: 42,
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        member.name.split(' ').first,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppTextStyle.dmSans(
                          size: 11,
                          weight: FontWeight.w600,
                          color: selected ? AppColors.gold : AppColors.text,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildServiceSection(BookingController controller) {
    if (_services.isEmpty) {
      return const AppEmpty(
        emoji: '✂️',
        title: 'Aucun service disponible',
        subtitle: "Ce salon n'a pas encore publié son catalogue.",
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('اختار الخدمة ✂️'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: _services.map((service) {
            final selected = controller.service?.id == service.id;
            return GestureDetector(
              onTap: () => controller.selectService(service),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.gold.withValues(alpha: 0.1)
                      : AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? AppColors.gold : AppColors.border,
                  ),
                ),
                child: Row(children: [
                  Text(service.icon, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(
                        service.nameAr.trim().isNotEmpty ? service.nameAr : service.name,
                        style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text('⏱ ${service.duration} دقيقة',
                          style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
                    ]),
                  ),
                  Text('${service.price.toStringAsFixed(0)} DT',
                      style: AppTextStyle.playfair(size: 16, color: AppColors.gold)),
                ]),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildDaySection(BookingController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('اختار النهار 📅'),
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: controller.days.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) {
            final day = controller.days[i];
            final selected = controller.dayIndex == i;
            final etat = controller.availabilityFor(day);
            final ouvert = controller.isDayOpen(day);

            // Un jour fermé se voit avant d'être touché : le client n'a plus
            // à essayer les quatorze cases pour trouver celle où le coiffeur
            // travaille. Le motif distingue « راحة » de « كامل », qui
            // n'appellent pas la même réaction.
            return Opacity(
              opacity: ouvert ? 1 : 0.45,
              child: GestureDetector(
                onTap: ouvert ? () => controller.selectDay(i) : null,
                child: Container(
                  width: 60,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.gold : AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                    ),
                  ),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(day.dayShort,
                            style: AppTextStyle.dmSans(
                              size: 11,
                              color: selected ? Colors.black : AppColors.sub,
                            )),
                        const SizedBox(height: 3),
                        Text(day.dayNum,
                            style: AppTextStyle.playfair(
                              size: 19,
                              color: selected ? Colors.black : AppColors.text,
                            )),
                        if (!ouvert && etat?.reason != null) ...[
                          const SizedBox(height: 2),
                          Text(etat!.reason!.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.dmSans(
                                size: 9,
                                color:
                                    selected ? Colors.black : AppColors.sub,
                              )),
                        ],
                      ]),
                ),
              ),
            );
          },
        ),
      ),
      if (controller.days.every((d) => !controller.isDayOpen(d)) &&
          !controller.loadingDays)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'هالحجّام ما عندو حتّى نهار خالي في الأسبوعين الجايين — '
            'جرّب حجّام آخر.',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
          ),
        ),
    ]);
  }

  /// Journée sans créneau : le motif change ce que le client doit faire.
  ///
  /// « Complet » invite à revenir un autre jour ; un jour de repos invite à
  /// changer de coiffeur. Le même message pour les deux faisait tourner en
  /// rond ceux qui tombaient sur le repos hebdomadaire.
  Widget _buildEmptyDay(BookingController controller) {
    final motif = controller.availabilityFor(controller.selectedDay)?.reason;
    return switch (motif) {
      DayUnavailability.dayOff => const AppEmpty(
          emoji: '😴',
          title: 'الحجّام في راحة',
          subtitle: 'اختار نهار آخر ولا حجّام آخر.',
        ),
      DayUnavailability.salonClosed => const AppEmpty(
          emoji: '🔒',
          title: 'الصالون مسكّر',
          subtitle: 'شوف نهار آخر في التقويم.',
        ),
      DayUnavailability.staffUnavailable => const AppEmpty(
          emoji: '🚫',
          title: 'الحجّام مش متوفّر',
          subtitle: 'جرّب حجّام آخر في نفس الصالون.',
        ),
      _ => const AppEmpty(
          emoji: '📅',
          title: 'كامل هالنهار',
          subtitle: 'جرّب نهار آخر ولا حجّام آخر.',
        ),
    };
  }

  Widget _buildSlotsSection(BookingController controller) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('اختار الوقت 🕐'),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Text(controller.selectedDay.fullDate,
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
      ),
      if (controller.loadingSlots)
        const Padding(padding: EdgeInsets.all(24), child: AppLoader())
      else if (controller.staffId == null)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: AppEmpty(
            emoji: '💈',
            title: 'Choisis un coiffeur',
            subtitle: 'Les créneaux dépendent de son planning.',
          ),
        )
      else if (controller.slots.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _buildEmptyDay(controller),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: controller.slots.map((slot) {
              final selected = controller.slot?.start == slot.start;
              return GestureDetector(
                onTap: () => controller.selectSlot(slot),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.gold : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                    ),
                  ),
                  child: Text(slot.time, style: AppTextStyle.dmSans(
                    size: 13,
                    weight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? Colors.black : AppColors.text,
                  )),
                ),
              );
            }).toList(),
          ),
        ),
    ]);
  }

  Widget _buildPaymentSection() {
    final options = <Map<String, String>>[
      {'id': 'cash', 'label': '💵 كاش في الصالون'},
      {'id': 'online', 'label': '💳 خلص أونلاين'},
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionTitle('طريقة الخلاص 💳'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: options.map((option) {
            final selected = _paymentMethod == option['id'];
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _paymentMethod = option['id']!),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.gold.withValues(alpha: 0.12)
                        : AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? AppColors.gold : AppColors.border,
                    ),
                  ),
                  child: Text(option['label']!,
                      textAlign: TextAlign.center,
                      style: AppTextStyle.dmSans(
                        size: 12,
                        weight: selected ? FontWeight.w700 : FontWeight.w400,
                        color: selected ? AppColors.gold : AppColors.sub,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildSummary(BookingController controller) {
    final service = controller.service!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          _summaryRow('الخدمة',
              service.nameAr.trim().isNotEmpty ? service.nameAr : service.name),
          _summaryRow('التاريخ', controller.selectedDay.fullDate),
          _summaryRow('الوقت', controller.slot?.time ?? '—'),
          const Divider(color: AppColors.border, height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('المجموع',
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
            Text('${service.price.toStringAsFixed(0)} DT',
                style: AppTextStyle.playfair(size: 20, color: AppColors.gold)),
          ]),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        Flexible(
          child: Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _buildBottomBar(BookingController controller) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).padding.bottom + 16),
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (controller.alternatives.isNotEmpty) ...[
          Text(
            'Créneau pris entre-temps — essaie : '
            '${controller.alternatives.take(3).map(_formatIso).join('  ·  ')}',
            textAlign: TextAlign.center,
            style: AppTextStyle.dmSans(size: 12, color: AppColors.gold),
          ),
          const SizedBox(height: 10),
        ],
        controller.submitting
            ? const SizedBox(height: 56, child: AppLoader())
            : GoldButton(
                text: _paymentMethod == 'online'
                    ? 'خلص و أكد ✨'
                    : 'أكد الحجز ✨',
                enabled: controller.canBook,
                onPressed: _confirm,
              ),
      ]),
    );
  }

  String _formatIso(String iso) {
    final parsed = DateTime.tryParse(iso)?.toLocal();
    if (parsed == null) return iso;
    return '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}';
  }

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
        child: Text(title, style: AppTextStyle.playfair(size: 17)),
      );
}
