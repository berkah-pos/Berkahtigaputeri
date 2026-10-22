import 'dart:convert';

import 'package:berkahtigaputeri_pos/core/auth/identity_service.dart';
import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/core/config/config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemoryTokenStore implements AccessTokenStore {
  String? token;

  @override
  Future<void> delete() async => token = null;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('TenantFeatures', () {
    test('clientA hides Akuntansi', () {
      final features = TenantFeatures.fromJson(
        <String, dynamic>{'pos': true, 'akuntansi': false},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('clientB shows POS and Akuntansi', () {
      final features = TenantFeatures.fromJson(
        <String, dynamic>{'pos': true, 'akuntansi': true},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('feature flags are derived from the central API resolver envelope', () {
      final features = TenantFeatures.fromEffectiveConfig(
        <String, dynamic>{
          'tenant_id': 'tenant-a',
          'service': 'pos',
          'config': <String, dynamic>{
            'features': <String, dynamic>{'pos': true, 'akuntansi': false},
          },
        },
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('supports canonical flat feature flags in effective config', () {
      final features = TenantFeatures.fromEffectiveConfig(
        <String, dynamic>{
          'pos_enabled': true,
          'akuntansi_enabled': true,
        },
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('fails closed when effective config has no feature flags', () {
      expect(
        () => TenantFeatures.fromEffectiveConfig(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });

  test('authenticated config uses the server-verified tenant and device', () async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    final tokens = _MemoryTokenStore();
    var verifiedDeviceId = '';
    var configRequestCount = 0;

    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          verifiedDeviceId =
              (jsonDecode(request.body) as Map<String, dynamic>)['device_id'] as String;
          return http.Response(
            '{"status":"authenticated","access_token":"test-token"}',
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/session') {
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'authenticated',
              'token_kind': 'device',
              'token_expires_at': '2026-10-22T12:00:00Z',
              'user': <String, dynamic>{
                'id': 7,
                'name': 'Tenant Owner',
                'email': 'owner@example.test',
                'is_super_admin': false,
              },
              'memberships': <Map<String, dynamic>>[
                <String, dynamic>{
                  'tenant_id': 'tenant-a',
                  'role': 'owner',
                  'template_id': 'BASIC',
                },
              ],
              'device': <String, dynamic>{
                'device_id': verifiedDeviceId,
                'tenant_id': 'tenant-a',
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/config/pos') {
          configRequestCount++;
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.headers['x-device-id'], verifiedDeviceId);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'tenant_id': 'tenant-a',
                'device_id': verifiedDeviceId,
                'service': 'pos',
                'version': 19,
                'hash': 'a-fixed-test-hash',
                'config': <String, dynamic>{
                  'mdr': 0.5,
                  'features': <String, dynamic>{'pos': true, 'akuntansi': false},
                },
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final login = await identity.signIn(
      email: 'owner@example.test',
      password: 'test-password',
      tenantId: 'tenant-a',
    );
    expect(login.status, SignInStatus.authenticated);

    final service = ConfigService(identity, preferences);
    expect(service.hasAuthenticatedSession, isTrue);

    final result = await service.getEffectiveConfig(
      tenantId: 'tenant-a',
      deviceId: verifiedDeviceId,
      service: 'pos',
    );

    expect(result.fromCache, isFalse);
    expect(result.value['tenant_id'], 'tenant-a');
    expect(result.value['device_id'], verifiedDeviceId);
    expect(result.value['config']['mdr'], 0.5);
    expect(configRequestCount, 1);
    expect(
      TenantFeatures.fromEffectiveConfig(result.value).akuntansi,
      isFalse,
    );
  });

  test('server authorization denial never falls back to cached config', () async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    final tokens = _MemoryTokenStore();
    var verifiedDeviceId = '';
    var configRequestCount = 0;

    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          verifiedDeviceId =
              (jsonDecode(request.body) as Map<String, dynamic>)['device_id'] as String;
          return http.Response(
            '{"status":"authenticated","access_token":"test-token"}',
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/session') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'authenticated',
              'token_kind': 'device',
              'token_expires_at': '2026-10-22T12:00:00Z',
              'user': <String, dynamic>{
                'id': 7,
                'name': 'Tenant Owner',
                'email': 'owner@example.test',
                'is_super_admin': false,
              },
              'memberships': <Map<String, dynamic>>[
                <String, dynamic>{'tenant_id': 'tenant-a', 'role': 'owner'},
              ],
              'device': <String, dynamic>{
                'device_id': verifiedDeviceId,
                'tenant_id': 'tenant-a',
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/config/pos') {
          configRequestCount++;
          if (configRequestCount == 1) {
            return http.Response(
              '{"data":{"tenant_id":"tenant-a","device_id":"$verifiedDeviceId",'
              '"service":"pos","config":{"features":{"pos":true,"akuntansi":false}}}}',
              200,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"error":{"code":"device_access_denied","message":"Device was revoked"}}',
            403,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final login = await identity.signIn(
      email: 'owner@example.test',
      password: 'test-password',
      tenantId: 'tenant-a',
    );
    expect(login.status, SignInStatus.authenticated);
    final service = ConfigService(identity, preferences);

    final first = await service.getEffectiveConfig(
      tenantId: 'tenant-a',
      deviceId: verifiedDeviceId,
      service: 'pos',
    );
    expect(first.fromCache, isFalse);

    await expectLater(
      service.getEffectiveConfig(
        tenantId: 'tenant-a',
        deviceId: verifiedDeviceId,
        service: 'pos',
      ),
      throwsA(
        isA<IdentityApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'device_access_denied'),
      ),
    );
    expect(configRequestCount, 2);
  });

  test('mismatched local tenant/device cannot be authorized by cache', () async {
    final preferences = await SharedPreferences.getInstance();
    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((http.Request request) async {
        fail('No request should be sent for a mismatched identity context.');
      }),
    );

    final service = ConfigService(identity, preferences);
    await expectLater(
      service.getEffectiveConfig(
        tenantId: 'forged-tenant',
        deviceId: 'forged-device-123456',
        service: 'pos',
      ),
      throwsA(isA<IdentityApiException>()),
    );
  });
}
