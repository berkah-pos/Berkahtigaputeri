import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('ensureDeviceId creates a stable valid installation identifier', () async {
    final identity = AppIdentityStore(await SharedPreferences.getInstance());

    final first = await identity.ensureDeviceId();
    final second = await identity.ensureDeviceId();

    expect(
      first,
      matches(RegExp(
        r'^device-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(second, first);
    expect(identity.deviceId, first);
  });

  test('ensureDeviceId preserves a valid previously assigned ID', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'p6.device_id',
      'device-existing-installation-123',
    );
    final identity = AppIdentityStore(preferences);

    expect(
      await identity.ensureDeviceId(),
      'device-existing-installation-123',
    );
  });

  test('invalid saved ID is replaced with a valid generated ID', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('p6.device_id', '! invalid stored device');
    final identity = AppIdentityStore(preferences);

    final generated = await identity.ensureDeviceId();

    expect(
      generated,
      matches(RegExp(
        r'^device-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(identity.deviceId, generated);
  });

  test('setDeviceId rejects malformed values without overwriting valid ID', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'p6.device_id',
      'device-existing-installation-123',
    );
    final identity = AppIdentityStore(preferences);

    await expectLater(identity.setDeviceId('bad!'), throwsArgumentError);
    expect(identity.deviceId, 'device-existing-installation-123');
  });

  test('concurrent ensureDeviceId calls resolve to the same ID', () async {
    final identity = AppIdentityStore(await SharedPreferences.getInstance());

    final values = await Future.wait(<Future<String>>[
      identity.ensureDeviceId(),
      identity.ensureDeviceId(),
      identity.ensureDeviceId(),
    ]);

    expect(values.toSet().length, 1);
    expect(identity.deviceId, values.first);
  });

  test('explicit device ID assignment wins over in-flight generation', () async {
    final identity = AppIdentityStore(await SharedPreferences.getInstance());
    final generation = identity.ensureDeviceId();

    await identity.setDeviceId('device-explicit-installation-123');
    await generation;

    expect(identity.deviceId, 'device-explicit-installation-123');
    expect(
      await identity.ensureDeviceId(),
      'device-explicit-installation-123',
    );
  });
  
  test('rotateDeviceId replaces a revoked installation ID with a fresh stable ID', () async {
    final preferences = await SharedPreferences.getInstance();
    final identity = AppIdentityStore(preferences);
    await identity.setDeviceId('device-revoked-installation-123');

    final replacement = await identity.rotateDeviceId();

    expect(replacement, isNot('device-revoked-installation-123'));
    expect(
      replacement,
      matches(RegExp(
        r'^device-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )),
    );
    expect(identity.deviceId, replacement);
    expect(await identity.ensureDeviceId(), replacement);
  });

}
