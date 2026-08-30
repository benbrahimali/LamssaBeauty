import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/location.dart';

/// Remplissage de la ville et de l'adresse à la création d'un salon (§3.1).
///
/// « موقعي الحالي » ne posait que des coordonnées : les champs ville et
/// adresse restaient vides et le gérant devait tout retaper. Le sélecteur de
/// carte, lui, fondait tout en une seule chaîne — « Av. Habib Bourguiba,
/// Menzah, Tunis » dans le champ adresse, et rien dans le champ ville.
void main() {
  group('Adresse postale', () {
    test('rue et ville restent séparées', () {
      const a = PostalAddress(street: 'Av. Habib Bourguiba', city: 'Tunis');

      expect(a.street, 'Av. Habib Bourguiba');
      expect(a.city, 'Tunis',
          reason: 'le formulaire demande les deux séparément');
    });

    test('le rendu d’un seul tenant reste disponible', () {
      const a = PostalAddress(street: 'Rue de Marseille', city: 'Tunis');

      // Le sélecteur de carte n'a qu'une ligne à afficher sous le pointeur.
      expect(a.full, 'Rue de Marseille, Tunis');
    });

    test('une ville seule se rend sans virgule orpheline', () {
      const a = PostalAddress(city: 'Sfax');

      expect(a.full, 'Sfax');
    });

    test('une rue seule aussi', () {
      const a = PostalAddress(street: 'Rue 8601');

      expect(a.full, 'Rue 8601');
    });

    test('une adresse vide se reconnaît', () {
      const a = PostalAddress();

      // Un géocodeur muet ne doit pas empêcher de créer un salon.
      expect(a.isEmpty, isTrue);
      expect(a.full, '');
    });

    test('une adresse partielle n’est pas vide', () {
      expect(const PostalAddress(city: 'Bizerte').isEmpty, isFalse);
      expect(const PostalAddress(street: 'Rue 1').isEmpty, isFalse);
    });
  });

  group('Règle de remplissage', () {
    /// Ce que fait l'écran de création : compléter, jamais écraser.
    String complete(String saisi, String propose) =>
        saisi.trim().isEmpty && propose.isNotEmpty ? propose : saisi;

    test('un champ vide se remplit', () {
      expect(complete('', 'Tunis'), 'Tunis');
    });

    test('une saisie du gérant n’est jamais écrasée', () {
      // Il connaît son quartier mieux qu'un géocodeur inverse : « Menzah 6 »
      // vaut mieux que « Ariana » même si le géocodeur préfère le second.
      expect(complete('Menzah 6', 'Ariana'), 'Menzah 6');
    });

    test('un champ contenant des espaces compte comme vide', () {
      expect(complete('   ', 'Tunis'), 'Tunis');
    });

    test('un géocodeur muet laisse le champ tel quel', () {
      expect(complete('', ''), '');
      expect(complete('Sousse', ''), 'Sousse');
    });
  });
}
