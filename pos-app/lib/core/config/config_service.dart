import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'central_api_client.dart';

class TenantFeatures {
  final bool pos;
  final bool akuntansi;

  const TenantFeatures({required this.pos, required this.akuntansi});

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
    if (config.containsKey('pos_enabled') ||
        config.containsKey('akuntansi_enabled')) {
      return TenantFeatures(
        pos: config['pos_enabled'] == true,
        akuntansi: config['akuntansi_enabled'] == true,
      );
    }
    throw const FormatException(
      'Effective configuration does not contain tenant feature flags',
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

  const EffectiveConfigResult({required this.value, required this.fromCache});
}

class ConfigService {
  final CentralApiClient _client;
  final SharedPreferences _preferences;

  ConfigService(this._client, this._preferences);

  /// True only when a Laravel API access token was issued after login.
  bool get hasAuthenticatedSession => _client.hasSession;

  Future<EffectiveConfigResult> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final cacheKey = _effectiveCacheKey(tenantId, deviceId, service);
    if (!hasAuthenticatedSession) {
      throw StateError(
        'A Laravel Central API login is required for effective configuration.',
      );
    }

    try {
      final effective = await _client.getEffectiveConfig(
        tenantId: tenantId,
        deviceId: deviceId,
        service: service,
      );
      await _preferences.setString(cacheKey, jsonEncode(effective));
      return EffectiveConfigResult(value: effective, fromCache: false);
    } catch (_) {
      final cached = _preferences.getString(cacheKey);
      if (cached == null) rethrow;
      return EffectiveConfigResult(
        value: _asJsonMap(jsonDecode(cached)),
        fromCache: true,
      );
    }
  }

  /// Merge layers in the only supported order:
  /// GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE.
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

  static String _effectiveCacheKey(
    String tenantId,
    String deviceId,
    String service,
  ) => 'central.effective.$tenantId.$deviceId.$service';
}
