import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('creates a stable random 64-character lowercase hexadecimal device ID', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    final generated = await store.ensureDeviceId();

    expect(generated, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(store.deviceId, generated);
    expect(await store.ensureDeviceId(), generated);
  });

  test('retains a previously valid device ID', () async {
    final existing = List<String>.filled(64, 'a').join();
    SharedPreferences.setMockInitialValues(<String, Object>{'p6.device_id': existing});
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    expect(await store.ensureDeviceId(), existing);
    expect(store.deviceId, existing);
  });

  test('replaces a legacy non-API device ID with a valid ID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'p6.device_id': 'legacy-device-id'});
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    final generated = await store.ensureDeviceId();

    expect(generated, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(store.deviceId, generated);
  });
}
