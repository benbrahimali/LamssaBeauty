import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:lamssa/main.dart';

/// Sens de lecture de l'interface (§2.5).
///
/// L'app est rédigée en arabe tunisien : la rendre en base LTR déplace la
/// ponctuation, les chevrons et les alignements du mauvais côté. C'est le genre
/// de régression qu'aucun autre test ne voit — d'où celui-ci.
void main() {
  group('Locale de l’interface', () {
    test('un invité lit en arabe', () {
      expect(LamssaApp.localeFor(null), const Locale('ar'));
    });

    test('un compte en arabe lit en arabe', () {
      expect(LamssaApp.localeFor('ar'), const Locale('ar'));
    });

    test('un compte en français lit en français', () {
      expect(LamssaApp.localeFor('fr'), const Locale('fr'));
    });

    test('une locale inconnue retombe sur l’arabe, pas sur du LTR', () {
      // Le serveur pourrait renvoyer 'en' ou une valeur vide : l'interface
      // reste en arabe, donc son sens de lecture doit le rester aussi.
      for (final value in ['', 'en', 'ar-TN', 'AR']) {
        expect(LamssaApp.localeFor(value), const Locale('ar'), reason: value);
      }
    });

    test('l’arabe est bien traité comme droite-à-gauche', () {
      // C'est ce que MaterialApp propage en Directionality à tout l'arbre :
      // si cette hypothèse tombait, tout le reste de l'écran serait faux.
      expect(Bidi.isRtlLanguage(LamssaApp.localeFor('ar').languageCode), isTrue);
      expect(Bidi.isRtlLanguage(LamssaApp.localeFor('fr').languageCode), isFalse);
    });
  });
}
