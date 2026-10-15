import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CentralApiException implements Exception {
  final String message;
  final int? statusCode;

  const CentralApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Authenticated client for the Laravel Central API. No Supabase client,
/// public database credential, or client-side tenant table access is used.
class CentralApiClient {
  static const String _tokenKey = 'central_api.access_token';

  final String baseUrl;
  final SharedPreferences preferences;
  final FlutterSecureStorage secureStorage;
  final http.Client _http;
  String? _cachedToken;

  CentralApiClient({
    required this.baseUrl,
    required this.preferences,
    required this.secureStorage,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  bool get hasSession => (_token ?? '').isNotEmpty;

  String? get _token => _cachedToken;

  Future<void> hydrateSession() async {
    // Remove tokens written by earlier builds before reading the secure vault.
    await preferences.remove(_tokenKey);
    final token = (await secureStorage.read(key: _tokenKey))?.trim();
    _cachedToken = token == null || token.isEmpty ? null : token;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (normalized.isEmpty) {
      throw const CentralApiException('CENTRAL_API_BASE_URL belum dikonfigurasi.');
    }
    return Uri.parse('$normalized$path').replace(queryParameters: query);
  }

  Future<void> signIn({required String email, required String password}) async {
    final response = await _http
        .post(
          _uri('/api/v1/auth/login'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'email': email.trim(), 'password': password}),
        )
        .timeout(const Duration(seconds: 20));
    final body = _decodeResponse(response);
    final token = body['token'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        token is! String ||
        token.isEmpty) {
      throw CentralApiException(
        _errorMessage(body, 'Login ditolak oleh Laravel Central API.'),
        statusCode: response.statusCode,
      );
    }
    // Publish an authenticated session only after secure persistence succeeds.
    await preferences.remove(_tokenKey);
    await secureStorage.write(key: _tokenKey, value: token);
    final stored = await secureStorage.read(key: _tokenKey);
    if (stored != token) {
      await secureStorage.delete(key: _tokenKey);
      throw const CentralApiException(
        'Token tidak dapat diverifikasi pada secure storage.',
      );
    }
    _cachedToken = token;
  }

  Future<void> signOut() async {
    final token = _token;
    try {
      if (token != null && token.isNotEmpty) {
        await _http
            .post(
              _uri('/api/v1/auth/logout'),
              headers: _headers(token),
            )
            .timeout(const Duration(seconds: 10));
      }
    } finally {
      _cachedToken = null;
      try {
        await secureStorage.delete(key: _tokenKey);
      } finally {
        await preferences.remove(_tokenKey);
      }
    }
  }

  Future<Map<String, dynamic>> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final token = _token;
    if (token == null || token.isEmpty) {
      throw const CentralApiException(
        'Sesi Laravel tidak tersedia. Silakan masuk kembali.',
      );
    }
    final response = await _http
        .get(
          _uri('/api/v1/effective-config', {
            'tenant_id': tenantId,
            'device_id': deviceId,
            'service': service,
          }),
          headers: _headers(token),
        )
        .timeout(const Duration(seconds: 20));
    final body = _decodeResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CentralApiException(
        _errorMessage(body, 'Konfigurasi ditolak oleh Laravel Central API.'),
        statusCode: response.statusCode,
      );
    }
    final value = body['effective_config'] ?? body;
    if (value is Map) return Map<String, dynamic>.from(value);
    throw const CentralApiException('Respons konfigurasi tidak valid.');
  }

  Map<String, String> _headers(String token) => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.body.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      // The endpoint may return an HTML proxy error; never display raw HTML.
    }
    return <String, dynamic>{};
  }

  static String _errorMessage(
    Map<String, dynamic> body,
    String fallback,
  ) {
    final message = body['message'];
    return message is String && message.trim().isNotEmpty
        ? message
        : fallback;
  }

  void close() => _http.close();
}
