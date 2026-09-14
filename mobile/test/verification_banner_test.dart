import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/data/repositories/auth_repository.dart';
import 'package:lamssa/widgets/verification_banner.dart';

/// Salon créé tout de suite, visible des clients après vérification (§2.5).
///
/// Le gérant doit savoir que son salon attend : sans le bandeau, l'absence de
/// réservations ressemblerait à une panne.
void main() {
  Future<void> monter(WidgetTester tester, String status,
      {String reason = '', double largeur = 400}) async {
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: largeur,
              child: VerificationBanner(status: status, reason: reason),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  group('Bandeau de vérification', () {
    testWidgets('un salon en attente l’annonce au gérant', (tester) async {
      await monter(tester, 'pending');

      expect(find.text('صالونك في انتظار التثبّت'), findsOneWidget);
      expect(find.textContaining('حضّر الخدمات'), findsOneWidget,
          reason: 'il doit savoir qu’il peut tout préparer en attendant');
    });

    testWidgets('un refus montre la raison saisie dans la console',
        (tester) async {
      await monter(tester, 'rejected', reason: 'Adresse introuvable');

      expect(find.text('صالونك ما تقبلش'), findsOneWidget);
      expect(find.text('Adresse introuvable'), findsOneWidget);
    });

    testWidgets('un refus sans raison invite à nous contacter', (tester) async {
      await monter(tester, 'rejected');

      expect(find.textContaining('كلّمنا'), findsOneWidget);
    });

    testWidgets('un salon vérifié n’affiche rien', (tester) async {
      await monter(tester, 'verified');

      expect(find.text('صالونك في انتظار التثبّت'), findsNothing);
      expect(find.text('صالونك ما تقبلش'), findsNothing);
    });

    testWidgets('tient sur un écran étroit avec une longue raison',
        (tester) async {
      await monter(tester, 'rejected',
          reason: 'Les photos ne correspondent pas au salon indiqué. ' * 4,
          largeur: 320);

      expect(tester.takeException(), isNull);
    });
  });

  group('Contexte du gérant', () {
    const user = AppUser(
      id: 'u1',
      phone: '+21690000000',
      name: 'Ilyes',
      role: AppRole.owner,
    );

    test('un salon en attente est signalé caché', () {
      const ctx = AccountContext(
        user: user,
        ownedSalonId: 's1',
        ownedSalonVerification: 'pending',
      );
      expect(ctx.ownedSalonHidden, isTrue);
    });

    test('un salon vérifié ne l’est pas', () {
      const ctx = AccountContext(
        user: user,
        ownedSalonId: 's1',
        ownedSalonVerification: 'verified',
      );
      expect(ctx.ownedSalonHidden, isFalse);
    });

    test('sans salon, rien n’est caché', () {
      // Le défaut « verified » ne doit pas faire croire à un salon inexistant.
      const ctx = AccountContext(user: user, ownedSalonVerification: 'pending');
      expect(ctx.ownedSalonHidden, isFalse);
    });

    test('un contexte ancien, sans l’information, reste visible', () {
      const ctx = AccountContext(user: user, ownedSalonId: 's1');
      expect(ctx.ownedSalonHidden, isFalse);
    });
  });
}
