import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/main.dart';

class _FailingReadVault implements SecureVault {
  _FailingReadVault({this.failDelete = false});

  final bool failDelete;
  int readAttempts = 0;
  bool deleteCalled = false;

  @override
  Future<String?> read(String key) async {
    readAttempts++;
    throw StateError('simulated secure storage unavailable');
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {
    deleteCalled = true;
    if (failDelete) {
      throw StateError('simulated secure storage delete failure');
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'database startup failure shows recovery UI and retry opens the app',
    (tester) async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues(<String, Object>{});

      var attempts = 0;
      final openedDatabase = (await tester.runAsync(
        () => PosDatabase.openAt(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;

      Future<PosDatabase> openDatabase() async {
        attempts++;
        if (attempts == 1) {
          throw StateError('simulated database unavailable');
        }
        // The real disposable database is opened before widget initialization,
        // so this retry does not nest WidgetTester.runAsync calls.
        return openedDatabase;
      }

      addTearDown(() async {
        await tester.runAsync(openedDatabase.close);
      });

      await tester.pumpWidget(
        BerkahTigaPuteriBootstrapApp(
          apiBaseUrl: '',
          loadPreferences: SharedPreferences.getInstance,
          openDatabase: openDatabase,
        ),
      );
      await _settle(tester);

      expect(find.text('Data lokal belum siap'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.textContaining('Startup failed (StateError)'), findsOneWidget);
      expect(attempts, 1);

      await tester.tap(find.text('Coba lagi'));
      await _settle(tester);

      expect(attempts, 2);
      expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'pending logout latch blocks session restore until secure deletion retry succeeds',
    (tester) async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p6.session_cleanup_pending': true,
      });
      final preferences = await SharedPreferences.getInstance();
      final identityStore = AppIdentityStore(preferences);
      final deviceId = await identityStore.ensureDeviceId();
      final database = (await tester.runAsync(
        () => PosDatabase.openAt(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;
      final vault = _FailingReadVault(failDelete: true);
      final httpClient = MockClient(
        (_) async => http.Response('{}', 200),
      );

      addTearDown(() async {
        await tester.runAsync(database.close);
        httpClient.close();
      });

      await tester.pumpWidget(
        BerkahTigaPuteriApp(
          database: database,
          authService: LaravelAuthService(
            baseUrl: 'https://api.example.test',
            vault: vault,
            client: httpClient,
          ),
          identityStore: identityStore,
          deviceId: deviceId,
        ),
      );
      await _settle(tester);

      expect(vault.readAttempts, 0);
      expect(find.text('Coba bersihkan sesi cloud lagi'), findsOneWidget);
      expect(find.text('Lanjutkan sebagai kasir lokal'), findsOneWidget);

      await tester.tap(find.text('Coba bersihkan sesi cloud lagi'));
      await _settle(tester);

      expect(vault.readAttempts, 1);
      expect(vault.deleteCalled, isTrue);
      expect(identityStore.sessionCleanupPending, isTrue);
      expect(find.text('Coba bersihkan sesi cloud lagi'), findsOneWidget);

      // Model the platform secure-storage service recovering, then retry.
      vault.failDelete = false;
      await tester.tap(find.text('Coba bersihkan sesi cloud lagi'));
      await _settle(tester);

      expect(identityStore.sessionCleanupPending, isFalse);
      expect(find.text('Coba bersihkan sesi cloud lagi'), findsNothing);
      expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  testWidgets(
    'secure session restore exception releases the gate and preserves local mode',
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

      final httpClient = MockClient(
        (_) async => http.Response('{}', 200),
      );
      addTearDown(() async {
        await tester.runAsync(database.close);
        httpClient.close();
      });

      await tester.pumpWidget(
        BerkahTigaPuteriApp(
          database: database,
          authService: LaravelAuthService(
            baseUrl: 'https://api.example.test',
            vault: _FailingReadVault(),
            client: httpClient,
          ),
          identityStore: identityStore,
          deviceId: deviceId,
        ),
      );
      await _settle(tester);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining('Sesi cloud tidak dapat dipulihkan'),
        findsOneWidget,
      );
      expect(find.text('Masuk ke akun Berkah POS'), findsOneWidget);
      expect(find.text('Lanjutkan lokal tanpa akun cloud'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
