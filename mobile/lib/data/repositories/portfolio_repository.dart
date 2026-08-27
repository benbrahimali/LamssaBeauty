import 'dart:io';

import '../../core/api_client.dart';

/// Portfolio coiffeur & fil « En vogue » (§3.8, §8.3).
///
/// C'est le levier d'acquisition organique : le coiffeur publie ses coupes, le
/// client les découvre et réserve chez celui dont le travail lui plaît.
class PortfolioRepository {
  PortfolioRepository(this._api);

  final ApiClient _api;

  /// Une photo pleine résolution part plus lentement qu'un appel JSON.
  static const _uploadTimeout = Duration(seconds: 60);

  /// Fil local, trié par likes puis fraîcheur côté serveur.
  Future<List<PortfolioPost>> trending({
    int days = 14,
    String? tag,
    String? salonId,
    int limit = 30,
  }) async {
    final data = await _api.get('/portfolio/trending', query: {
      'days': days,
      'limit': limit,
      if (tag != null && tag.isNotEmpty) 'tag': tag,
      if (salonId != null) 'salon_id': salonId,
    }) as List;
    return data
        .map((e) => PortfolioPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<PortfolioPost>> ofStaff(String staffId, {int limit = 40}) async {
    final data = await _api.get('/portfolio/staff/$staffId', query: {'limit': limit})
        as List;
    return data
        .map((e) => PortfolioPost.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Envoie le fichier puis publie : le serveur renvoie l'URL à référencer.
  Future<PortfolioPost> publish({
    required File image,
    String caption = '',
    List<String> tags = const [],
  }) async {
    final upload = await _api.postMultipart(
      '/portfolio/upload',
      field: 'file',
      bytes: await image.readAsBytes(),
      filename: image.path.split(RegExp(r'[/\\]')).last,
      contentType: contentTypeOf(image.path),
      timeout: _uploadTimeout,
    ) as Map<String, dynamic>;

    final data = await _api.post('/portfolio', body: {
      'image_url': upload['url'],
      'caption': caption,
      'tags': tags,
    }) as Map<String, dynamic>;
    return PortfolioPost.fromJson(data);
  }

  /// Renvoie l'état après bascule — le serveur fait foi sur le compteur.
  Future<({int likes, bool likedByMe})> toggleLike(String itemId) async {
    final data = await _api.post('/portfolio/$itemId/like') as Map<String, dynamic>;
    return (
      likes: (data['likes'] as num?)?.toInt() ?? 0,
      likedByMe: data['liked_by_me'] == true,
    );
  }

  Future<void> remove(String itemId) => _api.delete('/portfolio/$itemId');

  /// Ne déguise jamais un fichier inconnu en image : le serveur doit pouvoir
  /// le refuser en 415 plutôt que de tenter de le décoder.
  static String contentTypeOf(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }
}

/// Une réalisation publiée, décorée par le serveur du nom du coiffeur et du salon.
class PortfolioPost {
  const PortfolioPost({
    required this.id,
    required this.imageUrl,
    required this.staffId,
    required this.salonId,
    this.beforeUrl,
    this.caption = '',
    this.tags = const [],
    this.likes = 0,
    this.likedByMe = false,
    this.staffName = '',
    this.salonName = '',
    this.createdAt,
  });

  final String id;
  final String imageUrl;
  final String? beforeUrl;
  final String staffId;
  final String salonId;
  final String caption;
  final List<String> tags;
  final int likes;
  final bool likedByMe;
  final String staffName;
  final String salonName;
  final DateTime? createdAt;

  PortfolioPost copyWith({int? likes, bool? likedByMe}) => PortfolioPost(
        id: id,
        imageUrl: imageUrl,
        beforeUrl: beforeUrl,
        staffId: staffId,
        salonId: salonId,
        caption: caption,
        tags: tags,
        likes: likes ?? this.likes,
        likedByMe: likedByMe ?? this.likedByMe,
        staffName: staffName,
        salonName: salonName,
        createdAt: createdAt,
      );

  factory PortfolioPost.fromJson(Map<String, dynamic> json) => PortfolioPost(
        id: (json['id'] ?? json['_id'])?.toString() ?? '',
        imageUrl: json['image_url']?.toString() ?? '',
        beforeUrl: json['before_url']?.toString(),
        staffId: json['staff_id']?.toString() ?? '',
        salonId: json['salon_id']?.toString() ?? '',
        caption: json['caption']?.toString() ?? '',
        tags: ((json['tags'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        likes: (json['likes'] as num?)?.toInt() ?? 0,
        likedByMe: json['liked_by_me'] == true,
        staffName: json['staff_name']?.toString() ?? '',
        salonName: json['salon_name']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      );
}
