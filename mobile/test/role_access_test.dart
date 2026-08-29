import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/state/auth_controller.dart';

/// Espaces accessibles côté app (§2.5, §3.5).
///
/// Le backend n'accorde un accès qu'à partir des faits : posséder un salon,
/// être rattaché à une équipe. L'app doit dériver exactement la même chose —
/// afficher un espace de plus produirait des 403, un de moins cacherait une
/// fonctionnalité payée.
void main() {
  group('Espaces accordés', () {
    test('un client n’a que son espace client', () {
      expect(AuthController.rolesFor(), [AppRole.client]);
    });

    test('posséder un salon ouvre l’espace gérant', () {
      expect(AuthController.rolesFor(ownedSalonId: 'salon-1'),
          containsAll([AppRole.client, AppRole.owner]));
    });

    test('être rattaché à une équipe ouvre l’espace coiffeur', () {
      expect(AuthController.rolesFor(staffId: 'staff-1'),
          containsAll([AppRole.client, AppRole.coiffeur]));
    });

    test('un coiffeur qui ouvre son salon cumule les trois', () {
      // Cas vérifié côté serveur : il garde sa caisse d'employé chez son
      // ancien patron et gagne celle de son propre salon.
      expect(
        AuthController.rolesFor(ownedSalonId: 'salon-1', staffId: 'staff-1'),
        [AppRole.client, AppRole.owner, AppRole.coiffeur],
      );
    });

    test('l’espace client existe toujours', () {
      // Un gérant reste un client : il peut réserver ailleurs que chez lui.
      for (final owned in [null, 'salon-1']) {
        for (final staff in [null, 'staff-1']) {
          expect(AuthController.rolesFor(ownedSalonId: owned, staffId: staff),
              contains(AppRole.client));
        }
      }
    });
  });

  group('Espace affiché après rechargement', () {
    test('le choix de l’utilisateur est conservé', () {
      // Un gérant qui regarde l'app en client ne doit pas être ramené à son
      // tableau de bord parce qu'il a modifié son profil.
      expect(
        AuthController.viewAfterRefresh(
          current: AppRole.client,
          available: const [AppRole.client, AppRole.owner],
          serverRole: AppRole.owner,
        ),
        AppRole.client,
      );
    });

    test('un espace perdu retombe sur le rôle du serveur', () {
      // Coiffeur renvoyé pendant que l'app est ouverte sur son espace.
      expect(
        AuthController.viewAfterRefresh(
          current: AppRole.coiffeur,
          available: const [AppRole.client],
          serverRole: AppRole.client,
        ),
        AppRole.client,
      );
    });

    test('un rôle serveur lui-même périmé retombe sur client', () {
      // Défensif : le serveur dit OWNER mais ne renvoie plus de salon.
      expect(
        AuthController.viewAfterRefresh(
          current: AppRole.owner,
          available: const [AppRole.client],
          serverRole: AppRole.owner,
        ),
        AppRole.client,
      );
    });

    test('le résultat est toujours un espace accordé', () {
      for (final current in AppRole.values) {
        for (final server in AppRole.values) {
          for (final available in [
            const [AppRole.client],
            const [AppRole.client, AppRole.owner],
            const [AppRole.client, AppRole.coiffeur],
            const [AppRole.client, AppRole.owner, AppRole.coiffeur],
          ]) {
            expect(
              available,
              contains(AuthController.viewAfterRefresh(
                current: current,
                available: available,
                serverRole: server,
              )),
              reason: '$current / $server / $available',
            );
          }
        }
      }
    });
  });
}
