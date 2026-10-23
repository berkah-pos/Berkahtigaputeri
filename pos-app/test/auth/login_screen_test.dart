import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/features/auth/login_screen.dart';

class _MemoryVault implements SecureVault {
  final Map<String, String> values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  const deviceId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const tokenKey = 'berkah.auth.laravel.access_token';

  test('effective config is fetched with bearer token and validated tuple', () async {
    final vault = _MemoryVault()..values[tokenKey] = '1|stored-token';
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(jsonEncode(<String, dynamic>{
        'data': <String, dynamic>{
          'tenant_id': 'tenant-a',
          'device_id': deviceId,
          'service': 'pos',
          'version': 5,
          'versions': <String, int>{
            'global': 1, 'template': 2, 'tenant': 3, 'service': 4, 'device': 5,
          },
          'hash': List<String>.filled(64, 'a').join(),
          'config': <String, dynamic>{
            'features': <String, dynamic>{'pos': true, 'akuntansi': false},
          },
        },
      }), 200);
    });
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );

    final snapshot = await service.fetchEffectiveConfig(service: 'POS');

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.url.path, '/api/v1/config/pos');
    expect(
      capturedRequest.headers.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
          .value,
      'Bearer 1|stored-token',
    );
    expect(
      capturedRequest.headers.keys.any((key) => key.toLowerCase() == 'x-tenant-id'),
      isFalse,
    );
    expect(snapshot.tenantId, 'tenant-a');
    expect(snapshot.deviceId, deviceId);
    expect(snapshot.service, 'pos');
    expect(snapshot.version, 5);
    expect(snapshot.versions['device'], 5);
    expect(snapshot.config['features'], <String, dynamic>{'pos': true, 'akuntansi': false});
  });

  test('effective config rejects invalid service and missing sessions locally', () async {
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: _MemoryVault(),
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      service.fetchEffectiveConfig(service: 'pos,akuntansi'),
      throwsA(isA<AuthFailure>().having((failure) => failure.code, 'code', 'invalid_service')),
    );
    await expectLater(
      service.fetchEffectiveConfig(service: 'pos'),
      throwsA(isA<AuthFailure>().having((failure) => failure.code, 'code', 'session_missing')),
    );
  });

  test('effective config preserves the nested Laravel error code', () async {
    final vault = _MemoryVault()..values[tokenKey] = '1|stored-token';
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: MockClient((_) async => http.Response(jsonEncode(<String, dynamic>{
        'error': <String, dynamic>{
          'code': 'configuration_not_ready',
          'message': 'Configuration requires operator provisioning.',
        },
      }), 409)),
    );

    await expectLater(
      service.fetchEffectiveConfig(service: 'pos'),
      throwsA(isA<AuthFailure>()
          .having((failure) => failure.code, 'code', 'configuration_not_ready')
          .having((failure) => failure.statusCode, 'statusCode', 409)),
    );
  });

  testWidgets('configured Laravel login shows credentials and safe local-only option', (tester) async {
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: _MemoryVault(),
      client: MockClient((_) async => http.Response('{}', 401)),
    );

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        authService: service,
        deviceId: deviceId,
        onAuthenticated: (_) async {},
        onContinueLocal: () {},
      ),
    ));

    expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata sandi'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Lanjutkan lokal tanpa akun cloud'), findsOneWidget);
  });

  testWidgets('unconfigured cloud mode clearly explains local-only boundary', (tester) async {
    final service = LaravelAuthService(baseUrl: '', vault: _MemoryVault());
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        authService: service,
        deviceId: deviceId,
        onAuthenticated: (_) async {},
        onContinueLocal: () {},
      ),
    ));

    expect(find.text('Mode cloud belum tersedia pada build ini'), findsOneWidget);
    expect(find.textContaining('BERKAH_API_BASE_URL'), findsOneWidget);
    expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
  });

  testWidgets('pending device does not invoke authenticated navigation', (tester) async {
    final vault = _MemoryVault();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/api/v1/auth/login')) {
        return http.Response(jsonEncode(<String, dynamic>{
          'access_token': '1|pending-token',
          'tenant_id': 'tenant-a',
          'device_id': deviceId,
          'device_status': 'unregistered',
          'user': <String, dynamic>{'id': 7, 'name': 'Cashier', 'email': 'cashier@example.test'},
        }), 200);
      }
      if (request.url.path.endsWith('/api/v1/devices/enroll')) {
        return http.Response(jsonEncode(<String, dynamic>{'status': 'pending'}), 202);
      }
      return http.Response('{}', 200);
    });
    final service = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );
    var authenticated = false;

    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        authService: service,
        deviceId: deviceId,
        onAuthenticated: (_) async => authenticated = true,
        onContinueLocal: () {},
      ),
    ));
    await tester.enterText(find.byType(TextFormField).at(0), 'cashier@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'correct-password');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.textContaining('belum disetujui administrator'), findsOneWidget);
    expect(authenticated, isFalse);
  });
}
