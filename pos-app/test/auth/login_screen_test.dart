import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:berkahtigaputeri_pos/features/auth/login_screen.dart';

void main() {
  testWidgets('configured cloud mode asks for credentials and offers local mode',
      (tester) async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-publishable-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
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
    expect(
      find.textContaining('membership tenant dan enrollment'),
      findsOneWidget,
    );
  });

  testWidgets('unconfigured cloud mode explains local-only data boundary',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          client: null,
          configurationMessage: 'Cloud login belum dikonfigurasi.',
          onAuthenticated: () {},
          onContinueLocal: () {},
        ),
      ),
    );

    expect(find.text('Mode cloud belum tersedia pada build ini'), findsOneWidget);
    expect(find.text('Cloud login belum dikonfigurasi.'), findsOneWidget);
    expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
  });
}
