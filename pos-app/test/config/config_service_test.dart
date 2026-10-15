import 'dart:convert';

import 'package:berkahtigaputeri_pos/core/config/central_api_client.dart';
import 'package:berkahtigaputeri_pos/core/config/config_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late _FakeCentralApiClient api;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    preferences = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 10, 20);
    api = _FakeCentralApiClient(preferences);
  });

  tearDown(() => api.close());

  group('ConfigService feature flag and canonical merge', () {
    test('parses only declared source modes', () {
      expect(ConfigSourceMode.parse('laravel'), ConfigSourceMode.laravel);
      expect(ConfigSourceMode.parse('dual'), ConfigSourceMode.dual);
      expect(ConfigSourceMode.parse('supabase'), ConfigSourceMode.supabase);
      expect(() => ConfigSourceMode.parse('unknown'), throwsFormatException);
    });

    test('GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE overwrites fields', () {
      final merged = ConfigService.mergeLayers(<Map<String, dynamic>>[
        <String, dynamic>{'mdr': 0.1, 'theme': 'global', 'printer': 'none'},
        <String, dynamic>{'mdr': 0.15, 'theme': 'template'},
        <String, dynamic>{'mdr': 0.2, 'theme': 'tenant'},
        <String, dynamic>{'mdr': 0.5, 'qris_enabled': true},
        <String, dynamic>{'printer': 'PDF Preview'},
      ]);
      expect(merged['mdr'], 0.5);
      expect(merged['theme'], 'tenant');
      expect(merged['qris_enabled'], isTrue);
      expect(merged['printer'], 'PDF Preview');
    });

    test('resolves requested services independently', () async {
      api.responses['pos'] = <String, dynamic>{'service': 'pos', 'value': 1};
      api.responses['akuntansi'] = <String, dynamic>{
        'service': 'akuntansi',
        'value': 2,
      };
      final service = ConfigService(api, preferences);
      final pos = await service.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      final accounting = await service.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'akuntansi');
      expect(pos.value['service'], 'pos');
      expect(pos.value['value'], 1);
      expect(accounting.value['service'], 'akuntansi');
      expect(accounting.value['value'], 2);
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'all'),
        throwsArgumentError,
      );
    });

    test('dual mode returns Laravel config only after exact legacy parity', () async {
      final expected = <String, dynamic>{
        'nested': <String, dynamic>{'a': 1, 'b': 2},
        'service': 'pos',
      };
      api.responses['pos'] = expected;
      final legacy = _FakeLegacySource(expected);
      final service = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        legacySource: legacy,
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      final result = await service.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      expect(result.value, expected);
      expect(result.sourceMode, ConfigSourceMode.dual);
      expect(result.parityVerified, isTrue);
      expect(result.fromCache, isFalse);
      expect(legacy.calls, 1);
      expect(preferences.getString('central.config.transition.last_status'),
          contains('parity_passed'));
    });

    test('parity mismatch blocks result and does not cache divergent values', () async {
      api.responses['pos'] = <String, dynamic>{'enabled': true};
      final legacy = _FakeLegacySource(<String, dynamic>{'enabled': false});
      final service = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        legacySource: legacy,
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsA(isA<ConfigParityException>()),
      );
      expect(
        preferences.getKeys().where((key) => key.startsWith('central.effective.')),
        isEmpty,
      );
      expect(preferences.getInt('central.config.transition.parity_mismatch_count'), 1);
      expect(preferences.getString('central.config.transition.last_status'),
          contains('parity_failed'));
    });

    test('dual mode fails closed without a legacy adapter', () async {
      final service = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsStateError,
      );
    });

    test('dual-mode expiry blocks even a fresh parity cache under kill switch',
        () async {
      api.responses['pos'] = <String, dynamic>{'value': 1};
      final legacy = _FakeLegacySource(<String, dynamic>{'value': 1});
      final normal = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        legacySource: legacy,
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      await normal.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      now = DateTime.utc(2026, 11, 12);
      final emergency = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        legacySource: legacy,
        killSwitch: true,
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      await expectLater(
        emergency.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsStateError,
      );
    });

    test('dual mode expires at the explicit deadline', () async {
      now = DateTime.utc(2026, 11, 12);
      final service = ConfigService(
        api, preferences,
        sourceMode: ConfigSourceMode.dual,
        legacySource: _FakeLegacySource(<String, dynamic>{'service': 'pos'}),
        dualModeStartedAt: DateTime.utc(2026, 10, 15),
        dualModeDeadline: DateTime.utc(2026, 11, 12),
        clock: () => now,
      );
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsStateError,
      );
    });

    test('cache keys isolate tenant/device identifiers containing dots', () async {
      api.scopedResponses[jsonEncode(<String>['a.b', 'c', 'pos'])] =
          <String, dynamic>{'scope': 'tenant-dot'};
      api.scopedResponses[jsonEncode(<String>['a', 'b.c', 'pos'])] =
          <String, dynamic>{'scope': 'device-dot'};
      final service = ConfigService(api, preferences);
      final first = await service.getEffectiveConfig(
        tenantId: 'a.b', deviceId: 'c', service: 'pos');
      final second = await service.getEffectiveConfig(
        tenantId: 'a', deviceId: 'b.c', service: 'pos');
      expect(first.value['scope'], 'tenant-dot');
      expect(second.value['scope'], 'device-dot');
      expect(
        preferences.getKeys()
            .where((key) => key.startsWith('central.effective.'))
            .length,
        2,
      );
    });

    test('only fresh exact-scope Laravel cache is usable offline', () async {
      api.responses['pos'] = <String, dynamic>{'cached': true};
      final service = ConfigService(
        api, preferences,
        cacheTtl: const Duration(hours: 6),
        clock: () => now,
      );
      await service.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      api.failure = const CentralApiException('network failure');
      now = now.add(const Duration(hours: 2));
      final cached = await service.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      expect(cached.fromCache, isTrue);
      expect(cached.value['cached'], isTrue);
      now = now.add(const Duration(hours: 5));
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsA(isA<CentralApiException>()),
      );
    });

    test('kill switch permits a fresh cache but blocks remote reads', () async {
      api.responses['pos'] = <String, dynamic>{'cached': true};
      await ConfigService(api, preferences, clock: () => now).getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      final calls = api.calls;
      final disabled = ConfigService(
        api, preferences, killSwitch: true, clock: () => now);
      final result = await disabled.getEffectiveConfig(
        tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos');
      expect(result.fromCache, isTrue);
      expect(api.calls, calls);
    });

    test('Supabase mode cannot run without an explicit effective-config adapter', () async {
      final service = ConfigService(
        api, preferences, sourceMode: ConfigSourceMode.supabase);
      await expectLater(
        service.getEffectiveConfig(
          tenantId: 'tenant_001', deviceId: 'device_001', service: 'pos'),
        throwsStateError,
      );
    });

    test('parity JSON ignores map key order only', () {
      expect(
        ConfigService.canonicalJson(<String, dynamic>{
          'nested': <String, dynamic>{'b': 2, 'a': 1},
        }),
        ConfigService.canonicalJson(<String, dynamic>{
          'nested': <String, dynamic>{'a': 1, 'b': 2},
        }),
      );
      expect(
        ConfigService.canonicalJson(<String, dynamic>{'enabled': true}),
        isNot(ConfigService.canonicalJson(<String, dynamic>{'enabled': false})),
      );
    });
  });

  group('TenantFeatures', () {
    test('reads nested effective config flags', () {
      final features = TenantFeatures.fromEffectiveConfig(<String, dynamic>{
        'features': <String, dynamic>{'pos': true, 'akuntansi': false},
      });
      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('supports flat canonical feature flags', () {
      final features = TenantFeatures.fromEffectiveConfig(<String, dynamic>{
        'pos_enabled': true, 'akuntansi_enabled': true,
      });
      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('fails closed when feature flags are missing', () {
      expect(
        () => TenantFeatures.fromEffectiveConfig(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}

class _FakeCentralApiClient extends CentralApiClient {
  _FakeCentralApiClient(SharedPreferences preferences)
      : super(
          baseUrl: 'https://example.invalid',
          preferences: preferences,
          secureStorage: const FlutterSecureStorage(),
        );

  final Map<String, Map<String, dynamic>> responses = <String, Map<String, dynamic>>{};
  final Map<String, Map<String, dynamic>> scopedResponses = <String, Map<String, dynamic>>{};
  Object? failure;
  int calls = 0;

  @override
  bool get hasSession => true;

  @override
  Future<Map<String, dynamic>> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    calls++;
    if (failure != null) throw failure!;
    final scopeKey = jsonEncode(<String>[tenantId, deviceId, service]);
    return Map<String, dynamic>.from(
      scopedResponses[scopeKey] ??
          responses[service] ??
          <String, dynamic>{'service': service},
    );
  }
}

class _FakeLegacySource implements LegacyEffectiveConfigSource {
  _FakeLegacySource(this.response);
  final Map<String, dynamic> response;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    calls++;
    return Map<String, dynamic>.from(response);
  }
}
