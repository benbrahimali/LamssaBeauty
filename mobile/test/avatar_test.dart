import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/state/auth_controller.dart';
import 'package:lamssa/widgets/common_widgets.dart';
import 'package:lamssa/widgets/editable_avatar.dart';

/// Photo de profil des coiffeurs et des gérants : affichée dans les cartes,
/// initiales sinon.
void main() {
  Widget cadre(Widget child) => MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: child)),
        ),
      );

  group('Avatar', () {
    testWidgets('sans photo, les initiales', (tester) async {
      await tester.pumpWidget(cadre(const InitialsAvatar(
          initials: 'RG', color: Colors.amber, size: 56)));

      expect(find.text('RG'), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsNothing);
    });

    testWidgets('une photo vide compte comme pas de photo', (tester) async {
      await tester.pumpWidget(cadre(const InitialsAvatar(
          initials: 'RG', color: Colors.amber, imageUrl: '  ')));

      expect(find.byType(CachedNetworkImage), findsNothing);
      expect(find.text('RG'), findsOneWidget);
    });

    testWidgets('avec photo, l’image du compte', (tester) async {
      await tester.pumpWidget(cadre(const InitialsAvatar(
        initials: 'RG',
        color: Colors.amber,
        imageUrl: 'https://res.cloudinary.com/demo/image/upload/rania.jpg',
      )));

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });
  });

  group('Avatar du profil', () {
    testWidgets('un client n’a pas de pastille appareil photo', (tester) async {
      await tester.pumpWidget(
          cadre(const EditableAvatar(name: 'Amal Ben Salah', editable: false)));

      expect(find.byIcon(Icons.photo_camera_rounded), findsNothing);
      expect(find.text('AB'), findsOneWidget);
    });

    testWidgets('un coiffeur ou un gérant peut la changer', (tester) async {
      await tester.pumpWidget(
          cadre(const EditableAvatar(name: 'Rania Gharbi', editable: true)));

      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
    });
  });

  group('Qui peut avoir une photo', () {
    test('un client, non', () {
      expect(AuthController.canHaveAvatarFor(), isFalse);
    });

    test('un coiffeur employé, oui', () {
      expect(AuthController.canHaveAvatarFor(staffId: 'st1'), isTrue);
    });

    test('un gérant, oui', () {
      expect(AuthController.canHaveAvatarFor(ownedSalonId: 's1'), isTrue);
    });
  });

  group('Lecture des réponses du serveur', () {
    test('le compte porte sa photo', () {
      final user = AppUser.fromJson(const {
        'id': 'u1',
        'name': 'Rania',
        'avatar_url': 'https://res.cloudinary.com/demo/image/upload/rania.jpg',
      });
      expect(user.avatarUrl, 'https://res.cloudinary.com/demo/image/upload/rania.jpg');
    });

    test('sans photo, rien — pas une chaîne vide à charger', () {
      expect(AppUser.fromJson(const {'id': 'u1'}).avatarUrl, isNull);
      expect(AppUser.fromJson(const {'id': 'u1', 'avatar_url': ''}).avatarUrl, isNull);
    });

    test('la photo survit à la mise en cache du profil', () {
      const user = AppUser(id: 'u1', avatarUrl: 'https://res.cloudinary.com/x/a.jpg');
      expect(AppUser.fromJson(user.toJson()).avatarUrl, user.avatarUrl);
    });

    test('un membre d’équipe porte la photo de son compte', () {
      final c = Coiffeur.fromJson(const {
        'id': 'st1',
        'display_name': 'Rania',
        'avatar_url': 'https://res.cloudinary.com/demo/image/upload/rania.jpg',
      });
      expect(c.avatarUrl, isNotNull);
      expect(Coiffeur.fromJson(const {'id': 'st2'}).avatarUrl, isNull);
    });
  });
}
