import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/sqlite_sale_repository.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  test('active product can be sold; inactive checkout is atomic and preserves history', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final products = SqliteProductRepository(database);

    await products.upsert(
      const Product(
        id: 'P-LIFECYCLE',
        sku: 'SKU-LIFECYCLE',
        barcode: null,
        nameId: 'Produk Siklus Hidup',
        price: 12000,
        ppnExempt: false,
        stockQty: 0,
      ),
    );
    await products.addInventoryLot(
      id: 'LOT-LIFECYCLE',
      productId: 'P-LIFECYCLE',
      quantity: 2,
      unitCost: 7000,
      acquiredAtUtc: DateTime.utc(2026, 10, 24),
      batchNo: 'BATCH-LIFECYCLE',
    );

    final checkout = PaymentService(repository: SqliteSaleRepository(database));
    await checkout.process(
      PaymentRequest(
        transactionId: 'TRX-LIFECYCLE-ACTIVE',
        method: PaymentMethod.cash,
        occurredAtUtc: DateTime.utc(2026, 10, 24, 2),
        lines: const <PaymentLineInput>[
          PaymentLineInput(productId: 'P-LIFECYCLE', quantity: 1),
        ],
      ),
    );
    expect(await database.database.query('sales'), hasLength(1));
    expect(await database.database.query('sale_items'), hasLength(1));

    await products.setActiveStatus(
      (await products.findById('P-LIFECYCLE'))!,
      isActive: false,
      reason: 'Produk dihentikan sementara untuk pengujian',
    );
    final existingSale = (await database.database.query('sales')).single;
    final existingSaleItem = (await database.database.query('sale_items')).single;
    final tablesBeforeFailedCheckout = <String, int>{};
    for (final table in <String>[
      'inventory_lots',
      'inventory_cost_layers',
      'inventory_movements',
      'sale_lot_allocations',
      'cost_layer_consumptions',
      'stock_movements',
      'sales',
      'sale_items',
      'journals',
      'journal_lines',
    ]) {
      final rows = await database.database.rawQuery('SELECT COUNT(*) AS value FROM $table');
      tablesBeforeFailedCheckout[table] = rows.single['value']! as int;
    }
    final stockBeforeFailedCheckout = (await products.findById('P-LIFECYCLE'))!.stockQty;
    final saleOutboxBefore = await database.database.rawQuery(
      "SELECT COUNT(*) AS value FROM outbox_events WHERE entity_type = 'sale'",
    );
    final saleOutboxCountBefore = saleOutboxBefore.single['value']! as int;

    await expectLater(
      checkout.process(
        PaymentRequest(
          transactionId: 'TRX-LIFECYCLE-INACTIVE',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 10, 24, 3),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-LIFECYCLE', quantity: 1),
          ],
        ),
      ),
      throwsA(isA<ProductInactiveException>()),
    );

    for (final entry in tablesBeforeFailedCheckout.entries) {
      final rows = await database.database.rawQuery(
        'SELECT COUNT(*) AS value FROM ${entry.key}',
      );
      expect(rows.single['value']! as int, entry.value, reason: entry.key);
    }
    expect((await database.database.query('sales')).single['id'], existingSale['id']);
    expect((await database.database.query('sale_items')).single['id'], existingSaleItem['id']);
    expect((await products.findById('P-LIFECYCLE'))!.stockQty, stockBeforeFailedCheckout);
    final saleOutboxAfter = await database.database.rawQuery(
      "SELECT COUNT(*) AS value FROM outbox_events WHERE entity_type = 'sale'",
    );
    expect(saleOutboxAfter.single['value']! as int, saleOutboxCountBefore);

    await products.setActiveStatus(
      (await products.findById('P-LIFECYCLE'))!,
      isActive: true,
      reason: 'Produk diaktifkan kembali setelah pengujian',
    );
    expect((await products.findById('P-LIFECYCLE'))!.isActive, isTrue);
    final audit = await database.database.query(
      'product_status_history',
      orderBy: 'product_version',
    );
    expect(audit, hasLength(2));
    expect(audit.first['from_active'], 1);
    expect(audit.first['to_active'], 0);
    expect(audit.first['reason'], contains('dihentikan'));
    expect(audit.last['from_active'], 0);
    expect(audit.last['to_active'], 1);
  });
}
