import 'dart:convert';

import 'package:berkahtigaputeri_pos/core/auth/identity_service.dart';
import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
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

  testWidgets('configured cloud mode uses Central API login and offers local mode',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: AppIdentityStore(preferences),
      tokenStore: _MemoryTokenStore(),
      httpClient: MockClient((http.Request request) async {
        return http.Response('{"error":"not_expected"}', 500);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          api: service,
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Kata sandi'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Lanjutkan lokal tanpa akun'), findsOneWidget);
    expect(find.text('Lupa kata sandi?'), findsOneWidget);
    expect(
      find.textContaining('Membership dan status perangkat diperiksa server'),
      findsOneWidget,
    );
  });

  testWidgets('unconfigured cloud mode explains local-only data boundary',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          api: null,
          configurationMessage: 'Central API belum dikonfigurasi.',
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    expect(find.text('Mode cloud belum tersedia pada build ini'), findsOneWidget);
    expect(find.text('Central API belum dikonfigurasi.'), findsOneWidget);
    expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
  });

  testWidgets('tenant selection is shown only after server requires it',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final tokenStore = _MemoryTokenStore();
    final identityStore = AppIdentityStore(preferences);
    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokenStore,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response(
            '{"error":"tenant_selection_required","message":"Select tenant",'
            '"memberships":[{"tenant_id":"tenant-a","role":"owner","template_id":"BASIC"},'
            '{"tenant_id":"tenant-b","role":"cashier","template_id":"BASIC"}]}',
            422,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          api: service,
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'safe-password');
    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Select tenant'), findsOneWidget);
    expect(find.textContaining('tenant-a'), findsOneWidget);
    expect(find.textContaining('tenant-b'), findsOneWidget);
    expect(tokenStore.token, isNull);
  });
  testWidgets('revoked device can request approval with a new installation ID',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final identityStore = AppIdentityStore(preferences);
    final tokenStore = _MemoryTokenStore();
    final requestedDeviceIds = <String>[];
    var loginCount = 0;

    final service = IdentityService(
      baseUrl: 'https://api.example.test',
      identityStore: identityStore,
      tokenStore: tokenStore,
      httpClient: MockClient((http.Request request) async {
        if (request.url.path == '/api/v1/auth/login') {
          loginCount++;
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          requestedDeviceIds.add(payload['device_id'] as String);
          if (loginCount == 1) {
            return http.Response(
              '{"error":"device_revoked","message":"Device revoked"}',
              403,
              headers: const <String, String>{'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"status":"device_pending_approval","message":"Awaiting approval"}',
            202,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          api: service,
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'safe-password');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();

    expect(find.text('Daftarkan ulang dengan ID perangkat baru'), findsOneWidget);
    expect(tokenStore.token, isNull);

    await tester.ensureVisible(
      find.text('Daftarkan ulang dengan ID perangkat baru'),
    );
    await tester.tap(find.text('Daftarkan ulang dengan ID perangkat baru'));
    await tester.pumpAndSettle();

    expect(loginCount, 2);
    expect(requestedDeviceIds, hasLength(2));
    expect(requestedDeviceIds[0], isNot(requestedDeviceIds[1]));
    expect(identityStore.deviceId, requestedDeviceIds[1]);
    expect(find.text('Coba lagi setelah perangkat disetujui'), findsOneWidget);
    expect(tokenStore.token, isNull);
  });


}
