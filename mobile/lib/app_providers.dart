import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/push_service.dart';
import 'core/token_store.dart';
import 'data/repositories/auth_repository.dart';
import 'data/repositories/booking_repository.dart';
import 'data/repositories/cash_repository.dart';
import 'data/repositories/notification_repository.dart';
import 'data/repositories/portfolio_repository.dart';
import 'data/repositories/reel_repository.dart';
import 'data/repositories/salon_admin_repository.dart';
import 'data/repositories/salon_repository.dart';
import 'data/repositories/style_dna_repository.dart';
import 'state/auth_controller.dart';
import 'state/booking_controller.dart';
import 'state/cash_controller.dart';
import 'state/notifications_controller.dart';
import 'state/portfolio_controller.dart';
import 'state/reels_controller.dart';
import 'state/salons_controller.dart';

/// Assemble le graphe de dépendances : un seul [ApiClient] partagé par tous les
/// repositories, eux-mêmes partagés par les contrôleurs.
class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = TokenStore();
    final api = ApiClient(tokens);

    final authRepo = AuthRepository(api);
    final salonRepo = SalonRepository(api);
    final bookingRepo = BookingRepository(api);
    final cashRepo = CashRepository(api);
    final notificationRepo = NotificationRepository(api);
    final portfolioRepo = PortfolioRepository(api);
    final reelRepo = ReelRepository(api);
    final push = PushService(authRepo);

    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<PushService>.value(value: push),
        Provider<SalonRepository>.value(value: salonRepo),
        Provider<BookingRepository>.value(value: bookingRepo),
        Provider<CashRepository>.value(value: cashRepo),
        Provider<StyleDnaRepository>(create: (_) => StyleDnaRepository(api)),
        Provider<PortfolioRepository>.value(value: portfolioRepo),
        Provider<ReelRepository>.value(value: reelRepo),
        Provider<SalonAdminRepository>(
          create: (_) => SalonAdminRepository(api),
        ),
        ChangeNotifierProvider(
          create: (_) => AuthController(api, authRepo, push)..bootstrap(),
        ),
        ChangeNotifierProvider(create: (_) => SalonsController(salonRepo)),
        ChangeNotifierProvider(
          create: (_) => BookingController(salonRepo, bookingRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => CashController(cashRepo, bookingRepo, salonRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => MyCashController(cashRepo, bookingRepo, salonRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => NotificationsController(notificationRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => PortfolioController(portfolioRepo),
        ),
        ChangeNotifierProvider(
          create: (_) => MyPortfolioController(portfolioRepo),
        ),
        ChangeNotifierProvider(create: (_) => ReelsController(reelRepo)),
      ],
      child: child,
    );
  }
}
