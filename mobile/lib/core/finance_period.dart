/// Périodes du compte de résultat (§3.4) : le mois, la semaine, ou une période
/// choisie par le gérant.
///
/// Isolé de l'écran pour être vérifiable : une semaine qui commencerait le
/// dimanche, ou un mois de janvier qui reculerait vers le mois 0, fausserait
/// tous les chiffres affichés sans que rien ne le signale.
library;

enum PeriodMode { month, week, custom }

/// Bornes d'une période, jours inclus.
typedef DayRange = ({DateTime start, DateTime end});

const kArabicMonths = [
  'جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان',
  'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// Le mois de [now] décalé de [offset] mois : 0 = en cours, -1 = le précédent.
DayRange monthRange(DateTime now, int offset) {
  final premier = DateTime(now.year, now.month + offset, 1);
  // Jour 0 du mois suivant = dernier jour du mois visé.
  return (start: premier, end: DateTime(premier.year, premier.month + 1, 0));
}

/// La semaine de [now], du lundi au dimanche, décalée de [offset] semaines.
///
/// Le lundi, comme la paie et le serveur : une semaine qui commencerait le
/// dimanche ne recouperait pas les mêmes encaissements.
DayRange weekRange(DateTime now, int offset) {
  final lundi = DateTime(
    now.year,
    now.month,
    now.day - (now.weekday - DateTime.monday) + 7 * offset,
  );
  return (start: lundi, end: DateTime(lundi.year, lundi.month, lundi.day + 6));
}

/// Le libellé affiché au-dessus du résultat.
///
/// L'année n'apparaît que si elle n'est pas l'année en cours : « 14/09 » suffit
/// cette année, pas pour une période de l'an dernier.
String rangeLabel(PeriodMode mode, DayRange range, {DateTime? now}) {
  if (mode == PeriodMode.month) {
    return '${kArabicMonths[range.start.month - 1]} ${range.start.year}';
  }
  final annee = (now ?? DateTime.now()).year;
  String jour(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.year != annee ? '/${d.year}' : ''}';
  return '${jour(range.start)} → ${jour(range.end)}';
}
