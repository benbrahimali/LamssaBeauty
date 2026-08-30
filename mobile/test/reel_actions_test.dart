import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/screens/reels_screen.dart';
import 'package:provider/provider.dart';
import 'package:lamssa/state/reels_controller.dart';
import 'package:lamssa/data/repositories/reel_repository.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/push_service.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/auth_repository.dart';
import 'package:lamssa/state/auth_controller.dart';

/// Bouton « احجز » du lecteur de reels (§3.8).
///
/// Le lecteur est une route posée AU-DESSUS de la coquille de l'app. Les
/// callbacks de navigation changeaient bien l'écran de la coquille, mais elle
/// restait cachée sous le lecteur : le bouton semblait mort alors qu'il
/// agissait. Il faut refermer le lecteur avant de naviguer.
class _FauxReelsController extends ReelsController {
  _FauxReelsController(this._reels)
      : super(ReelRepository(ApiClient(TokenStore())));

  final List<Reel> _reels;

  @override
  List<Reel> get reels => _reels;

  @override
  bool get loading => false;

  @override
  String? get error => null;

  @override
  Future<void> load({bool force = false, String? salonId, String? staffId}) async {}

  @override
  void markViewed(Reel reel) {}
}

void main() {
  Reel reel({String? staffId}) => Reel(
        id: 'r1',
        salonId: 'salon1',
        staffId: staffId,
        videoUrl: '',
        salonName: 'Berber King',
        staffName: 'Amin',
        caption: 'hi',
      );

  /// Monte la coquille, puis pousse le lecteur par-dessus — comme le font le
  /// profil et « En vogue ».
  Future<void> monter(
    WidgetTester tester,
    Reel r, {
    void Function(String)? onGoStaff,
    void Function(String)? onGoSalon,
  }) async {
    // Le lecteur lit AuthController avant de laisser aimer : sans lui, aucun
    // reel ne se construit.
    final api = ApiClient(TokenStore());
    final auth = AuthController(api, AuthRepository(api),
        PushService(AuthRepository(api)));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ReelsController>.value(
              value: _FauxReelsController([r])),
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReelsScreen(
                        onGoStaff: onGoStaff,
                        onGoSalon: onGoSalon,
                      ),
                    ),
                  ),
                  child: const Text('coquille'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('coquille'));
    await tester.pumpAndSettle();
  }

  testWidgets('le bouton referme le lecteur avant de naviguer', (tester) async {
    String? vise;
    await monter(tester, reel(staffId: 'staff1'),
        onGoStaff: (id) => vise = id);

    await tester.tap(find.text('احجز'));
    await tester.pumpAndSettle();

    expect(vise, 'staff1', reason: 'la navigation doit partir');
    // Sans le retrait de la route, la coquille changeait sous un lecteur
    // toujours affiché : rien de visible, un bouton qui paraît mort.
    expect(find.text('coquille'), findsOneWidget,
        reason: 'le lecteur doit avoir été refermé');
  });

  testWidgets('un reel de salon passe par le chemin salon', (tester) async {
    String? vise;
    await monter(tester, reel(), onGoSalon: (id) => vise = id);

    await tester.tap(find.text('احجز'));
    await tester.pumpAndSettle();

    // Un reel publié par le salon lui-même n'a pas de coiffeur.
    expect(vise, 'salon1');
    expect(find.text('coquille'), findsOneWidget);
  });

  testWidgets('le coiffeur prime sur le salon quand les deux existent',
      (tester) async {
    String? staff, salon;
    await monter(tester, reel(staffId: 'staff1'),
        onGoStaff: (id) => staff = id, onGoSalon: (id) => salon = id);

    await tester.tap(find.text('احجز'));
    await tester.pumpAndSettle();

    // On réserve chez la personne dont on vient de voir le travail.
    expect(staff, 'staff1');
    expect(salon, isNull);
  });

  testWidgets('sans aucun chemin, le lecteur le dit et reste ouvert',
      (tester) async {
    await monter(tester, reel(staffId: 'staff1'));

    await tester.tap(find.text('احجز'));
    await tester.pump();

    // Refermer sans naviguer serait pire que tout : l'utilisateur perdrait sa
    // place dans le fil sans rien obtenir.
    expect(find.text('coquille'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('la cible de tap atteint la taille du doigt', (tester) async {
    await monter(tester, reel(staffId: 'staff1'), onGoStaff: (_) {});

    // La colonne se réduisait à la largeur de son texte — une trentaine de
    // pixels, sous le minimum tactile : le doigt tombait à côté.
    final taille = tester.getSize(find.ancestor(
      of: find.text('احجز'),
      matching: find.byType(Container),
    ).first);
    expect(taille.width, greaterThanOrEqualTo(48));
    expect(taille.height, greaterThanOrEqualTo(48));
  });
}
