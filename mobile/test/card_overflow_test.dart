import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/screens/home_screen.dart';

/// Hauteur des cartes des listes horizontales de l'accueil.
///
/// Elle était figée à 210 px alors qu'une carte avec un prix en réclame ~225 :
/// « A RenderFlex overflowed by 15 pixels » à chaque défilement, visible
/// seulement sur l'appareil. Ces tests mesurent la carte réelle et vérifient
/// que la place réservée suffit — y compris quand l'utilisateur agrandit la
/// police du système, ce qui cassait tout.
void main() {
  const salon = Salon(
    id: '1',
    name: 'Barbier El Menzah',
    type: SalonType.barbershop,
    rating: 4.8,
    // Les trois lignes optionnelles réunies : le pire cas, et celui qui
    // débordait en production.
    distance: '3.9 km',
    price: 'من 15 DT',
    open: true,
  );

  const coiffeur = Coiffeur(
    id: '1',
    name: 'Ahmed Trabelsi',
    role: 'حجّام',
    rating: 4.9,
    cuts: 320,
    available: true,
  );

  /// Hauteur réellement nécessaire à la carte pour sa largeur.
  ///
  /// On demande la hauteur *intrinsèque* et non la taille rendue : une `Column`
  /// prend par défaut toute la hauteur qu'on lui offre, donc une mesure directe
  /// renverrait la taille de l'écran, pas celle du contenu.
  Future<double> measure(
    WidgetTester tester,
    Widget card,
    double width, {
    double textScale = 1.0,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Align(
            alignment: Alignment.topCenter,
            child: KeyedSubtree(key: key, child: card),
          ),
        ),
      ),
    );
    final box = tester.renderObject<RenderBox>(find.byKey(key));
    return box.getMaxIntrinsicHeight(width);
  }

  /// Ce que la liste réserve pour cette échelle de police.
  Future<double> reserved(
    WidgetTester tester,
    double Function(BuildContext) heightIn, {
    double textScale = 1.0,
  }) async {
    late double value;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Builder(builder: (context) {
          value = heightIn(context);
          return const SizedBox();
        }),
      ),
    );
    return value;
  }

  group('Carte salon', () {
    testWidgets('la place réservée couvre une carte complète', (tester) async {
      final needed = await measure(tester, const SalonCard(salon: salon), 240);
      final given = await reserved(tester, SalonCard.heightIn);

      expect(given, greaterThanOrEqualTo(needed),
          reason: 'il manquait 15 px, d’où le RenderFlex overflowed');
    });

    testWidgets('… et tient encore avec une police agrandie', (tester) async {
      for (final scale in [1.15, 1.3, 1.5]) {
        final needed = await measure(tester, const SalonCard(salon: salon), 240,
            textScale: scale);
        final given =
            await reserved(tester, SalonCard.heightIn, textScale: scale);

        expect(given, greaterThanOrEqualTo(needed),
            reason: 'police ×$scale — réglage d’accessibilité courant');
      }
    });

    testWidgets('la vitrine occupe toute la largeur de la carte',
        (tester) async {
      // Le bloc visuel n'imposait aucune largeur : dans un Column non étiré il
      // se réduisait à la largeur du monogramme — 96 px au milieu d'une carte
      // de 240, soit une bande étroite au lieu d'une vitrine.
      await tester.pumpWidget(const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SalonCard(salon: salon),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final vitrine = tester.getSize(find.byWidgetPredicate(
          (w) => w is SizedBox && w.height == SalonCard.imageHeight));
      expect(tester.getSize(find.byType(SalonCard)).width, SalonCard.cardWidth);
      // Moins les 1 px de bordure de chaque côté : la vitrine occupe tout
      // l'intérieur de la carte.
      expect(vitrine.width, SalonCard.cardWidth - 2,
          reason: 'la photo doit couvrir la carte, pas une bande centrale');
      expect(vitrine.height, SalonCard.imageHeight);
    });

    testWidgets('un salon sans avis est annoncé neuf, pas mal noté',
        (tester) async {
      const neuf = Salon(
        id: '2',
        name: 'Xbfbb',
        type: SalonType.barbershop,
        rating: 0,
        reviews: 0,
        distance: '0.2 km',
      );
      await tester.pumpWidget(const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
                alignment: Alignment.topCenter, child: SalonCard(salon: neuf)),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // « 0.0 ★ » se lit comme une mauvaise note alors que le salon vient
      // d'ouvrir : personne ne cliquerait.
      expect(find.text('جديد'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
    });

    testWidgets('la réserve ne devient pas absurde pour autant', (tester) async {
      final given = await reserved(tester, SalonCard.heightIn);
      // Une réserve trop généreuse laisserait une bande vide en bas de chaque
      // carte, aussi visible qu'un débordement. La marge couvre l'écart entre
      // les polices de test et celles de l'appareil, pas davantage.
      final needed = await measure(tester, const SalonCard(salon: salon), 240);
      expect(given - needed, lessThan(25));
    });
  });

  group('Carte coiffeur', () {
    testWidgets('la place réservée couvre la carte', (tester) async {
      final needed = await measure(tester, const CoiffeurCard(coiffeur: coiffeur), 120);
      final given = await reserved(tester, CoiffeurCard.heightIn);

      expect(given, greaterThanOrEqualTo(needed));
    });

    testWidgets('… et tient avec une police agrandie', (tester) async {
      for (final scale in [1.15, 1.3, 1.5]) {
        final needed = await measure(tester, const CoiffeurCard(coiffeur: coiffeur), 120,
            textScale: scale);
        final given =
            await reserved(tester, CoiffeurCard.heightIn, textScale: scale);

        expect(given, greaterThanOrEqualTo(needed), reason: 'police ×$scale');
      }
    });
  });
}
