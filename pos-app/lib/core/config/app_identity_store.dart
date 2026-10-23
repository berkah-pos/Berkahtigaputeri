import 'dart:math';

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

  /// Creates a per-install identifier accepted by the Laravel identity API.
  /// The identifier is not authentication; the server still verifies the
  /// matching device secret, tenant membership, and administrator approval.
  Future<String> ensureDeviceId() async {
    final current = deviceId;
    if (RegExp(r'^[a-f0-9]{64}  Future<void> setTenantId(String tenantId) async {
    await _preferences.setString(_tenantKey, tenantId);
  }

  Future<void> setDeviceId(String deviceId) async {
    await _preferences.setString(_deviceKey, deviceId);
  }
}
).hasMatch(current)) return current;

    final random = Random.secure();
    final generated = List<int>.generate(32, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await _preferences.setString(_deviceKey, generated);
    return generated;
  }

  Future<void> setTenantId(String tenantId) async {
    await _preferences.setString(_tenantKey, tenantId);
  }

  Future<void> setDeviceId(String deviceId) async {
    await _preferences.setString(_deviceKey, deviceId);
  }
}
