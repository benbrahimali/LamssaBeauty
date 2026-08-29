import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_exception.dart';
import '../data/repositories/salon_admin_repository.dart';
import '../theme/app_theme.dart';
import 'async_states.dart';

/// Classement interne de l'équipe (§3.5).
///
/// Volontairement réservé au gérant : affiché aux clients, il exposerait les
/// coiffeurs les moins bien notés. Son rôle est la motivation en interne, pas
/// la sélection en vitrine.
class TeamRankingSheet extends StatefulWidget {
  const TeamRankingSheet({super.key, required this.salonId});

  final String salonId;

  static Future<void> show(BuildContext context, String salonId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TeamRankingSheet(salonId: salonId),
    );
  }

  @override
  State<TeamRankingSheet> createState() => _TeamRankingSheetState();
}

class _TeamRankingSheetState extends State<TeamRankingSheet> {
  List<RankedStaff> _rows = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await context.read<SalonAdminRepository>().ranking(widget.salonId);
      if (!mounted) return;
      setState(() { _rows = rows; _loading = false; });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
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
        Text('🏆 ترتيب الفريق', style: AppTextStyle.playfair(size: 20)),
        const SizedBox(height: 4),
        Text('حسب عدد القصّات ثم التنقيط',
            style: AppTextStyle.dmSans(size: 12, color: AppColors.sub)),
        const SizedBox(height: 18),
        Flexible(child: _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SizedBox(height: 160, child: AppLoader());
    if (_error != null) {
      return SizedBox(height: 180, child: AppError(message: _error!, onRetry: _load));
    }
    if (_rows.isEmpty) {
      return const AppEmpty(
        emoji: '✂️',
        title: 'ما فماش فريق',
        subtitle: 'زيد حجّامة باش يبدا الترتيب',
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final row = _rows[i];
        final podium = row.rank <= 3;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card2,
            borderRadius: BorderRadius.circular(14),
            // Le podium se distingue d'un liseré, pas d'une couleur criarde :
            // les autres ne doivent pas avoir l'air sanctionnés.
            border: podium
                ? Border.all(color: AppColors.gold.withValues(alpha: 0.4))
                : null,
          ),
          child: Row(children: [
            SizedBox(
              width: 34,
              child: Text(
                row.medal,
                textAlign: TextAlign.center,
                style: podium
                    ? const TextStyle(fontSize: 20)
                    : AppTextStyle.dmSans(size: 14, color: AppColors.sub),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.name.isEmpty ? 'حجّام' : row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.dmSans(weight: FontWeight.w700)),
                Text('كرسي ${row.chair}',
                    style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${row.cuts} قصّة',
                  style: AppTextStyle.dmSans(
                      size: 13, weight: FontWeight.w700, color: AppColors.gold)),
              Row(children: [
                const Icon(Icons.star_rounded, size: 12, color: AppColors.gold),
                const SizedBox(width: 3),
                Text(row.rating.toStringAsFixed(1),
                    style: AppTextStyle.dmSans(size: 11, color: AppColors.sub)),
              ]),
            ]),
          ]),
        );
      },
    );
  }
}
