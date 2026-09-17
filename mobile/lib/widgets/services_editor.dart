import 'package:flutter/material.dart';

import '../core/money.dart';
import '../data/models.dart';
import '../theme/app_theme.dart';

/// Vrai si les prestations finales diffèrent de celles réservées.
///
/// L'ordre ne compte pas : décocher puis recocher la même prestation n'est pas
/// un changement, et ne doit pas réécrire le rendez-vous.
bool servicesChanged(List<String> avant, List<String> apres) {
  final a = avant.toSet(), b = apres.toSet();
  return a.length != b.length || !a.containsAll(b);
}

/// Prix catalogue des prestations choisies, ou null si l'une n'est plus au
/// catalogue — on affiche alors le prix du rendez-vous plutôt qu'un faux total.
double? servicesTotal(List<ServiceItem> catalogue, List<String> ids) {
  var total = 0.0;
  for (final id in ids) {
    final service = catalogue.where((s) => s.id == id).firstOrNull;
    if (service == null) return null;
    total += service.price;
  }
  return total;
}

/// Prestations réellement faites, modifiables au moment d'encaisser (§3.4).
///
/// Le client ajoute une prestation sur place, ou l'une des prévues n'est pas
/// faite : le prix encaissé doit porter sur ce qui a eu lieu.
class ServicesEditor extends StatelessWidget {
  const ServicesEditor({
    super.key,
    required this.catalogue,
    required this.selected,
    required this.onToggle,
    required this.fallbackTotal,
  });

  final List<ServiceItem> catalogue;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  /// Prix du rendez-vous, affiché si le total ne peut pas être recalculé.
  final double fallbackTotal;

  @override
  Widget build(BuildContext context) {
    final total = servicesTotal(catalogue, selected) ?? fallbackTotal;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('الخدمات اللي تعملت — زيد ولا نحّي',
          style: AppTextStyle.dmSans(size: 12, color: AppColors.sub, weight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final service in catalogue)
            _chip(
              service,
              selected.contains(service.id),
              () => onToggle(service.id),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (selected.isEmpty)
        Text(
          'لازم خدمة وحدة على الأقل — كان الزبون ما عمل شي، بطّل الموعد',
          style: AppTextStyle.dmSans(size: 12, color: AppColors.red),
        )
      else
        Row(children: [
          Expanded(
            child: Text('المجموع',
                style: AppTextStyle.dmSans(size: 13, weight: FontWeight.w700)),
          ),
          Text(formatDt(total),
              style: AppTextStyle.dmSans(
                  size: 16, weight: FontWeight.w700, color: AppColors.gold)),
        ]),
    ]);
  }

  Widget _chip(ServiceItem service, bool actif, VoidCallback onTap) {
    final nom = service.nameAr.trim().isNotEmpty ? service.nameAr : service.name;
    return Semantics(
      button: true,
      selected: actif,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: actif ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: actif ? AppColors.gold : AppColors.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              actif ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
              size: 16,
              color: actif ? AppColors.gold : AppColors.sub,
            ),
            const SizedBox(width: 6),
            Text('$nom · ${formatDt(service.price)}',
                style: AppTextStyle.dmSans(
                  size: 12,
                  weight: actif ? FontWeight.w700 : FontWeight.w400,
                  color: actif ? AppColors.gold : AppColors.text,
                )),
          ]),
        ),
      ),
    );
  }
}
