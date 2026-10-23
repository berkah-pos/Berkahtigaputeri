import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

abstract interface class SecureVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureVault implements SecureVault {
  const FlutterSecureVault([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class TenantChoice {
  const TenantChoice({required this.id, required this.label});

  final String id;
  final String label;

  factory TenantChoice.fromJson(Map<String, dynamic> json) => TenantChoice(
        id: json['tenant_id'] as String? ?? '',
        label: json['label'] as String? ?? json['tenant_id'] as String? ?? '',
      );
}

class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.userName,
    required this.email,
    required this.tenantId,
    required this.deviceId,
    required this.deviceStatus,
    this.expiresAt,
  });

  final String token;
  final String userId;
  final String userName;
  final String email;
  final String tenantId;
  final String deviceId;
  final String deviceStatus;
  final DateTime? expiresAt;

  bool get deviceIsActive => deviceStatus == 'active';
  bool get deviceNeedsApproval =>
      deviceStatus == 'pending' || deviceStatus == 'unregistered';
}

class EffectiveConfigSnapshot {
  const EffectiveConfigSnapshot({
    required this.tenantId,
    required this.deviceId,
    required this.service,
    required this.version,
    required this.versions,
    required this.hash,
    required this.config,
  });

  static const List<String> _layerOrder = <String>[
    'global', 'template', 'tenant', 'service', 'device',
  ];

  final String tenantId;
  final String deviceId;
  final String service;
  final int version;
  final Map<String, int> versions;
  final String hash;
  final Map<String, dynamic> config;

  factory EffectiveConfigSnapshot.fromJson(
    Map<String, dynamic> json, {
    required String expectedService,
  }) {
    final tenantId = json['tenant_id'];
    final deviceId = json['device_id'];
    final service = json['service'];
    final version = json['version'];
    final hash = json['hash'];
    final rawVersions = json['versions'];
    final rawConfig = json['config'];

    if (tenantId is! String || tenantId.isEmpty ||
        deviceId is! String || deviceId.isEmpty ||
        service != expectedService ||
        version is! int || version < 1 ||
        hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        rawVersions is! Map || rawConfig is! Map) {
      throw const FormatException('Effective configuration response is malformed.');
    }

    if (rawVersions.length != _layerOrder.length) {
      throw const FormatException('Effective configuration version vector is incomplete.');
    }
    final versions = <String, int>{};
    for (final layer in _layerOrder) {
      final layerVersion = rawVersions[layer];
      if (layerVersion is! int || layerVersion < 1) {
        throw const FormatException('Effective configuration version vector is invalid.');
      }
      versions[layer] = layerVersion;
    }

    return EffectiveConfigSnapshot(
      tenantId: tenantId,
      deviceId: deviceId,
      service: service as String,
      version: version,
      versions: versions,
      hash: hash,
      config: Map<String, dynamic>.from(rawConfig),
    );
  }
}

class AuthFailure implements Exception {
  const AuthFailure({
    required this.message,
    required this.code,
    this.memberships = const <TenantChoice>[],
    this.statusCode,
  });

  final String message;
  final String code;
  final List<TenantChoice> memberships;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Laravel Central API identity client. Only server-issued sessions are used
/// for cloud identity. The install-scoped device secret is held in platform
/// secure storage; the server stores only its SHA-256 digest.
class LaravelAuthService {
  LaravelAuthService({
    required String baseUrl,
    required SecureVault vault,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 12),
  })  : _baseUri = _parseBaseUrl(baseUrl),
        _vault = vault,
        _client = client ?? http.Client() {
    final trimmed = baseUrl.trim();
    configurationMessage = trimmed.isEmpty
        ? 'BERKAH_API_BASE_URL belum dikonfigurasi. Gunakan mode lokal sampai API Laravel HTTPS tersedia.'
        : _baseUri == null
            ? 'Alamat API harus berupa URL HTTPS yang valid.'
            : null;
  }

  static const String _tokenKey = 'berkah.auth.laravel.access_token';
  static const String _deviceSecretPrefix = 'berkah.device.secret.';
  final Uri? _baseUri;
  final SecureVault _vault;
  final http.Client _client;
  final Duration requestTimeout;
  late final String? configurationMessage;

  bool get isConfigured => _baseUri != null;

  static Uri? _parseBaseUrl(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasFragment) {
      return null;
    }
    return parsed.toString().endsWith('/')
        ? parsed
        : Uri.parse(parsed.toString() + '/');
  }

  Future<String> deviceSecretFor(String deviceId) async {
    final key = _deviceSecretPrefix + deviceId;
    final existing = await _vault.read(key);
    if (existing != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(existing)) {
      return existing;
    }

    final random = Random.secure();
    final secret = List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _vault.write(key, secret);
    return secret;
  }

  Future<AuthSession> login({
    required String email,
    required String password,
    required String deviceId,
    String? tenantId,
  }) async {
    if (!isConfigured) {
      throw AuthFailure(
        message: configurationMessage ?? 'API Laravel belum dikonfigurasi.',
        code: 'api_not_configured',
      );
    }

    final secret = await deviceSecretFor(deviceId);
    final previousToken = await _vault.read(_tokenKey);
    if (previousToken != null && previousToken.isNotEmpty) {
      try {
        await _request('POST', 'auth/logout', token: previousToken);
      } catch (_) {
        // Local credential deletion must happen even if the server is offline.
      }
      await _vault.delete(_tokenKey);
    }

    final response = await _request(
      'POST',
      'auth/login',
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'tenant_id': tenantId,
        'device_id': deviceId,
        'device_secret': secret,
      },
    );

    final token = response.data['access_token'] as String?;
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        message: 'Server tidak mengembalikan sesi yang valid.',
        code: 'invalid_auth_response',
      );
    }
    await _vault.write(_tokenKey, token);

    final session = _sessionFrom(response.data, token);
    if (session.deviceIsActive) return session;

    if (!session.deviceNeedsApproval) {
      await _vault.delete(_tokenKey);
      throw const AuthFailure(
        message: 'Status perangkat tidak diizinkan.',
        code: 'device_not_usable',
      );
    }

    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : Platform.isMacOS
                ? 'macos'
                : Platform.isWindows
                    ? 'windows'
                    : Platform.isLinux
                        ? 'linux'
                        : 'other';

    try {
      final enrollment = await _request(
        'POST',
        'devices/enroll',
        token: token,
        body: <String, dynamic>{
          'device_secret': secret,
          'device_name': 'Berkah POS ($platform)',
          'platform': platform,
        },
      );
      return AuthSession(
        token: token,
        userId: session.userId,
        userName: session.userName,
        email: session.email,
        tenantId: session.tenantId,
        deviceId: session.deviceId,
        deviceStatus: enrollment.data['status'] as String? ?? 'pending',
        expiresAt: session.expiresAt,
      );
    } on AuthFailure catch (failure) {
      if (failure.code == 'device_approval_requires_signin' ||
          failure.code == 'device_revoked' ||
          failure.code == 'device_identity_conflict') {
        await _vault.delete(_tokenKey);
      }
      rethrow;
    }
  }

  /// Fetches one service configuration through the authenticated Laravel API.
  /// Tenant and device context are derived by the server from the bearer token;
  /// this client deliberately does not send a client-selected tenant identifier.
  Future<EffectiveConfigSnapshot> fetchEffectiveConfig({
    required String service,
  }) async {
    final normalizedService = service.trim().toLowerCase();
    if (normalizedService != 'pos' && normalizedService != 'akuntansi') {
      throw const AuthFailure(
        message: 'Layanan konfigurasi tidak valid.',
        code: 'invalid_service',
        statusCode: 422,
      );
    }

    final token = await _vault.read(_tokenKey);
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        message: 'Sesi cloud tidak tersedia. Masuk kembali untuk melanjutkan.',
        code: 'session_missing',
        statusCode: 401,
      );
    }

    final response = await _request(
      'GET',
      'config/$normalizedService',
      token: token,
    );
    final rawSnapshot = response.data['data'];
    if (rawSnapshot is! Map) {
      throw const AuthFailure(
        message: 'Server tidak mengembalikan konfigurasi efektif yang valid.',
        code: 'invalid_config_response',
        statusCode: 502,
      );
    }

    try {
      return EffectiveConfigSnapshot.fromJson(
        Map<String, dynamic>.from(rawSnapshot),
        expectedService: normalizedService,
      );
    } on FormatException {
      throw const AuthFailure(
        message: 'Konfigurasi server tidak dapat diverifikasi.',
        code: 'invalid_config_response',
        statusCode: 502,
      );
    }
  }

  /// Restores only a server-verified session. Network errors never enable
  /// cloud mode and do not erase the token, allowing a retry when back online.
  Future<AuthSession?> restoreSession() async {
    if (!isConfigured) return null;
    final token = await _vault.read(_tokenKey);
    if (token == null || token.isEmpty) return null;

    try {
      final response = await _request('GET', 'auth/me', token: token);
      final session = _sessionFrom(response.data, token);
      if (session.tenantId.isEmpty || session.deviceId.isEmpty) {
        await _vault.delete(_tokenKey);
        return null;
      }
      return session;
    } on AuthFailure catch (failure) {
      if (failure.statusCode == 401 ||
          failure.statusCode == 403 ||
          failure.code == 'invalid_auth_response') {
        await _vault.delete(_tokenKey);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    final token = await _vault.read(_tokenKey);
    try {
      if (isConfigured && token != null && token.isNotEmpty) {
        await _request('POST', 'auth/logout', token: token);
      }
    } finally {
      await _vault.delete(_tokenKey);
    }
  }

  /// Sends one durable event using the current bearer token. Tenant and device
  /// identity are intentionally derived by the Laravel middleware, not this body.
  Future<Map<String, dynamic>> syncOutboxEvent({
    required Map<String, dynamic> event,
    String appVersion = 'unknown',
  }) async {
    final token = await _vault.read(_tokenKey);
    if (token == null || token.isEmpty) {
      throw const AuthFailure(
        message: 'Sesi cloud tidak tersedia. Masuk kembali untuk melanjutkan.',
        code: 'session_missing',
        statusCode: 401,
      );
    }
    final response = await _request(
      'POST',
      'sync',
      token: token,
      body: <String, dynamic>{
        'app_version': appVersion,
        'events': <Map<String, dynamic>>[event],
      },
    );
    return response.data;
  }

  AuthSession _sessionFrom(Map<String, dynamic> data, String token) {
    final rawUser = data['user'];
    final user = rawUser is Map
        ? Map<String, dynamic>.from(rawUser)
        : <String, dynamic>{};
    final expires = data['expires_at'] as String?;
    return AuthSession(
      token: token,
      userId: user['id']?.toString() ?? '',
      userName: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
      tenantId: data['tenant_id'] as String? ?? '',
      deviceId: data['device_id'] as String? ?? '',
      deviceStatus: data['device_status'] as String? ?? 'unregistered',
      expiresAt: expires == null ? null : DateTime.tryParse(expires),
    );
  }

  Future<_ApiResult> _request(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final base = _baseUri;
    if (base == null) {
      throw AuthFailure(
        message: configurationMessage ?? 'API Laravel belum dikonfigurasi.',
        code: 'api_not_configured',
      );
    }

    final uri = base.resolve('api/v1/$endpoint');
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    late final http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(requestTimeout);
          break;
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(requestTimeout);
          break;
        default:
          throw StateError('Unsupported API method.');
      }
    } on TimeoutException {
      throw const AuthFailure(
        message: 'Server terlalu lama merespons. Periksa koneksi lalu coba lagi.',
        code: 'network_timeout',
      );
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        message: 'Tidak dapat menghubungi API Berkah POS. Sesi cloud tidak diaktifkan.',
        code: 'network_error',
      );
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } catch (_) {
      data = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final rawError = data['error'];
      final errorBody = rawError is Map
          ? Map<String, dynamic>.from(rawError)
          : const <String, dynamic>{};
      final message = data['message'] is String
          ? data['message'] as String
          : errorBody['message'] as String?;
      final code = data['code'] is String
          ? data['code'] as String
          : errorBody['code'] as String?;
      final membershipsRaw = data['memberships'];
      final memberships = membershipsRaw is List
          ? membershipsRaw
              .whereType<Map>()
              .map((value) => TenantChoice.fromJson(Map<String, dynamic>.from(value)))
              .where((choice) => choice.id.isNotEmpty)
              .toList(growable: false)
          : const <TenantChoice>[];
      throw AuthFailure(
        message: message ?? 'Permintaan API ditolak.',
        code: code ?? 'http_' + response.statusCode.toString(),
        memberships: memberships,
        statusCode: response.statusCode,
      );
    }

    return _ApiResult(data);
  }
}

class _ApiResult {
  const _ApiResult(this.data);
  final Map<String, dynamic> data;
}
