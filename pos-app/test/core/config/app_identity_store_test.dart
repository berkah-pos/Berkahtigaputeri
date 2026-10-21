import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('generates and persists a stable random per-install device ID', () async {
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    final first = await store.ensureDeviceId();
    final second = await store.ensureDeviceId();
    final restored = AppIdentityStore(preferences);

    expect(first, matches(RegExp(r'^btp_[a-f0-9]{32}$')));
    expect(second, first);
    expect(await restored.ensureDeviceId(), first);
    expect(store.tenantId, isEmpty);
  });

  test('preserves an existing valid operator-provided device ID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'p6.device_id': 'POS_COUNTER_01',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    expect(await store.ensureDeviceId(), 'POS_COUNTER_01');
    expect(store.deviceId, 'POS_COUNTER_01');
  });

  test('replaces an invalid stored device ID with a valid generated ID', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'p6.device_id': 'not a valid / device ID',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = AppIdentityStore(preferences);

    final generated = await store.ensureDeviceId();

    expect(generated, matches(RegExp(r'^btp_[a-f0-9]{32}$')));
    expect(store.deviceId, generated);
  });
}
