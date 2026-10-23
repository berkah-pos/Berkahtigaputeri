import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  testWidgets(
    'dashboard database read failure does not expose SQLite exception text',
    (tester) async {
      sqfliteFfiInit();
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final database = (await tester.runAsync(
        () => PosDatabase.openAt(
          inMemoryDatabasePath,
          factory: databaseFactoryFfi,
        ),
      ))!;

      // Force the dashboard's product-count query to fail with an SQLite error.
      await tester.runAsync(() => database.database.execute('DROP TABLE products'));
      addTearDown(() async {
        await tester.runAsync(database.close);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            database: database,
            identityStore: AppIdentityStore(preferences),
          ),
        ),
      );

      for (var attempt = 0; attempt < 5; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
      }
      await tester.pump();

      expect(
        find.text(
          'Dashboard gagal dimuat: Data lokal belum dapat dibaca. Periksa penyimpanan perangkat, lalu coba lagi.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no such table'), findsNothing);
      expect(find.textContaining('products'), findsNothing);
      expect(find.text('Coba lagi'), findsOneWidget);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}