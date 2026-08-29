import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/async_states.dart';

/// Obtention de la position, avec les cas d'échec qui arrivent vraiment.
///
/// Trois écrans en dépendent — recherche « près de moi », création de salon,
/// Style DNA. Dupliquer la séquence aurait produit trois comportements
/// légèrement différents, et c'est justement ici que les écarts se paient :
/// l'utilisateur ne sait jamais pourquoi ça ne marche pas.
///
/// Renvoie `null` après avoir affiché la raison ; l'appelant n'a rien à dire
/// de plus.
Future<Position?> resolvePosition(BuildContext context) async {
  void dire(String message) {
    if (context.mounted) showAppSnack(context, message);
  }

  try {
    // Cas le plus fréquent et le moins deviné : le GPS de l'appareil est
    // simplement éteint. Sans ce test, on tombait dans le `catch` avec
    // « Position indisponible », qui ne dit pas quoi faire.
    if (!await Geolocator.isLocationServiceEnabled()) {
      dire('شعّل الـ GPS في إعدادات التليفون');
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      // Redemander ne sert plus à rien : seul le réglage système débloque.
      dire('الإذن مرفوض — بدّلو في إعدادات التطبيق');
      return null;
    }
    if (permission == LocationPermission.denied) {
      dire('اسمح بالموقع باش نلقاولك الصالونات القريبة');
      return null;
    }

    // Un point précis peut mettre longtemps en intérieur : on borne l'attente
    // et on se rabat sur la dernière position connue, qui suffit largement
    // pour trier des salons par distance.
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) dire('ما نجّمناش نلقاو موقعك — عاود برّا');
      return last;
    }
  } catch (e) {
    // Le message brut est plus utile qu'un « indisponible » générique : c'est
    // souvent lui qui dit que le service Google Play manque sur l'appareil.
    dire('الموقع ما خدمش: $e');
    return null;
  }
}
