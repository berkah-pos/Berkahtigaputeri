import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.code, this.message);

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => 'ApiException(' + statusCode.toString() + ', ' + code + '): ' + message;
}

class ApiTransportException implements Exception {
  const ApiTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiSession {
  const ApiSession({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  final String token;
  final DateTime expiresAt;
  final Map<String, dynamic> user;
}

class ApiSessionStore {
  ApiSessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const String _sessionKey = 'berkahpos.api-session.v1';
  final FlutterSecureStorage _storage;
  ApiSession? _session;

  ApiSession? get session {
    final value = _session;
    if (value == null || !value.expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }
    return value;
  }

  bool get hasValidSession => session != null;

  Future<void> restore() async {
    try {
      final raw = await _storage.read(key: _sessionKey);
      if (raw == null || raw.isEmpty) {
        _session = null;
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await clear();
        return;
      }
      final token = decoded['access_token'];
      final expiry = DateTime.tryParse((decoded['expires_at'] ?? '').toString());
      final user = decoded['user'];
      if (token is! String ||
          token.isEmpty ||
          expiry == null ||
          !expiry.isAfter(DateTime.now().toUtc()) ||
          user is! Map) {
        await clear();
        return;
      }

      _session = ApiSession(
        token: token,
        expiresAt: expiry.toUtc(),
        user: Map<String, dynamic>.from(user),
      );
    } catch (_) {
      await clear();
    }
  }

  Future<void> save(ApiSession session) async {
    if (!session.expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const FormatException('Refusing to store an expired API token.');
    }
    await _storage.write(
      key: _sessionKey,
      value: jsonEncode(<String, dynamic>{
        'access_token': session.token,
        'expires_at': session.expiresAt.toUtc().toIso8601String(),
        'user': session.user,
      }),
    );
    _session = session;
  }

  Future<void> clear() async {
    _session = null;
    try {
      await _storage.delete(key: _sessionKey);
    } catch (_) {
      // The in-memory token is cleared even if secure storage is unavailable.
    }
  }
}

/// Client for the approved Laravel Central API. Production origins must use
/// HTTPS and the platform TLS trust store; HTTP is limited to local development.
class LaravelApiClient {
  LaravelApiClient({
    required Uri baseUri,
    required ApiSessionStore sessions,
    HttpClient? httpClient,
    this.requestTimeout = const Duration(seconds: 15),
  })  : _baseUri = _validatedBaseUri(baseUri),
        _sessions = sessions,
        _httpClient = httpClient ??
            (HttpClient()..connectionTimeout = const Duration(seconds: 10));

  final Uri _baseUri;
  final ApiSessionStore _sessions;
  final HttpClient _httpClient;
  final Duration requestTimeout;

  bool get hasAuthenticatedSession => _sessions.hasValidSession;
  Map<String, dynamic>? get currentUser => _sessions.session?.user;

  static Uri _validatedBaseUri(Uri value) {
    const loopbackHosts = <String>{'localhost', '127.0.0.1', '::1', '10.0.2.2'};
    final localHttp = value.scheme == 'http' && loopbackHosts.contains(value.host);
    if (value.host.isEmpty ||
        value.userInfo.isNotEmpty ||
        value.hasQuery ||
        value.hasFragment ||
        (value.path.isNotEmpty && value.path != '/') ||
        (value.scheme != 'https' && !localHttp)) {
      throw ArgumentError.value(
        value.toString(),
        'baseUri',
        'Use an HTTPS origin without a path/query; HTTP is limited to local development.',
      );
    }

    return Uri(
      scheme: value.scheme,
      host: value.host,
      port: value.hasPort ? value.port : null,
      path: '/',
    );
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String deviceName = 'android-client',
  }) async {
    final response = await _send(
      'POST',
      '/api/v1/auth/login',
      authenticated: false,
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'device_name': deviceName,
      },
    );

    final token = response['access_token'];
    final expiresAt = DateTime.tryParse((response['expires_at'] ?? '').toString());
    final rawUser = response['user'];
    if (token is! String || token.isEmpty || expiresAt == null || rawUser is! Map) {
      throw const FormatException('The Laravel API returned an invalid login response.');
    }

    final user = Map<String, dynamic>.from(rawUser);
    final tenantId = user['tenant_id']?.toString().trim() ?? '';
    if (tenantId.isEmpty) {
      await _sessions.clear();
      throw const ApiException(
        403,
        'tenant_not_entitled',
        'Akun belum ditautkan ke tenant aktif. Hubungi administrator.',
      );
    }

    await _sessions.save(
      ApiSession(
        token: token,
        expiresAt: expiresAt.toUtc(),
        user: user,
      ),
    );
    return user;
  }

  Future<void> logout() async {
    final token = _sessions.session?.token;
    try {
      if (token != null) {
        await _send(
          'POST',
          '/api/v1/auth/logout',
          authenticated: true,
          bearerToken: token,
        );
      }
    } catch (_) {
      // Local sign-out is unconditional. A network outage can delay server
      // revocation, so the server token also has a finite lifetime.
    } finally {
      await _sessions.clear();
    }
  }

  Future<Map<String, dynamic>> enrollDevice(String deviceId) => _send(
        'POST',
        '/api/v1/devices/enroll',
        body: <String, dynamic>{'device_id': deviceId.trim()},
      );

  Future<Map<String, dynamic>> getEffectiveConfig({
    required String deviceId,
    required String service,
  }) =>
      _send(
        'POST',
        '/api/v1/config/effective',
        body: <String, dynamic>{
          'device_id': deviceId.trim(),
          'service': service,
        },
      );

  Future<Map<String, dynamic>> syncOutboxEvent({
    required String deviceId,
    required String appVersion,
    required Map<String, dynamic> event,
  }) =>
      _send(
        'POST',
        '/api/v1/sync',
        body: <String, dynamic>{
          'device_id': deviceId.trim(),
          'app_version': appVersion,
          'events': <Map<String, dynamic>>[event],
        },
      );

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool authenticated = true,
    String? bearerToken,
  }) async {
    final token = bearerToken ?? _sessions.session?.token;
    if (authenticated && (token == null || token.isEmpty)) {
      throw const ApiException(401, 'unauthenticated', 'Silakan login kembali.');
    }

    try {
      final request = await _httpClient
          .openUrl(method, _baseUri.resolve(path))
          .timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.contentType = ContentType.json;
      if (authenticated && token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + token);
      }
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close().timeout(requestTimeout);
      final responseText = await utf8.decoder.bind(response).join().timeout(requestTimeout);
      dynamic decoded;
      if (responseText.trim().isEmpty) {
        decoded = <String, dynamic>{};
      } else {
        decoded = jsonDecode(responseText);
      }
      if (decoded is! Map) {
        throw const FormatException('The Laravel API returned a non-object response.');
      }

      final result = Map<String, dynamic>.from(decoded);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = result['error'];
        final errorMap = error is Map
            ? Map<String, dynamic>.from(error)
            : <String, dynamic>{};
        throw ApiException(
          response.statusCode,
          (errorMap['code'] ?? 'api_request_failed').toString(),
          (errorMap['message'] ?? 'Permintaan ke server ditolak.').toString(),
        );
      }
      return result;
    } on SocketException {
      throw const ApiTransportException('Tidak dapat terhubung ke server. Periksa jaringan.');
    } on TimeoutException {
      throw const ApiTransportException('Server tidak merespons dalam batas waktu.');
    } on HttpException {
      throw const ApiTransportException('Koneksi ke server terputus.');
    }
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}
