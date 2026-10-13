import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/sqlite_sale_repository.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  test('checkout rejects product with unreviewed tax classification', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final products = SqliteProductRepository(database);

    await products.upsert(
      const Product(
        id: 'legacy-product-1',
        sku: 'KOPI-OLD',
        barcode: null,
        nameId: 'Kopi dari trial',
        price: 25000,
        ppnExempt: false,
        stockQty: 0,
        requiresReview: true,
      ),
    );
    await products.addInventoryLot(
      id: 'lot-legacy-review',
      productId: 'legacy-product-1',
      quantity: 1,
      unitCost: 10000,
      acquiredAtUtc: DateTime.utc(2026, 10, 12),
      batchNo: 'OPENING-1',
    );

    final service = PaymentService(
      repository: SqliteSaleRepository(database),
    );

    await expectLater(
      service.process(
        PaymentRequest(
          transactionId: 'TRX-REVIEW-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 10, 12, 12),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'legacy-product-1', quantity: 1),
          ],
        ),
      ),
      throwsA(isA<ProductRequiresReviewException>()),
    );

    expect(await database.database.query('sales'), isEmpty);
    expect(await database.database.query('journals'), isEmpty);
    expect(await database.database.query('outbox_events'), isEmpty);
    expect((await products.findById('legacy-product-1'))!.stockQty, 1);
  });
}
