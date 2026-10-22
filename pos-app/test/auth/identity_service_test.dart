import 'dart:convert';

import 'package:berkahtigaputeri_pos/core/auth/identity_service.dart';
import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
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

Map<String, dynamic> _verifiedDeviceSession(String deviceId) =>
    <String, dynamic>{
      'status': 'authenticated',
      'token_kind': 'device',
      'token_expires_at': '2026-10-22T12:00:00Z',
      'user': <String, dynamic>{
        'id': 42,
        'name': 'Test Owner',
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
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('stores a token only after the API verifies the new device session',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    final tokens = _MemoryTokenStore();
    var loginRequests = 0;
    var sessionRequests = 0;
    var requestedDeviceId = '';

    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          loginRequests++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          requestedDeviceId = payload['device_id'] as String;
          expect(request.headers['content-type'], contains('application/json'));
          return http.Response(
            jsonEncode(<String, dynamic>{
              'status': 'authenticated',
              'token_type': 'Bearer',
              'token_kind': 'device',
              'access_token': 'one-time-secret-token',
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/session') {
          sessionRequests++;
          expect(
            request.headers['authorization'],
            'Bearer one-time-secret-token',
          );
          return http.Response(
            jsonEncode(_verifiedDeviceSession(requestedDeviceId)),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/logout') {
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      }),
    );

    final result = await service.signIn(
      email: 'owner@example.test',
      password: 'test-password',
      tenantId: 'tenant-a',
    );

    expect(result.status, SignInStatus.authenticated);
    expect(loginRequests, 1);
    expect(sessionRequests, 1);
    expect(tokens.token, 'one-time-secret-token');
    expect(service.currentSession?.tenantId, 'tenant-a');
    expect(service.currentSession?.deviceId, requestedDeviceId);
    expect(identityStore.tenantId, 'tenant-a');
    expect(identityStore.deviceId, requestedDeviceId);
  });

  test('pending device enrollment never persists a bearer token', () async {
    final preferences = await SharedPreferences.getInstance();
    final tokens = _MemoryTokenStore();
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        expect(request.url.path, '/api/v1/auth/login');
        return http.Response(
          '{"status":"device_pending_approval","message":"Awaiting approval"}',
          202,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.signIn(
      email: 'owner@example.test',
      password: 'test-password',
      tenantId: 'tenant-a',
    );

    expect(result.status, SignInStatus.devicePendingApproval);
    expect(tokens.token, isNull);
    expect(service.currentSession, isNull);
  });

  test('multi-tenant login exposes only server-listed membership choices', () async {
    final preferences = await SharedPreferences.getInstance();
    final tokens = _MemoryTokenStore();
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        return http.Response(
          '{"error":"tenant_selection_required","message":"Choose a tenant",'
          '"memberships":[{"tenant_id":"tenant-a","role":"owner"},'
          '{"tenant_id":"tenant-b","role":"cashier"}]}',
          422,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    final result = await service.signIn(
      email: 'owner@example.test',
      password: 'test-password',
    );

    expect(result.status, SignInStatus.tenantSelectionRequired);
    expect(result.memberships.map((entry) => entry.tenantId),
        <String>['tenant-a', 'tenant-b']);
    expect(tokens.token, isNull);
  });

  test('invalid persisted token is cleared when the server revokes it', () async {
    final preferences = await SharedPreferences.getInstance();
    final tokens = _MemoryTokenStore()..token = 'revoked-token';
    final identityStore = AppIdentityStore(preferences);
    await identityStore.setTenantId('stale-tenant');

    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        expect(request.url.path, '/api/v1/auth/session');
        expect(request.headers['authorization'], 'Bearer revoked-token');
        return http.Response(
          '{"error":"identity_disabled","message":"Account disabled"}',
          403,
          headers: const <String, String>{'content-type': 'application/json'},
        );
      }),
    );

    expect(await service.restoreSession(), isNull);
    expect(tokens.token, isNull);
    expect(service.currentSession, isNull);
    expect(identityStore.tenantId, '');
  });

  test('offline session restore does not treat the stored token as verified',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final tokens = _MemoryTokenStore()..token = 'saved-but-unverified';
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: tokens,
      httpClient: MockClient((http.Request request) async {
        throw http.ClientException('simulated offline');
      }),
    );

    await expectLater(
      service.restoreSession(),
      throwsA(
        isA<IdentityApiException>().having(
          (error) => error.code,
          'code',
          'network_unavailable',
        ),
      ),
    );
    expect(tokens.token, 'saved-but-unverified');
    expect(service.hasAuthenticatedSession, isFalse);
  });

  test('local tenant/device spoofing cannot request cloud configuration',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((http.Request request) async {
        fail('A mismatched local identity must be rejected before HTTP.');
      }),
    );

    await expectLater(
      service.getEffectiveConfig(
        tenantId: 'forged-tenant',
        deviceId: 'forged-device-identifier',
        service: 'pos',
      ),
      throwsA(isA<IdentityApiException>()),
    );
  });

  test('rejects non-HTTPS remote API configuration', () async {
    final preferences = await SharedPreferences.getInstance();
    expect(
      () => IdentityService(
        baseUrl: 'http://api.example.test',
        identityStore: AppIdentityStore(preferences),
        tokenStore: _MemoryTokenStore(),
      ),
      throwsArgumentError,
    );
  });
}
