import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistance de la session (tokens + profil courant) entre deux lancements.
class TokenStore {
  static const _kAccess = 'lamssa.access_token';
  static const _kRefresh = 'lamssa.refresh_token';
  static const _kUser = 'lamssa.user';

  String? accessToken;
  String? refreshToken;
  Map<String, dynamic>? user;

  bool get isLoggedIn => accessToken != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString(_kAccess);
    refreshToken = prefs.getString(_kRefresh);
    final raw = prefs.getString(_kUser);
    if (raw != null) {
      try {
        user = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        user = null;
      }
    }
  }

  Future<void> save({
    required String access,
    required String refresh,
    Map<String, dynamic>? profile,
  }) async {
    accessToken = access;
    refreshToken = refresh;
    if (profile != null) user = profile;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, access);
    await prefs.setString(_kRefresh, refresh);
    if (profile != null) await prefs.setString(_kUser, jsonEncode(profile));
  }

  Future<void> clear() async {
    accessToken = null;
    refreshToken = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
  }
}
