// test/pos/checkout/payment_service_test.dart

import 'dart:io';

import 'package:berkahtigaputeri_pos/features/accounting/exceptions/accounting_exceptions.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/features/accounting/models/journal_entry.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/sqlite_sale_repository.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

void main() {
  group('PaymentService + SQLite transaction', () {
    test('diskon diposting ke 4-4020 dan PPN dihitung setelah diskon', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-001',
        sku: 'SKU-001',
        name: 'Produk Kena PPN',
        price: 100000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-001',
            quantity: 1,
            unitCost: 60000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final service = PaymentService(
        repository: SqliteSaleRepository(database),
      );

      final result = await service.process(
        PaymentRequest(
          transactionId: 'TRX-PAY-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 10),
          transactionDiscountAmount: 10000,
          lines: const <PaymentLineInput>[
            PaymentLineInput(
              productId: 'P-001',
              quantity: 1,
              itemDiscountAmount: 10000,
            ),
          ],
        ),
      );

      expect(result.grossAmount, 100000);
      expect(result.discountAmount, 20000);
      expect(result.taxableDpp, 80000);
      expect(result.exemptDpp, 0);
      expect(result.ppnAmount, 8800);
      expect(result.grandTotal, 88800);
      expect(result.cogsAmount, 60000);
      expect(result.journalEntry.isBalanced, isTrue);

      final cash = _line(result, '1-1010');
      final discount = _line(result, '4-4020');
      final sales = _line(result, '4-4010');
      final ppn = _line(result, '2-2010');
      final cogs = _line(result, '5-5010');
      final inventory = _line(result, '1-1040');

      expect(cash.debit, 88800);
      expect(discount.debit, 20000);
      expect(sales.credit, 100000);
      expect(ppn.credit, 8800);
      expect(cogs.debit, 60000);
      expect(inventory.credit, 60000);

      final storedProduct = await products.findById('P-001');
      expect(storedProduct!.stockQty, 0);

      expect(await _count(database, 'outbox_events'), 1);
    });

    test('cart campuran mengalokasikan diskon dan PPN hanya ke DPP kena pajak', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-TAX',
        sku: 'SKU-TAX',
        name: 'Produk Pajak',
        price: 100000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-TAX',
            quantity: 1,
            unitCost: 50000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      await _seedProduct(
        products,
        id: 'P-EXEMPT',
        sku: 'SKU-EXEMPT',
        name: 'Produk Bebas PPN',
        price: 50000,
        ppnExempt: true,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-EXEMPT',
            quantity: 1,
            unitCost: 20000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final service = PaymentService(
        repository: SqliteSaleRepository(database),
      );

      final result = await service.process(
        PaymentRequest(
          transactionId: 'TRX-MIXED-001',
          method: PaymentMethod.qris,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 11),
          transactionDiscountAmount: 15000,
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-TAX', quantity: 1),
            PaymentLineInput(productId: 'P-EXEMPT', quantity: 1),
          ],
        ),
      );

      expect(result.grossAmount, 150000);
      expect(result.discountAmount, 15000);
      expect(result.taxableDpp, 90000);
      expect(result.exemptDpp, 45000);
      expect(result.ppnAmount, 9900);
      expect(result.grandTotal, 144900);
      expect(result.cogsAmount, 70000);

      final qris = _line(result, '1-1020');
      expect(qris.debit, 144900);
      expect(_line(result, '2-2010').credit, 9900);

      final itemRows = await database.database.query(
        'sale_items',
        orderBy: 'line_no',
      );
      expect(itemRows[0]['transaction_discount_amount'], 10000);
      expect(itemRows[0]['ppn_exempt'], 0);
      expect(itemRows[1]['transaction_discount_amount'], 5000);
      expect(itemRows[1]['ppn_exempt'], 1);
    });

    test('FIFO mengambil lot tertua dan menghitung COGS otomatis', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-FIFO',
        sku: 'SKU-FIFO',
        name: 'Produk FIFO',
        price: 100000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-OLD',
            quantity: 1,
            unitCost: 30000,
            acquiredAtUtc: DateTime.utc(2026, 8, 1),
          ),
          _LotSeed(
            id: 'LOT-NEW',
            quantity: 2,
            unitCost: 40000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final service = PaymentService(
        repository: SqliteSaleRepository(database),
      );

      final result = await service.process(
        PaymentRequest(
          transactionId: 'TRX-FIFO-001',
          method: PaymentMethod.transfer,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 12),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-FIFO', quantity: 2),
          ],
        ),
      );

      expect(result.cogsAmount, 70000);
      expect(_line(result, '1-1030').debit, result.grandTotal);
      expect(_line(result, '5-5010').debit, 70000);
      expect(_line(result, '1-1040').credit, 70000);

      final lotRows = await database.database.query(
        'inventory_lots',
        orderBy: 'first_received_at_utc, id',
      );
      expect(lotRows[0]['on_hand_qty'], 0);
      expect(lotRows[1]['on_hand_qty'], 1);

      final costLayerRows = await database.database.query(
        'inventory_cost_layers',
        orderBy: 'acquired_at_utc, id',
      );
      expect(costLayerRows[0]['remaining_qty'], 0);
      expect(costLayerRows[1]['remaining_qty'], 1);

      final movementRows = await database.database.query(
        'stock_movements',
        orderBy: 'id',
      );
      expect(movementRows, hasLength(2));
      expect(
        movementRows.fold<int>(
          0,
          (sum, row) => sum + (row['total_cost']! as int),
        ),
        70000,
      );

      final storedProduct = await products.findById('P-FIFO');
      expect(storedProduct!.stockQty, 1);
    });

    test('retry setelah service dibuat ulang tidak double post atau kurangi stok lagi', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-IDEMP',
        sku: 'SKU-IDEMP',
        name: 'Produk Idempoten',
        price: 25000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-IDEMP',
            quantity: 2,
            unitCost: 12000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final request = PaymentRequest(
        transactionId: 'TRX-IDEMP-001',
        method: PaymentMethod.cash,
        occurredAtUtc: DateTime.utc(2026, 9, 29, 13),
        lines: const <PaymentLineInput>[
          PaymentLineInput(productId: 'P-IDEMP', quantity: 1),
        ],
      );

      final first = await PaymentService(
        repository: SqliteSaleRepository(database),
      ).process(request);

      final second = await PaymentService(
        repository: SqliteSaleRepository(database),
      ).process(request);

      expect(first.alreadyProcessed, isFalse);
      expect(second.alreadyProcessed, isTrue);
      expect(second.journalEntry.sameAs(first.journalEntry), isTrue);

      expect(
        (await products.findById('P-IDEMP'))!.stockQty,
        1,
      );
      expect(await _count(database, 'sales'), 1);
      expect(await _count(database, 'journals'), 1);
      expect(await _count(database, 'outbox_events'), 1);
      expect(await _count(database, 'stock_movements'), 1);
    });

    test('transactionId sama dengan request berbeda ditolak tanpa mutasi kedua', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-CONFLICT',
        sku: 'SKU-CONFLICT',
        name: 'Produk Konflik',
        price: 20000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-CONFLICT',
            quantity: 3,
            unitCost: 10000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final service = PaymentService(
        repository: SqliteSaleRepository(database),
      );

      await service.process(
        PaymentRequest(
          transactionId: 'TRX-CONFLICT-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 14),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-CONFLICT', quantity: 1),
          ],
        ),
      );

      await expectLater(
        service.process(
          PaymentRequest(
            transactionId: 'TRX-CONFLICT-001',
            method: PaymentMethod.cash,
            occurredAtUtc: DateTime.utc(2026, 9, 29, 14),
            lines: const <PaymentLineInput>[
              PaymentLineInput(productId: 'P-CONFLICT', quantity: 2),
            ],
          ),
        ),
        throwsA(isA<DuplicateTransactionIdException>()),
      );

      expect((await products.findById('P-CONFLICT'))!.stockQty, 2);
      expect(await _count(database, 'sales'), 1);
      expect(await _count(database, 'journals'), 1);
      expect(await _count(database, 'outbox_events'), 1);
    });

    test('stok tidak cukup me-roll back sale, jurnal, stok movement, dan outbox', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-ROLLBACK',
        sku: 'SKU-ROLLBACK',
        name: 'Produk Terbatas',
        price: 30000,
        ppnExempt: false,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-ROLLBACK',
            quantity: 1,
            unitCost: 15000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final service = PaymentService(
        repository: SqliteSaleRepository(database),
      );

      await expectLater(
        service.process(
          PaymentRequest(
            transactionId: 'TRX-ROLLBACK-001',
            method: PaymentMethod.cash,
            occurredAtUtc: DateTime.utc(2026, 9, 29, 15),
            lines: const <PaymentLineInput>[
              PaymentLineInput(productId: 'P-ROLLBACK', quantity: 2),
            ],
          ),
        ),
        throwsA(isA<InsufficientStockException>()),
      );

      expect((await products.findById('P-ROLLBACK'))!.stockQty, 1);
      final lots = await database.database.query('inventory_lots');
      expect(lots.single['on_hand_qty'], 1);
      final costLayers =
          await database.database.query('inventory_cost_layers');
      expect(costLayers.single['remaining_qty'], 1);
      expect(await _count(database, 'sales'), 0);
      expect(await _count(database, 'sale_items'), 0);
      expect(await _count(database, 'journals'), 0);
      expect(await _count(database, 'journal_lines'), 0);
      expect(await _count(database, 'stock_movements'), 0);
      expect(await _count(database, 'outbox_events'), 0);
    });

    test('outbox insert failure rolls back all prior checkout writes', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);
      await _seedProduct(
        products,
        id: 'P-ATOMIC',
        sku: 'SKU-ATOMIC',
        name: 'Produk Atomic',
        price: 10000,
        ppnExempt: true,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-ATOMIC',
            quantity: 2,
            unitCost: 4000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      // Adding the opening lot creates one legitimate inventory receipt
      // movement before checkout. The failed sale must preserve that baseline.
      final initialInventoryMovementCount =
          await _count(database, 'inventory_movements');
      const transactionId = 'TRX-ATOMIC-FAIL';
      await database.database.insert('outbox_events', <String, Object?>{
        'id': 'outbox:sale:$transactionId',
        'entity_type': 'test-sentinel',
        'entity_id': 'sentinel',
        'payload': '{}',
        'status': 'pending',
        'retry_count': 0,
        'created_at_utc': DateTime.utc(2026, 9, 1).toIso8601String(),
      });

      await expectLater(
        PaymentService(repository: SqliteSaleRepository(database)).process(
          PaymentRequest(
            transactionId: transactionId,
            method: PaymentMethod.cash,
            occurredAtUtc: DateTime.utc(2026, 9, 29, 16),
            lines: const <PaymentLineInput>[
              PaymentLineInput(productId: 'P-ATOMIC', quantity: 1),
            ],
          ),
        ),
        throwsA(isA<DatabaseException>()),
      );

      expect((await products.findById('P-ATOMIC'))!.stockQty, 2);
      expect((await database.database.query('inventory_lots')).single['on_hand_qty'], 2);
      expect((await database.database.query('inventory_cost_layers')).single['remaining_qty'], 2);
      for (final table in <String>[
        'sales', 'sale_items', 'journals', 'journal_lines', 'stock_movements',
      ]) {
        expect(await _count(database, table), 0, reason: '$table must roll back');
      }
      expect(
        await _count(database, 'inventory_movements'),
        initialInventoryMovementCount,
        reason: 'inventory movements must roll back to the pre-checkout baseline',
      );
      expect(await _count(database, 'outbox_events'), 1);
      final sentinel = (await database.database.query('outbox_events')).single;
      expect(sentinel['entity_id'], 'sentinel');
      expect(sentinel['payload'], '{}');
    });

    test('two concurrent checkouts cannot sell the same last unit twice', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);
      await _seedProduct(
        products,
        id: 'P-RACE',
        sku: 'SKU-RACE',
        name: 'Produk Race',
        price: 15000,
        ppnExempt: true,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-RACE',
            quantity: 1,
            unitCost: 7000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );
      final service = PaymentService(repository: SqliteSaleRepository(database));
      PaymentRequest request(String id) => PaymentRequest(
            transactionId: id,
            method: PaymentMethod.cash,
            occurredAtUtc: DateTime.utc(2026, 9, 29, 17),
            lines: const <PaymentLineInput>[
              PaymentLineInput(productId: 'P-RACE', quantity: 1),
            ],
          );

      final results = await Future.wait<Object>(<Future<Object>>[
        _capturePayment(service, request('TRX-RACE-A')),
        _capturePayment(service, request('TRX-RACE-B')),
      ]);
      expect(results.whereType<PaymentResult>(), hasLength(1));
      expect(results.whereType<InsufficientStockException>(), hasLength(1));
      expect((await products.findById('P-RACE'))!.stockQty, 0);
      expect((await database.database.query('inventory_lots')).single['on_hand_qty'], 0);
      expect((await database.database.query('inventory_cost_layers')).single['remaining_qty'], 0);
      expect(await _count(database, 'sales'), 1);
      expect(await _count(database, 'sale_items'), 1);
      expect(await _count(database, 'journals'), 1);
      expect(await _count(database, 'outbox_events'), 1);
    });

    test('pending sale and outbox survive database close/reopen and local replay', () async {
      sqfliteFfiInit();
      final temporaryDirectory = await Directory.systemTemp.createTemp('berkah-pos-offline-');
      PosDatabase? activeDatabase;
      try {
        final dbPath = p.join(temporaryDirectory.path, 'offline-checkout.db');
        activeDatabase = await PosDatabase.openAt(dbPath, factory: databaseFactoryFfi);
        final products = SqliteProductRepository(activeDatabase);
        await _seedProduct(
          products,
          id: 'P-DURABLE',
          sku: 'SKU-DURABLE',
          name: 'Produk Durable',
          price: 12000,
          ppnExempt: true,
          lots: <_LotSeed>[
            _LotSeed(
              id: 'LOT-DURABLE',
              quantity: 2,
              unitCost: 5000,
              acquiredAtUtc: DateTime.utc(2026, 9, 1),
            ),
          ],
        );
        final request = PaymentRequest(
          transactionId: 'TRX-DURABLE-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 18),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-DURABLE', quantity: 1),
          ],
        );
        final first = await PaymentService(
          repository: SqliteSaleRepository(activeDatabase),
        ).process(request);
        expect(first.alreadyProcessed, isFalse);
        final pendingBeforeClose = (await activeDatabase.database.query('outbox_events')).single;
        expect(pendingBeforeClose['id'], 'outbox:sale:TRX-DURABLE-001');
        expect(pendingBeforeClose['status'], 'pending');
        await activeDatabase.close();
        activeDatabase = null;

        activeDatabase = await PosDatabase.openAt(dbPath, factory: databaseFactoryFfi);
        final replay = await PaymentService(
          repository: SqliteSaleRepository(activeDatabase),
        ).process(request);
        expect(replay.alreadyProcessed, isTrue);
        expect(replay.saleId, first.saleId);
        expect(await _count(activeDatabase, 'sales'), 1);
        expect(await _count(activeDatabase, 'sale_items'), 1);
        expect(await _count(activeDatabase, 'journals'), 1);
        expect(await _count(activeDatabase, 'outbox_events'), 1);
        final pendingAfterReopen = (await activeDatabase.database.query('outbox_events')).single;
        expect(pendingAfterReopen['status'], 'pending');
        expect((await activeDatabase.database.query('products')).single['stock_qty'], 1);
      } finally {
        await activeDatabase?.close();
        await temporaryDirectory.delete(recursive: true);
      }
    });

    test('transaksi malam WIB disimpan pada businessDate Indonesia', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      final products = SqliteProductRepository(database);

      await _seedProduct(
        products,
        id: 'P-DATE',
        sku: 'SKU-DATE',
        name: 'Produk Tanggal',
        price: 10000,
        ppnExempt: true,
        lots: <_LotSeed>[
          _LotSeed(
            id: 'LOT-DATE',
            quantity: 1,
            unitCost: 5000,
            acquiredAtUtc: DateTime.utc(2026, 9, 1),
          ),
        ],
      );

      final result = await PaymentService(
        repository: SqliteSaleRepository(database),
      ).process(
        PaymentRequest(
          transactionId: 'TRX-DATE-001',
          method: PaymentMethod.cash,
          occurredAtUtc: DateTime.utc(2026, 9, 29, 17, 30),
          lines: const <PaymentLineInput>[
            PaymentLineInput(productId: 'P-DATE', quantity: 1),
          ],
        ),
      );

      expect(result.businessDate, '2026-09-30');
      expect(result.journalEntry.businessDate, '2026-09-30');
      expect(result.journalEntry.timezone, 'Asia/Jakarta');
    });
  });
}

JournalLine _line(PaymentResult result, String accountCode) {
  return result.journalEntry.lines.singleWhere(
    (line) => line.accountCode == accountCode,
  );
}

Future<Object> _capturePayment(
  PaymentService service,
  PaymentRequest request,
) async {
  try {
    return await service.process(request);
  } catch (error) {
    return error;
  }
}

Future<int> _count(PosDatabase database, String table) async {
  final rows = await database.database.rawQuery(
    'SELECT COUNT(*) AS value FROM $table',
  );
  return rows.single['value']! as int;
}

Future<void> _seedProduct(
  SqliteProductRepository repository, {
  required String id,
  required String sku,
  required String name,
  required int price,
  required bool ppnExempt,
  required List<_LotSeed> lots,
}) async {
  await repository.upsert(
    Product(
      id: id,
      sku: sku,
      barcode: null,
      nameId: name,
      price: price,
      ppnExempt: ppnExempt,
      stockQty: 0,
    ),
  );

  for (final lot in lots) {
    await repository.addInventoryLot(
      id: lot.id,
      productId: id,
      quantity: lot.quantity,
      unitCost: lot.unitCost,
      acquiredAtUtc: lot.acquiredAtUtc,
    );
  }
}

class _LotSeed {
  const _LotSeed({
    required this.id,
    required this.quantity,
    required this.unitCost,
    required this.acquiredAtUtc,
  });

  final String id;
  final int quantity;
  final int unitCost;
  final DateTime acquiredAtUtc;
}

