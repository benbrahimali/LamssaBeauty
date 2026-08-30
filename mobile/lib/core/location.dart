import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../widgets/async_states.dart';

/// Obtention de la position, avec les cas d'échec qui arrivent vraiment.
///
/// Trois écrans en dépendent — recherche « près de moi », création de salon,
/// Style DNA. Dupliquer la séquence aurait produit trois comportements
/// légèrement différents, et c'est justement ici que les écarts se paient :
/// l'utilisateur ne sait jamais pourquoi ça ne marche pas.
///
/// Adresse lue à partir de coordonnées.
///
/// Rue et ville sont séparées, parce que le formulaire de création les demande
/// séparément. Les fondre en une seule chaîne laissait le champ « ville » vide
/// et l'adresse redondante — « Av. Habib Bourguiba, Tunis » dans un champ, rien
/// dans l'autre.
class PostalAddress {
  const PostalAddress({this.street = '', this.city = ''});

  /// Rue et quartier, sans la ville.
  final String street;
  final String city;

  bool get isEmpty => street.isEmpty && city.isEmpty;

  /// Rendu d'un seul tenant, pour les écrans qui n'ont qu'une ligne.
  String get full =>
      [street, city].where((p) => p.isNotEmpty).join(', ');
}

/// Traduit des coordonnées en adresse.
///
/// Renvoie une adresse vide plutôt qu'une erreur : un géocodeur muet ne doit
/// pas empêcher de créer un salon, le gérant saisira à la main.
Future<PostalAddress> resolveAddress(double lat, double lng) async {
  try {
    final lieux = await placemarkFromCoordinates(lat, lng);
    if (lieux.isEmpty) return const PostalAddress();
    final lieu = lieux.first;

    return PostalAddress(
      street: [lieu.street, lieu.subLocality]
          .where((p) => p != null && p.isNotEmpty)
          .join(', '),
      // `locality` est la ville ; à défaut la gouvernorat, qui vaut mieux que
      // rien pour retrouver un salon.
      city: (lieu.locality?.isNotEmpty ?? false)
          ? lieu.locality!
          : (lieu.administrativeArea ?? ''),
    );
  } catch (_) {
    return const PostalAddress();
  }
}

/// Position obtenue, et ce qu'elle vaut.
class ResolvedPosition {
  const ResolvedPosition(this.position, {this.approximate = false});

  final Position position;

  /// Vrai quand le point ne vient pas d'une mesure fraîche mais du dernier
  /// point connu de l'appareil — il peut dater de plusieurs heures et d'un
  /// autre quartier. Suffisant pour trier des salons par distance, pas pour
  /// figer l'adresse d'un salon.
  final bool approximate;
}

/// Renvoie `null` après avoir affiché la raison ; l'appelant n'a rien à dire
/// de plus.
///
/// [silencieux] pour une tentative que l'utilisateur n'a pas demandée — à
/// l'ouverture de l'accueil, par exemple. Enchaîner les messages d'erreur sur
/// un écran qu'on vient d'ouvrir donne l'impression que l'app est cassée,
/// alors que l'utilisateur n'a rien demandé. L'écran affiche alors sa propre
/// invite, que l'utilisateur peut toucher s'il le veut.
Future<ResolvedPosition?> resolvePosition(
  BuildContext context, {
  bool silencieux = false,
}) async {
  void dire(String message) {
    if (!silencieux && context.mounted) showAppSnack(context, message);
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
      // Une boîte de permission qui surgit sans geste de l'utilisateur se fait
      // refuser par réflexe — et un refus définitif ne se rattrape plus.
      if (silencieux) return null;
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

    // Un point précis peut mettre longtemps à venir en intérieur — et c'est
    // justement là que se tient un gérant qui crée son salon. On dégrade donc
    // par étapes, en préférant toujours une mesure fraîche à une mesure
    // précise mais périmée.
    for (final essai in const [
      (LocationAccuracy.high, 12),
      // Deuxième chance moins exigeante : un point à cent mètres près, obtenu
      // maintenant, vaut mieux que la position d'hier.
      (LocationAccuracy.medium, 6),
    ]) {
      try {
        return ResolvedPosition(await Geolocator.getCurrentPosition(
          desiredAccuracy: essai.$1,
          timeLimit: Duration(seconds: essai.$2),
        ));
      } catch (_) {
        // Essai suivant, puis repli.
      }
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last == null) {
      dire('ما نجّمناش نلقاو موقعك — عاود برّا');
      return null;
    }
    // Signalé comme approximatif : l'appelant décide s'il peut s'en contenter.
    return ResolvedPosition(last, approximate: true);
  } catch (e) {
    // Le message brut est plus utile qu'un « indisponible » générique : c'est
    // souvent lui qui dit que le service Google Play manque sur l'appareil.
    dire('الموقع ما خدمش: $e');
    return null;
  }
}
