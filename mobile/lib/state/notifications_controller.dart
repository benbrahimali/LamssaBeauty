import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/notification_repository.dart';

class NotificationsController extends ChangeNotifier {
  NotificationsController(this._repo);

  final NotificationRepository _repo;

  List<AppNotification> _items = const [];
  int _unread = 0;
  bool _loading = false;
  String? _error;

  List<AppNotification> get items => _items;
  int get unread => _unread;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final feed = await _repo.list();
      _items = feed.items;
      _unread = feed.unread;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void reset() {
    _items = const [];
    _unread = 0;
    notifyListeners();
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.read) return;
    notification.read = true;
    _unread = (_unread - 1).clamp(0, 9999);
    notifyListeners();
    try {
      await _repo.markRead(notification.id);
    } on ApiException {
      await load(); // resynchronise si le serveur a refusé
    }
  }

  Future<void> markAllRead() async {
    for (final item in _items) {
      item.read = true;
    }
    _unread = 0;
    notifyListeners();
    try {
      await _repo.markAllRead();
    } on ApiException {
      await load();
    }
  }
}
