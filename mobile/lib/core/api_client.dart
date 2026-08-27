import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'api_exception.dart';
import 'env.dart';
import 'token_store.dart';

/// Client HTTP unique de l'application.
///
/// Porte le JWT, renouvelle l'access token de façon transparente sur 401 et
/// traduit toutes les erreurs en [ApiException].
class ApiClient {
  ApiClient(this.tokens);

  final TokenStore tokens;
  final http.Client _http = http.Client();

  /// Garde-fou : un seul renouvellement en vol, même si dix requêtes échouent
  /// simultanément en 401.
  Future<bool>? _refreshing;

  /// Appelé quand la session est définitivement perdue (refresh refusé).
  void Function()? onSessionExpired;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse('${Env.apiBaseUrl}${Env.apiPrefix}$path');
    if (query == null || query.isEmpty) return base;

    final params = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is Iterable) {
        params[key] = value.map((e) => e.toString()).toList();
      } else {
        params[key] = value.toString();
      }
    });
    return base.replace(queryParameters: params);
  }

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (tokens.accessToken != null)
          'Authorization': 'Bearer ${tokens.accessToken}',
      };

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _http.post(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Future<dynamic> patch(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _http.patch(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// `body` est nécessaire pour `DELETE /auth/me/device`, qui identifie
  /// l'appareil à retirer par son token FCM.
  Future<dynamic> delete(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _http.delete(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// Envoi d'un fichier en `multipart/form-data`, avec le même JWT et la même
  /// gestion d'erreurs que les autres appels.
  Future<dynamic> postMultipart(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
    Duration? timeout,
  }) {
    return _send(
      () async {
        final request = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ));
        return http.Response.fromStream(await _http.send(request));
      },
      timeout: timeout,
    );
  }

  /// POST en `multipart/form-data` sans fichier — les routes FastAPI qui
  /// déclarent des `Form(...)` n'acceptent pas de corps JSON.
  Future<dynamic> postForm(
    String path, {
    required Map<String, String> fields,
    Duration? timeout,
  }) {
    return _send(
      () async {
        final request = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(fields);
        return http.Response.fromStream(await _http.send(request));
      },
      timeout: timeout,
    );
  }

  /// Comme [postMultipart], mais la réponse est binaire (une image générée) et
  /// non du JSON : elle ne doit pas passer par le décodage habituel.
  Future<Uint8List> postMultipartBytes(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const {},
    Duration? timeout,
  }) async {
    final response = await _sendRaw(
      () async {
        final request = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: filename,
            contentType: MediaType.parse(contentType),
          ));
        return http.Response.fromStream(await _http.send(request));
      },
      timeout: timeout,
    );
    return response.bodyBytes;
  }

  Future<dynamic> _send(
    Future<http.Response> Function() request, {
    bool allowRetry = true,
    Duration? timeout,
  }) async {
    http.Response response;
    try {
      response = await request().timeout(timeout ?? Env.requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    }

    if (response.statusCode == 401 && allowRetry && tokens.refreshToken != null) {
      if (await _refreshSession()) {
        return _send(request, allowRetry: false);
      }
    }

    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      throw ApiException.fromBody(response.statusCode, decoded);
    }
    return decoded;
  }

  /// Même politique que [_send] — renouvellement du JWT, traduction des
  /// erreurs — mais rend la réponse brute au lieu du JSON décodé.
  Future<http.Response> _sendRaw(
    Future<http.Response> Function() request, {
    bool allowRetry = true,
    Duration? timeout,
  }) async {
    http.Response response;
    try {
      response = await request().timeout(timeout ?? Env.requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout();
    } on SocketException {
      throw ApiException.network();
    } on http.ClientException {
      throw ApiException.network();
    }

    if (response.statusCode == 401 && allowRetry && tokens.refreshToken != null) {
      if (await _refreshSession()) {
        return _sendRaw(request, allowRetry: false);
      }
    }
    if (response.statusCode >= 400) {
      // Le corps d'erreur reste du JSON même quand le succès est binaire.
      throw ApiException.fromBody(response.statusCode, _decode(response));
    }
    return response;
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  Future<bool> _refreshSession() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    try {
      final response = await _http
          .post(
            _uri('/auth/refresh'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh_token': tokens.refreshToken}),
          )
          .timeout(Env.requestTimeout);

      if (response.statusCode >= 400) {
        await tokens.clear();
        onSessionExpired?.call();
        return false;
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      await tokens.save(
        access: data['access_token'] as String,
        refresh: data['refresh_token'] as String,
      );
      return true;
    } catch (_) {
      return false; // panne réseau : on ne détruit pas la session pour autant
    }
  }

  void dispose() => _http.close();
}
