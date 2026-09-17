import 'package:flutter/material.dart';

import '../core/booking_actions.dart';
import '../theme/app_theme.dart';

/// Menu « ⋮ » d'un rendez-vous : « ما جاش » et « بطّل الموعد ».
///
/// « خلّص » reste un bouton à part : c'est le geste de tous les jours, il ne
/// doit pas se cacher dans un menu.
class BookingActionsMenu extends StatelessWidget {
  const BookingActionsMenu({super.key, required this.actions, required this.onSelected});

  final List<BookingAction> actions;
  final ValueChanged<BookingAction> onSelected;

  /// Vrai si le menu a quelque chose à proposer.
  static bool hasItems(List<BookingAction> actions) =>
      actions.contains(BookingAction.noShow) || actions.contains(BookingAction.cancel);

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<BookingAction>(
      tooltip: 'خيارات الموعد',
      color: AppColors.card,
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.sub),
      onSelected: onSelected,
      itemBuilder: (_) => [
        if (actions.contains(BookingAction.noShow))
          _item(BookingAction.noShow, Icons.person_off_rounded, 'ما جاش', AppColors.text),
        if (actions.contains(BookingAction.cancel))
          _item(BookingAction.cancel, Icons.event_busy_rounded, 'بطّل الموعد', AppColors.red),
      ],
    );
  }

  PopupMenuItem<BookingAction> _item(
      BookingAction action, IconData icon, String label, Color couleur) {
    return PopupMenuItem(
      value: action,
      child: Row(children: [
        Icon(icon, size: 18, color: couleur),
        const SizedBox(width: 10),
        Text(label, style: AppTextStyle.dmSans(size: 14, color: couleur)),
      ]),
    );
  }
}

/// Demande confirmation avant de marquer absent ou d'annuler.
///
/// Les deux gestes préviennent ou pénalisent le client : un toucher par erreur
/// ne doit pas suffire.
Future<bool> confirmBookingAction(BuildContext context, BookingAction action) async {
  final absent = action == BookingAction.noShow;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.card,
      title: Text(absent ? 'الزبون ما جاش ؟' : 'تبطّل الموعد ؟',
          style: AppTextStyle.playfair(size: 18)),
      content: Text(
        absent
            ? 'الموعد يتسجّل « غايب ». كان جا من بعد، تنجم تخلّصو عادي.'
            : 'الزبون يوصلو إشعار بلي الموعد تبطّل.',
        style: AppTextStyle.dmSans(size: 13, color: AppColors.sub).copyWith(height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('لا', style: AppTextStyle.dmSans(color: AppColors.sub)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text('نعم',
              style: AppTextStyle.dmSans(
                  color: absent ? AppColors.gold : AppColors.red, weight: FontWeight.w700)),
        ),
      ],
    ),
  );
  return ok == true;
}
