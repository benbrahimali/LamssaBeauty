import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/push_service.dart';
import '../data/models.dart';
import '../data/repositories/auth_repository.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

/// Session courante : qui est connecté, avec quel rôle, sur quel salon.
class AuthController extends ChangeNotifier {
  AuthController(this._api, this._repo, this._push) {
    _api.onSessionExpired = () {
      _status = AuthStatus.loggedOut;
      _context = null;
      notifyListeners();
    };
  }

  final ApiClient _api;
  final AuthRepository _repo;
  final PushService _push;

  AuthStatus _status = AuthStatus.unknown;
  AccountContext? _context;
  bool _busy = false;
  String? _error;
  String? _devCode;

  AuthStatus get status => _status;
  AppUser? get user => _context?.user;
  AccountContext? get context => _context;
  bool get busy => _busy;
  String? get error => _error;

  /// Code OTP renvoyé par le backend en dev — évite de fouiller les logs.
  String? get devCode => _devCode;

  /// Espace affiché. Un gérant qui coupe lui-même peut basculer côté coiffeur.
  AppRole _viewAs = AppRole.client;
  AppRole get role => _viewAs;

  /// Espaces réellement accessibles au compte.
  List<AppRole> get availableRoles =>
      rolesFor(ownedSalonId: _context?.ownedSalonId, staffId: _context?.staffId);

  /// Espaces ouverts par les rattachements du compte.
  ///
  /// Dérivés de ce que le serveur renvoie, jamais du rôle déclaré : c'est la
  /// possession d'un salon ou d'un profil coiffeur qui ouvre un espace,
  /// exactement comme le backend en décide. Afficher les autres ne produirait
  /// que des 403.
  static List<AppRole> rolesFor({String? ownedSalonId, String? staffId}) => [
        AppRole.client,
        if (ownedSalonId != null) AppRole.owner,
        if (staffId != null) AppRole.coiffeur,
      ];

  /// Espace à afficher après un rechargement du contexte.
  ///
  /// On conserve le choix de l'utilisateur tant qu'il reste valable : écraser
  /// systématiquement par le rôle serveur renvoyait un gérant passé en vue
  /// client vers son tableau de bord dès qu'il modifiait son profil.
  ///
  /// Un espace perdu entre-temps — coiffeur renvoyé de son salon — retombe sur
  /// le rôle que le serveur reconnaît, et à défaut sur client, qui existe
  /// toujours.
  static AppRole viewAfterRefresh({
    required AppRole current,
    required List<AppRole> available,
    required AppRole serverRole,
  }) {
    if (available.contains(current)) return current;
    if (available.contains(serverRole)) return serverRole;
    return AppRole.client;
  }

  String? get salonId => _context?.activeSalonId;
  String? get staffId => _context?.staffId;

  /// Restaure la session persistée au démarrage.
  Future<void> bootstrap() async {
    await _api.tokens.load();
    if (!_api.tokens.isLoggedIn) {
      _status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    try {
      _context = await _repo.me();
      // À l'ouverture, on part de l'espace que le serveur reconnaît.
      _viewAs = _context!.user.role;
      _alignView();
      _status = AuthStatus.loggedIn;
      unawaited(_push.registerForUser());
    } on ApiException {
      await _api.tokens.clear();
      _status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<bool> requestOtp(String phone) async {
    _setBusy(true);
    try {
      _devCode = await _repo.requestOtp(phone);
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _setBusy(false);
    }
  }

  Future<bool> verifyOtp({
    required String phone,
    required String code,
    String name = '',
  }) async {
    _setBusy(true);
    try {
      await _repo.verifyOtp(phone: phone, code: code, name: name);
      _context = await _repo.me();
      _viewAs = _context!.user.role;
      _alignView();
      _status = AuthStatus.loggedIn;
      _devCode = null;
      // Sans attendre : la permission push ne doit pas retarder l'entrée dans l'app.
      unawaited(_push.registerForUser());
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } finally {
      _setBusy(false);
    }
  }

  /// Met à jour le profil (nom, langue) et recharge le contexte.
  ///
  /// Renvoie le message d'erreur, ou null si tout s'est bien passé.
  Future<String?> updateProfile({String? name, String? locale}) async {
    try {
      await _repo.updateProfile(name: name, locale: locale);
      // On relit plutôt que de patcher l'objet local : le serveur normalise
      // (nom vide, locale inconnue) et reste la source de vérité.
      await refreshContext();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Change la langue de l'interface (§2.5) et la persiste côté serveur —
  /// c'est aussi celle des SMS et notifications envoyés au compte.
  ///
  /// Renvoie le message d'erreur, ou null si tout s'est bien passé.
  Future<String?> setLocale(String locale) async {
    if (_context == null || _context!.user.locale == locale) return null;
    try {
      await _repo.updateProfile(locale: locale);
      // On recharge plutôt que de patcher l'objet local : le serveur reste la
      // source de vérité, et il peut normaliser la valeur.
      await refreshContext();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Recharge les rattachements — après création d'un salon, par exemple.
  Future<void> refreshContext() async {
    try {
      _context = await _repo.me();
      _alignView();
      notifyListeners();
    } on ApiException {
      // On garde le contexte précédent plutôt que de vider l'écran.
    }
  }

  /// Bascule d'espace. Un rôle non accordé est ignoré : le serveur le
  /// refuserait de toute façon, autant ne pas afficher un écran mort.
  void switchView(AppRole role) {
    if (!availableRoles.contains(role)) return;
    _viewAs = role;
    notifyListeners();
  }

  void _alignView() {
    _viewAs = viewAfterRefresh(
      current: _viewAs,
      available: availableRoles,
      serverRole: _context?.user.role ?? AppRole.client,
    );
  }

  Future<void> logout() async {
    // Avant `logout()` : le retrait de l'appareil exige un JWT encore valide,
    // sinon ce téléphone continuerait de recevoir les notifications du compte.
    await _push.unregisterForUser();
    await _repo.logout();
    _context = null;
    _status = AuthStatus.loggedOut;
    _viewAs = AppRole.client;
    notifyListeners();
  }

  /// Mode invité : on explore sans compte, la réservation exigera une connexion.
  void continueAsGuest() {
    _status = AuthStatus.loggedOut;
    _viewAs = AppRole.client;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setBusy(bool value) {
    _busy = value;
    if (value) _error = null;
    notifyListeners();
  }
}
