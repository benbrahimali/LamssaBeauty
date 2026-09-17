import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/api_client.dart';
import 'package:lamssa/core/token_store.dart';
import 'package:lamssa/data/repositories/salon_repository.dart';
import 'package:lamssa/widgets/my_reviews.dart';
import 'package:provider/provider.dart';

/// Le coiffeur voit sa note et les avis de ses clients (§3.8).
class _FauxDepot extends SalonRepository {
  _FauxDepot(this._avis) : super(ApiClient(TokenStore()));

  final MyReviews _avis;

  @override
  Future<MyReviews> myReviews() async => _avis;
}

void main() {
  Widget cadre(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  test('la réponse du serveur donne la note et les avis', () {
    final r = MyReviews.fromJson(const {
      'rating_avg': 4.5,
      'rating_count': 2,
      'reviews': [
        {'id': 'r1', 'rating': 5, 'comment': 'Parfait'},
        {'id': 'r2', 'rating': 4, 'comment': ''},
      ],
    });
    expect(r.ratingAvg, 4.5);
    expect(r.hasReviews, isTrue);
    expect(r.reviews.map((a) => a.rating), [5, 4]);
  });

  group('Carte « تقييمي »', () {
    testWidgets('montre la note et le nombre d’avis', (tester) async {
      await tester.pumpWidget(cadre(const MyRatingCard(
        reviews: MyReviews(ratingAvg: 4.5, ratingCount: 12),
      )));

      expect(find.text('4.5'), findsOneWidget);
      expect(find.text('12 رأي'), findsOneWidget);
    });

    testWidgets('sans avis, explique comment en recevoir', (tester) async {
      await tester.pumpWidget(cadre(const MyRatingCard(reviews: MyReviews())));

      expect(find.textContaining('مازال ما عندك حتى تقييم'), findsOneWidget);
    });

    testWidgets('non chargée, la carte ne s’affiche pas', (tester) async {
      await tester.pumpWidget(cadre(const MyRatingCard(reviews: null)));

      expect(find.text('⭐ تقييمي'), findsNothing);
    });
  });

  group('Feuille « آراء الحرفاء »', () {
    Future<void> monter(WidgetTester tester, MyReviews avis) async {
      tester.view.physicalSize = const Size(720, 1612);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(Provider<SalonRepository>.value(
        value: _FauxDepot(avis),
        child: const MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: MyReviewsSheet()),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('liste les avis, commentaires compris', (tester) async {
      await monter(
        tester,
        const MyReviews(ratingAvg: 3.5, ratingCount: 2, reviews: [
          ReviewEntry(id: 'r1', rating: 5, comment: 'Très bon dégradé'),
          ReviewEntry(id: 'r2', rating: 2, comment: 'Trop d’attente'),
        ]),
      );

      expect(find.text('Très bon dégradé'), findsOneWidget);
      expect(find.text('Trop d’attente'), findsOneWidget,
          reason: 'un avis négatif dit au coiffeur quoi améliorer');
      expect(find.text('الآراء ما فيهاش أسامي الحرفاء'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans avis, le dit simplement', (tester) async {
      await monter(tester, const MyReviews());

      expect(find.text('مازال ما عندك حتى رأي'), findsOneWidget);
    });
  });
}
