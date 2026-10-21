import 'dart:convert';

import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  group('SqliteProductRepository', () {
    test('lists products and deletes only an unused product', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = SqliteProductRepository(database);

      expect(await repository.listAll(), isEmpty);

      await repository.upsert(
        const Product(
          id: 'P-UNUSED',
          sku: 'SKU-UNUSED',
          barcode: null,
          nameId: 'Produk Belum Dipakai',
          price: 12000,
          ppnExempt: false,
          stockQty: 0,
        ),
      );

      final products = await repository.listAll();
      expect(products, hasLength(1));
      expect(products.single.id, 'P-UNUSED');
      final productEvents = await database.database.query(
        'outbox_events',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>['product', 'P-UNUSED'],
      );
      expect(productEvents, hasLength(1));
      final eventPayload = jsonDecode(productEvents.single['payload']! as String) as Map<String, dynamic>;
      expect(eventPayload['product']['id'], 'P-UNUSED');
      expect(eventPayload['product'].containsKey('stock_qty'), isFalse);

      await repository.deleteIfUnused('P-UNUSED');
      expect(await repository.findById('P-UNUSED'), isNull);
      expect(
        await database.database.query(
          'outbox_events',
          where: 'entity_type = ? AND entity_id = ?',
          whereArgs: <Object?>['product', 'P-UNUSED'],
        ),
        isEmpty,
      );
    });

    test('does not delete a product with inventory lot history', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = SqliteProductRepository(database);

      await repository.upsert(
        const Product(
          id: 'P-HISTORY',
          sku: 'SKU-HISTORY',
          barcode: null,
          nameId: 'Produk Dengan Riwayat',
          price: 25000,
          ppnExempt: false,
          stockQty: 0,
        ),
      );
      await repository.addInventoryLot(
        id: 'LOT-HISTORY',
        productId: 'P-HISTORY',
        quantity: 2,
        unitCost: 15000,
        acquiredAtUtc: DateTime.utc(2026, 10, 12),
      );

      final receiptEvents = await database.database.query(
        'outbox_events',
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: <Object?>['inventory_receipt', 'P-HISTORY'],
      );
      expect(receiptEvents, hasLength(1));
      final receiptPayload = jsonDecode(receiptEvents.single['payload']! as String) as Map<String, dynamic>;
      expect(receiptPayload['receipt']['lot_id'], 'LOT-HISTORY');
      expect(receiptPayload['receipt']['quantity'], 2);

      expect(await repository.hasInventoryLots('P-HISTORY'), isTrue);
      await expectLater(
        repository.deleteIfUnused('P-HISTORY'),
        throwsA(isA<ProductValidationException>()),
      );
      expect(await repository.findById('P-HISTORY'), isNotNull);
    });
    test('editing product never overwrites stock ledger quantity', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = SqliteProductRepository(database);

      await repository.upsert(
        const Product(
          id: 'P-STOCK',
          sku: 'SKU-STOCK',
          barcode: null,
          nameId: 'Produk Stok',
          price: 10000,
          ppnExempt: false,
          stockQty: 0,
        ),
      );
      await repository.addInventoryLot(
        id: 'LOT-STOCK',
        productId: 'P-STOCK',
        quantity: 2,
        unitCost: 4000,
        acquiredAtUtc: DateTime.utc(2026, 10, 12),
      );

      final staleProduct = (await repository.findById('P-STOCK'))!
          .copyWith(nameId: 'Produk Stok Diperbarui', stockQty: 0);
      await repository.upsert(staleProduct);

      expect((await repository.findById('P-STOCK'))!.stockQty, 2);
    });

    test('does not change expiry policy after lots are recorded', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final repository = SqliteProductRepository(database);

      await repository.upsert(
        const Product(
          id: 'P-EXPIRY-LOCK',
          sku: 'SKU-EXPIRY-LOCK',
          barcode: null,
          nameId: 'Produk Expiry Lock',
          price: 10000,
          ppnExempt: false,
          stockQty: 0,
        ),
      );
      await repository.addInventoryLot(
        id: 'LOT-EXPIRY-LOCK',
        productId: 'P-EXPIRY-LOCK',
        quantity: 1,
        unitCost: 5000,
        acquiredAtUtc: DateTime.utc(2026, 10, 12),
      );

      final changed = (await repository.findById('P-EXPIRY-LOCK'))!
          .copyWith(trackExpiry: true);
      await expectLater(
        repository.upsert(changed),
        throwsA(isA<ProductValidationException>()),
      );
      expect((await repository.findById('P-EXPIRY-LOCK'))!.trackExpiry, isFalse);
    });
  });
}
