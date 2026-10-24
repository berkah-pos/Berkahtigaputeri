// test/inventory/fefo_checkout_test.dart

import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/features/inventory/repositories/sqlite_inventory_repository.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/sqlite_sale_repository.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  group('Apotek FEFO checkout', () {
    test('physical FEFO is independent from financial FIFO', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _createExpiryProduct(
        products,
        id: 'P-FEFO-FIFO',
        minShelfLifeDays: 0,
      );

      await products.addInventoryLot(
        id: 'LOT-LATE-EXPIRY',
        productId: 'P-FEFO-FIFO',
        batchNo: 'B-LATE',
        expiryDate: DateTime(2027, 1, 31),
        quantity: 1,
        unitCost: 30000,
        acquiredAtUtc: DateTime.utc(2026, 8, 1),
      );
      await products.addInventoryLot(
        id: 'LOT-EARLY-EXPIRY',
        productId: 'P-FEFO-FIFO',
        batchNo: 'B-EARLY',
        expiryDate: DateTime(2026, 10, 15),
        quantity: 1,
        unitCost: 40000,
        acquiredAtUtc: DateTime.utc(2026, 9, 1),
      );

      final result = await PaymentService(
        repository: SqliteSaleRepository(database),
      ).process(
        PaymentRequest(
          transactionId: 'TRX-FEFO-FIFO-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 30, 3),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-FEFO-FIFO', quantity: 1),
          ],
        ),
      );

      expect(result.cogsAmount, 30000);

      final physical = await database.database.query(
        'inventory_lots',
        orderBy: 'id',
      );
      final byId = <String, Map<String, Object?>>{
        for (final row in physical) row['id']! as String: row,
      };
      expect(byId['LOT-EARLY-EXPIRY']!['on_hand_qty'], 0);
      expect(byId['LOT-LATE-EXPIRY']!['on_hand_qty'], 1);

      final costs = await database.database.query(
        'inventory_cost_layers',
        orderBy: 'acquired_at_utc, id',
      );
      expect(costs[0]['id'], 'cost:LOT-LATE-EXPIRY');
      expect(costs[0]['remaining_qty'], 0);
      expect(costs[1]['remaining_qty'], 1);

      final allocations = await database.database.query(
        'sale_lot_allocations',
      );
      expect(allocations.single['lot_id'], 'LOT-EARLY-EXPIRY');

      final costAudit = await database.database.query(
        'cost_layer_consumptions',
      );
      expect(costAudit.single['cost_layer_id'], 'cost:LOT-LATE-EXPIRY');
      expect(costAudit.single['total_cost'], 30000);
    });

    test('active hold removes a lot from FEFO eligibility', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);
      final inventory = SqliteInventoryRepository(database);

      await _createExpiryProduct(products, id: 'P-HOLD');
      await products.addInventoryLot(
        id: 'LOT-HOLD',
        productId: 'P-HOLD',
        batchNo: 'B-HOLD',
        expiryDate: DateTime(2026, 10, 5),
        quantity: 1,
        unitCost: 10000,
        acquiredAtUtc: DateTime.utc(2026, 9, 1),
      );
      await products.addInventoryLot(
        id: 'LOT-NEXT',
        productId: 'P-HOLD',
        batchNo: 'B-NEXT',
        expiryDate: DateTime(2026, 11, 5),
        quantity: 1,
        unitCost: 11000,
        acquiredAtUtc: DateTime.utc(2026, 9, 2),
      );

      await inventory.placeHold(
        id: 'HOLD-001',
        lotId: 'LOT-HOLD',
        holdType: 'recall',
        reason: 'Supplier recall',
        createdAtUtc: DateTime.utc(2026, 9, 30),
      );

      await PaymentService(
        repository: SqliteSaleRepository(database),
      ).process(
        PaymentRequest(
          transactionId: 'TRX-HOLD-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 30, 3),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-HOLD', quantity: 1),
          ],
        ),
      );

      final allocations = await database.database.query(
        'sale_lot_allocations',
      );
      expect(allocations.single['lot_id'], 'LOT-NEXT');

      final lots = await inventory.listLotsForProduct('P-HOLD');
      final held = lots.singleWhere((lot) => lot.id == 'LOT-HOLD');
      expect(held.onHandQty, 1);
    });

    test(
      'checkout rejects a known-expired lot when tracking is disabled and '
      'the expiry maintenance job has not run',
      () async {
        final database = await openTestDatabase();
        addTearDown(database.close);
        final products = SqliteProductRepository(database);

        await _createNonExpiryProduct(products, id: 'P-UNTRACKED-EXPIRED');
        await products.addInventoryLot(
          id: 'LOT-EXPIRED-UNTRACKED',
          productId: 'P-UNTRACKED-EXPIRED',
          batchNo: 'B-EXPIRED',
          expiryDate: DateTime(2026, 9, 29),
          quantity: 1,
          unitCost: 10000,
          acquiredAtUtc: DateTime.utc(2026, 9, 1),
        );

        // This proves checkout is safe without relying on markExpiredLots().
        final before = (await database.database.query('inventory_lots')).single;
        expect(before['status'], 'saleable');
        expect(before['on_hand_qty'], 1);

        await expectLater(
          PaymentService(
            repository: SqliteSaleRepository(database),
          ).process(
            PaymentRequest(
              transactionId: 'TRX-EXPIRED-UNTRACKED-001',
              method: PaymentMethod.cash,
              occurredAtUtc: DateTime.utc(2026, 9, 30, 3),
              lines: const <PaymentLineInput>[
                PaymentLineInput(
                  productId: 'P-UNTRACKED-EXPIRED',
                  quantity: 1,
                ),
              ],
            ),
          ),
          throwsA(isA<InsufficientStockException>()),
        );

        final after = (await database.database.query('inventory_lots')).single;
        expect(after['on_hand_qty'], 1);
        expect(await _count(database, 'sales'), 0);
        expect(await _count(database, 'sale_lot_allocations'), 0);
        expect(await _count(database, 'inventory_movements'), 1);
      },
    );

    test('minimum shelf life excludes near-expiry stock', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _createExpiryProduct(
        products,
        id: 'P-SHELF',
        minShelfLifeDays: 30,
      );
      await products.addInventoryLot(
        id: 'LOT-TOO-SOON',
        productId: 'P-SHELF',
        batchNo: 'B-SOON',
        expiryDate: DateTime(2026, 10, 20),
        quantity: 1,
        unitCost: 10000,
        acquiredAtUtc: DateTime.utc(2026, 9, 1),
      );

      await expectLater(
        PaymentService(
          repository: SqliteSaleRepository(database),
        ).process(
          PaymentRequest(
            transactionId: 'TRX-SHELF-001',
            method: PaymentMethod.cash,
            occurredAtUtc: DateTime.utc(2026, 9, 30, 3),
            lines: const <PaymentLineInput>[
              PaymentLineInput(productId: 'P-SHELF', quantity: 1),
            ],
          ),
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      final lot = (await database.database.query('inventory_lots')).single;
      expect(lot['on_hand_qty'], 1);
      expect(await _count(database, 'sales'), 0);
      expect(await _count(database, 'inventory_movements'), 1);
    });

    test('expiry-tracked receipt requires batch and expiry date', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _createExpiryProduct(products, id: 'P-RECEIVE');

      await expectLater(
        products.addInventoryLot(
          id: 'LOT-MISSING-EXPIRY',
          productId: 'P-RECEIVE',
          quantity: 1,
          unitCost: 10000,
          acquiredAtUtc: DateTime.utc(2026, 9, 30),
        ),
        throwsA(isA<ProductValidationException>()),
      );

      expect((await products.findById('P-RECEIVE'))!.stockQty, 0);
      expect(await _count(database, 'inventory_lots'), 0);
      expect(await _count(database, 'inventory_cost_layers'), 0);
    });
  });
}

Future<void> _createExpiryProduct(
  SqliteProductRepository products, {
  required String id,
  int minShelfLifeDays = 0,
}) {
  return products.upsert(
    Product(
      id: id,
      sku: 'SKU-$id',
      barcode: null,
      nameId: 'Obat $id',
      price: 50000,
      ppnExempt: false,
      stockQty: 0,
      trackExpiry: true,
      minShelfLifeDays: minShelfLifeDays,
    ),
  );
}

Future<void> _createNonExpiryProduct(
  SqliteProductRepository products, {
  required String id,
}) {
  return products.upsert(
    Product(
      id: id,
      sku: 'SKU-$id',
      barcode: null,
      nameId: 'Produk $id',
      price: 50000,
      ppnExempt: false,
      stockQty: 0,
      trackExpiry: false,
      minShelfLifeDays: 0,
    ),
  );
}

Future<int> _count(PosDatabase database, String table) async {
  final rows = await database.database.rawQuery(
    'SELECT COUNT(*) AS value FROM $table',
  );
  return rows.single['value']! as int;
}