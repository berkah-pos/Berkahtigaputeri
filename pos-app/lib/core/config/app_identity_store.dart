import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

class AppIdentityStore {
  static const String defaultTenantId = '';
  static const String defaultDeviceId = '';

  static const String _tenantKey = 'p6.tenant_id';
  static const String _deviceKey = 'p6.device_id';

  final SharedPreferences _preferences;

  AppIdentityStore(this._preferences);

  String get tenantId =>
      _preferences.getString(_tenantKey) ?? defaultTenantId;

  String get deviceId =>
      _preferences.getString(_deviceKey) ?? defaultDeviceId;

  Future<void> setTenantId(String tenantId) async {
    await _preferences.setString(_tenantKey, tenantId);
  }

  /// Returns a stable per-install ID without reading hardware identifiers.
  ///
  /// Registration remains an explicit server operation; generating this local
  /// ID alone grants no access to tenant data or cloud configuration.
  Future<String> ensureDeviceId() async {
    final existing = deviceId.trim();
    if (RegExp(r'^[A-Za-z0-9_.:-]{3,150}$').hasMatch(existing)) {
      return existing;
    }

    final secureRandom = math.Random.secure();
    final suffix = List<String>.generate(
      16,
      (_) => secureRandom.nextInt(256).toRadixString(16).padLeft(2, '0'),
      growable: false,
    ).join();
    final generated = 'btp_$suffix';
    await _preferences.setString(_deviceKey, generated);
    return generated;
  }

  Future<void> setDeviceId(String deviceId) async {
    await _preferences.setString(_deviceKey, deviceId);
  }
}
