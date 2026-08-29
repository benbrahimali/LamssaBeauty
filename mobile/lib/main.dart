import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_providers.dart';
import 'core/api_exception.dart';
import 'core/push_service.dart';
import 'data/repositories/salon_repository.dart';
import 'data/models.dart';
import 'screens/auth_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/caisse_screen.dart';
import 'screens/coiffeur_dashboard_screen.dart';
import 'screens/coiffeur_profile_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/home_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/my_bookings_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/owner_dashboard_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/salon_detail_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/style_dna_screen.dart';
import 'screens/trending_screen.dart';
import 'state/auth_controller.dart';
import 'state/booking_controller.dart';
import 'state/cash_controller.dart';
import 'state/notifications_controller.dart';
import 'state/portfolio_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/async_states.dart';
import 'widgets/bottom_nav.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const AppProviders(child: LamssaApp()));
}

class LamssaApp extends StatelessWidget {
  const LamssaApp({super.key});

  /// Locale de l'interface (§2.5).
  ///
  /// L'app est écrite en arabe tunisien : l'arabe est donc la locale par défaut,
  /// y compris pour un invité. Sans ça, du texte arabe serait rendu en base LTR
  /// — ponctuation, icônes et alignements se retrouvent du mauvais côté.
  static Locale localeFor(String? userLocale) =>
      userLocale == 'fr' ? const Locale('fr') : const Locale('ar');

  @override
  Widget build(BuildContext context) {
    // `watch` : changer de langue depuis le profil doit repeindre toute l'app.
    final locale = localeFor(context.watch<AuthController>().user?.locale);

    return MaterialApp(
      title: 'LAMSSA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: locale,
      supportedLocales: const [Locale('ar'), Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppShell(),
    );
  }
}

// ── Screen states ─────────────────────────────────────────────────
enum _Screen { splash, onboarding, landing, auth, main, styleDna }

class _AppShell extends StatefulWidget {
  const _AppShell();
  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  _Screen _screen = _Screen.splash;
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    // Le tap sur une notification doit atterrir sur l'écran concerné, pas sur
    // l'accueil : c'est ce qui différencie un rappel utile d'une alerte subie.
    context.read<PushService>().onTap = _openFromPush;
  }

  /// Le client a cinq onglets (« En vogue » en plus), les rôles pro quatre :
  /// l'index des notifications n'est donc pas le même selon le rôle.
  int get _notificationsIndex => _auth.role == AppRole.client ? 3 : 2;

  void _openFromPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    context.read<NotificationsController>().load();

    switch (type) {
      case 'booking_confirmed':
      case 'booking_cancelled':
      case 'reminder_j1':
      case 'reminder_h2':
      case 'your_turn':
        // Côté pro, ces notifications parlent de l'agenda ; côté client, de ses RDV.
        if (_auth.role == AppRole.client) {
          if (_auth.status != AuthStatus.loggedIn) return;
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => const MyBookingsScreen(),
          ));
        } else {
          setState(() { _screen = _Screen.main; _navIndex = 0; });
        }
      case 'advance_requested':
      case 'advance_decided':
      case 'closure_ready':
        setState(() { _screen = _Screen.main; _navIndex = 1; });
      default:
        setState(() { _screen = _Screen.main; _navIndex = _notificationsIndex; });
    }
  }

  // Detail navigation
  Salon? _currentSalon;
  Coiffeur? _currentCoiffeur;
  bool _inBooking = false;
  Booking? _confirmedBooking;

  AuthController get _auth => context.read<AuthController>();

  void _goSalon(Salon s) => setState(() { _currentSalon = s; _currentCoiffeur = null; });
  void _goCoiffeur(Coiffeur c) => setState(() { _currentCoiffeur = c; });
  void _goBack() => setState(() {
    if (_inBooking) { _inBooking = false; }
    else if (_currentCoiffeur != null) { _currentCoiffeur = null; }
    else { _currentSalon = null; }
  });

  void _goBook(Salon s, Coiffeur? c) {
    // La réservation exige un compte : on redirige plutôt que d'échouer en 401.
    if (_auth.status != AuthStatus.loggedIn) {
      setState(() => _screen = _Screen.auth);
      return;
    }
    context.read<BookingController>().start(salonId: s.id, staffId: c?.id);
    setState(() {
      _currentSalon = s;
      _currentCoiffeur = c;
      _inBooking = true;
      _confirmedBooking = null;
    });
  }

  void _onAuthSuccess() {
    setState(() {
      _screen = _Screen.main;
      _navIndex = 0;
    });
    _refreshForSession();
  }

  /// Recharge ce qui dépend du compte connecté.
  void _refreshForSession() {
    final auth = _auth;
    context.read<NotificationsController>().load();
    if (auth.role != AppRole.client) {
      context.read<CashController>().attach(auth.salonId);
      if (auth.role == AppRole.owner) {
        context.read<CashController>().load();
      } else {
        context.read<MyCashController>().load();
      }
    }
  }

  void _goStyleDna() => setState(() => _screen = _Screen.styleDna);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: _buildScreen(),
    );
  }

  Widget _buildScreen() {
    switch (_screen) {
      case _Screen.splash:
        return SplashScreen(
          key: const ValueKey('splash'),
          onContinue: () {
            // Session déjà valide : on saute l'onboarding et la landing.
            final auth = _auth;
            if (auth.status == AuthStatus.loggedIn) {
              _onAuthSuccess();
            } else {
              setState(() => _screen = _Screen.onboarding);
            }
          },
        );
      case _Screen.onboarding:
        return OnboardingScreen(
          key: const ValueKey('onboarding'),
          onFinish: () => setState(() => _screen = _Screen.landing),
        );
      case _Screen.landing:
        return LandingScreen(
          key: const ValueKey('landing'),
          onSignIn: () => setState(() => _screen = _Screen.auth),
          onSignUp: () => setState(() => _screen = _Screen.auth),
          onGuest: () {
            _auth.continueAsGuest();
            setState(() { _screen = _Screen.main; _navIndex = 0; });
          },
        );
      case _Screen.auth:
        return AuthScreen(
          key: const ValueKey('auth'),
          onSuccess: _onAuthSuccess,
          onBack: () => setState(() => _screen = _Screen.landing),
        );
      case _Screen.styleDna:
        return StyleDnaScreen(
          key: const ValueKey('styleDna'),
          onBack: () => setState(() => _screen = _Screen.main),
          onGoStaff: (staffId) {
            // On quitte l'écran d'analyse avant d'ouvrir le coiffeur, sinon le
            // retour ramènerait sur un résultat périmé.
            setState(() => _screen = _Screen.main);
            _goStaffById(staffId);
          },
        );
      case _Screen.main:
        break;
    }

    // ── Post-auth: detail screens overlay ─────────────────────────
    if (_inBooking && _currentSalon != null) {
      if (_confirmedBooking != null) return _buildConfirmationPage();
      return BookingScreen(
        key: const ValueKey('booking'),
        salon: _currentSalon!,
        coiffeur: _currentCoiffeur,
        onBack: () => setState(() => _inBooking = false),
        onConfirm: (booking) => setState(() => _confirmedBooking = booking),
      );
    }
    if (_currentCoiffeur != null) {
      return CoiffeurProfileScreen(
        key: ValueKey('coiffeur_${_currentCoiffeur!.id}'),
        coiffeur: _currentCoiffeur!,
        onBack: _goBack,
        onBook: _currentSalon == null
            ? null
            : () => _goBook(_currentSalon!, _currentCoiffeur),
      );
    }
    if (_currentSalon != null) {
      return SalonDetailScreen(
        key: ValueKey('salon_${_currentSalon!.id}'),
        salon: _currentSalon!,
        onBack: _goBack,
        onBook: _goBook,
        onGoCoiffeur: _goCoiffeur,
      );
    }

    // ── Main shell ─────────────────────────────────────────────────
    final unread = context.watch<NotificationsController>().unread;
    final role = context.watch<AuthController>().role;

    return Scaffold(
      key: const ValueKey('main'),
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          _buildMainContent(role),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: LamssaBottomNav(
              currentIndex: _navIndex,
              role: role,
              badgeCount: unread,
              isGuest: context.watch<AuthController>().status != AuthStatus.loggedIn,
              onTap: (i) {
                setState(() => _navIndex = i);
                if (i == _notificationsIndex) {
                  context.read<NotificationsController>().load();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(AppRole role) {
    switch (role) {
      case AppRole.client:   return _clientScreen();
      case AppRole.owner:    return _ownerScreen();
      case AppRole.coiffeur: return _coiffeurScreen();
    }
  }

  Widget _clientScreen() {
    switch (_navIndex) {
      case 0: return HomeScreen(
        onGoSalon: _goSalon, onGoCoiffeur: _goCoiffeur,
        onNav: (i) => setState(() => _navIndex = i),
        onStyleDna: _goStyleDna,
      );
      case 1: return ExploreScreen(onGoSalon: _goSalon);
      case 2: return TrendingScreen(onGoStaff: _goStaffById);
      case 3: return const NotificationsScreen();
      case 4: return ProfileScreen(onSignedOut: _onSignedOut);
      default: return const SizedBox();
    }
  }

  /// Depuis le fil « En vogue » on n'a que l'identifiant du coiffeur : on charge
  /// son profil avant d'ouvrir l'écran, sinon la réservation partirait sans
  /// savoir de quel salon il s'agit.
  Future<void> _goStaffById(String staffId) async {
    try {
      final profile = await context.read<SalonRepository>().staffProfile(staffId);
      if (!mounted) return;
      setState(() => _currentCoiffeur = profile.coiffeur);
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppSnack(context, e.message);
    }
  }

  Widget _ownerScreen() {
    switch (_navIndex) {
      case 0: return OwnerDashboardScreen(onNav: (i) => setState(() => _navIndex = i));
      case 1: return const CaisseScreen();
      case 2: return const NotificationsScreen();
      case 3: return ProfileScreen(onSignedOut: _onSignedOut);
      default: return const SizedBox();
    }
  }

  Widget _coiffeurScreen() {
    switch (_navIndex) {
      case 0: return const CoiffeurDashboardScreen();
      case 1: return const CoiffeurDashboardScreen(showAgendaOnly: true);
      case 2: return const NotificationsScreen();
      case 3: return ProfileScreen(onSignedOut: _onSignedOut);
      default: return const SizedBox();
    }
  }

  void _onSignedOut() {
    context.read<NotificationsController>().reset();
    // Sans ça, les cœurs « aimé » du compte précédent resteraient allumés
    // pour le suivant, et le mur du coiffeur resterait visible après logout.
    context.read<PortfolioController>().reset();
    context.read<MyPortfolioController>().reset();
    setState(() {
      _screen = _Screen.landing;
      _navIndex = 0;
      _currentSalon = null;
      _currentCoiffeur = null;
      _inBooking = false;
    });
  }

  Widget _buildConfirmationPage() {
    final booking = _confirmedBooking!;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text('✅', style: TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: 24),
              Text('تم الحجز!', style: AppTextStyle.playfair(size: 32)),
              const SizedBox(height: 12),
              Text(
                'حجزك تأكد عند ${_currentSalon?.name ?? 'الصالون'}\n'
                '${booking.date} · ${booking.time} · ${booking.price.toStringAsFixed(0)} DT',
                style: AppTextStyle.dmSans(color: AppColors.sub),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.gold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () {
                    context.read<NotificationsController>().load();
                    setState(() {
                      _inBooking = false;
                      _confirmedBooking = null;
                      _currentSalon = null;
                      _currentCoiffeur = null;
                      _navIndex = 0;
                    });
                  },
                  child: Text('الرئيسية',
                      style: AppTextStyle.dmSans(
                          color: Colors.black, weight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
