import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/repositories/reel_repository.dart';

/// Fil public des reels (§3.8).
///
/// Chargé sans authentification : un visiteur doit voir les vidéos avant même
/// d'avoir un compte, c'est tout l'intérêt du fil.
class ReelsController extends ChangeNotifier {
  ReelsController(this._repo);

  final ReelRepository _repo;

  List<Reel> _reels = const [];
  bool _loading = false;
  bool _publishing = false;
  String? _error;

  /// Vues déjà comptées dans cette session : sans ce garde-fou, revenir sur
  /// une vidéo en faisant défiler gonflerait son compteur.
  final Set<String> _viewed = {};

  List<Reel> get reels => _reels;
  bool get loading => _loading;
  bool get publishing => _publishing;
  String? get error => _error;

  Future<void> load({bool force = false, String? salonId, String? staffId}) async {
    if (_loading) return;
    if (_reels.isNotEmpty && !force) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _reels = await _repo.feed(salonId: salonId, staffId: staffId);
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Renvoie le message d'erreur, ou null si la publication a réussi.
  Future<String?> publish({
    required File video,
    String caption = '',
    List<String> tags = const [],
  }) async {
    _publishing = true;
    notifyListeners();
    try {
      final reel = await _repo.publish(video: video, caption: caption, tags: tags);
      _reels = [reel, ..._reels];
      return null;
    } on ApiException catch (e) {
      // Le serveur renvoie 422 avec la durée mesurée quand la vidéo dépasse
      // 90 s : son message est plus utile que n'importe quel texte générique.
      return e.message;
    } finally {
      _publishing = false;
      notifyListeners();
    }
  }

  /// Compte une vue au plus une fois par session, sans bloquer la lecture.
  void markViewed(Reel reel) {
    if (!_viewed.add(reel.id)) return;
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index >= 0) {
      _reels = [..._reels]..[index] = _reels[index].copyWith(views: reel.views + 1);
      notifyListeners();
    }
    // Une vue perdue n'a aucune conséquence : on n'attend pas la réponse.
    _repo.countView(reel.id).catchError((_) {});
  }

  Future<void> toggleLike(Reel reel) async {
    final index = _reels.indexWhere((r) => r.id == reel.id);
    if (index < 0) return;

    final before = _reels[index];
    _reels = [..._reels]..[index] = before.copyWith(
        likedByMe: !before.likedByMe,
        likes: before.likes + (before.likedByMe ? -1 : 1),
      );
    notifyListeners();

    try {
      final result = await _repo.toggleLike(reel.id);
      final i = _reels.indexWhere((r) => r.id == reel.id);
      if (i >= 0) {
        _reels = [..._reels]
          ..[i] = _reels[i].copyWith(likes: result.likes, likedByMe: result.likedByMe);
      }
    } on ApiException {
      // Session expirée : on remet l'état d'avant plutôt que de laisser un
      // cœur allumé qui ne correspond à rien côté serveur.
      final i = _reels.indexWhere((r) => r.id == reel.id);
      if (i >= 0) _reels = [..._reels]..[i] = before;
    } finally {
      notifyListeners();
    }
  }

  Future<String?> remove(Reel reel) async {
    final before = _reels;
    _reels = _reels.where((r) => r.id != reel.id).toList();
    notifyListeners();
    try {
      await _repo.remove(reel.id);
      return null;
    } on ApiException catch (e) {
      _reels = before;
      notifyListeners();
      return e.message;
    }
  }

  void reset() {
    _reels = const [];
    _viewed.clear();
    notifyListeners();
  }
}
