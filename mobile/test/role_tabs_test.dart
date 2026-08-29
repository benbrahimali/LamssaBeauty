import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/bottom_nav.dart';

/// Onglets par rôle (§2.5).
///
/// Le client en a cinq, les professionnels quatre. Avec de simples index,
/// basculer de client (profil = index 4) vers gérant affichait un écran vide :
/// l'index 4 n'existe pas dans une barre de quatre onglets. Ces tests
/// garantissent qu'un onglet se retrouve par son identité, jamais par sa
/// position.
void main() {
  group('Composition des barres', () {
    test('chaque rôle a des onglets, sans doublon', () {
      for (final role in AppRole.values) {
        final tabs = tabsFor(role);
        expect(tabs, isNotEmpty, reason: '$role');
        expect(tabs.toSet().length, tabs.length, reason: '$role : doublon');
      }
    });

    test('notifications et profil existent dans les trois rôles', () {
      // Ce sont les deux points de repère communs : ils doivent survivre à
      // n'importe quelle bascule.
      for (final role in AppRole.values) {
        expect(tabsFor(role), contains(LamssaTab.notifications), reason: '$role');
        expect(tabsFor(role), contains(LamssaTab.profile), reason: '$role');
      }
    });

    test('le client a un onglet de plus que les rôles pro', () {
      expect(tabsFor(AppRole.client).length,
          greaterThan(tabsFor(AppRole.owner).length));
    });
  });

  group('Bascule de rôle', () {
    test('depuis le profil, on reste sur le profil', () {
      // C'est de cet écran que part le changement de rôle : atterrir ailleurs
      // ferait perdre le fil à l'utilisateur.
      for (final role in AppRole.values) {
        expect(tabAfterRoleChange(LamssaTab.profile, role), LamssaTab.profile);
      }
    });

    test('un onglet absent du nouveau rôle retombe sur son accueil', () {
      // « موضة » n'existe pas côté gérant : c'était le cas qui produisait
      // l'écran vide.
      expect(tabAfterRoleChange(LamssaTab.trending, AppRole.owner),
          tabsFor(AppRole.owner).first);
      expect(tabAfterRoleChange(LamssaTab.explore, AppRole.coiffeur),
          tabsFor(AppRole.coiffeur).first);
      expect(tabAfterRoleChange(LamssaTab.cash, AppRole.client),
          tabsFor(AppRole.client).first);
    });

    test('l’onglet retenu est toujours affichable dans le nouveau rôle', () {
      for (final depuis in LamssaTab.values) {
        for (final role in AppRole.values) {
          expect(tabsFor(role), contains(tabAfterRoleChange(depuis, role)),
              reason: '$depuis → $role');
        }
      }
    });

    test('les notifications survivent à toutes les bascules', () {
      for (final role in AppRole.values) {
        expect(tabAfterRoleChange(LamssaTab.notifications, role),
            LamssaTab.notifications);
      }
    });
  });
}
