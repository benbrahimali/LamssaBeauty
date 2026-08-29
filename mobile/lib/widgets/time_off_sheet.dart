import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Congés d'un coiffeur (§3.5).
///
/// Un congé posé ici retire automatiquement ses créneaux du calendrier public :
/// sans cet écran, un gérant devait refuser les RDV un par un.
class TimeOffSheet extends StatefulWidget {
  const TimeOffSheet({
    super.key,
    required this.salonId,
    required this.member,
  });

  final String salonId;
  final Coiffeur member;

  static Future<void> show(
    BuildContext context, {
    required String salonId,
    required Coiffeur member,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TimeOffSheet(salonId: salonId, member: member),
    );
  }

  @override
  State<TimeOffSheet> createState() => _TimeOffSheetState();
}

class _TimeOffSheetState extends State<TimeOffSheet> {
  List<TimeOff> _all = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  SalonAdminRepository get _repo => context.read<SalonAdminRepository>();

  /// Congés de ce coiffeur uniquement : le serveur renvoie ceux de tout le salon.
  List<TimeOff> get _mine =>
      _all.where((o) => o.staffId == widget.member.id).toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final all = await _repo.timeOff(widget.salonId);
      if (!mounted) return;
      setState(() { _all = all; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  Future<void> _add() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.gold,
            onPrimary: Colors.black,
            surface: AppColors.card,
          ),
        ),
        child: child!,
      ),
    );
    if (range == null || !mounted) return;

    setState(() => _saving = true);
    try {
      final result = await _repo.addTimeOff(
        salonId: widget.salonId,
        staffId: widget.member.id,
        start: range.start,
        // La date de fin choisie est un jour entier de congé : sans cette
        // borne, le dernier jour resterait réservable jusqu'à minuit.
        end: DateTime(range.end.year, range.end.month, range.end.day, 23, 59),
      );
      if (!mounted) return;
      setState(() {
        _all = [..._all, result.timeOff];
        _saving = false;
      });

      // Le serveur compte les RDV déjà pris sur la période. Les taire ferait
      // découvrir le problème aux clients avant le gérant.
      showAppSnack(
        context,
        result.toReschedule == 0
            ? 'العطلة تسجّلت ✅'
            : '⚠️ العطلة تسجّلت — ${result.toReschedule} موعد لازم يتبدّل',
        success: result.toReschedule == 0,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppSnack(context, e.message);
    }
  }

  Future<void> _remove(TimeOff off) async {
    final before = _all;
    setState(() => _all = _all.where((o) => o.id != off.id).toList());
    try {
      await _repo.removeTimeOff(widget.salonId, off.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _all = before);
      showAppSnack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
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
        Text('عطل ${widget.member.name}', style: AppTextStyle.playfair(size: 19)),
        const SizedBox(height: 4),
        Text(
          'المواعيد تتشطب أوتوماتيك في هالأيام',
          style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
        ),
        const SizedBox(height: 18),
        Flexible(child: _buildList()),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _saving ? null : _add,
            icon: _saving
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black),
                  )
                : const Icon(Icons.event_busy_rounded, size: 18),
            label: Text('زيد عطلة',
                style: AppTextStyle.dmSans(
                    color: Colors.black, weight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _buildList() {
    if (_loading) return const SizedBox(height: 120, child: AppLoader());
    if (_error != null) {
      return SizedBox(
        height: 140,
        child: AppError(message: _error!, onRetry: _load),
      );
    }
    if (_mine.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('ما فماش عطل مسجّلة',
            style: AppTextStyle.dmSans(size: 13, color: AppColors.sub)),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _mine.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final off = _mine[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            const Icon(Icons.event_busy_rounded, size: 18, color: AppColors.gold),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(off.range,
                    style: AppTextStyle.dmSans(weight: FontWeight.w600)),
                if (off.reason.isNotEmpty)
                  Text(off.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
              ]),
            ),
            GestureDetector(
              onTap: () => _remove(off),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 18, color: AppColors.red),
              ),
            ),
          ]),
        );
      },
    );
  }
}
