import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/main.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _MemorySecureVault implements SecureVault {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

Future<void> _settle(WidgetTester tester, String checkpoint) async {
  debugPrint('PUMP_BEGIN:$checkpoint');
  // sqflite_common_ffi services database operations on a separate isolate.
  // Pump fixed frames and briefly yield to the real event loop between frames:
  // pumpAndSettle can hang while a database-backed loading indicator is active.
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pump();
  debugPrint('PUMP_DONE:$checkpoint');
}

Future<void> _tap(WidgetTester tester, Finder finder, String checkpoint) async {
  debugPrint('TAP_BEGIN:$checkpoint');
  // These smoke-test controls are visible without scrolling. Keep the tap
  // helper to a single tap and frame pump; async database work is handled by
  // the separate settle helper above.
  await tester.tap(finder);
  await tester.pump();
  debugPrint('TAP_DONE:$checkpoint');
}

void main() {
  testWidgets('combined POS shell exposes product, cashier, stock and reports',
      (tester) async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final preferences = await SharedPreferences.getInstance();
      final identityStore = AppIdentityStore(preferences);
      final deviceId = await identityStore.ensureDeviceId();
    final database = (await tester.runAsync(
      () => PosDatabase.openAt(
        inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      ),
    ))!;
    addTearDown(() async {
      await tester.runAsync(database.close);
    });

    await tester.pumpWidget(
      BerkahTigaPuteriApp(
        database: database,
        authService: LaravelAuthService(
          baseUrl: '',
          vault: _MemorySecureVault(),
        ),
        identityStore: identityStore,
        deviceId: deviceId,
      ),
    );
    await _settle(tester, 'initial app');

    // An unconfigured Laravel API must preserve the explicit local-only path.
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
    expect(find.text('Terima stok'), findsOneWidget);

    await _tap(tester, find.text('Laporan'), 'tap-6');
    await _settle(tester, 'reports tab');
    expect(find.text('Transaksi lokal'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
