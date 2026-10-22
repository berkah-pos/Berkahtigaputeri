import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_identity_store.dart';

typedef JsonObject = Map<String, dynamic>;

abstract interface class AccessTokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class SecureAccessTokenStore implements AccessTokenStore {
  static const String _tokenKey = 'berkahpos.central_api.access_token';

  final FlutterSecureStorage _storage;

  SecureAccessTokenStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

class IdentityApiException implements Exception {
  const IdentityApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details = const <String, dynamic>{},
  });

  final int statusCode;
  final String code;
  final String message;
  final JsonObject details;

  bool get isAuthenticationFailure =>
      statusCode == 401 || statusCode == 403;

  bool get isTransient =>
      statusCode == 0 || statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => '$code ($statusCode): $message';
}

class TenantMembershipInfo {
  const TenantMembershipInfo({
    required this.tenantId,
    required this.role,
    this.templateId = '',
  });

  final String tenantId;
  final String role;
  final String templateId;

  factory TenantMembershipInfo.fromJson(JsonObject value) {
    return TenantMembershipInfo(
      tenantId: value['tenant_id']?.toString() ?? '',
      role: value['role']?.toString() ?? 'member',
      templateId: value['template_id']?.toString() ?? '',
    );
  }

  JsonObject toJson() => <String, dynamic>{
        'tenant_id': tenantId,
        'role': role,
        'template_id': templateId,
      };
}

class IdentitySession {
  const IdentitySession({
    required this.accessToken,
    required this.tokenKind,
    required this.user,
    required this.memberships,
    required this.expiresAt,
    this.device,
  });

  final String accessToken;
  final String tokenKind;
  final JsonObject user;
  final List<TenantMembershipInfo> memberships;
  final DateTime? expiresAt;
  final JsonObject? device;

  bool get isDeviceSession => tokenKind == 'device';
  bool get isPlatformAdmin => tokenKind == 'platform_admin';
  String get userId => user['id']?.toString() ?? '';
  String get email => user['email']?.toString() ?? '';
  String get name => user['name']?.toString() ?? '';
  String get tenantId => device?['tenant_id']?.toString() ?? '';
  String get deviceId => device?['device_id']?.toString() ?? '';

  factory IdentitySession.fromServer({
    required String accessToken,
    required JsonObject payload,
  }) {
    final rawUser = payload['user'];
    if (rawUser is! Map) {
      throw const FormatException('Identity response omitted the user object.');
    }

    final rawMemberships = payload['memberships'];
    final memberships = <TenantMembershipInfo>[];
    if (rawMemberships is List) {
      for (final entry in rawMemberships) {
        if (entry is Map) {
          memberships.add(
            TenantMembershipInfo.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }

    final rawDevice = payload['device'];
    return IdentitySession(
      accessToken: accessToken,
      tokenKind: payload['token_kind']?.toString() ?? 'unbound',
      user: Map<String, dynamic>.from(rawUser),
      memberships: List<TenantMembershipInfo>.unmodifiable(memberships),
      expiresAt: DateTime.tryParse(
        payload['token_expires_at']?.toString() ?? '',
      ),
      device: rawDevice is Map
          ? Map<String, dynamic>.from(rawDevice)
          : null,
    );
  }
}

enum SignInStatus {
  authenticated,
  devicePendingApproval,
  tenantSelectionRequired,
  emailVerificationRequired,
  failed,
}

class SignInResult {
  const SignInResult({
    required this.status,
    required this.message,
    this.memberships = const <TenantMembershipInfo>[],
  });

  final SignInStatus status;
  final String message;
  final List<TenantMembershipInfo> memberships;

  bool get isAuthenticated => status == SignInStatus.authenticated;
}

class IdentityService {
  IdentityService({
    required String baseUrl,
    required AppIdentityStore identityStore,
    AccessTokenStore? tokenStore,
    http.Client? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUrl),
        _identityStore = identityStore,
        _tokenStore = tokenStore ?? SecureAccessTokenStore(),
        _http = httpClient ?? http.Client();

  static const Duration _requestTimeout = Duration(seconds: 15);

  final Uri _baseUri;
  final AppIdentityStore _identityStore;
  final AccessTokenStore _tokenStore;
  final http.Client _http;

  IdentitySession? currentSession;

  bool get hasAuthenticatedSession => currentSession != null;

  static Uri _normalizeBaseUri(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, 'baseUrl', 'API base URL is required.');
    }

    final parsed = Uri.parse(trimmed.endsWith('/') ? trimmed : '$trimmed/');
    if (!parsed.hasAuthority ||
        (parsed.scheme != 'https' && parsed.scheme != 'http')) {
      throw ArgumentError.value(value, 'baseUrl', 'API URL must be an absolute HTTP(S) URL.');
    }
    if (parsed.scheme != 'https' &&
        parsed.host != 'localhost' &&
        parsed.host != '127.0.0.1' &&
        parsed.host != '10.0.2.2') {
      throw ArgumentError.value(value, 'baseUrl', 'Non-local API endpoints must use HTTPS.');
    }
    return parsed;
  }

  Uri _endpoint(String path) => _baseUri.resolve(path);

  Future<IdentitySession?> restoreSession() async {
    currentSession = null;
    final token = await _tokenStore.read();
    if (token == null || token.trim().isEmpty) {
      await _tokenStore.delete();
      return null;
    }

    try {
      final response = await _http
          .get(
            _endpoint('api/v1/auth/session'),
            headers: _headers(token),
          )
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final payload = _decodeObject(response.body);
        final session = IdentitySession.fromServer(
          accessToken: token,
          payload: payload,
        );
        _validateTenantSession(session);
        currentSession = session;
        await _synchronizeVerifiedIdentity(session);
        return session;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        await _clearLocalSession();
        return null;
      }

      if (response.statusCode >= 500 ||
          response.statusCode == 408 ||
          response.statusCode == 429) {
        throw _apiException(response);
      }

      await _clearLocalSession();
      return null;
    } on IdentityApiException {
      rethrow;
    } on TimeoutException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Cannot verify the saved session because the API did not respond.',
      );
    } on SocketException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Cannot verify the saved session because the API is unreachable.',
      );
    } on http.ClientException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'Cannot verify the saved session because the API is unreachable.',
      );
    } on FormatException {
      await _clearLocalSession();
      rethrow;
    }
  }

  Future<SignInResult> signIn({
    required String email,
    required String password,
    String? tenantId,
  }) async {
    try {
      final deviceId = await _identityStore.ensureDeviceId();
      final payload = <String, dynamic>{
        'email': email.trim(),
        'password': password,
        'device_id': deviceId,
        'device_name': 'Berkah POS Android',
      };
      final selectedTenant = tenantId?.trim() ?? '';
      if (selectedTenant.isNotEmpty) {
        payload['tenant_id'] = selectedTenant;
      }

      final response = await _http
          .post(
            _endpoint('api/v1/auth/login'),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
            },
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);

      final body = _tryDecodeObject(response.body);
      if (response.statusCode == 202 &&
          body?['status'] == 'device_pending_approval') {
        return SignInResult(
          status: SignInStatus.devicePendingApproval,
          message: body?['message']?.toString() ??
              'Perangkat menunggu persetujuan administrator. Belum ada akses cloud yang diberikan.',
        );
      }

      if (response.statusCode != 200) {
        final code = _errorCode(body);
        final message = _errorMessage(body) ??
            'Login gagal. Periksa email, kata sandi, dan status akun.';

        if (code == 'tenant_selection_required') {
          return SignInResult(
            status: SignInStatus.tenantSelectionRequired,
            message: message,
            memberships: _parseMemberships(body?['memberships']),
          );
        }

        if (code == 'email_verification_required') {
          return SignInResult(
            status: SignInStatus.emailVerificationRequired,
            message: message,
          );
        }

        return SignInResult(
          status: SignInStatus.failed,
          message: _safeUserMessage(code, message, response.statusCode),
        );
      }

      final accessToken = body?['access_token']?.toString() ?? '';
      if (accessToken.isEmpty) {
        return const SignInResult(
          status: SignInStatus.failed,
          message: 'Server tidak mengembalikan token akses. Tidak ada sesi yang disimpan.',
        );
      }

      // The platform-admin token belongs to the central admin surface, not a
      // POS terminal. Revoke it instead of ever persisting it in the POS app.
      if (body?['token_kind'] == 'platform_admin') {
        await _revokeUnstoredToken(accessToken);
        return const SignInResult(
          status: SignInStatus.failed,
          message: 'Akun administrator pusat tidak dapat digunakan sebagai sesi kasir. Gunakan akun dengan membership tenant.',
        );
      }

      // A 200 login response is not enough by itself: confirm that the newly
      // issued bearer token still resolves to a live server-verified identity.
      final sessionResponse = await _http
          .get(
            _endpoint('api/v1/auth/session'),
            headers: _headers(accessToken),
          )
          .timeout(_requestTimeout);

      if (sessionResponse.statusCode != 200) {
        await _revokeUnstoredToken(accessToken);
        final failure = sessionResponse.statusCode == 401 ||
                sessionResponse.statusCode == 403
            ? 'Server menolak sesi baru. Periksa membership dan status perangkat.'
            : 'Sesi baru tidak dapat diverifikasi. Tidak ada token yang disimpan pada perangkat.';
        return SignInResult(status: SignInStatus.failed, message: failure);
      }

      final session = IdentitySession.fromServer(
        accessToken: accessToken,
        payload: _decodeObject(sessionResponse.body),
      );
      _validateTenantSession(session);
      await _tokenStore.write(accessToken);
      currentSession = session;
      await _synchronizeVerifiedIdentity(session);

      return const SignInResult(
        status: SignInStatus.authenticated,
        message: 'Login berhasil. Sesi telah diverifikasi oleh server.',
      );
    } on TimeoutException {
      return const SignInResult(
        status: SignInStatus.failed,
        message: 'API tidak merespons. Periksa koneksi lalu coba lagi.',
      );
    } on SocketException {
      return const SignInResult(
        status: SignInStatus.failed,
        message: 'API tidak dapat dijangkau. Periksa koneksi dan alamat API.',
      );
    } on http.ClientException {
      return const SignInResult(
        status: SignInStatus.failed,
        message: 'API tidak dapat dijangkau. Periksa koneksi dan alamat API.',
      );
    } on IdentityApiException catch (error) {
      return SignInResult(
        status: SignInStatus.failed,
        message: error.message,
      );
    } catch (_) {
      return const SignInResult(
        status: SignInStatus.failed,
        message: 'Login tidak dapat diselesaikan. Tidak ada sesi cloud yang diaktifkan.',
      );
    }
  }

  Future<bool> signOut() async {
    final token = await _tokenStore.read();
    var serverRevoked = false;
    try {
      if (token != null && token.trim().isNotEmpty) {
        final response = await _http
            .post(
              _endpoint('api/v1/auth/logout'),
              headers: _headers(token),
            )
            .timeout(_requestTimeout);
        serverRevoked =
            response.statusCode == 200 || response.statusCode == 204;
      }
    } on Object {
      // The local session is always removed; network failure must never leave
      // the current UI treating the cached bearer token as authenticated.
      serverRevoked = false;
    } finally {
      await _clearLocalSession();
    }
    return serverRevoked;
  }

  Future<void> requestEmailVerification(String email) async {
    final response = await _postPublic(
      'api/v1/auth/email/verification-notification',
      <String, dynamic>{'email': email.trim()},
    );
    if (response.statusCode != 202) {
      throw _apiException(response);
    }
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await _postPublic(
      'api/v1/auth/password/forgot',
      <String, dynamic>{'email': email.trim()},
    );
    if (response.statusCode != 202) {
      throw _apiException(response);
    }
  }

  Future<JsonObject> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final session = currentSession;
    if (session == null || !session.isDeviceSession) {
      throw const IdentityApiException(
        statusCode: 401,
        code: 'authenticated_device_required',
        message: 'A server-verified device session is required.',
      );
    }
    if (tenantId != session.tenantId || deviceId != session.deviceId) {
      throw const IdentityApiException(
        statusCode: 403,
        code: 'identity_context_mismatch',
        message: 'Local tenant/device values do not match the server-verified session.',
      );
    }
    if (service != 'pos' && service != 'akuntansi') {
      throw const IdentityApiException(
        statusCode: 422,
        code: 'invalid_service',
        message: 'Service must be exactly pos or akuntansi.',
      );
    }

    final response = await _http
        .get(
          _endpoint('api/v1/config/$service'),
          headers: <String, String>{
            ..._headers(session.accessToken),
            'X-Device-ID': session.deviceId,
          },
        )
        .timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw _apiException(response);
    }

    final payload = _decodeObject(response.body);
    final data = payload['data'];
    if (data is! Map) {
      throw const FormatException('Effective configuration response omitted data.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<http.Response> _postPublic(
    String path,
    JsonObject payload,
  ) async {
    try {
      return await _http
          .post(
            _endpoint(path),
            headers: const <String, String>{
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Cache-Control': 'no-store',
            },
            body: jsonEncode(payload),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'API tidak merespons. Coba kembali saat koneksi tersedia.',
      );
    } on SocketException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'API tidak dapat dijangkau.',
      );
    } on http.ClientException {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'network_unavailable',
        message: 'API tidak dapat dijangkau.',
      );
    }
  }

  Future<void> _revokeUnstoredToken(String token) async {
    try {
      await _http
          .post(
            _endpoint('api/v1/auth/logout'),
            headers: _headers(token),
          )
          .timeout(const Duration(seconds: 5));
    } on Object {
      // Token is intentionally not persisted; it will expire if revocation
      // cannot reach the server.
    }
  }

  Future<void> _synchronizeVerifiedIdentity(IdentitySession session) async {
    if (session.isDeviceSession &&
        session.tenantId.isNotEmpty &&
        session.deviceId.isNotEmpty) {
      await _identityStore.setTenantId(session.tenantId);
      await _identityStore.setDeviceId(session.deviceId);
    } else {
      await _identityStore.setTenantId('');
    }
  }

  Future<void> _clearLocalSession() async {
    currentSession = null;
    await _tokenStore.delete();
    await _identityStore.setTenantId('');
  }

  void _validateTenantSession(IdentitySession session) {
    // This client is the POS terminal, never the central admin panel. Requiring
    // a server-confirmed tenant/device token blocks privilege confusion.
    if (!session.isDeviceSession ||
        session.tenantId.isEmpty ||
        session.deviceId.isEmpty ||
        session.memberships.every((membership) =>
            membership.tenantId != session.tenantId)) {
      throw const FormatException(
        'The server session does not contain a verified tenant/device membership.',
      );
    }
  }

  Map<String, String> _headers(String token) => <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'Cache-Control': 'no-store',
      };

  JsonObject _decodeObject(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object from the Central API.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  JsonObject? _tryDecodeObject(String body) {
    try {
      return _decodeObject(body);
    } on Object {
      return null;
    }
  }

  IdentityApiException _apiException(http.Response response) {
    final payload = _tryDecodeObject(response.body);
    return IdentityApiException(
      statusCode: response.statusCode,
      code: _errorCode(payload),
      message: _errorMessage(payload) ?? 'Central API request failed.',
      details: payload ?? const <String, dynamic>{},
    );
  }

  String _errorCode(JsonObject? body) {
    if (body == null) return 'api_error';
    final error = body['error'];
    if (error is Map) {
      return error['code']?.toString() ?? 'api_error';
    }
    return error?.toString() ?? 'api_error';
  }

  String? _errorMessage(JsonObject? body) {
    if (body == null) return null;
    final error = body['error'];
    if (error is Map && error['message'] is String) {
      return error['message'] as String;
    }
    return body['message'] is String ? body['message'] as String : null;
  }

  String _safeUserMessage(String code, String message, int statusCode) {
    if (statusCode == 401 || code == 'invalid_credentials') {
      return 'Login gagal. Periksa email dan kata sandi.';
    }
    if (statusCode == 429) {
      return 'Terlalu banyak percobaan. Tunggu beberapa saat sebelum mencoba lagi.';
    }
    return message;
  }

  List<TenantMembershipInfo> _parseMemberships(dynamic values) {
    if (values is! List) return const <TenantMembershipInfo>[];
    return List<TenantMembershipInfo>.unmodifiable(
      values
          .whereType<Map>()
          .map((value) => TenantMembershipInfo.fromJson(
                Map<String, dynamic>.from(value),
              )),
    );
  }

  void close() => _http.close();
}
