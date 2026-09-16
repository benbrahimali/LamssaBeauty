import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/core/money.dart';

/// Affichage des montants de la caisse (§3.4).
void main() {
  test('un montant rond reste sans décimales', () {
    expect(formatDt(15), '15 DT');
  });

  test('une moitié de dinar s’affiche au centime', () {
    // 15 DT partagés à 50 % : « 8 + 8 » à l'écran ne faisait pas 15.
    expect(formatDt(7.5), '7.50 DT');
  });

  test('les deux parts affichées retombent sur le total', () {
    expect('${formatDt(7.5)} + ${formatDt(7.5)}', '7.50 DT + 7.50 DT');
  });

  test('un reste de calcul flottant est arrondi au centime', () {
    expect(formatDt(7.499999), '7.50 DT');
    expect(formatDt(0.1 + 0.2), '0.30 DT');
  });

  test('un montant négatif garde son signe', () {
    expect(formatDt(-8), '-8 DT');
  });

  test('pas de « -0 DT » pour un reste minuscule', () {
    expect(formatDt(-0.001), '0 DT');
  });

  test('le libellé peut changer', () {
    expect(formatDt(5, suffix: ' بقشيش'), '5 بقشيش');
  });
}
