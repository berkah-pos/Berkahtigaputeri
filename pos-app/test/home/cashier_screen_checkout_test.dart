import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:berkahtigaputeri_pos/main.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

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
  testWidgets(
    'cashier screen commits sale, stock, journal and pending outbox together',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final database = (await tester.runAsync(openTestDatabase))!;
      addTearDown(() async {
        await tester.runAsync(database.close);
      });

      final products = SqliteProductRepository(database);
      await tester.runAsync(() async {
        await products.upsert(
          const Product(
            id: 'P-CHECKOUT-UI',
            sku: 'SKU-CHECKOUT-UI',
            barcode: '899000000001',
            nameId: 'Kopi Integrasi',
            price: 25000,
            ppnExempt: false,
            stockQty: 0,
          ),
        );
        await products.addInventoryLot(
          id: 'LOT-CHECKOUT-UI',
          productId: 'P-CHECKOUT-UI',
          quantity: 3,
          unitCost: 10000,
          acquiredAtUtc: DateTime.utc(2026, 10, 12, 12),
          batchNo: 'BATCH-CHECKOUT-UI',
        );
      });

      await tester.pumpWidget(
        BerkahTigaPuteriApp(
          database: database,
          identityStore: AppIdentityStore(preferences),
        ),
      );
      await _settle(tester, 'initial app');

      await _tap(tester, find.text('Lanjutkan sebagai kasir lokal'), 'tap-2');
      await _settle(tester, 'local mode');
      await _tap(tester, find.text('Kasir'), 'tap-3');
      await _settle(tester, 'cashier tab');

      expect(find.text('Kopi Integrasi'), findsOneWidget);
      await _tap(tester, find.byTooltip('Tambahkan ke keranjang'), 'tap-4');
      await _settle(tester, 'add item');

      expect(find.text('Selesaikan checkout'), findsOneWidget);
      await _tap(tester, find.text('Selesaikan checkout'), 'tap-5');
      await _settle(tester, 'checkout');

      expect(find.text('Transaksi tersimpan'), findsOneWidget);
      expect(
        find.textContaining('Sinkronisasi cloud belum aktif'),
        findsOneWidget,
      );

      late List<Map<String, Object?>> sales;
      late List<Map<String, Object?>> saleItems;
      late List<Map<String, Object?>> journals;
      late List<Map<String, Object?>> journalLines;
      late List<Map<String, Object?>> stockMovements;
      late List<Map<String, Object?>> outbox;
      late Product product;
      await tester.runAsync(() async {
        sales = await database.database.query('sales');
        saleItems = await database.database.query('sale_items');
        journals = await database.database.query('journals');
        journalLines = await database.database.query('journal_lines');
        stockMovements = await database.database.query('stock_movements');
        outbox = await database.database.query('outbox_events');
        product = (await products.findById('P-CHECKOUT-UI'))!;
      });

      expect(sales, hasLength(1));
      expect((sales.single['grand_total'] as num).toInt(), greaterThan(0));
      expect(saleItems, hasLength(1));
      expect((saleItems.single['quantity'] as num).toInt(), 1);
      expect(journals, hasLength(1));
      expect(journalLines, isNotEmpty);
      expect(stockMovements, isNotEmpty);
      expect(outbox, hasLength(1));
      expect(outbox.single['status'], isNot('acknowledged'));
      expect(product.stockQty, 2);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
