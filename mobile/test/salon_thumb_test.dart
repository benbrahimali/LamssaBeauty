import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/salon_thumb.dart';

/// Vignette d'un salon (§3.2).
///
/// Trois écrans la dessinaient chacun de leur côté et deux avaient oublié la
/// photo : la recherche et le tunnel de réservation affichaient les initiales
/// même quand le gérant avait mis une vitrine. C'est pourtant la photo qui
/// fait cliquer, et le gérant croyait son envoi perdu.
void main() {
  const sansPhoto = Salon(
    id: '1',
    name: 'Berber King',
    type: SalonType.barbershop,
  );
  const avecPhoto = Salon(
    id: '2',
    name: 'Berber King',
    type: SalonType.barbershop,
    photos: ['https://res.cloudinary.com/demo/image/upload/v1/salon.jpg'],
  );

  Future<void> monter(WidgetTester tester, Salon salon, {double size = 64}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: SalonThumb(salon: salon, size: size))),
      ));

  testWidgets('la photo du salon est affichée quand elle existe',
      (tester) async {
    await monter(tester, avecPhoto);

    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text(sansPhoto.initials), findsNothing,
        reason: 'la photo remplace le monogramme, elle ne s’y ajoute pas');
  });

  testWidgets('sans photo, le monogramme prend le relais', (tester) async {
    await monter(tester, sansPhoto);

    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.text(sansPhoto.initials), findsOneWidget);
  });

  testWidgets('la vignette respecte la taille demandée', (tester) async {
    await monter(tester, avecPhoto, size: 52);

    final taille = tester.getSize(find.byType(SalonThumb));
    expect(taille.width, 52);
    expect(taille.height, 52);
  });

  testWidgets('le monogramme s’adapte à la taille', (tester) async {
    // Une taille de police figée rend la vignette illisible en petit format.
    for (final size in [40.0, 64.0]) {
      await monter(tester, sansPhoto, size: size);
      final texte = tester.widget<Text>(find.text(sansPhoto.initials));
      expect(texte.style!.fontSize, size * 0.34);
    }
  });

  testWidgets('la photo est recadrée, jamais déformée', (tester) async {
    await monter(tester, avecPhoto);

    final image = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage));
    // Un salon large affiché en carré serait étiré : BoxFit.cover recadre.
    expect(image.fit, BoxFit.cover);
  });
}
