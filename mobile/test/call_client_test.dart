import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamssa/data/models.dart';
import 'package:lamssa/widgets/call_client_button.dart';

/// Le salon voit qui vient et peut l'appeler (§3.3).
void main() {
  test('le rendez-vous porte le téléphone du client', () {
    final b = Booking.fromJson(const {
      'id': 'b1',
      'client_name': 'Mehdi Ben Salah',
      'client_phone': '+21698000000',
    });
    expect(b.clientName, 'Mehdi Ben Salah');
    expect(b.clientPhone, '+21698000000');
  });

  test('sans téléphone, rien', () {
    expect(Booking.fromJson(const {'id': 'b1'}).clientPhone, '');
  });

  Future<void> monter(WidgetTester tester, String phone) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: CallClientButton(phone: phone)))),
      );

  testWidgets('un numéro affiche le bouton d’appel', (tester) async {
    await monter(tester, '+21698000000');
    expect(find.byIcon(Icons.phone_rounded), findsOneWidget);
    expect(find.byTooltip('+21698000000'), findsOneWidget);
  });

  testWidgets('sans numéro, pas de bouton qui ne mène nulle part', (tester) async {
    await monter(tester, '');
    expect(find.byIcon(Icons.phone_rounded), findsNothing);
  });
}
