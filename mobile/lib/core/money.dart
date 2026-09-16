/// Montant en dinars tel qu'il s'affiche dans la caisse.
///
/// Sans décimales quand il est rond, au centime sinon. Arrondir chaque montant
/// à l'unité faisait afficher 15 DT partagés en « 8 + 8 » : deux parts justes,
/// une somme fausse à l'écran.
String formatDt(double montant, {String suffix = ' DT'}) {
  var arrondi = (montant * 100).round() / 100;
  // « -0 DT » pour un reste de calcul minuscule n'aurait aucun sens.
  if (arrondi == 0) arrondi = 0;
  final texte = arrondi == arrondi.roundToDouble()
      ? arrondi.toStringAsFixed(0)
      : arrondi.toStringAsFixed(2);
  return '$texte$suffix';
}
