import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppIdentityStore {
  static const String defaultTenantId = '';
  static const String defaultDeviceId = '';

  static const String _tenantKey = 'p6.tenant_id';
  static const String _deviceKey = 'p6.device_id';

  final SharedPreferences _preferences;
  Future<String>? _creatingDeviceId;

  AppIdentityStore(this._preferences);

  String get tenantId =>
      _preferences.getString(_tenantKey) ?? defaultTenantId;

  String get deviceId =>
      _preferences.getString(_deviceKey) ?? defaultDeviceId;

  /// Creates a stable opaque installation identifier when one is not stored.
  ///
  /// The identifier is not an authentication secret. The server still binds
  /// it to a user and tenant and requires explicit device approval.
  Future<String> ensureDeviceId() {
    final existing = deviceId.trim();
    if (existing.isNotEmpty) return Future<String>.value(existing);
    return _creatingDeviceId ??= _generateAndStoreDeviceId();
  }

  Future<String> _generateAndStoreDeviceId() async {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    final uuid = hex.substring(0, 8) + '-' +
        hex.substring(8, 12) + '-' +
        hex.substring(12, 16) + '-' +
        hex.substring(16, 20) + '-' +
        hex.substring(20, 32);
    final generated = 'device-$uuid';
    await _preferences.setString(_deviceKey, generated);
    return generated;
  }

  Future<void> setTenantId(String tenantId) async {
    await _preferences.setString(_tenantKey, tenantId);
  }

  Future<void> setDeviceId(String deviceId) async {
    // If initial ID generation is already underway, let it finish before the
    // explicit assignment so its final write cannot overwrite the chosen ID.
    final pending = _creatingDeviceId;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed initial generation does not prevent explicit configuration.
      }
    }
    await _preferences.setString(_deviceKey, deviceId);
    _creatingDeviceId = null;
  }
}
