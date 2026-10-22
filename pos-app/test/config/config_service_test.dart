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
    test('parses tenant flags', () {
      final features = TenantFeatures.fromJson(
        <String, dynamic>{'pos': true, 'akuntansi': false},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('parses flags from the central API resolver envelope', () {
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

    test('supports canonical flat feature flags', () {
      final features = TenantFeatures.fromEffectiveConfig(
        <String, dynamic>{'pos_enabled': true, 'akuntansi_enabled': true},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('fails closed if feature flags are missing', () {
      expect(
        () => TenantFeatures.fromEffectiveConfig(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });

  test('effective configuration uses the verified API session context',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    final tokens = _MemoryTokenStore();
    var deviceId = '';
    var configRequests = 0;

    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          deviceId =
              (jsonDecode(request.body) as Map<String, dynamic>)['device_id'] as String;
          return http.Response(
            '{"status":"authenticated","token_kind":"device",'
            '"access_token":"test-token"}',
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
                'device_id': deviceId,
                'tenant_id': 'tenant-a',
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/config/pos') {
          configRequests++;
          expect(request.headers['authorization'], 'Bearer test-token');
          expect(request.headers['x-device-id'], deviceId);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'data': <String, dynamic>{
                'tenant_id': 'tenant-a',
                'device_id': deviceId,
                'service': 'pos',
                'version': 19,
                'hash': 'fixed-test-hash',
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

    final service = ConfigService(identity);
    expect(service.hasAuthenticatedSession, isTrue);

    final result = await service.getEffectiveConfig(
      tenantId: 'tenant-a',
      deviceId: deviceId,
      service: 'pos',
    );

    expect(result.fromCache, isFalse);
    expect(result.value['tenant_id'], 'tenant-a');
    expect(result.value['device_id'], deviceId);
    expect(result.value['config']['mdr'], 0.5);
    expect(configRequests, 1);
    expect(TenantFeatures.fromEffectiveConfig(result.value).akuntansi, isFalse);
  });

  test('server authorization denial cannot be hidden by a cache fallback',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    var deviceId = '';

    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          deviceId =
              (jsonDecode(request.body) as Map<String, dynamic>)['device_id'] as String;
          return http.Response(
            '{"status":"authenticated","token_kind":"device",'
            '"access_token":"test-token"}',
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
                'device_id': deviceId,
                'tenant_id': 'tenant-a',
              },
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/config/pos') {
          return http.Response(
            '{"error":{"code":"device_access_denied","message":"Device revoked"}}',
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

    final service = ConfigService(identity);
    await expectLater(
      service.getEffectiveConfig(
        tenantId: 'tenant-a',
        deviceId: deviceId,
        service: 'pos',
      ),
      throwsA(
        isA<IdentityApiException>()
            .having((error) => error.statusCode, 'statusCode', 403)
            .having((error) => error.code, 'code', 'device_access_denied'),
      ),
    );
  });

  test('unverified identity cannot request configuration using forged local IDs',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final identity = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((http.Request request) async {
        fail('No HTTP request should be made without a verified identity session.');
      }),
    );

    final service = ConfigService(identity);
    await expectLater(
      service.getEffectiveConfig(
        tenantId: 'forged-tenant',
        deviceId: 'forged-device-identifier',
        service: 'pos',
      ),
      throwsStateError,
    );
  });
}
