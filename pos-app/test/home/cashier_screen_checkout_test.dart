import 'package:berkahtigaputeri_pos/core/config/app_identity_store.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:berkahtigaputeri_pos/main.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_database.dart';

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
  testWidgets(
    'cashier screen commits sale, stock, journal and pending outbox together',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();
      final database = await openTestDatabase();
      addTearDown(database.close);
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final products = SqliteProductRepository(database);
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

      final sales = await database.database.query('sales');
      final saleItems = await database.database.query('sale_items');
      final journals = await database.database.query('journals');
      final journalLines = await database.database.query('journal_lines');
      final stockMovements = await database.database.query('stock_movements');
      final outbox = await database.database.query('outbox_events');
      final product = (await products.findById('P-CHECKOUT-UI'))!;

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
