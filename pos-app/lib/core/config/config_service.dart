import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'central_api_client.dart';

enum ConfigSourceMode {
  supabase,
  laravel,
  dual;

  static ConfigSourceMode parse(String value) {
    for (final mode in ConfigSourceMode.values) {
      if (mode.name == value.trim().toLowerCase()) return mode;
    }
    throw FormatException('Unsupported CONFIG_SOURCE_MODE: ' + value);
  }
}

/// Temporary bridge contract. Production has no Supabase SDK or raw table
/// adapter; a reviewed bridge may return only server-resolved effective config.
abstract interface class LegacyEffectiveConfigSource {
  Future<Map<String, dynamic>> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  });
}

class ConfigParityException implements Exception {
  const ConfigParityException(this.service);

  final String service;

  @override
  String toString() =>
      'Effective configuration parity failed for service "' +
      service +
      '". Cutover is blocked.';
}

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
  final ConfigSourceMode sourceMode;
  final bool parityVerified;

  const EffectiveConfigResult({
    required this.value,
    required this.fromCache,
    this.sourceMode = ConfigSourceMode.laravel,
    this.parityVerified = false,
  });
}

class _CachedEffectiveConfig {
  const _CachedEffectiveConfig({
    required this.value,
    required this.parityVerified,
  });

  final Map<String, dynamic> value;
  final bool parityVerified;
}

class ConfigService {
  ConfigService(
    this._client,
    this._preferences, {
    this.sourceMode = ConfigSourceMode.laravel,
    this.legacySource,
    this.killSwitch = false,
    this.cacheTtl = const Duration(hours: 6),
    this.dualModeStartedAt,
    this.dualModeDeadline,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final CentralApiClient _client;
  final SharedPreferences _preferences;
  final DateTime Function() _clock;

  final ConfigSourceMode sourceMode;
  final LegacyEffectiveConfigSource? legacySource;

  /// Prevent remote config reads when enabled. Only a fresh cache for the
  /// same tenant, device, service and source mode may be used.
  final bool killSwitch;
  final Duration cacheTtl;
  final DateTime? dualModeStartedAt;
  final DateTime? dualModeDeadline;

  static const String _telemetryKey = 'central.config.transition.last_status';
  static const String _parityMismatchCountKey =
      'central.config.transition.parity_mismatch_count';

  Future<void> _recordTelemetry({
    required String service,
    required String status,
    bool parityVerified = false,
  }) async {
    await _preferences.setString(
      _telemetryKey,
      jsonEncode(<String, dynamic>{
        'source_mode': sourceMode.name,
        'service': service,
        'status': status,
        'parity_verified': parityVerified,
        'observed_at_utc': _clock().toUtc().toIso8601String(),
      }),
    );
    if (status == 'parity_failed') {
      final count = _preferences.getInt(_parityMismatchCountKey) ?? 0;
      await _preferences.setInt(_parityMismatchCountKey, count + 1);
    }
  }

  bool get hasAuthenticatedSession {
    switch (sourceMode) {
      case ConfigSourceMode.supabase:
        return legacySource != null;
      case ConfigSourceMode.laravel:
        return _client.hasSession;
      case ConfigSourceMode.dual:
        return _client.hasSession && legacySource != null;
    }
  }

  Future<EffectiveConfigResult> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    _validateScope(tenantId: tenantId, deviceId: deviceId, service: service);
    // Expiry dominates even a cached-parity result under the emergency kill switch.
    if (sourceMode == ConfigSourceMode.dual) _validateDualWindow();
    final cacheKey = _effectiveCacheKey(tenantId, deviceId, service);

    if (killSwitch) {
      final cached = _readFreshCache(cacheKey);
      if (cached != null) {
        await _recordTelemetry(service: service, status: 'kill_switch_cache');
        return _cacheResult(cached);
      }
      await _recordTelemetry(service: service, status: 'kill_switch_blocked');
      throw StateError(
        'Configuration kill switch is active and no fresh exact-scope cache exists.',
      );
    }

    switch (sourceMode) {
      case ConfigSourceMode.supabase:
        final legacy = legacySource;
        if (legacy == null) {
          await _recordTelemetry(service: service, status: 'legacy_adapter_missing');
          throw StateError(
            'Supabase mode is unavailable: no reviewed legacy effective-config adapter is installed. '
            'Direct client-side table queries are forbidden.',
          );
        }
        final value = await legacy.getEffectiveConfig(
          tenantId: tenantId,
          deviceId: deviceId,
          service: service,
        );
        await _writeCache(cacheKey, value, parityVerified: false);
        await _recordTelemetry(service: service, status: 'legacy_resolved');
        return EffectiveConfigResult(
          value: value,
          fromCache: false,
          sourceMode: sourceMode,
        );

      case ConfigSourceMode.laravel:
        if (!_client.hasSession) {
          throw StateError(
            'A Laravel Central API login is required for effective configuration.',
          );
        }
        try {
          final value = await _client.getEffectiveConfig(
            tenantId: tenantId,
            deviceId: deviceId,
            service: service,
          );
          await _writeCache(cacheKey, value, parityVerified: false);
          await _recordTelemetry(service: service, status: 'laravel_resolved');
          return EffectiveConfigResult(
            value: value,
            fromCache: false,
            sourceMode: sourceMode,
          );
        } catch (error) {
          if (error is CentralApiException &&
              const <int>{401, 402, 403, 422}.contains(error.statusCode)) {
            rethrow;
          }
          final cached = _readFreshCache(cacheKey);
          if (cached == null) rethrow;
          await _recordTelemetry(service: service, status: 'laravel_cache_fallback');
          return _cacheResult(cached);
        }

      case ConfigSourceMode.dual:
        if (!_client.hasSession) {
          throw StateError(
            'Dual-mode parity requires an authenticated Laravel Central API session.',
          );
        }
        final legacy = legacySource;
        if (legacy == null) {
          await _recordTelemetry(service: service, status: 'dual_adapter_missing');
          throw StateError(
            'Dual-mode parity is blocked: no reviewed legacy effective-config adapter is installed.',
          );
        }
        // Neither source may silently win. Source failure or any value mismatch
        // fails closed, leaves the parity cache unchanged and blocks cutover.
        final laravelValue = await _client.getEffectiveConfig(
          tenantId: tenantId,
          deviceId: deviceId,
          service: service,
        );
        final legacyValue = await legacy.getEffectiveConfig(
          tenantId: tenantId,
          deviceId: deviceId,
          service: service,
        );
        if (_canonicalJson(laravelValue) != _canonicalJson(legacyValue)) {
          await _recordTelemetry(service: service, status: 'parity_failed');
          throw ConfigParityException(service);
        }
        await _writeCache(cacheKey, laravelValue, parityVerified: true);
        await _recordTelemetry(
          service: service, status: 'parity_passed', parityVerified: true);

        return EffectiveConfigResult(
          value: laravelValue,
          fromCache: false,
          sourceMode: sourceMode,
          parityVerified: true,
        );
    }
  }

  void _validateDualWindow() {
    final startedAt = dualModeStartedAt?.toUtc();
    final deadline = dualModeDeadline?.toUtc();
    if (startedAt == null || deadline == null) {
      throw StateError(
        'Dual mode requires explicit CONFIG_DUAL_MODE_STARTED_AT_UTC and '
        'CONFIG_DUAL_MODE_DEADLINE_UTC values.',
      );
    }
    if (!deadline.isAfter(startedAt) ||
        deadline.difference(startedAt) > const Duration(days: 28)) {
      throw StateError(
        'Dual-mode deprecation window must be positive and no longer than 28 days.',
      );
    }
    final now = _clock().toUtc();
    if (now.isBefore(startedAt)) {
      throw StateError('Dual mode is not active yet.');
    }
    if (!now.isBefore(deadline)) {
      throw StateError(
        'Dual-mode deprecation deadline passed. Cutover remains blocked pending explicit review.',
      );
    }
  }

  static void _validateScope({
    required String tenantId,
    required String deviceId,
    required String service,
  }) {
    if (tenantId.trim().isEmpty || deviceId.trim().isEmpty) {
      throw ArgumentError('Tenant and device scope are required.');
    }
    if (service != 'pos' && service != 'akuntansi') {
      throw ArgumentError.value(
        service,
        'service',
        'Only one canonical service (pos or akuntansi) may be resolved.',
      );
    }
  }

  Future<void> _writeCache(
    String cacheKey,
    Map<String, dynamic> value, {
    required bool parityVerified,
  }) async {
    await _preferences.setString(
      cacheKey,
      jsonEncode(<String, dynamic>{
        'value': value,
        'cached_at_utc': _clock().toUtc().toIso8601String(),
        'source_mode': sourceMode.name,
        'parity_verified': parityVerified,
      }),
    );
  }

  _CachedEffectiveConfig? _readFreshCache(String cacheKey) {
    final raw = _preferences.getString(cacheKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final envelope = Map<String, dynamic>.from(decoded);
      if (envelope['source_mode'] != sourceMode.name ||
          envelope['cached_at_utc'] is! String ||
          envelope['value'] is! Map) {
        return null;
      }
      final parityVerified = envelope['parity_verified'] == true;
      if (sourceMode == ConfigSourceMode.dual && !parityVerified) {
        return null;
      }
      final cachedAt = DateTime.tryParse(envelope['cached_at_utc'] as String);
      if (cachedAt == null) return null;
      final age = _clock().toUtc().difference(cachedAt.toUtc());
      if (age.isNegative || age > cacheTtl) return null;
      return _CachedEffectiveConfig(
        value: _asJsonMap(envelope['value']),
        parityVerified: parityVerified,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  EffectiveConfigResult _cacheResult(_CachedEffectiveConfig cached) {
    return EffectiveConfigResult(
      value: cached.value,
      fromCache: true,
      sourceMode: sourceMode,
      parityVerified: cached.parityVerified,
    );
  }

  static Map<String, dynamic> mergeLayers(
    Iterable<Map<String, dynamic>> layers,
  ) {
    final merged = <String, dynamic>{};
    for (final layer in layers) {
      merged.addAll(layer);
    }
    return merged;
  }

  static String canonicalJson(Map<String, dynamic> value) =>
      _canonicalJson(value);

  static String _canonicalJson(Map<String, dynamic> value) =>
      jsonEncode(_canonicalize(value));

  static dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) {
      return value.map<dynamic>(_canonicalize).toList();
    }
    return value;
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
  ) =>
      'central.effective.' +
      _cacheSegment(tenantId) + '.' +
      _cacheSegment(deviceId) + '.' +
      _cacheSegment(service);

  // Base64url has no period separator, so arbitrary IDs cannot collide across scopes.
  static String _cacheSegment(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');
}
