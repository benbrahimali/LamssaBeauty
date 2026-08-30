import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/booking_repository.dart';
import 'package:lamssa/data/repositories/cash_repository.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/state/cash_controller.dart';
import 'package:lamssa/widgets/treasury_sheet.dart';
import 'package:provider/provider.dart';

/// Mise en page réelle de la feuille « الصندوق » sur un écran d'appareil.
///
/// Elle a crashé en production avec « A RenderFlex overflowed by 99781 pixels
/// on the bottom », suivi d'un arbre corrompu — GlobalKeys dupliquées, écran
/// rouge. Un test qui n'assemble que des morceaux de widgets ne l'aurait pas
/// vu : il faut la vraie feuille, à la vraie taille d'écran, clavier ouvert
/// compris, puisque c'est là que la hauteur disponible s'effondre.
class _FauxCashController extends CashController {
  _FauxCashController(this._tresor)
      : super(
          CashRepository(ApiClient(TokenStore())),
          BookingRepository(ApiClient(TokenStore())),
          SalonRepository(ApiClient(TokenStore())),
        );

  final Treasury _tresor;

  @override
  Future<Treasury?> treasury() async => _tresor;
}

void main() {
  /// Une journée chargée : toutes les lignes présentes, un écart constaté et
  /// assez de mouvements pour que la feuille dépasse un petit écran.
  Treasury journeeChargee({bool closed = false}) => Treasury(
        day: '2026-08-30',
        openingFloat: 200,
        cashIn: 845.5,
        deposits: 50,
        cashExpenses: 120,
        cashAdvances: 80,
        withdrawals: 300,
        expectedCash: 595.5,
        cardTotal: 320,
        onlineTotal: 90,
        bankExpenses: 900,
        bankTotal: -490,
        closed: closed,
        countedCash: closed ? 590.5 : null,
        cashVariance: closed ? -5 : 0,
        varianceReason: closed ? 'rendu de monnaie au dernier client' : '',
        closingFloat: closed ? 490.5 : 0,
        movements: List.generate(
          8,
          (i) => CashMovement(
            id: '$i',
            type: i.isEven ? 'withdrawal' : 'deposit',
            amount: 25.0 * (i + 1),
            label: 'Mouvement numéro $i avec un libellé plutôt long',
          ),
        ),
      );

  /// Monte la feuille comme le fait `showModalBottomSheet` : alignée en bas,
  /// sur toute la largeur, avec l'espace que lui laisse le clavier.
  Future<void> monter(
    WidgetTester tester,
    Treasury tresor, {
    double clavier = 0,
    double police = 1.0,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<CashController>.value(
        value: _FauxCashController(tresor),
        child: MaterialApp(
          // La taille vient de la vue configurée par le test : la figer ici
          // ferait mesurer la feuille contre un écran qui n'existe pas.
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewInsets: EdgeInsets.only(bottom: clavier),
                textScaler: TextScaler.linear(police),
              ),
              child: const Scaffold(
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: TreasurySheet(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void ecranDe(WidgetTester tester, double hauteur) {
    tester.view.physicalSize = Size(720, hauteur);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  testWidgets('la feuille tient dans l’écran', (tester) async {
    ecranDe(tester, 1612);
    await monter(tester, journeeChargee());

    expect(tester.takeException(), isNull,
        reason: 'aucun débordement ne doit survenir à l’ouverture');
    expect(find.byType(TreasurySheet), findsOneWidget);
  });

  testWidgets('le clavier ouvert ne fait pas déborder la feuille',
      (tester) async {
    ecranDe(tester, 1612);
    // 340 px de clavier : ce que prend un IME Android sur un écran de 806 px.
    await monter(tester, journeeChargee(), clavier: 340);

    expect(tester.takeException(), isNull,
        reason: 'la feuille doit défiler quand la hauteur s’effondre');
  });

  testWidgets('sur un petit écran la feuille défile au lieu de déborder',
      (tester) async {
    ecranDe(tester, 1000);
    await monter(tester, journeeChargee());

    expect(tester.takeException(), isNull);
  });

  testWidgets('une journée clôturée s’affiche sans déborder non plus',
      (tester) async {
    ecranDe(tester, 1000);
    await monter(tester, journeeChargee(closed: true), clavier: 340);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('ناقص'), findsOneWidget,
        reason: 'l’écart constaté doit rester visible après clôture');
  });

  testWidgets('une police système agrandie ne fait pas déborder les lignes',
      (tester) async {
    ecranDe(tester, 1612);
    // 1.3 : le réglage d'accessibilité le plus courant chez les gérants qui
    // consultent leur caisse sans lunettes. C'est ce qui avait fait déborder
    // les cartes de l'accueil.
    await monter(tester, journeeChargee(closed: true), police: 1.3);

    expect(tester.takeException(), isNull);
  });

  testWidgets('une journée vide reste lisible', (tester) async {
    ecranDe(tester, 1612);
    await monter(tester, const Treasury(day: '2026-08-30'));

    expect(tester.takeException(), isNull);
    // Rien encaissé : le tiroir est à zéro, pas en erreur.
    expect(find.textContaining('0.00 DT'), findsWidgets);
  });
}
