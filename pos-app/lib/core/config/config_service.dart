import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/laravel_api_client.dart';

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

  factory TenantFeatures.fromEffectiveConfig(Map<String, dynamic> config) {
    final rawFeatures = config['features'];
    if (rawFeatures is Map) {
      return TenantFeatures.fromJson(Map<String, dynamic>.from(rawFeatures));
    }
    if (config.containsKey('pos_enabled') || config.containsKey('akuntansi_enabled')) {
      return TenantFeatures(
        pos: config['pos_enabled'] == true,
        akuntansi: config['akuntansi_enabled'] == true,
      );
    }
    throw const FormatException('Effective configuration does not contain tenant feature flags.');
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
  final LaravelApiClient _client;
  final SharedPreferences _preferences;

  ConfigService(this._client, this._preferences);

  bool get hasAuthenticatedSession => _client.hasAuthenticatedSession;

  Future<EffectiveConfigResult> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final normalizedTenant = tenantId.trim();
    final normalizedDevice = deviceId.trim();
    if (normalizedTenant.isEmpty || normalizedDevice.isEmpty) {
      throw const ApiException(
        403,
        'device_not_authorized',
        'Tenant dan perangkat belum terdaftar.',
      );
    }
    if (!hasAuthenticatedSession) {
      throw const ApiException(401, 'unauthenticated', 'Silakan login kembali.');
    }

    final cacheKey = _effectiveCacheKey(normalizedTenant, normalizedDevice, service);
    late final Map<String, dynamic> response;
    try {
      response = await _client.getEffectiveConfig(
        deviceId: normalizedDevice,
        service: service,
      );
    } on ApiTransportException {
      // Cache is only an offline fallback for a previously server-issued
      // envelope bound to this exact tenant/device/service tuple. HTTP 401,
      // 403, 503 and other server decisions never fall back to cached access.
      final cachedRaw = _preferences.getString(cacheKey);
      if (cachedRaw == null) rethrow;

      final cached = _asJsonMap(jsonDecode(cachedRaw));
      if (cached['tenant_id']?.toString() != normalizedTenant ||
          cached['device_id']?.toString() != normalizedDevice ||
          cached['service']?.toString() != service ||
          cached['config'] is! Map) {
        await _preferences.remove(cacheKey);
        rethrow;
      }

      return EffectiveConfigResult(
        value: Map<String, dynamic>.from(cached['config'] as Map),
        fromCache: true,
      );
    }

    // The server derives tenant identity from the token. The local tenant ID
    // is only used here to prevent displaying a stale cache for another scope.
    if (response['tenant_id']?.toString() != normalizedTenant ||
        response['device_id']?.toString() != normalizedDevice ||
        response['service']?.toString() != service) {
      throw const ApiException(
        403,
        'config_scope_mismatch',
        'Server mengembalikan scope konfigurasi yang tidak cocok.',
      );
    }

    final config = _asJsonMap(response['config']);
    final envelope = <String, dynamic>{
      'tenant_id': normalizedTenant,
      'device_id': normalizedDevice,
      'service': service,
      'config': config,
      'versions': response['versions'],
      'sha256': response['sha256'],
    };
    await _preferences.setString(cacheKey, jsonEncode(envelope));
    return EffectiveConfigResult(value: config, fromCache: false);
  }

  /// Pure fixture helper. Production resolution is exclusively server-side.
  static Map<String, dynamic> mergeLayers(
    Iterable<Map<String, dynamic>> layers,
  ) {
    final merged = <String, dynamic>{};
    for (final layer in layers) {
      merged.addAll(layer);
    }
    return merged;
  }

  static Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    }
    throw const FormatException('Expected JSON object');
  }

  static String _effectiveCacheKey(String tenantId, String deviceId, String service) =>
      'berkahpos.effective.$tenantId.$deviceId.$service';
}
