import 'dart:io';

import '../../core/api_client.dart';

/// Reels vidéo (§3.8) — le fil public de LAMSSA.
///
/// Coiffeurs et salons y publient des vidéos courtes ; clients et simples
/// visiteurs les regardent sans compte. C'est ce qui en fait un levier
/// d'acquisition : le contenu doit être visible avant l'inscription.
class ReelRepository {
  ReelRepository(this._api);

  final ApiClient _api;

  /// Une vidéo met bien plus longtemps à monter qu'une photo, surtout en 3G.
  static const _uploadTimeout = Duration(minutes: 5);

  /// Fil public. Aucun jeton n'est requis côté serveur.
  Future<List<Reel>> feed({
    int days = 30,
    String? tag,
    String? salonId,
    String? staffId,
    int limit = 20,
  }) async {
    final data = await _api.get('/reels', query: {
      'days': days,
      'limit': limit,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (salonId != null) 'salon_id': salonId,
      if (staffId != null) 'staff_id': staffId,
    }) as List;
    return data
        .map((e) => Reel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Publie une vidéo. Le serveur mesure la durée et refuse au-delà de 90 s.
  Future<Reel> publish({
    required File video,
    String caption = '',
    List<String> tags = const [],
  }) async {
    final data = await _api.postMultipart(
      '/reels',
      field: 'file',
      bytes: await video.readAsBytes(),
      filename: video.path.split(RegExp(r'[/\\]')).last,
      contentType: contentTypeOf(video.path),
      fields: {'caption': caption, 'tags': tags.join(',')},
      timeout: _uploadTimeout,
    ) as Map<String, dynamic>;
    return Reel.fromJson(data);
  }

  /// Une vue ne bloque jamais la lecture : l'échec est silencieux côté appelant.
  Future<void> countView(String reelId) => _api.post('/reels/$reelId/view');

  Future<({int likes, bool likedByMe})> toggleLike(String reelId) async {
    final data = await _api.post('/reels/$reelId/like') as Map<String, dynamic>;
    return (
      likes: (data['likes'] as num?)?.toInt() ?? 0,
      likedByMe: data['liked_by_me'] == true,
    );
  }

  Future<void> remove(String reelId) => _api.delete('/reels/$reelId');

  /// Ne déguise pas un fichier inconnu en vidéo : le serveur doit pouvoir le
  /// refuser en 415 plutôt que de le pousser chez le fournisseur.
  static String contentTypeOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    if (lower.endsWith('.webm')) return 'video/webm';
    return 'application/octet-stream';
  }
}

/// Une vidéo courte publiée par un coiffeur ou un salon.
class Reel {
  const Reel({
    required this.id,
    required this.videoUrl,
    required this.salonId,
    this.staffId,
    this.thumbnailUrl = '',
    this.durationSec = 0,
    this.caption = '',
    this.tags = const [],
    this.views = 0,
    this.likes = 0,
    this.likedByMe = false,
    this.staffName = '',
    this.salonName = '',
  });

  final String id;
  final String videoUrl;

  /// Vignette dérivée de la vidéo par Cloudinary : le fil s'affiche sans
  /// télécharger les vidéos entières.
  final String thumbnailUrl;
  final String salonId;
  final String? staffId;
  final double durationSec;
  final String caption;
  final List<String> tags;
  final int views;
  final int likes;
  final bool likedByMe;
  final String staffName;
  final String salonName;

  /// Qui signe la vidéo : le coiffeur s'il y en a un, sinon le salon.
  String get authorLabel => staffName.isNotEmpty ? staffName : salonName;

  String get durationLabel {
    final seconds = durationSec.round();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Reel copyWith({int? likes, bool? likedByMe, int? views}) => Reel(
        id: id,
        videoUrl: videoUrl,
        thumbnailUrl: thumbnailUrl,
        salonId: salonId,
        staffId: staffId,
        durationSec: durationSec,
        caption: caption,
        tags: tags,
        views: views ?? this.views,
        likes: likes ?? this.likes,
        likedByMe: likedByMe ?? this.likedByMe,
        staffName: staffName,
        salonName: salonName,
      );

  factory Reel.fromJson(Map<String, dynamic> json) => Reel(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        videoUrl: json['video_url']?.toString() ?? '',
        thumbnailUrl: json['thumbnail_url']?.toString() ?? '',
        salonId: json['salon_id']?.toString() ?? '',
        staffId: json['staff_id']?.toString(),
        durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 0,
        caption: json['caption']?.toString() ?? '',
        tags: ((json['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        views: (json['views'] as num?)?.toInt() ?? 0,
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        likedByMe: json['liked_by_me'] == true,
        staffName: json['staff_name']?.toString() ?? '',
        salonName: json['salon_name']?.toString() ?? '',
      );
}
