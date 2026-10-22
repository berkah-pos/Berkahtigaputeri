import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class AppIdentityStore {
  static const String defaultTenantId = '';
  static const String defaultDeviceId = '';

  static const String _tenantKey = 'p6.tenant_id';
  static const String _deviceKey = 'p6.device_id';
  static final RegExp _validDeviceId =
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{15,149}$');

  final SharedPreferences _preferences;
  Future<String>? _creatingDeviceId;

  AppIdentityStore(this._preferences);

  String get tenantId =>
      _preferences.getString(_tenantKey) ?? defaultTenantId;

  String get deviceId =>
      _preferences.getString(_deviceKey) ?? defaultDeviceId;

  /// Creates a stable opaque installation identifier when one is not stored.
  /// The identifier itself is not an authentication secret.
  Future<String> ensureDeviceId() {
    final existing = deviceId.trim();
    if (_validDeviceId.hasMatch(existing)) {
      return Future<String>.value(existing);
    }
    return _creatingDeviceId ??= _replaceInvalidOrMissingDeviceId();
  }

  Future<String> _replaceInvalidOrMissingDeviceId() async {
    await _preferences.remove(_deviceKey);
    return _generateAndStoreDeviceId();
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

  /// Rotates the installation ID after the server has explicitly revoked
  /// the previous ID. The replacement is still untrusted until an administrator
  /// approves its new enrollment request.
  Future<String> rotateDeviceId() async {
    final pending = _creatingDeviceId;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed pending generation does not block rotation.
      }
    }

    _creatingDeviceId = null;
    await _preferences.remove(_deviceKey);
    return ensureDeviceId();
  }

  Future<void> setTenantId(String tenantId) async {
    await _preferences.setString(_tenantKey, tenantId);
  }

  Future<void> setDeviceId(String deviceId) async {
    final normalized = deviceId.trim();
    if (!_validDeviceId.hasMatch(normalized)) {
      throw ArgumentError.value(
        deviceId,
        'deviceId',
        'Must be 16–150 safe characters.',
      );
    }

    // Wait for initial generation so its final write cannot override this ID.
    final pending = _creatingDeviceId;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // A failed generated ID does not block explicit configuration.
      }
    }
    await _preferences.setString(_deviceKey, normalized);
    _creatingDeviceId = null;
  }
}
