import 'dart:ui' show Size;

import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/main.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _settle(WidgetTester tester, String checkpoint) async {
  debugPrint('PUMP_FRAMES_BEGIN:$checkpoint');
  // Pump a fixed number of frames. Waiting for global quiescence is brittle
  // when a visible screen owns a repeating ticker or asynchronous DB read.
  for (var frame = 0; frame < 15; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  debugPrint('PUMP_FRAMES_DONE:$checkpoint');
}

Future<void> _tap(WidgetTester tester, Finder finder, String checkpoint) async {
  expect(
    finder,
    findsOneWidget,
    reason: 'Tap target must be unique before checkpoint $checkpoint.',
  );
  await tester.tap(finder);
  await tester.pump();
}

void main() {
  testWidgets('combined POS shell exposes product, cashier, stock and reports',
      (tester) async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
    final database = await PosDatabase.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      BerkahTigaPuteriApp(
        database: database,
        identityStore: AppIdentityStore(preferences),
      ),
    );
    await _settle(tester, 'initial app');

    // No Supabase client is injected in this test, so enter explicit local-only
    // mode rather than implying the cloud account is authenticated.
    expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
    await _tap(tester, find.text('Lanjutkan sebagai kasir lokal'), 'tap-2');
    await _settle(tester, 'local mode');

    expect(find.text('Beranda'), findsOneWidget);
    expect(find.text('Buka kasir'), findsOneWidget);

    await _tap(tester, find.text('Produk').last, 'tap-3');
    await _settle(tester, 'products tab');
    expect(find.text('Tambah produk'), findsOneWidget);

    await _tap(tester, find.text('Kasir'), 'tap-4');
    await _settle(tester, 'cashier tab');
    expect(find.text('Katalog produk'), findsOneWidget);
    expect(find.text('Selesaikan checkout'), findsOneWidget);

    await _tap(tester, find.text('Stok'), 'tap-5');
    await _settle(tester, 'stock tab');
    expect(find.text('Ringkasan stok lokal'), findsOneWidget);

    await _tap(tester, find.text('Laporan'), 'tap-6');
    await _settle(tester, 'reports tab');
    expect(find.text('Transaksi terbaru'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
