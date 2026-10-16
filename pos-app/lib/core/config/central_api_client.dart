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

/// Strict, typed representation of the complete Laravel effective-config envelope.
///
/// Config values and scope/version metadata travel together into the durable cache.
/// The caller's expected scope is checked before a response can be accepted.
class EffectiveConfigResponse {
  EffectiveConfigResponse({
    required this.effectiveConfig,
    required this.tenantId,
    required this.deviceId,
    required this.service,
    required this.effectiveVersion,
    required this.configHash,
    required this.scopedHash,
    required this.layerVersions,
    required this.meta,
  });

  final Map<String, dynamic> effectiveConfig;
  final String tenantId;
  final String deviceId;
  final String service;
  final String effectiveVersion;
  final String configHash;
  final String scopedHash;
  final Map<String, int> layerVersions;
  final Map<String, dynamic> meta;

  String get effectiveRevision => meta['effective_revision'] as String;
  String get versionVector => meta['version_vector'] as String;
  bool get deviceConfigMissing => meta['device_config_missing'] as bool;
  Map<String, dynamic>? get subscription {
    final value = meta['subscription'];
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }

  factory EffectiveConfigResponse.fromJson(
    Map<String, dynamic> json, {
    required String expectedTenantId,
    required String expectedDeviceId,
    required String expectedService,
  }) {
    if (json['tenant_id'] != expectedTenantId ||
        json['device_id'] != expectedDeviceId ||
        json['service'] != expectedService) {
      throw const FormatException(
        'Effective configuration response does not match the requested scope.',
      );
    }

    final rawConfig = json['effective_config'];
    final rawMeta = json['meta'];
    final rawLayerVersions = json['layer_versions'];
    if (rawConfig is! Map || rawMeta is! Map || rawLayerVersions is! Map) {
      throw const FormatException(
        'Effective configuration response is missing its envelope or metadata.',
      );
    }
    final meta = Map<String, dynamic>.from(rawMeta);
    final effectiveVersion = _requiredString(
      json['effective_version'],
      'effective_version',
    );
    final configHash = _requiredHash(json['config_hash'], 'config_hash');
    final scopedHash = _requiredHash(json['scoped_hash'], 'scoped_hash');

    if (meta['effective_version'] != effectiveVersion ||
        meta['config_hash'] != configHash ||
        meta['scoped_hash'] != scopedHash) {
      throw const FormatException(
        'Effective configuration top-level and meta fields disagree.',
      );
    }
    if (meta['effective_revision'] is! String ||
        meta['version_vector'] is! String ||
        meta['device_config_missing'] is! bool ||
        (meta['subscription'] != null && meta['subscription'] is! Map) ||
        meta['layer_versions'] is! Map) {
      throw const FormatException(
        'Effective configuration version metadata is incomplete or invalid.',
      );
    }

    final nestedLayers = Map<String, dynamic>.from(meta['layer_versions'] as Map);
    final layers = <String, int>{};
    for (final name in const <String>[
      'global', 'template', 'tenant', 'service', 'device',
    ]) {
      final topValue = rawLayerVersions[name];
      final nestedValue = nestedLayers[name];
      if (topValue is! num ||
          nestedValue is! num ||
          topValue.toInt() != topValue ||
          nestedValue.toInt() != nestedValue ||
          topValue.toInt() != nestedValue.toInt()) {
        throw FormatException('Invalid or inconsistent layer version: ' + name);
      }
      layers[name] = topValue.toInt();
    }

    return EffectiveConfigResponse(
      effectiveConfig: Map<String, dynamic>.from(rawConfig),
      tenantId: expectedTenantId,
      deviceId: expectedDeviceId,
      service: expectedService,
      effectiveVersion: effectiveVersion,
      configHash: configHash,
      scopedHash: scopedHash,
      layerVersions: layers,
      meta: meta,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'effective_config': effectiveConfig,
        'effective_version': effectiveVersion,
        'config_hash': configHash,
        'scoped_hash': scopedHash,
        'layer_versions': layerVersions,
        'tenant_id': tenantId,
        'device_id': deviceId,
        'service': service,
        'meta': meta,
      };

  static String _requiredString(dynamic value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Missing or invalid ' + field + '.');
    }
    return value;
  }

  static String _requiredHash(dynamic value, String field) {
    if (value is! String || !RegExp(r'^[a-fA-F0-9]{64} No Supabase client,
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

  Future<EffectiveConfigResponse> getEffectiveConfig({
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
    try {
      return EffectiveConfigResponse.fromJson(
        body,
        expectedTenantId: tenantId,
        expectedDeviceId: deviceId,
        expectedService: service,
      );
    } on FormatException {
      // A 2xx response with a missing/incorrect envelope is a contract failure,
      // not a transport outage: ConfigService must not silently serve stale data.
      throw CentralApiException(
        'Respons konfigurasi atau metadata versi/hash tidak valid.',
        statusCode: response.statusCode,
      );
    }
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
).hasMatch(value)) {
      throw FormatException('Missing or invalid SHA-256 ' + field + '.');
    }
    return value.toLowerCase();
  }
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
