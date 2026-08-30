import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/push_service.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/auth_repository.dart';
import 'package:lamssa/screens/profile_screen.dart';
import 'package:lamssa/state/auth_controller.dart';
import 'package:provider/provider.dart';

/// Menu du profil selon la vue active (§2.5).
///
/// « مواعيدي » liste les RDV qu'on a PRIS, jamais ceux qu'on reçoit : c'est la
/// vue client. En vue salon ou coiffeur elle était vide, ce qui laissait
/// croire que les rendez-vous du salon avaient disparu — alors que leur
/// planning vit dans l'agenda.
class _FauxAuth extends AuthController {
  _FauxAuth(this._role, {String? salonId})
      : _ctx = AccountContext(
          user: const AppUser(
            id: 'u1',
            phone: '+21696106351',
            name: 'Abdallah',
            role: AppRole.owner,
          ),
          ownedSalonId: salonId,
          ownedSalonName: 'Berber King',
          staffId: 'staff1',
          staffSalonId: salonId,
        ),
        super(_api, AuthRepository(_api), PushService(AuthRepository(_api)));

  static final _api = ApiClient(TokenStore());

  final AppRole _role;
  final AccountContext _ctx;

  @override
  AuthStatus get status => AuthStatus.loggedIn;

  @override
  AppRole get role => _role;

  @override
  AccountContext? get context => _ctx;
}

void main() {
  Future<void> monter(WidgetTester tester, AppRole vue) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: _FauxAuth(vue, salonId: 'salon1'),
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ProfileScreen(onSignedOut: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('un client voit ses rendez-vous', (tester) async {
    await monter(tester, AppRole.client);

    expect(find.text('مواعيدي'), findsOneWidget);
  });

  testWidgets('un gérant ne voit pas une entrée qui serait vide',
      (tester) async {
    await monter(tester, AppRole.owner);

    expect(find.text('مواعيدي'), findsNothing,
        reason: 'le planning du salon vit dans l’agenda, pas ici');
  });

  testWidgets('un coiffeur non plus', (tester) async {
    await monter(tester, AppRole.coiffeur);

    expect(find.text('مواعيدي'), findsNothing);
  });

  testWidgets('la gestion du salon reste accessible au gérant', (tester) async {
    await monter(tester, AppRole.owner);

    // Retirer « مواعيدي » ne doit pas emporter le reste du menu.
    expect(find.text('إدارة صالوني'), findsOneWidget);
  });
}
