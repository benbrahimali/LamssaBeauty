import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';
import '../core/money.dart';

/// Ce que la feuille de saisie renvoie pour créer un walk-in.
class WalkInPayload {
  final String staffId;

  /// Une ou plusieurs prestations, dans l'ordre du catalogue.
  final List<String> serviceIds;
  final String clientName;

  /// Encaisser tout de suite : le client de passage est déjà servi.
  final bool payNow;

  /// `cash` ou `card`, quand [payNow].
  final String method;

  const WalkInPayload({
    required this.staffId,
    required this.serviceIds,
    required this.clientName,
    this.payNow = false,
    this.method = 'cash',
  });
}

/// Saisie d'un client de passage (§3.3, §8.4).
///
/// Partagée entre la caisse du gérant et le tableau de bord du coiffeur : le
/// coiffeur ne choisit pas la personne, il ne peut saisir que pour lui-même.
class WalkInSheet extends StatefulWidget {
  const WalkInSheet({
    super.key,
    required this.services,
    required this.team,
    this.lockedStaffId,
  });

  final List<ServiceItem> services;
  final List<Coiffeur> team;

  /// Non nul côté coiffeur : le sélecteur d'équipe disparaît.
  final String? lockedStaffId;

  @override
  State<WalkInSheet> createState() => _WalkInSheetState();
}

class _WalkInSheetState extends State<WalkInSheet> {
  final _nameCtrl = TextEditingController();
  String? _staffId;
  /// Coupe + barbe se saisissent d'un coup : un client de passage prend
  /// souvent plus d'une prestation.
  final Set<String> _serviceIds = {};

  /// Activé par défaut : oublier « خلّص » laissait la recette du jour
  /// inchangée alors que le client avait payé.
  bool _payNow = true;
  String _method = 'cash';

  @override
  void initState() {
    super.initState();
    _staffId = widget.lockedStaffId ??
        (widget.team.where((c) => c.available).isNotEmpty
            ? widget.team.firstWhere((c) => c.available).id
            : widget.team.first.id);
    _serviceIds.add(widget.services.first.id);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _valid => _staffId != null && _serviceIds.isNotEmpty;

  double get _total => widget.services
      .where((s) => _serviceIds.contains(s.id))
      .fold(0.0, (total, s) => total + s.price);

  @override
  Widget build(BuildContext context) {
    final showTeam = widget.lockedStaffId == null && widget.team.length > 1;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        decoration: const BoxDecoration(
          color: AppColors.card2,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(50),
              ),
            ),
            const SizedBox(height: 18),
            Text('زبون طيّاح', style: AppTextStyle.playfair(size: 20)),
            const SizedBox(height: 4),
            Text(
              'زيدو للأجندة باش الكاسة تبقى صحيحة',
              style: AppTextStyle.dmSans(size: 12, color: AppColors.sub),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              style: AppTextStyle.dmSans(size: 15),
              decoration: const InputDecoration(hintText: 'اسم الزبون'),
            ),
            const SizedBox(height: 16),

            if (showTeam) ...[
              _label('الحجام'),
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.team.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final member = widget.team[i];
                    return _chip(
                      label: member.name.split(' ').first,
                      selected: _staffId == member.id,
                      onTap: () => setState(() => _staffId = member.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],

            _label('الخدمة — وحدة ولا أكثر'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.services.map((service) {
                    final title = service.nameAr.trim().isNotEmpty
                        ? service.nameAr
                        : service.name;
                    return _chip(
                      label: '$title · ${service.price.toStringAsFixed(0)} DT',
                      selected: _serviceIds.contains(service.id),
                      onTap: () => setState(() {
                        if (!_serviceIds.remove(service.id)) {
                          _serviceIds.add(service.id);
                        }
                      }),
                    );
                  }).toList(),
                ),
              ),
            ),
            if (_serviceIds.length > 1) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text('المجموع : ${formatDt(_total)}',
                    style: AppTextStyle.dmSans(
                        size: 13, weight: FontWeight.w700, color: AppColors.gold)),
              ),
            ],
            const SizedBox(height: 16),
            _buildPayNow(),
            const SizedBox(height: 22),

            GoldButton(
              text: _payNow ? 'زيدو و خلّص' : 'زيدو',
              enabled: _valid,
              onPressed: () => Navigator.pop(
                context,
                WalkInPayload(
                  staffId: _staffId!,
                  serviceIds: [
                    for (final s in widget.services)
                      if (_serviceIds.contains(s.id)) s.id,
                  ],
                  clientName: _nameCtrl.text.trim().isEmpty
                      ? 'زبون طيّاح'
                      : _nameCtrl.text.trim(),
                  payNow: _payNow,
                  method: _method,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPayNow() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Row(children: [
          Expanded(
            child: Text('خلّص توّا',
                style: AppTextStyle.dmSans(size: 14, weight: FontWeight.w700)),
          ),
          Switch(
            value: _payNow,
            activeTrackColor: AppColors.gold,
            onChanged: (v) => setState(() => _payNow = v),
          ),
        ]),
        if (_payNow)
          Row(children: [
            Expanded(
              child: _chip(
                label: '💵 كاش',
                selected: _method == 'cash',
                onTap: () => setState(() => _method = 'cash'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _chip(
                label: '💳 كارط',
                selected: _method == 'card',
                onTap: () => setState(() => _method = 'card'),
              ),
            ),
          ]),
      ]),
    );
  }

  Widget _label(String text) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(text,
              style: AppTextStyle.dmSans(
                  size: 12, weight: FontWeight.w600, color: AppColors.sub)),
        ),
      );

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold.withValues(alpha: 0.15) : AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.gold : AppColors.border),
        ),
        alignment: Alignment.center,
        child: Text(label, style: AppTextStyle.dmSans(
          size: 12,
          weight: selected ? FontWeight.w700 : FontWeight.w400,
          color: selected ? AppColors.gold : AppColors.text,
        )),
      ),
    );
  }
}
