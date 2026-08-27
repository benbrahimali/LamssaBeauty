import '../../core/api_client.dart';
import '../models.dart';

/// Historique des notifications in-app (§3.7).
class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<NotificationFeed> list({bool unreadOnly = false}) async {
    final data = await _api.get('/notifications', query: {
      if (unreadOnly) 'unread_only': true,
    }) as Map<String, dynamic>;

    return NotificationFeed(
      unread: (data['unread'] as num?)?.toInt() ?? 0,
      items: ((data['items'] as List?) ?? const [])
          .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  Future<void> markRead(String id) => _api.patch('/notifications/$id/read');

  Future<void> markAllRead() => _api.post('/notifications/read-all');
}

class NotificationFeed {
  final int unread;
  final List<AppNotification> items;

  const NotificationFeed({this.unread = 0, this.items = const []});
}
