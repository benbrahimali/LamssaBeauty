import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/env.dart';
import '../data/models.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import 'create_salon_screen.dart';
import 'manage_salon_screen.dart';
import 'my_bookings_screen.dart';
import 'my_portfolio_screen.dart';
import 'salon_qr_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.onSignedOut});

  final VoidCallback onSignedOut;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(context, auth)),
          if (auth.status == AuthStatus.loggedIn) ...[
            SliverToBoxAdapter(child: _buildRoleSwitch(context, auth)),
            SliverToBoxAdapter(child: _buildAccountInfo(context, auth)),
          ],
          SliverToBoxAdapter(child: _buildMenu(context, auth)),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AuthController auth) {
    final user = auth.user;
    final name = user?.name.trim().isNotEmpty == true ? user!.name : 'ضيف';
    final label = switch (auth.role) {
      AppRole.client => '👤 عميل',
      AppRole.owner => '👑 صاحب صالون',
      AppRole.coiffeur => '✂️ حجام',
    };

    return Container(
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 20, 24, 28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.gold.withValues(alpha: 0.08), AppColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(children: [
        Container(
          width: 90,
          height: 90,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppColors.goldGradient,
          ),
          alignment: Alignment.center,
          child: Text(initialsOf(name),
              style: GoogleFonts.playfairDisplay(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              )),
        ),
        const SizedBox(height: 16),
        Text(name,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            )),
        const SizedBox(height: 4),
        Text(
          user?.phone.isNotEmpty == true ? user!.phone : 'Non connecté',
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Text(label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                color: AppColors.gold,
                fontWeight: FontWeight.w600,
              )),
        ),
      ]),
    );
  }

  /// Un compte n'accède qu'aux espaces que son rôle serveur autorise :
  /// afficher les autres ne ferait que produire des 403.
  Widget _buildRoleSwitch(BuildContext context, AuthController auth) {
    final available = <AppRole>[
      AppRole.client,
      if (auth.context?.ownedSalonId != null) AppRole.owner,
      if (auth.context?.staffId != null) AppRole.coiffeur,
    ];
    if (available.length < 2) return const SizedBox.shrink();

    const labels = {
      AppRole.client: '👤 عميل',
      AppRole.owner: '👑 صالون',
      AppRole.coiffeur: '✂️ حجام',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text('تبديل الحساب',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              )),
        ),
        Row(
          children: available.map((role) {
            final active = auth.role == role;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => auth.switchView(role),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.gold : AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: active ? AppColors.gold : AppColors.border),
                  ),
                  child: Text(labels[role]!,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active ? Colors.black : AppColors.sub,
                      )),
                ),
              ),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildAccountInfo(BuildContext context, AuthController auth) {
    final salonName = auth.context?.ownedSalonName ?? '';
    final isArabic = auth.user?.locale != 'fr';
    final rows = <List<String>>[
      if (salonName.isNotEmpty) ['🏪', 'صالوني', salonName],
      ['🌐', 'اللغة', isArabic ? 'العربية' : 'Français'],
      ['🔗', 'API', Env.apiBaseUrl],
    ];
    // La langue pilote le sens de lecture de toute l'app : la ligne doit être
    // actionnable, pas seulement informative.
    final localeRow = salonName.isNotEmpty ? 1 : 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: List.generate(rows.length, (i) {
            final row = rows[i];
            final tappable = i == localeRow;
            return GestureDetector(
              onTap: tappable
                  ? () async {
                      final error =
                          await auth.setLocale(isArabic ? 'fr' : 'ar');
                      if (error != null && context.mounted) {
                        showAppSnack(context, error);
                      }
                    }
                  : null,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  border: i == rows.length - 1
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(children: [
                  Text(row[0], style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 12),
                  Text(row[1],
                      style: GoogleFonts.dmSans(
                          fontSize: 13, color: AppColors.sub)),
                  const Spacer(),
                  Flexible(
                    child: Text(row[2],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.text,
                        )),
                  ),
                  if (tappable) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.swap_horiz_rounded,
                        size: 16, color: AppColors.gold),
                  ],
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, AuthController auth) {
    final loggedIn = auth.status == AuthStatus.loggedIn;
    final items = <Map<String, Object>>[
      if (loggedIn)
        {
          'icon': Icons.calendar_month_rounded,
          'label': 'مواعيدي',
          'action': 'bookings',
        },
      if (loggedIn && auth.context?.ownedSalonId != null) ...[
        {
          'icon': Icons.storefront_rounded,
          'label': 'إدارة صالوني',
          'action': 'manage_salon',
        },
        {
          'icon': Icons.qr_code_2_rounded,
          'label': 'كود الصالون',
          'action': 'salon_qr',
        },
      ],
      // Tout compte connecté peut ouvrir un salon : le backend le promeut
      // automatiquement au rôle OWNER à la création (§3.1).
      if (loggedIn && auth.context?.ownedSalonId == null)
        {
          'icon': Icons.add_business_rounded,
          'label': 'أنشئ صالون',
          'action': 'create_salon',
        },
      // Le coiffeur alimente son mur : c'est ce qui remonte dans « En vogue »
      // et amène les réservations (§8.3).
      if (loggedIn && auth.context?.staffId != null)
        {
          'icon': Icons.photo_library_rounded,
          'label': 'خدمتي',
          'action': 'my_portfolio',
        },
      {'icon': Icons.person_rounded, 'label': 'تعديل الحساب', 'action': 'soon'},
      {
        'icon': Icons.lock_rounded,
        'label': 'الأمان والخصوصية',
        'action': 'soon'
      },
      {'icon': Icons.help_rounded, 'label': 'المساعدة', 'action': 'soon'},
      {
        'icon': loggedIn ? Icons.logout_rounded : Icons.login_rounded,
        'label': loggedIn ? 'تسجيل الخروج' : 'تسجيل الدخول',
        'action': loggedIn ? 'logout' : 'login',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final action = item['action'] as String;
            final danger = action == 'logout';
            final isLast = i == items.length - 1;

            return GestureDetector(
              onTap: () async {
                switch (action) {
                  case 'bookings':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MyBookingsScreen(),
                    ));
                  case 'create_salon':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const CreateSalonScreen(),
                    ));
                  case 'manage_salon':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ManageSalonScreen(
                        salonId: auth.context!.ownedSalonId!,
                        salonName: auth.context!.ownedSalonName,
                      ),
                    ));
                  case 'my_portfolio':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MyPortfolioScreen(
                        staffId: auth.context!.staffId!,
                      ),
                    ));
                  case 'salon_qr':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => SalonQrScreen(
                        salonId: auth.context!.ownedSalonId!,
                        salonName: auth.context!.ownedSalonName,
                      ),
                    ));
                  case 'logout':
                    await auth.logout();
                    onSignedOut();
                  case 'login':
                    onSignedOut();
                  default:
                    showAppSnack(context, 'Bientôt disponible');
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: AppColors.border)),
                ),
                child: Row(children: [
                  Icon(item['icon'] as IconData,
                      size: 20, color: danger ? AppColors.red : AppColors.gold),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(item['label'] as String,
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          color: danger ? AppColors.red : AppColors.text,
                          fontWeight: FontWeight.w500,
                        )),
                  ),
                  if (!danger)
                    const Icon(Icons.chevron_right,
                        color: AppColors.sub, size: 18),
                ]),
              ),
            );
          }),
        ),
      ),
    );
  }
}
