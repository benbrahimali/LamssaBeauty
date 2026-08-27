import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../data/repositories/auth_repository.dart';

/// Ce que l'utilisateur a touché : sert à ouvrir le bon écran.
typedef PushTapHandler = void Function(Map<String, dynamic> data);

/// Notifications push (§3.7).
///
/// Firebase n'est configuré que pour Android et iOS ; sur le web et le desktop
/// tout est court-circuité pour que l'app continue de tourner (tests, `flutter
/// build web`) sans dépendre d'un projet Firebase.
class PushService {
  PushService(this._repo);

  final AuthRepository _repo;

  static const _channel = AndroidNotificationChannel(
    'lamssa_default',
    'Notifications LAMSSA',
    description: 'Rendez-vous, rappels, tséb9as et caisse.',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  bool _ready = false;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _tapSub;

  PushTapHandler? onTap;

  /// Le token de l'appareil, une fois la permission accordée.
  String? get token => _token;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Initialise Firebase et les canaux. Sans effet si la plateforme n'est pas
  /// supportée, ou si `google-services.json` est absent.
  Future<void> init() async {
    if (_ready || !_supported) return;
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Fichier de configuration absent : l'app doit rester utilisable.
      debugPrint('Push désactivé — Firebase non configuré: $e');
      return;
    }

    // Android 8+ exige un canal déclaré, sinon la notification est muette
    // quand l'app est au premier plan.
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // iOS affiche les notifications de premier plan lui-même ; sur Android
    // c'est à nous de les rendre visibles.
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
            alert: true, badge: true, sound: true);

    _foregroundSub = FirebaseMessaging.onMessage.listen(_showLocal);
    _tapSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // App tuée puis rouverte depuis la notification.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleTap(initial);

    _ready = true;
  }

  /// Demande la permission puis enregistre l'appareil côté serveur.
  ///
  /// À appeler une fois connecté : `/auth/me/device` exige un JWT.
  Future<void> registerForUser() async {
    if (!_ready) await init();
    if (!_ready) return;

    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('Push refusé par l’utilisateur');
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _register(token);

    // FCM fait tourner le token de lui-même (réinstallation, restauration de
    // sauvegarde, purge). Sans cet abonnement, l'appareil devient injoignable
    // sans que personne ne s'en aperçoive.
    _refreshSub?.cancel();
    _refreshSub = FirebaseMessaging.instance.onTokenRefresh.listen(_register);
  }

  Future<void> _register(String token) async {
    _token = token;
    try {
      await _repo.registerDevice(token);
    } catch (e) {
      // Un enregistrement raté ne doit jamais bloquer la connexion.
      debugPrint('Enregistrement FCM échoué: $e');
    }
  }

  /// À appeler avant la déconnexion, tant que le JWT est encore valide :
  /// sinon l'appareil continuerait de recevoir les notifications du compte.
  Future<void> unregisterForUser() async {
    final token = _token;
    _refreshSub?.cancel();
    _refreshSub = null;
    if (token == null) return;
    try {
      await _repo.unregisterDevice(token);
    } catch (e) {
      debugPrint('Retrait FCM échoué: $e');
    }
    _token = null;
  }

  Future<void> _showLocal(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['type']?.toString(),
    );
  }

  void _handleTap(RemoteMessage message) => onTap?.call(message.data);

  void dispose() {
    _refreshSub?.cancel();
    _foregroundSub?.cancel();
    _tapSub?.cancel();
  }
}
