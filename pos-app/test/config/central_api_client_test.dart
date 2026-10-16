import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:berkahtigaputeri_pos/core/config/central_api_client.dart';

const MethodChannel _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
final Map<String, String> _secureVault = <String, String>{};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _secureVault.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
      final arguments = call.arguments is Map
          ? Map<dynamic, dynamic>.from(call.arguments as Map)
          : <dynamic, dynamic>{};
      final key = arguments['key'] as String?;
      switch (call.method) {
        case 'write':
          if (key == null || arguments['value'] is! String) {
            throw const FormatException('Invalid secure storage write.');
          }
          _secureVault[key] = arguments['value'] as String;
          return null;
        case 'read':
          return key == null ? null : _secureVault[key];
        case 'delete':
          if (key != null) _secureVault.remove(key);
          return null;
        case 'deleteAll':
          _secureVault.clear();
          return null;
        case 'containsKey':
          return key != null && _secureVault.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(_secureVault);
        default:
          throw MissingPluginException('Unimplemented method: ' + call.method);
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  test('session hydration removes legacy plaintext preference and restores vault token',
      () async {
    final preferences = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage();
    await preferences.setString('central_api.access_token', 'legacy-plaintext');
    await secureStorage.write(
      key: 'central_api.access_token',
      value: 'secure-token',
    );
    final client = CentralApiClient(
      baseUrl: 'https://api.example.invalid',
      preferences: preferences,
      secureStorage: secureStorage,
      httpClient: MockClient((_) async => http.Response('{}', 500)),
    );
    addTearDown(client.close);

    await client.hydrateSession();

    expect(client.hasSession, isTrue);
    expect(_secureVault['central_api.access_token'], 'secure-token');
    expect(preferences.containsKey('central_api.access_token'), isFalse);
  });

  test('login stores token only after response and secure read-back verification',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final client = CentralApiClient(
      baseUrl: 'https://api.example.invalid',
      preferences: preferences,
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/auth/login');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'cashier@example.invalid');
        expect(body['password'], 'test-password');
        return http.Response(jsonEncode(<String, dynamic>{
          'token': 'issued-secure-token',
          'token_type': 'Bearer',
        }), 200, headers: <String, String>{
          'content-type': 'application/json',
        });
      }),
    );
    addTearDown(client.close);

    await client.signIn(
      email: ' cashier@example.invalid ',
      password: 'test-password',
    );

    expect(client.hasSession, isTrue);
    expect(_secureVault['central_api.access_token'], 'issued-secure-token');
    expect(preferences.containsKey('central_api.access_token'), isFalse);
  });

  test('logout reports missing remote confirmation but always clears local token',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final client = CentralApiClient(
      baseUrl: 'https://api.example.invalid',
      preferences: preferences,
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response('{"token":"issued-secure-token"}', 200);
        }
        expect(request.url.path, '/api/v1/auth/logout');
        expect(request.headers['authorization'], 'Bearer issued-secure-token');
        return http.Response('{"message":"Unavailable"}', 503);
      }),
    );
    addTearDown(client.close);

    await client.signIn(email: 'cashier@example.invalid', password: 'secret');
    final confirmed = await client.signOut();

    expect(confirmed, isFalse);
    expect(client.hasSession, isFalse);
    expect(_secureVault.containsKey('central_api.access_token'), isFalse);
    expect(preferences.containsKey('central_api.access_token'), isFalse);
  });

  test('logout accepts only server success or an already-invalid token as confirmed',
      () async {
    final preferences = await SharedPreferences.getInstance();
    var logoutStatus = 204;
    final client = CentralApiClient(
      baseUrl: 'https://api.example.invalid',
      preferences: preferences,
      secureStorage: const FlutterSecureStorage(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/api/v1/auth/login') {
          return http.Response('{"token":"token-for-revocation"}', 200);
        }
        return http.Response('{}', logoutStatus);
      }),
    );
    addTearDown(client.close);

    await client.signIn(email: 'cashier@example.invalid', password: 'secret');
    expect(await client.signOut(), isTrue);

    // A fresh token receiving 401 is already invalid on the server.
    logoutStatus = 401;
    await client.signIn(email: 'cashier@example.invalid', password: 'secret');
    expect(await client.signOut(), isTrue);
  });
}
