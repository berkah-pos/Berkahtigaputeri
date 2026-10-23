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
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pump();
  debugPrint('PUMP_DONE:$checkpoint');
}

void main() {
  testWidgets('local settings clearly reports cloud configuration and sync boundaries',
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
    await tester.tap(find.text('Lanjutkan sebagai kasir lokal'));
    await _settle(tester, 'local mode');
    await tester.tap(find.byTooltip('Pengaturan tenant dan cloud'));
    await _settle(tester, 'settings screen');

    expect(find.text('API cloud belum dikonfigurasi'), findsOneWidget);
    expect(
      find.textContaining('Data penjualan lokal tetap tersimpan di SQLite'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Sinkronisasi transaksi'),
      findsOneWidget,
    );
    expect(find.text('Muat POS'), findsNothing);
    expect(find.text('Muat Akuntansi'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets(
    'local-only mode can return to cloud login when the API is configured',
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
            baseUrl: 'https://api.example.test',
            vault: _MemorySecureVault(),
          ),
          identityStore: identityStore,
          deviceId: deviceId,
        ),
      );
      await _settle(tester, 'configured API login');
      expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);

      await tester.tap(find.text('Lanjutkan lokal tanpa akun cloud'));
      await _settle(tester, 'local-only mode');
      expect(find.text('Beranda'), findsOneWidget);

      await tester.tap(find.byTooltip('Pengaturan tenant dan cloud'));
      await _settle(tester, 'local-only settings');
      expect(find.text('Mode lokal aktif; sesi cloud tidak aktif'), findsOneWidget);
      expect(find.text('Kembali ke login cloud'), findsOneWidget);
      expect(find.text('Muat POS'), findsNothing);
      expect(find.text('Muat Akuntansi'), findsNothing);

      await tester.tap(find.text('Kembali ke login cloud'));
      await _settle(tester, 'return to cloud login');

      expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);
      expect(find.text('Lanjutkan lokal tanpa akun cloud'), findsOneWidget);
      expect(find.text('Beranda'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
