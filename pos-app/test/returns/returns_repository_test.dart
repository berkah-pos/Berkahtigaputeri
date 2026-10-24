import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/sqlite_sale_repository.dart';
import 'package:berkahtigaputeri_pos/features/returns/returns_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(() => sqfliteFfiInit());

  Future<PosDatabase> seededDatabase() async {
    final database = await openTestDatabase();
    await database.database.insert('products', <String, Object?>{
      'id': 'P-RETURN',
      'sku': 'SKU-RETURN',
      'barcode': null,
      'name_id': 'Produk return test',
      'price': 10000,
      'ppn_exempt': 0,
      'stock_qty': 2,
      'track_expiry': 0,
      'min_shelf_life_days': 0,
      'requires_review': 0,
      'is_active': 1,
      'version': 1,
    });
    await database.database.insert('inventory_lots', <String, Object?>{
      'id': 'LOT-RETURN',
      'product_id': 'P-RETURN',
      'batch_no': 'BATCH-RETURN',
      'expiry_date': '2030-12-31',
      'first_received_at_utc': '2026-10-01T00:00:00.000Z',
      'on_hand_qty': 2,
      'reserved_qty': 0,
      'status': 'saleable',
    });
    await database.database.insert('inventory_cost_layers', <String, Object?>{
      'id': 'COST-RETURN',
      'product_id': 'P-RETURN',
      'lot_id': 'LOT-RETURN',
      'acquired_at_utc': '2026-10-01T00:00:00.000Z',
      'remaining_qty': 2,
      'unit_cost': 5000,
    });
    return database;
  }

  test('partial return is atomic, idempotent, quarantined and reconciles FIFO value', () async {
    final database = await seededDatabase();
    addTearDown(database.close);

    final sale = await PaymentService(
      repository: SqliteSaleRepository(database),
    ).process(PaymentRequest(
      transactionId: 'sale-return-001',
      method: PaymentMethod.cash,
      occurredAtUtc: DateTime.utc(2026, 10, 23, 3),
      lines: const <PaymentLineInput>[
        PaymentLineInput(productId: 'P-RETURN', quantity: 2),
      ],
    ));

    final repository = ReturnsRepository(
      database: database,
      actorId: 'user-1',
      deviceId: 'device-1',
    );
    final result = await repository.processReturn(
      saleId: sale.saleId,
      quantities: <String, int>{'sale:sale-return-001:item:0': 1},
      type: SaleReturnType.returnItems,
      reason: 'Test partial return',
      returnId: 'return-stable-001',
    );

    expect(result['refund_total'], 11100);
    expect(result['cogs_amount'], 5000);
    expect(result['already_processed'], false);

    final db = database.database;
    expect((await db.query('sale_returns')).length, 1);
    expect((await db.query('sale_return_items')).single['quantity'], 1);
    final returnedLot = (await db.query(
      'inventory_lots',
      where: 'source_return_id = ?',
      whereArgs: <Object?>['return-stable-001'],
    )).single;
    expect(returnedLot['status'], 'quarantine');
    expect(returnedLot['origin_lot_id'], 'LOT-RETURN');
    expect(returnedLot['on_hand_qty'], 1);

    final restoredCostLayer = (await db.query(
      'inventory_cost_layers',
      where: 'id = ?',
      whereArgs: <Object?>['COST-RETURN'],
    )).single;
    expect(restoredCostLayer['lot_id'], 'LOT-RETURN');
    expect(restoredCostLayer['remaining_qty'], 1);
    expect(restoredCostLayer['unit_cost'], 5000);
    final costProvenance = (await db.query(
      'sale_return_cost_layers',
      where: 'original_sale_id = ?',
      whereArgs: <Object?>[sale.saleId],
    )).single;
    expect(costProvenance['source_cost_layer_id'], 'COST-RETURN');
    expect(costProvenance['returned_cost_layer_id'], 'COST-RETURN');

    final product = (await db.query('products', where: 'id = ?', whereArgs: <Object?>['P-RETURN'])).single;
    expect(product['stock_qty'], 1);
    final outbox = (await db.query(
      'outbox_events',
      where: 'id = ?',
      whereArgs: <Object?>['outbox:sale_return:return-stable-001'],
    )).single;
    expect(outbox['entity_type'], 'sale_return');
    expect(outbox['status'], 'pending');

    final postedJournal = (await db.query(
      'journals',
      where: 'transaction_id = ?',
      whereArgs: <Object?>['return:return-stable-001'],
    )).single;
    final journalLines = await db.query(
      'journal_lines',
      where: 'journal_id = ?',
      whereArgs: <Object?>[postedJournal['id']],
    );
    final debit = journalLines.fold<int>(0, (sum, row) => sum + (row['debit']! as num).toInt());
    final credit = journalLines.fold<int>(0, (sum, row) => sum + (row['credit']! as num).toInt());
    expect(debit, credit);

    final report = (await db.rawQuery('''
      SELECT
        COUNT(*) AS sale_count,
        COALESCE(SUM(grand_total), 0) AS revenue,
        COALESCE(SUM(cogs_amount), 0) AS cogs,
        (SELECT COUNT(*) FROM sale_returns) AS return_count,
        (SELECT COALESCE(SUM(refund_total), 0) FROM sale_returns) AS refund_total,
        (SELECT COALESCE(SUM(cogs_amount), 0) FROM sale_returns) AS returned_cogs,
        (SELECT COALESCE(SUM(on_hand_qty), 0) FROM inventory_lots WHERE status = 'saleable') AS saleable_qty,
        (SELECT COALESCE(SUM(on_hand_qty), 0) FROM inventory_lots WHERE status = 'quarantine') AS quarantine_qty,
        (SELECT COUNT(*) FROM journals) AS journal_count,
        (SELECT COUNT(*) FROM (
          SELECT j.id
          FROM journals j LEFT JOIN journal_lines jl ON jl.journal_id = j.id
          GROUP BY j.id
          HAVING COALESCE(SUM(jl.debit), 0) <> COALESCE(SUM(jl.credit), 0)
        )) AS unbalanced_journals
      FROM sales
    ''')).single;
    expect((report['revenue']! as num).toInt() - (report['refund_total']! as num).toInt(), 11100);
    expect((report['cogs']! as num).toInt() - (report['returned_cogs']! as num).toInt(), 5000);
    expect(report['return_count'], 1);
    expect(report['saleable_qty'], 0);
    expect(report['quarantine_qty'], 1);
    expect(report['journal_count'], 2);
    expect(report['unbalanced_journals'], 0);

    final aggregateStock = (await db.rawQuery(
      'SELECT COALESCE(SUM(stock_qty), 0) AS value FROM products WHERE id = ?',
      <Object?>['P-RETURN'],
    )).single['value']! as int;
    final physicalStock = (await db.rawQuery(
      'SELECT COALESCE(SUM(on_hand_qty), 0) AS value FROM inventory_lots WHERE product_id = ?',
      <Object?>['P-RETURN'],
    )).single['value']! as int;
    final fifoStock = (await db.rawQuery(
      'SELECT COALESCE(SUM(remaining_qty), 0) AS value FROM inventory_cost_layers WHERE product_id = ?',
      <Object?>['P-RETURN'],
    )).single['value']! as int;
    expect(aggregateStock, 1);
    expect(physicalStock, aggregateStock);
    expect(fifoStock, aggregateStock);

    final replay = await repository.processReturn(
      saleId: sale.saleId,
      quantities: <String, int>{'sale:sale-return-001:item:0': 1},
      type: SaleReturnType.returnItems,
      reason: 'Test partial return',
      returnId: 'return-stable-001',
    );
    expect(replay['already_processed'], true);
    expect((await db.query('sale_returns')).length, 1);
    expect((await db.query('outbox_events')).where((row) => row['entity_type'] == 'sale_return').length, 1);

    await expectLater(
      repository.processReturn(
        saleId: sale.saleId,
        quantities: <String, int>{'sale:sale-return-001:item:0': 1},
        type: SaleReturnType.returnItems,
        reason: 'A conflicting reason',
        returnId: 'return-stable-001',
      ),
      throwsA(isA<ReturnIdempotencyConflictException>()),
    );
    expect((await db.query('sale_returns')).length, 1);
  });

  test('stock disposition requires inspection before release and emits a self-approved outbox event', () async {
    final database = await seededDatabase();
    addTearDown(database.close);
    await database.database.update(
      'inventory_lots',
      <String, Object?>{'status': 'quarantine'},
      where: 'id = ?',
      whereArgs: <Object?>['LOT-RETURN'],
    );

    final repository = ReturnsRepository(
      database: database,
      actorId: 'user-2',
      deviceId: 'device-2',
    );
    await expectLater(
      repository.adjustDisposition(
        lotId: 'LOT-RETURN',
        action: 'release_quarantine',
        reason: 'Release without inspection',
        inspectionResult: 'passed',
      ),
      throwsA(isA<ReturnsValidationException>()),
    );
    expect((await database.database.query('inventory_lots', where: 'id = ?', whereArgs: <Object?>['LOT-RETURN'])).single['status'], 'quarantine');

    final adjustment = await repository.adjustDisposition(
      lotId: 'LOT-RETURN',
      action: 'release_quarantine',
      reason: 'Inspection complete',
      inspectionNote: 'Packaging and expiry verified',
      inspectionResult: 'passed',
      adjustmentId: 'adjust-stable-001',
    );
    expect(adjustment, 'adjust-stable-001');
    expect((await database.database.query('inventory_lots', where: 'id = ?', whereArgs: <Object?>['LOT-RETURN'])).single['status'], 'saleable');
    final audit = (await database.database.query('stock_adjustments')).single;
    expect(audit['actor_id'], 'user-2');
    expect(audit['approved_by_user_id'], 'user-2');
    expect(audit['approval_mode'], 'self');
    final event = (await database.database.query('outbox_events')).single;
    expect(event['entity_type'], 'stock_adjustment');
    expect(event['status'], 'pending');
  });


  test('full void preserves the original journal and posts one exact linked reversal', () async {
    final database = await seededDatabase();
    addTearDown(database.close);

    final sale = await PaymentService(
      repository: SqliteSaleRepository(database),
    ).process(PaymentRequest(
      transactionId: 'sale-void-001',
      method: PaymentMethod.cash,
      occurredAtUtc: DateTime.utc(2026, 10, 23, 3),
      lines: const <PaymentLineInput>[
        PaymentLineInput(productId: 'P-RETURN', quantity: 1),
      ],
    ));
    final db = database.database;
    final originalJournal = (await db.query(
      'journals',
      where: 'transaction_id = ?',
      whereArgs: <Object?>['sale-void-001'],
    )).single;
    final originalLines = await db.query(
      'journal_lines',
      where: 'journal_id = ?',
      whereArgs: <Object?>[originalJournal['id']],
      orderBy: 'line_no',
    );

    final repository = ReturnsRepository(
      database: database,
      actorId: 'user-void',
      deviceId: 'device-void',
    );
    final result = await repository.processReturn(
      saleId: sale.saleId,
      quantities: <String, int>{'sale:sale-void-001:item:0': 1},
      type: SaleReturnType.voidSale,
      reason: 'Full transaction void test',
      returnId: 'void-stable-001',
    );

    expect(result['refund_total'], 11100);
    expect(result['cogs_amount'], 5000);
    expect(result['already_processed'], false);
    final originalLinesAfter = await db.query(
      'journal_lines',
      where: 'journal_id = ?',
      whereArgs: <Object?>[originalJournal['id']],
      orderBy: 'line_no',
    );
    expect(originalLinesAfter, originalLines);

    final reversal = (await db.query(
      'journals',
      where: 'transaction_id = ?',
      whereArgs: <Object?>['return:void-stable-001'],
    )).single;
    expect(reversal['reversal_of_id'], originalJournal['id']);
    final reversalLines = await db.query(
      'journal_lines',
      where: 'journal_id = ?',
      whereArgs: <Object?>[reversal['id']],
      orderBy: 'line_no',
    );
    expect(reversalLines, hasLength(originalLines.length));
    for (var index = 0; index < originalLines.length; index++) {
      expect(reversalLines[index]['account_code'], originalLines[index]['account_code']);
      expect(reversalLines[index]['debit'], originalLines[index]['credit']);
      expect(reversalLines[index]['credit'], originalLines[index]['debit']);
    }

    final returned = (await db.query(
      'sale_returns',
      where: 'id = ?',
      whereArgs: <Object?>['void-stable-001'],
    )).single;
    expect(returned['return_type'], 'void');
    expect(returned['original_journal_entry_id'], originalJournal['id']);
    expect(returned['journal_entry_id'], reversal['id']);
    expect((await db.query(
      'inventory_lots',
      where: 'source_return_id = ?',
      whereArgs: <Object?>['void-stable-001'],
    )).single['status'], 'quarantine');
    expect((await db.query(
      'outbox_events',
      where: 'id = ?',
      whereArgs: <Object?>['outbox:sale_return:void-stable-001'],
    )).single['status'], 'pending');
    expect((await db.query('journals', where: 'reversal_of_id = ?', whereArgs: <Object?>[originalJournal['id']])).length, 1);
  });


}
