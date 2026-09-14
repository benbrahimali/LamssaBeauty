import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/async_states.dart';

/// Lien d'itinéraire Google Maps jusqu'à un point.
///
/// Le lien universel `maps/dir` ouvre l'application Google Maps quand elle est
/// installée — guidage rue par rue, à pied ou en voiture au choix du client —
/// et le navigateur sinon. Aucune clé ni API payante : tracer l'itinéraire
/// dans l'app demanderait l'API Directions, facturée à la requête.
///
/// Les coordonnées plutôt que l'adresse : « Rue de la Liberté » existe dans
/// chaque ville de Tunisie, le point GPS du salon n'existe qu'une fois.
Uri directionsUri(double lat, double lng) => Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'destination': '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
      },
    );

/// Un salon sans position enregistrée est à (0, 0), au large du Gabon :
/// proposer d'y aller enverrait le client en mer.
bool hasCoordinates(double lat, double lng) => lat != 0 || lng != 0;

/// Ouvre l'itinéraire dans Google Maps, ou prévient si rien ne peut l'ouvrir.
Future<void> openDirections(
  BuildContext context, {
  required double lat,
  required double lng,
}) async {
  var ouvert = false;
  try {
    ouvert = await launchUrl(
      directionsUri(lat, lng),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    ouvert = false;
  }
  if (!ouvert && context.mounted) {
    showAppSnack(context, 'ما نجمناش نحلّو الخريطة — ثبّت Google Maps ولا عاود جرّب');
  }
}
