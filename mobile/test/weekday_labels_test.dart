import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';

/// Noms des jours de la semaine (§3.1, §3.5).
///
/// Ils portaient des abréviations dialectales tronquées — « ثنين », « ربعا »,
/// « حدّ » — qui se lisent comme des fautes. Un réglage d'horaires se consulte
/// une fois et doit se comprendre sans hésiter.
void main() {
  /// Les sept noms, en arabe standard, dans l'ordre de la semaine.
  const attendus = {
    'mon': 'الاثنين',
    'tue': 'الثلاثاء',
    'wed': 'الأربعاء',
    'thu': 'الخميس',
    'fri': 'الجمعة',
    'sat': 'السبت',
    'sun': 'الأحد',
  };

  test('les sept jours portent leur nom complet', () {
    expect({for (final j in kWeekdays) j.key: j.label}, attendus);
  });

  test('la semaine commence lundi', () {
    // C'est la convention du backend : un décalage ici poserait le repos du
    // dimanche sur le lundi.
    expect(kWeekdays.first.key, 'mon');
    expect(kWeekdays.last.key, 'sun');
    expect(kWeekdays, hasLength(7));
  });

  test('les clés suivent l’ordre attendu par l’API', () {
    expect(kWeekdays.map((j) => j.key).toList(),
        ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun']);
  });

  test('aucun nom n’est une abréviation tronquée', () {
    // Chaque nom porte l'article défini : c'est ce qui distingue « الأحد » du
    // « حدّ » dialectal qui s'y trouvait.
    for (final j in kWeekdays) {
      expect(j.label.startsWith('ال'), isTrue,
          reason: '${j.key} doit porter son nom complet');
    }
  });

  test('la semaine par défaut couvre les sept jours', () {
    final semaine = parseWeekHours(null);

    // Un jour manquant serait invisible dans l'éditeur, donc impossible à
    // ouvrir pour le gérant.
    expect(semaine.keys.toSet(), attendus.keys.toSet());
  });

  test('le dimanche est fermé par défaut, les autres ouverts', () {
    final semaine = parseWeekHours(null);

    expect(semaine['sun']!.closed, isTrue);
    for (final jour in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat']) {
      expect(semaine[jour]!.closed, isFalse, reason: jour);
    }
  });

  test('les horaires reçus du serveur priment sur le défaut', () {
    final semaine = parseWeekHours({
      'sun': {'closed': false, 'open': '10:00', 'close': '16:00'},
    });

    // Un salon qui ouvre 7j/7 l'a déclaré : le défaut ne doit pas le contredire.
    expect(semaine['sun']!.closed, isFalse);
    expect(semaine['sun']!.open, '10:00');
    expect(semaine['mon']!.closed, isFalse, reason: 'les absents gardent le défaut');
  });
}
