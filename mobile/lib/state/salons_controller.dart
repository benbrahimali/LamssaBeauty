import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_exception.dart';
import '../data/models.dart';
import '../data/repositories/salon_repository.dart';

/// Découverte : liste de salons filtrée, avec géolocalisation optionnelle.
class SalonsController extends ChangeNotifier {
  SalonsController(this._repo);

  final SalonRepository _repo;

  List<Salon> _salons = const [];
  bool _loading = false;
  String? _error;

  SalonType? _type;
  bool _openNow = false;
  String _query = '';
  double? _lat;
  double? _lng;

  List<Coiffeur> _featured = const [];

  List<Salon> get salons => _salons;

  /// Coiffeurs mis en avant sur l'accueil, agrégés depuis les salons les mieux notés.
  List<Coiffeur> get featuredStaff => _featured;
  bool get loading => _loading;
  String? get error => _error;
  SalonType? get type => _type;
  bool get openNow => _openNow;
  bool get hasPosition => _lat != null && _lng != null;

  /// Dernière position connue — réutilisée par Style DNA pour proposer des
  /// coiffeurs proches sans redemander l'autorisation au milieu de l'analyse.
  double? get lat => _lat;
  double? get lng => _lng;

  void setPosition(double lat, double lng) {
    _lat = lat;
    _lng = lng;
  }

  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_salons.isNotEmpty && !force) return;
    await _fetch();
  }

  Future<void> refresh() => _fetch();

  Future<void> setType(SalonType? type) async {
    if (_type == type) return;
    _type = type;
    await _fetch();
  }

  Future<void> setOpenNow(bool value) async {
    if (_openNow == value) return;
    _openNow = value;
    await _fetch();
  }

  Future<void> setQuery(String value) async {
    if (_query == value) return;
    _query = value;
    await _fetch();
  }

  Future<void> _fetch() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _salons = await _repo.search(
        lat: _lat,
        lng: _lng,
        type: _type,
        openNow: _openNow,
        query: _query,
        // Sans position connue, on élargit : mieux vaut trop de salons qu'un écran vide.
        maxKm: hasPosition ? 15 : 200,
      );
    } on ApiException catch (e) {
      _error = e.message;
      _salons = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
    unawaited(_loadFeatured());
  }

  /// L'API n'expose pas d'annuaire global de coiffeurs : on assemble la vitrine
  /// à partir des premiers salons trouvés. Échec silencieux — c'est décoratif.
  Future<void> _loadFeatured() async {
    final targets = _salons.take(3).toList();
    if (targets.isEmpty) {
      _featured = const [];
      return;
    }
    final staff = <Coiffeur>[];
    for (final salon in targets) {
      try {
        staff.addAll((await _repo.detail(salon.id)).staff);
      } on ApiException {
        continue;
      }
    }
    staff.sort((a, b) => b.cuts.compareTo(a.cuts));
    _featured = staff.take(10).toList();
    notifyListeners();
  }
}
