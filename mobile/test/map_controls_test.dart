import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/map_controls.dart';

/// Carte « اكتشف » : fond de carte au choix, cadrage sur les salons, fiche du
/// salon touché.
void main() {
  Widget cadre(Widget child, {double largeur = 400}) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(child: SizedBox(width: largeur, child: child)),
          ),
        ),
      );

  group('Cadrage sur les salons', () {
    test('sans salon, rien à cadrer', () {
      expect(boundsOf(const []), isNull);
    });

    test('le cadre contient tous les salons', () {
      final b = boundsOf(const [
        LatLng(36.80, 10.18),
        LatLng(36.86, 10.10),
        LatLng(36.83, 10.25),
      ])!;
      expect(b.southwest.latitude, 36.80);
      expect(b.northeast.latitude, 36.86);
      expect(b.southwest.longitude, 10.10);
      expect(b.northeast.longitude, 10.25);
    });

    test('un salon seul ne fait pas zoomer au maximum', () {
      const salon = LatLng(36.8065, 10.1815);
      final b = boundsOf(const [salon])!;

      expect(b.contains(salon), isTrue);
      expect(b.northeast.latitude - b.southwest.latitude, closeTo(0.01, 1e-9));
      expect(b.northeast.longitude - b.southwest.longitude, closeTo(0.01, 1e-9));
    });
  });

  group('Style du plan', () {
    test('est un JSON valide — sinon Google ignore tout le style', () {
      expect(() => jsonDecode(kLamssaMapStyle), returnsNormally);
    });

    test('masque les arrêts de bus qui recouvraient les épingles', () {
      final regles = (jsonDecode(kLamssaMapStyle) as List).cast<Map>();
      expect(
        regles.any((r) =>
            r['featureType'] == 'transit' &&
            (r['stylers'] as List).any((s) => s['visibility'] == 'off')),
        isTrue,
      );
    });
  });

  group('Choix du fond de carte', () {
    testWidgets('propose plan, satellite et mixte', (tester) async {
      final semantique = tester.ensureSemantics();
      await tester.pumpWidget(cadre(
          MapTypeSelector(value: MapType.normal, onChanged: (_) {})));

      expect(find.byIcon(Icons.map_rounded), findsOneWidget);
      expect(find.byIcon(Icons.satellite_alt_rounded), findsOneWidget);
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
      // Les fonds inactifs n'affichent que leur icône, mais restent nommés.
      expect(find.bySemanticsLabel('ساتليت'), findsOneWidget);
      expect(find.bySemanticsLabel('مختلطة'), findsOneWidget);
      semantique.dispose();
    });

    testWidgets('le fond actif est nommé à l’écran', (tester) async {
      await tester.pumpWidget(cadre(
          MapTypeSelector(value: MapType.satellite, onChanged: (_) {})));

      expect(find.text('ساتليت'), findsOneWidget);
      expect(find.text('خريطة'), findsNothing);
    });

    testWidgets('toucher le satellite passe en satellite', (tester) async {
      MapType? choisi;
      await tester.pumpWidget(cadre(
          MapTypeSelector(value: MapType.normal, onChanged: (t) => choisi = t)));

      await tester.tap(find.byIcon(Icons.satellite_alt_rounded));
      expect(choisi, MapType.satellite);

      await tester.tap(find.byIcon(Icons.layers_rounded));
      expect(choisi, MapType.hybrid);
    });

    testWidgets('tient sur la largeur d’un petit téléphone', (tester) async {
      await tester.pumpWidget(cadre(
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MapTypeSelector(value: MapType.hybrid, onChanged: (_) {}),
          ),
          largeur: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('Fiche du salon sur la carte', () {
    const salon = Salon(
      id: 's1',
      name: 'Barbier El Menzah — Coupe, barbe et soins du visage',
      type: SalonType.barbershop,
      rating: 4.6,
      reviews: 38,
      distance: '1.2 km',
      price: 'من 15 DT',
    );

    testWidgets('montre le salon et ouvre sa fiche', (tester) async {
      var ouvert = false;
      await tester.pumpWidget(cadre(SalonMapPreview(
        salon: salon,
        onOpen: () => ouvert = true,
        onClose: () {},
      )));

      expect(find.textContaining('Barbier El Menzah'), findsOneWidget);
      expect(find.textContaining('1.2 km'), findsOneWidget);

      await tester.tap(find.text('شوف الصالون'));
      expect(ouvert, isTrue);
    });

    testWidgets('la croix ferme sans ouvrir le salon', (tester) async {
      var ouvert = false, ferme = false;
      await tester.pumpWidget(cadre(SalonMapPreview(
        salon: salon,
        onOpen: () => ouvert = true,
        onClose: () => ferme = true,
      )));

      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(ferme, isTrue);
      expect(ouvert, isFalse);
    });

    testWidgets('un nom long tient sur un écran étroit', (tester) async {
      await tester.pumpWidget(cadre(
          SalonMapPreview(salon: salon, onOpen: () {}, onClose: () {}),
          largeur: 300));

      expect(tester.takeException(), isNull);
    });
  });
}
