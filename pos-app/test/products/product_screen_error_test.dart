import 'package:berkahtigaputeri_pos/features/products/product_screen.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  testWidgets(
    'product load failure shows safe guidance instead of SQLite details',
    (tester) async {
      final database = await openTestDatabase();
      addTearDown(database.close);

      // A controlled missing-table failure provides realistic SQLite exception
      // detail without involving network services or changing application data.
      await tester.runAsync(
        () => database.database.execute('DROP TABLE products'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ProductScreen(
            repository: SqliteProductRepository(database),
            onChanged: () {},
          ),
        ),
      );

      // sqflite_common_ffi runs work on another isolate, so yield to its event
      // loop instead of relying on pumpAndSettle around asynchronous loading.
      for (var attempt = 0; attempt < 4; attempt++) {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      await tester.pump();

      expect(
        find.text(
          'Gagal membaca produk: Produk tidak dapat dimuat. '
          'Periksa penyimpanan perangkat, lalu coba lagi.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('no such table'), findsNothing);
      expect(find.textContaining('products'), findsNothing);
      expect(find.textContaining('/data/user/0/'), findsNothing);
    },
  );
}
