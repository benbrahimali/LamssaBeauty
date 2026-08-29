import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../data/models.dart';

/// Onglets de l'app, nommés plutôt que numérotés.
///
/// Les rôles n'ont pas le même nombre d'onglets — le client en a cinq, les
/// professionnels quatre. Avec de simples index, changer de rôle depuis le
/// profil (index 4) envoyait le gérant sur un onglet inexistant : écran vide.
/// Un onglet identifié se retrouve dans l'autre rôle, ou retombe sur l'accueil.
enum LamssaTab {
  home,
  explore,
  trending,
  dashboard,
  agenda,
  cash,
  notifications,
  profile,
}

/// Onglets d'un rôle, dans l'ordre d'affichage.
List<LamssaTab> tabsFor(AppRole role) => switch (role) {
      AppRole.client => const [
          LamssaTab.home,
          LamssaTab.explore,
          LamssaTab.trending,
          LamssaTab.notifications,
          LamssaTab.profile,
        ],
      AppRole.owner => const [
          LamssaTab.home,
          LamssaTab.dashboard,
          LamssaTab.notifications,
          LamssaTab.profile,
        ],
      AppRole.coiffeur => const [
          LamssaTab.agenda,
          LamssaTab.cash,
          LamssaTab.notifications,
          LamssaTab.profile,
        ],
    };

/// L'onglet équivalent dans un autre rôle, ou l'accueil de ce rôle.
///
/// « Profil » existe partout : basculer depuis cet écran doit y rester, c'est
/// de là que part le changement de rôle.
LamssaTab tabAfterRoleChange(LamssaTab current, AppRole role) {
  final tabs = tabsFor(role);
  return tabs.contains(current) ? current : tabs.first;
}

_NavItemData _itemFor(LamssaTab tab, {required bool isGuest}) => switch (tab) {
      LamssaTab.home =>
        const _NavItemData(icon: Icons.home_rounded, label: 'الرئيسية'),
      LamssaTab.explore =>
        const _NavItemData(icon: Icons.search_rounded, label: 'اكتشف'),
      LamssaTab.trending => const _NavItemData(
          icon: Icons.local_fire_department_rounded, label: 'موضة'),
      LamssaTab.dashboard =>
        const _NavItemData(icon: Icons.bar_chart_rounded, label: 'داشبورد'),
      LamssaTab.agenda =>
        const _NavItemData(icon: Icons.calendar_today_rounded, label: 'مواعيدي'),
      LamssaTab.cash =>
        const _NavItemData(icon: Icons.content_cut_rounded, label: 'كاستي'),
      LamssaTab.notifications => const _NavItemData(
          icon: Icons.notifications_rounded, label: 'إشعارات', hasBadge: true),
      LamssaTab.profile => isGuest
          ? const _NavItemData(icon: Icons.person_add_rounded, label: 'تسجيل')
          : const _NavItemData(icon: Icons.person_rounded, label: 'حسابي'),
    };

class LamssaBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final AppRole role;
  final int badgeCount;

  /// Un visiteur n'a pas de compte : lui parler de « mon compte » ne veut rien
  /// dire, l'onglet doit l'inviter à s'inscrire.
  final bool isGuest;

  const LamssaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.role = AppRole.client,
    this.badgeCount = 0,
    this.isGuest = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = _getItems();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        color: const Color(0xF00C0C16),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: _colorFilter(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: List.generate(items.length, (i) => _NavItem(
                item: items[i],
                isActive: currentIndex == i,
                onTap: () => onTap(i),
                badge: items[i].hasBadge ? badgeCount : 0,
              )),
            ),
          ),
        ),
      ),
    );
  }

  List<_NavItemData> _getItems() => tabsFor(role)
      .map((tab) => _itemFor(tab, isGuest: isGuest))
      .toList();

  ColorFilter _colorFilter() => const ColorFilter.mode(Colors.transparent, BlendMode.multiply);
}

class _NavItemData {
  final IconData icon;
  final String label;
  final bool hasBadge;
  const _NavItemData({required this.icon, required this.label, this.hasBadge = false});
}

class _NavItem extends StatelessWidget {
  final _NavItemData item;
  final bool isActive;
  final VoidCallback onTap;
  final int badge;

  const _NavItem({
    required this.item,
    required this.isActive,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? AppColors.gold.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: isActive
                ? Border.all(color: AppColors.gold.withValues(alpha: 0.2), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    transform: Matrix4.translationValues(0, isActive ? -2 : 0, 0),
                    child: Icon(
                      item.icon,
                      size: 22,
                      color: isActive ? AppColors.gold : const Color(0xFF4A4A5E),
                    ),
                  ),
                  if (badge > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: AppColors.red,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.bg, width: 1.5),
                        ),
                        child: Text(
                          badge > 9 ? '9+' : '$badge',
                          style: GoogleFonts.dmSans(
                            fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                item.label,
                style: GoogleFonts.dmSans(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  color: isActive ? AppColors.gold : const Color(0xFF3A3A50),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedOpacity(
                opacity: isActive ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 4, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.8), blurRadius: 6)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
