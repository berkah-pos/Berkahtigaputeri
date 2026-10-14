import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:berkahtigaputeri_pos/core/config/central_api_client.dart';
import 'package:berkahtigaputeri_pos/features/auth/login_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('configured API mode asks for credentials and offers local mode',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final client = CentralApiClient(
      baseUrl: 'https://api.example.invalid',
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          client: client,
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
    expect(find.textContaining('membership tenant dan enrollment'), findsOneWidget);
    client.close();
  });

  testWidgets('unconfigured API mode explains local-only boundary',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          client: null,
          configurationMessage: 'Laravel Central API belum dikonfigurasi.',
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    expect(find.text('Mode cloud belum tersedia pada build ini'), findsOneWidget);
    expect(find.text('Laravel Central API belum dikonfigurasi.'), findsOneWidget);
    expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
  });
}
