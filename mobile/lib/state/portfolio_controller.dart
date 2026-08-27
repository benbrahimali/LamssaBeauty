import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/repositories/portfolio_repository.dart';

/// Fil « En vogue » (§3.8, §8.3) : ce que les coiffeurs publient, trié par le
/// serveur sur les likes puis la fraîcheur.
class PortfolioController extends ChangeNotifier {
  PortfolioController(this._repo);

  final PortfolioRepository _repo;

  List<PortfolioPost> _posts = const [];
  List<String> _tags = const [];
  String? _activeTag;
  bool _loading = false;
  String? _error;

  List<PortfolioPost> get posts => _posts;
  bool get loading => _loading;
  String? get error => _error;
  String? get activeTag => _activeTag;

  /// Tags les plus présents dans le fil courant, pour les filtres rapides.
  List<String> get tags => _tags;

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_posts.isNotEmpty && !force && _activeTag == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _posts = await _repo.trending(tag: _activeTag);
      // Les tags ne sont recalculés que sur le fil complet : sinon filtrer sur
      // un tag ferait disparaître tous les autres de la barre de filtres.
      if (_activeTag == null) _tags = _extractTags(_posts);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> filterByTag(String? tag) async {
    if (_activeTag == tag) return;
    _activeTag = tag;
    _posts = const [];
    notifyListeners();
    await load(force: true);
  }

  /// Bascule optimiste : le cœur réagit tout de suite, le serveur fait foi ensuite.
  Future<void> toggleLike(PortfolioPost post) async {
    final index = _posts.indexWhere((p) => p.id == post.id);
    if (index < 0) return;

    final before = _posts[index];
    _posts = [..._posts]..[index] = before.copyWith(
        likedByMe: !before.likedByMe,
        likes: before.likes + (before.likedByMe ? -1 : 1),
      );
    notifyListeners();

    try {
      final result = await _repo.toggleLike(post.id);
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i < 0) return;
      _posts = [..._posts]
        ..[i] = _posts[i].copyWith(likes: result.likes, likedByMe: result.likedByMe);
    } on ApiException {
      // Un like refusé (session expirée) doit revenir en arrière, sinon
      // l'affichage ment jusqu'au prochain rechargement.
      final i = _posts.indexWhere((p) => p.id == post.id);
      if (i >= 0) _posts = [..._posts]..[i] = before;
    } finally {
      notifyListeners();
    }
  }

  static List<String> _extractTags(List<PortfolioPost> posts) {
    final counts = <String, int>{};
    for (final post in posts) {
      for (final tag in post.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final sorted = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return sorted.take(8).toList();
  }

  void reset() {
    _posts = const [];
    _tags = const [];
    _activeTag = null;
    notifyListeners();
  }
}

/// Les publications du coiffeur connecté : son propre mur, qu'il alimente.
class MyPortfolioController extends ChangeNotifier {
  MyPortfolioController(this._repo);

  final PortfolioRepository _repo;

  List<PortfolioPost> _posts = const [];
  bool _loading = false;
  bool _publishing = false;
  String? _error;
  String? _staffId;

  List<PortfolioPost> get posts => _posts;
  bool get loading => _loading;
  bool get publishing => _publishing;
  String? get error => _error;

  Future<void> load(String staffId) async {
    _staffId = staffId;
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _posts = await _repo.ofStaff(staffId);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Renvoie le message d'erreur, ou null si la publication a réussi.
  Future<String?> publish({
    required File image,
    String caption = '',
    List<String> tags = const [],
  }) async {
    _publishing = true;
    notifyListeners();
    try {
      final post = await _repo.publish(image: image, caption: caption, tags: tags);
      _posts = [post, ..._posts];
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      _publishing = false;
      notifyListeners();
    }
  }

  Future<String?> remove(PortfolioPost post) async {
    final before = _posts;
    _posts = _posts.where((p) => p.id != post.id).toList();
    notifyListeners();
    try {
      await _repo.remove(post.id);
      return null;
    } on ApiException catch (e) {
      _posts = before;
      notifyListeners();
      return e.message;
    }
  }

  void reset() {
    _posts = const [];
    _staffId = null;
    notifyListeners();
  }

  String? get staffId => _staffId;
}
