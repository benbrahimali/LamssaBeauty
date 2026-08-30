import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../core/env.dart';
import '../data/models.dart';
import '../state/auth_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/async_states.dart';
import 'create_salon_screen.dart';
import 'edit_profile_screen.dart';
import 'help_screen.dart';
import 'manage_salon_screen.dart';
import 'my_bookings_screen.dart';
import 'my_portfolio_screen.dart';
import 'privacy_screen.dart';
import 'reels_screen.dart';
import 'salon_qr_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.onSignedOut,
    this.onGoStaff,
    this.onGoSalon,
  });

  final VoidCallback onSignedOut;

  /// Navigation vers l'auteur d'un reel. Sans elle, le bouton « احجز » du
  /// lecteur ouvert depuis ce menu ne menait nulle part.
  final void Function(String staffId)? onGoStaff;
  final void Function(String salonId)? onGoSalon;

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
          ] else
            SliverToBoxAdapter(child: _buildSignUpInvite(context)),
          SliverToBoxAdapter(child: _buildMenu(context, auth)),
          const SliverToBoxAdapter(child: SizedBox(height: 110)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AuthController auth) {
    final user = auth.user;
    final guest = auth.status != AuthStatus.loggedIn;
    final name = user?.name.trim().isNotEmpty == true ? user!.name : 'ضيف';
    // Annoncer « عميل » à quelqu'un qui n'a pas de compte est faux : le rôle
    // n'existe que côté serveur, une fois inscrit.
    final label = guest
        ? null
        : switch (auth.role) {
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
          user?.phone.isNotEmpty == true ? user!.phone : 'تتفرّج كزائر',
          style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.sub),
        ),
        if (label != null) ...[
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
        ],
      ]),
    );
  }

  /// Ce qu'un visiteur gagne à s'inscrire.
  ///
  /// Sans compte il ne peut que regarder : réserver, aimer et suivre ses RDV
  /// exigent une identité. Autant le lui dire ici, plutôt que de le laisser
  /// buter sur un refus au moment de réserver.
  Widget _buildSignUpInvite(BuildContext context) {
    const avantages = [
      ('📅', 'احجز في ثواني'),
      ('🔔', 'تذكير قبل موعدك'),
      ('❤️', 'سجّل الحجامة اللي عجبوك'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            AppColors.gold.withValues(alpha: 0.14),
            AppColors.pink.withValues(alpha: 0.08),
          ]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('اعمل حساب في دقيقة',
              style: GoogleFonts.playfairDisplay(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.text,
              )),
          const SizedBox(height: 4),
          Text('برقم تليفونك، بلا كلمة سر',
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.sub)),
          const SizedBox(height: 16),
          ...avantages.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  Text(a.$1, style: const TextStyle(fontSize: 15)),
                  const SizedBox(width: 10),
                  Text(a.$2,
                      style:
                          GoogleFonts.dmSans(fontSize: 13, color: AppColors.text)),
                ]),
              )),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              // `onSignedOut` ramène à l'écran d'accueil non connecté, d'où
              // part l'inscription : c'est le même chemin que la déconnexion.
              onPressed: onSignedOut,
              child: Text('ابدأ ✨',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  )),
            ),
          ),
        ]),
      ),
    );
  }

  /// Un compte n'accède qu'aux espaces que son rôle serveur autorise :
  /// afficher les autres ne ferait que produire des 403.
  Widget _buildRoleSwitch(BuildContext context, AuthController auth) {
    // La liste vient du contrôleur : dupliquer la règle ici finirait par
    // proposer un espace que `switchView` refuse, ou l'inverse.
    final available = auth.availableRoles;
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
      // Les reels n'étaient atteignables que depuis l'onglet « موضة », réservé
      // au client : les seuls autorisés à publier ne pouvaient pas y accéder.
      if (loggedIn &&
          (auth.context?.staffId != null || auth.context?.ownedSalonId != null))
        {
          'icon': Icons.videocam_rounded,
          'label': 'ريلز — انشر فيديو',
          'action': 'reels',
        },
      // Modifier un compte ou régler sa confidentialité n'a aucun sens tant
      // qu'il n'y en a pas : ces entrées ne mèneraient nulle part.
      if (loggedIn) ...[
        {
          'icon': Icons.person_rounded,
          'label': 'تعديل الحساب',
          'action': 'edit_profile'
        },
        {
          'icon': Icons.lock_rounded,
          'label': 'الأمان والخصوصية',
          'action': 'privacy'
        },
      ],
      {'icon': Icons.help_rounded, 'label': 'المساعدة', 'action': 'help'},
      {
        'icon': loggedIn ? Icons.logout_rounded : Icons.login_rounded,
        'label': loggedIn ? 'تسجيل الخروج' : 'عندي حساب — دخول',
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
                  case 'edit_profile':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EditProfileScreen(),
                    ));
                  case 'privacy':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PrivacyScreen(),
                    ));
                  case 'help':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const HelpScreen(),
                    ));
                  case 'reels':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ReelsScreen(
                        onGoStaff: onGoStaff,
                        onGoSalon: onGoSalon,
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
