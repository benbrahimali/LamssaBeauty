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
  _FauxAuth(
    this._role, {
    String? salonId,
    String? staffId = 'staff1',
    bool canCreate = false,
  })  : _ctx = AccountContext(
          user: const AppUser(
            id: 'u1',
            phone: '+21696106351',
            name: 'Abdallah',
            role: AppRole.owner,
          ),
          ownedSalonId: salonId,
          ownedSalonName: 'Berber King',
          staffId: staffId,
          staffSalonId: salonId,
          canCreateSalon: canCreate,
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

  // `canCreateSalon` lit le champ privé du vrai contrôleur, pas le getter
  // `context` : sans cette surcharge, le double répondrait toujours « non
  // autorisé » et le cas positif ne pourrait jamais être testé.
  @override
  bool get canCreateSalon => _ctx.canCreateSalon;
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

  /// Monte le profil d'un compte précis, pour la création de salon.
  Future<void> monterCompte(
    WidgetTester tester, {
    required AppRole vue,
    String? salonId,
    String? staffId,
    bool canCreate = false,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthController>.value(
        value: _FauxAuth(vue,
            salonId: salonId, staffId: staffId, canCreate: canCreate),
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

  group('Création de salon dans le profil', () {
    testWidgets('un client ordinaire ne la voit pas', (tester) async {
      await monterCompte(tester, vue: AppRole.client);

      // Le serveur refuserait : l'entrée menait à un 403 après tout saisi.
      expect(find.text('أنشئ صالون'), findsNothing);
    });

    testWidgets('un coiffeur employé ne la voit pas', (tester) async {
      await monterCompte(tester,
          vue: AppRole.coiffeur, staffId: 'staff1', salonId: null);

      // Il travaille dans un salon : ça ne lui donne pas le droit d'en ouvrir un.
      expect(find.text('أنشئ صالون'), findsNothing);
    });

    testWidgets('un compte professionnel autorisé la voit', (tester) async {
      await monterCompte(tester, vue: AppRole.client, canCreate: true);

      expect(find.text('أنشئ صالون'), findsOneWidget,
          reason: 'c’est le seul chemin d’un futur gérant vers son salon');
    });

    testWidgets('un gérant installé ne la voit pas', (tester) async {
      await monterCompte(tester,
          vue: AppRole.owner, salonId: 'salon1', canCreate: true);

      // Il a déjà son salon : il le gère depuis « إدارة صالوني ».
      expect(find.text('أنشئ صالون'), findsNothing);
      expect(find.text('إدارة صالوني'), findsOneWidget);
    });
  });

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
