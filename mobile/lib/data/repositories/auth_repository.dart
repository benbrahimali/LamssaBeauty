import '../../core/api_client.dart';
import '../models.dart';

/// Authentification OTP SMS (§3.1 du cahier des charges).
class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// Demande l'envoi d'un code. Renvoie le code en dev (`dev_code`), sinon null.
  Future<String?> requestOtp(String phone) async {
    final data = await _api.post('/auth/otp/request', body: {'phone': phone});
    return (data as Map?)?['dev_code']?.toString();
  }

  /// Vérifie le code et ouvre la session.
  Future<AppUser> verifyOtp({
    required String phone,
    required String code,
    String name = '',
    String locale = 'fr',
  }) async {
    final data = await _api.post('/auth/otp/verify', body: {
      'phone': phone,
      'code': code,
      'name': name,
      'locale': locale,
    }) as Map<String, dynamic>;

    final user = AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    await _api.tokens.save(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
      profile: user.toJson(),
    );
    return user;
  }

  /// Profil courant + rattachements (salons possédés, profils coiffeur).
  Future<AccountContext> me() async {
    final data = await _api.get('/auth/me') as Map<String, dynamic>;
    final profiles = (data['staff_profiles'] as List?) ?? const [];
    final owned = (data['owned_salons'] as List?) ?? const [];
    return AccountContext(
      user: AppUser.fromJson(Map<String, dynamic>.from(data['user'] as Map)),
      staffId: profiles.isEmpty ? null : profiles.first['id']?.toString(),
      staffSalonId: profiles.isEmpty ? null : profiles.first['salon_id']?.toString(),
      ownedSalonId: owned.isEmpty ? null : owned.first['id']?.toString(),
      ownedSalonName: owned.isEmpty ? '' : (owned.first['name']?.toString() ?? ''),
    );
  }

  Future<void> updateProfile({String? name, String? locale}) async {
    await _api.patch('/auth/me', body: {
      if (name != null) 'name': name,
      if (locale != null) 'locale': locale,
    });
  }

  Future<void> registerDevice(String fcmToken) =>
      _api.post('/auth/me/device', body: {'fcm_token': fcmToken});

  Future<void> unregisterDevice(String fcmToken) =>
      _api.delete('/auth/me/device', body: {'fcm_token': fcmToken});

  Future<void> logout() async {
    final refresh = _api.tokens.refreshToken;
    if (refresh != null) {
      try {
        await _api.post('/auth/logout', body: {'refresh_token': refresh});
      } catch (_) {
        // Déconnexion locale malgré tout : l'utilisateur ne doit jamais rester bloqué.
      }
    }
    await _api.tokens.clear();
  }
}

/// Ce que le compte courant permet de faire — détermine l'espace affiché.
class AccountContext {
  final AppUser user;

  /// Identifiant `StaffMember` si l'utilisateur travaille dans un salon.
  final String? staffId;
  final String? staffSalonId;

  /// Premier salon possédé, s'il est gérant.
  final String? ownedSalonId;
  final String ownedSalonName;

  const AccountContext({
    required this.user,
    this.staffId,
    this.staffSalonId,
    this.ownedSalonId,
    this.ownedSalonName = '',
  });

  /// Le salon sur lequel travailler : celui qu'on possède, sinon celui où l'on est employé.
  String? get activeSalonId => ownedSalonId ?? staffSalonId;
}
