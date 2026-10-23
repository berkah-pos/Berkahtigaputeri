import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';

class MemoryVault implements SecureVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _LogoutFailureVault implements SecureVault {
  _LogoutFailureVault({this.failRead = false, this.failDelete = false});

  final bool failRead;
  final bool failDelete;
  bool deleteCalled = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('simulated secure storage read failure');
    return null;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {
    deleteCalled = true;
    if (failDelete) throw StateError('simulated secure storage delete failure');
  }
}

void main() {
  const deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  test('does not permit HTTP or an unconfigured cloud API', () async {
    final service = LaravelAuthService(
      baseUrl: 'http://api.example.test',
      vault: MemoryVault(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    expect(service.isConfigured, isFalse);
    await expectLater(
      service.login(
        email: 'owner@example.test',
        password: 'correct-password',
        deviceId: deviceId,
      ),
      throwsA(isA<AuthFailure>().having((failure) => failure.code, 'code', 'api_not_configured')),
    );
  });

  test('unknown device is enrolled as pending and never authenticated to cloud', () async {
    final vault = MemoryVault();
    var enrollmentCalled = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/auth/login')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_id'], deviceId);
        expect(body['device_secret'], matches(RegExp(r'^[a-f0-9]{64}$')));
        return http.Response(jsonEncode(<String, dynamic>{
          'access_token': '1|opaque-token',
          'tenant_id': 'tenant-a',
          'device_id': deviceId,
          'device_status': 'unregistered',
          'expires_at': '2026-10-22T10:00:00Z',
          'user': <String, dynamic>{'id': 4, 'name': 'Owner', 'email': 'owner@example.test'},
        }), 200);
      }
      if (request.url.path.endsWith('/api/v1/devices/enroll')) {
        enrollmentCalled = true;
        expect(request.headers['authorization'], 'Bearer 1|opaque-token');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_secret'], matches(RegExp(r'^[a-f0-9]{64}$')));
        return http.Response(jsonEncode(<String, dynamic>{
          'status': 'pending',
          'device_id': deviceId,
        }), 202);
      }
      fail('Unexpected request: ' + request.method + ' ' + request.url.toString());
    });

    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test/',
      vault: vault,
      client: client,
    );
    final session = await service.login(
      email: 'owner@example.test',
      password: 'correct-password',
      deviceId: deviceId,
    );

    expect(enrollmentCalled, isTrue);
    expect(session.deviceStatus, 'pending');
    expect(session.deviceIsActive, isFalse);
    expect(await vault.read('berkah.auth.laravel.access_token'), '1|opaque-token');
    expect(await vault.read('berkah.device.secret.$deviceId'), matches(RegExp(r'^[a-f0-9]{64}$')));
  });

  test('logout still attempts local token deletion when secure read throws', () async {
    final vault = _LogoutFailureVault(failRead: true);
    final service = LaravelAuthService(
      baseUrl: '',
      vault: vault,
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await service.logout();

    expect(vault.deleteCalled, isTrue);
  });

  test('logout reports local token deletion failure so the app can lock cloud access', () async {
    final vault = _LogoutFailureVault(failRead: true, failDelete: true);
    final service = LaravelAuthService(
      baseUrl: '',
      vault: vault,
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      service.logout(),
      throwsA(isA<AuthFailure>().having(
        (failure) => failure.code,
        'code',
        'local_session_cleanup_failed',
      )),
    );
    expect(vault.deleteCalled, isTrue);
  });

  test('restore rejects a revoked session and clears the local bearer token', () async {
    final vault = MemoryVault();
    vault.values['berkah.auth.laravel.access_token'] = '1|stale-token';
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer 1|stale-token');
        return http.Response(jsonEncode(<String, dynamic>{
          'message': 'Device revoked',
          'code': 'device_session_denied',
        }), 403);
      }),
    );

    expect(await service.restoreSession(), isNull);
    expect(await vault.read('berkah.auth.laravel.access_token'), isNull);
  });
}
