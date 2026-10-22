import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/identity_service.dart';

class TenantFeatures {
  final bool pos;
  final bool akuntansi;

  const TenantFeatures({
    required this.pos,
    required this.akuntansi,
  });

  factory TenantFeatures.fromJson(Map<String, dynamic> json) {
    return TenantFeatures(
      pos: json['pos'] == true,
      akuntansi: json['akuntansi'] == true,
    );
  }

  /// Extracts feature flags from the config object returned by the Central API.
  /// Supports the full resolver envelope as well as a direct config object.
  factory TenantFeatures.fromEffectiveConfig(Map<String, dynamic> response) {
    final rawConfig = response['config'];
    final effective = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig)
        : response;
    final rawFeatures = effective['features'];

    if (rawFeatures is Map) {
      return TenantFeatures.fromJson(Map<String, dynamic>.from(rawFeatures));
    }

    if (effective.containsKey('pos_enabled') ||
        effective.containsKey('akuntansi_enabled')) {
      return TenantFeatures(
        pos: effective['pos_enabled'] == true,
        akuntansi: effective['akuntansi_enabled'] == true,
      );
    }

    throw const FormatException(
      'Effective app_config does not contain tenant feature flags',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pos': pos,
        'akuntansi': akuntansi,
      };
}

class EffectiveConfigResult {
  final Map<String, dynamic> value;
  final bool fromCache;

  const EffectiveConfigResult({
    required this.value,
    required this.fromCache,
  });
}

class ConfigService {
  final IdentityService _identityService;
  final SharedPreferences _preferences;

  ConfigService(this._identityService, this._preferences);

  /// True only after the Central API verifies a live bearer session.
  bool get hasAuthenticatedSession =>
      _identityService.hasAuthenticatedSession;

  Future<EffectiveConfigResult> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final session = _identityService.currentSession;
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
        message: 'Local tenant/device values do not match the verified session.',
      );
    }

    if (service != 'pos' && service != 'akuntansi') {
      throw const IdentityApiException(
        statusCode: 422,
        code: 'invalid_service',
        message: 'Service must be exactly pos or akuntansi.',
      );
    }

    final cacheKey = _effectiveCacheKey(
      session.userId,
      session.tenantId,
      session.deviceId,
      service,
    );

    try {
      final effective = await _identityService.getEffectiveConfig(
        tenantId: session.tenantId,
        deviceId: session.deviceId,
        service: service,
      );
      await _preferences.setString(cacheKey, jsonEncode(effective));
      return EffectiveConfigResult(value: effective, fromCache: false);
    } on IdentityApiException catch (error) {
      // Never mask authorization, enrollment, tenant, subscription, or service
      // denial with old cache data. Only dependency failures can use offline cache.
      if (!_canUseOfflineCache(error.statusCode)) {
        rethrow;
      }
      final cached = _preferences.getString(cacheKey);
      if (cached == null) rethrow;
      return EffectiveConfigResult(
        value: _asJsonMap(jsonDecode(cached)),
        fromCache: true,
      );
    } on TimeoutException {
      return _offlineFallback(cacheKey);
    } on SocketException {
      return _offlineFallback(cacheKey);
    } on http.ClientException {
      return _offlineFallback(cacheKey);
    }
  }

  Future<EffectiveConfigResult> _offlineFallback(String cacheKey) async {
    final cached = _preferences.getString(cacheKey);
    if (cached == null) {
      throw const IdentityApiException(
        statusCode: 0,
        code: 'configuration_unavailable',
        message: 'Configuration is unavailable and no identity-scoped cache exists.',
      );
    }
    return EffectiveConfigResult(
      value: _asJsonMap(jsonDecode(cached)),
      fromCache: true,
    );
  }

  static bool _canUseOfflineCache(int statusCode) =>
      statusCode == 0 || statusCode == 408 || statusCode >= 500;

  static Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }
    throw const FormatException('Expected JSON object');
  }

  static String _effectiveCacheKey(
    String userId,
    String tenantId,
    String deviceId,
    String service,
  ) =>
      'p7.effective.${Uri.encodeComponent(userId)}.'
      '${Uri.encodeComponent(tenantId)}.'
      '${Uri.encodeComponent(deviceId)}.$service';
}
