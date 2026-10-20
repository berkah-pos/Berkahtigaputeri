// lib/features/pos/checkout/sqlite_sale_repository.dart

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database/pos_database.dart';
import '../../../core/time/business_date.dart';
import '../../accounting/exceptions/accounting_exceptions.dart';
import '../../accounting/models/coa_account.dart';
import '../../accounting/models/journal_entry.dart';
import '../../accounting/repositories/sqlite_journal_repository.dart';
import '../../accounting/services/journal_service.dart';
import '../../inventory/services/fefo_engine.dart';
import '../../inventory/services/fifo_cost_engine.dart';
import '../../products/models/product.dart';
import '../../products/repositories/sqlite_product_repository.dart';
import '../cart/sale_calculator.dart';
import 'payment_service.dart';

/// SQLite implementation of the atomic POS sale boundary.
///
/// Physical batches are allocated with FEFO. Financial valuation remains FIFO
/// to preserve the locked COA contract for 1-1040 / 5-5010.
class SqliteSaleRepository implements SaleRepository {
  const SqliteSaleRepository(this._database);

  final PosDatabase _database;

  @override
  Future<PaymentResult> processPayment(PaymentRequest request) async {
    request.validate();

    final transactionId = request.transactionId.trim();
    final fingerprint = _fingerprint(request);

    return _database.transaction<PaymentResult>((transaction) async {
      final existingRows = await transaction.query(
        'sales',
        where: 'transaction_id = ?',
        whereArgs: <Object?>[transactionId],
        limit: 1,
      );

      final journalRepository = SqliteJournalRepository(
        _database,
        executor: transaction,
      );
      final journalService = JournalService(journalRepository);

      if (existingRows.isNotEmpty) {
        final existing = existingRows.first;
        if (existing['request_fingerprint'] != fingerprint) {
          throw DuplicateTransactionIdException(transactionId);
        }

        final journal =
            await journalService.findByTransactionId(transactionId);
        if (journal == null) {
          throw const SaleDataIntegrityException(
            'Jurnal transaksi yang sudah tersimpan tidak ditemukan.',
          );
        }

        return _resultFromRow(
          saleRow: existing,
          journal: journal,
          alreadyProcessed: true,
        );
      }

      final products = <Product>[];
      final pricingLines = <SalePricingLine>[];

      for (final input in request.lines) {
        final rows = await transaction.query(
          'products',
          where: 'id = ?',
          whereArgs: <Object?>[input.productId.trim()],
          limit: 1,
        );

        if (rows.isEmpty) {
          throw ProductNotFoundException(input.productId.trim());
        }

        final product = _productFromRow(rows.first);
        if (product.requiresReview) {
          throw ProductRequiresReviewException(product.nameId);
        }
        products.add(product);
        pricingLines.add(
          SalePricingLine(
            productId: product.id,
            quantity: input.quantity,
            unitPrice: product.price,
            itemDiscountAmount: input.itemDiscountAmount,
            ppnExempt: product.ppnExempt,
          ),
        );
      }

      final calculation = SaleCalculator.calculate(
        lines: pricingLines,
        transactionDiscountAmount: request.transactionDiscountAmount,
      );

      final businessDate =
          BusinessDate.fromUtc(request.occurredAtUtc.toUtc());
      final businessDateValue = DateTime.parse(businessDate);
      final occurredAtUtc = request.occurredAtUtc.toUtc();

      final physicalAllocationsByLine = <List<FefoAllocation>>[];
      final costResultsByLine = <FifoCostResult>[];
      final cogsByLine = <int>[];
      var totalCogs = 0;

      for (var lineIndex = 0;
          lineIndex < request.lines.length;
          lineIndex++) {
        final product = products[lineIndex];
        final requestedQuantity = request.lines[lineIndex].quantity;

        if (product.stockQty < requestedQuantity) {
          throw InsufficientStockException(
            productName: product.nameId,
            available: product.stockQty,
            requested: requestedQuantity,
          );
        }

        final physicalAllocations = request.reservationId == null
            ? await _consumeFefo(
                transaction: transaction,
                transactionId: transactionId,
                lineIndex: lineIndex,
                product: product,
                quantity: requestedQuantity,
                businessDate: businessDateValue,
                occurredAtUtc: occurredAtUtc,
              )
            : await _consumeReservedFefo(
                transaction: transaction,
                transactionId: transactionId,
                reservationId: request.reservationId!.trim(),
                lineIndex: lineIndex,
                product: product,
                quantity: requestedQuantity,
                businessDate: businessDateValue,
                occurredAtUtc: occurredAtUtc,
              );

        final costResult = await _consumeFifoCost(
          transaction: transaction,
          transactionId: transactionId,
          lineIndex: lineIndex,
          product: product,
          quantity: requestedQuantity,
          occurredAtUtc: occurredAtUtc,
        );

        if (physicalAllocations.fold<int>(
              0,
              (sum, allocation) => sum + allocation.quantity,
            ) !=
            costResult.quantity) {
          throw InventoryDataIntegrityException(
            'Kuantitas FEFO dan FIFO tidak sama untuk "${product.nameId}".',
          );
        }

        await _decrementProductStock(
          transaction: transaction,
          product: product,
          quantity: requestedQuantity,
        );

        physicalAllocationsByLine.add(physicalAllocations);
        costResultsByLine.add(costResult);
        cogsByLine.add(costResult.totalCost);
        totalCogs += costResult.totalCost;
      }

      if (request.reservationId != null) {
        final committed = await transaction.update(
          'inventory_reservations',
          <String, Object?>{
            'status': 'committed',
            'committed_at_utc': occurredAtUtc.toIso8601String(),
          },
          where: 'id = ? AND transaction_id = ? AND status = ?',
          whereArgs: <Object?>[
            request.reservationId!.trim(),
            transactionId,
            'active',
          ],
        );
        if (committed != 1) {
          throw const ReservationCheckoutException(
            'Reservasi tidak aktif atau tidak cocok dengan transaksi.',
          );
        }
      }

      final saleId = 'sale:$transactionId';
      final createdAtUtc = DateTime.now().toUtc().toIso8601String();

      await transaction.insert(
        'sales',
        <String, Object?>{
          'id': saleId,
          'transaction_id': transactionId,
          'request_fingerprint': fingerprint,
          'occurred_at_utc': occurredAtUtc.toIso8601String(),
          'business_date': businessDate,
          'timezone': request.timezone,
          'gross_amount': calculation.grossAmount,
          'item_discount_amount': calculation.itemDiscountAmount,
          'transaction_discount_amount':
              calculation.transactionDiscountAmount,
          'discount_amount': calculation.discountAmount,
          'taxable_dpp': calculation.taxableDpp,
          'exempt_dpp': calculation.exemptDpp,
          'dpp': calculation.dpp,
          'ppn_amount': calculation.ppnAmount,
          'grand_total': calculation.grandTotal,
          'cogs_amount': totalCogs,
          'payment_method': request.method.name,
          'created_at_utc': createdAtUtc,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      for (var index = 0; index < calculation.lines.length; index++) {
        final line = calculation.lines[index];
        final saleItemId = '$saleId:item:$index';

        await transaction.insert(
          'sale_items',
          <String, Object?>{
            'id': saleItemId,
            'sale_id': saleId,
            'line_no': index,
            'product_id': line.source.productId,
            'quantity': line.source.quantity,
            'unit_price': line.source.unitPrice,
            'gross_amount': line.grossAmount,
            'item_discount_amount': line.itemDiscountAmount,
            'transaction_discount_amount':
                line.transactionDiscountAmount,
            'discount_amount': line.discountAmount,
            'dpp': line.dpp,
            'ppn_exempt': line.ppnExempt ? 1 : 0,
            'cogs_amount': cogsByLine[index],
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final physicalAllocations = physicalAllocationsByLine[index];
        for (var allocationIndex = 0;
            allocationIndex < physicalAllocations.length;
            allocationIndex++) {
          final allocation = physicalAllocations[allocationIndex];
          await transaction.insert(
            'sale_lot_allocations',
            <String, Object?>{
              'sale_item_id': saleItemId,
              'allocation_no': allocationIndex,
              'lot_id': allocation.lotId,
              'quantity': allocation.quantity,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }

        final consumptions = costResultsByLine[index].consumptions;
        for (var consumptionIndex = 0;
            consumptionIndex < consumptions.length;
            consumptionIndex++) {
          final consumption = consumptions[consumptionIndex];
          await transaction.insert(
            'cost_layer_consumptions',
            <String, Object?>{
              'sale_item_id': saleItemId,
              'consumption_no': consumptionIndex,
              'cost_layer_id': consumption.costLayerId,
              'quantity': consumption.quantity,
              'unit_cost': consumption.unitCost,
              'total_cost': consumption.totalCost,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      final journal = await journalService.post(
        _buildSaleJournal(
          request: request,
          transactionId: transactionId,
          calculation: calculation,
          totalCogs: totalCogs,
          businessDate: businessDate,
        ),
      );

      final outboxId = 'outbox:sale:$transactionId';
      final syncEnvelope = await _buildSaleSyncEnvelope(
        transaction: transaction,
        eventId: outboxId,
        saleId: saleId,
        transactionId: transactionId,
      );
      await transaction.insert(
        'outbox_events',
        <String, Object?>{
          'id': outboxId,
          'entity_type': 'sale',
          'entity_id': saleId,
          'payload': jsonEncode(syncEnvelope),
          'status': 'pending',
          'retry_count': 0,
          'last_error': null,
          'next_retry_at_utc': null,
          'acked_at_utc': null,
          'server_receipt_id': null,
          'created_at_utc': createdAtUtc,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return PaymentResult(
        saleId: saleId,
        journalEntry: journal,
        grossAmount: calculation.grossAmount,
        discountAmount: calculation.discountAmount,
        taxableDpp: calculation.taxableDpp,
        exemptDpp: calculation.exemptDpp,
        ppnAmount: calculation.ppnAmount,
        grandTotal: calculation.grandTotal,
        cogsAmount: totalCogs,
        businessDate: businessDate,
        alreadyProcessed: false,
      );
    });
  }

  Future<Map<String, Object?>> _buildSaleSyncEnvelope({
    required Transaction transaction,
    required String eventId,
    required String saleId,
    required String transactionId,
  }) async {
    final sales = await transaction.query(
      'sales',
      where: 'id = ? AND transaction_id = ?',
      whereArgs: <Object?>[saleId, transactionId],
      limit: 1,
    );
    if (sales.length != 1) {
      throw const SaleDataIntegrityException('Header penjualan tidak ditemukan untuk outbox.');
    }

    final itemRows = await transaction.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: <Object?>[saleId],
      orderBy: 'line_no',
    );
    if (itemRows.isEmpty) {
      throw const SaleDataIntegrityException('Outbox penjualan wajib berisi minimal satu baris item.');
    }

    final items = <Map<String, Object?>>[];
    for (final row in itemRows) {
      final item = Map<String, Object?>.from(row);
      final saleItemId = row['id']! as String;
      final allocations = await transaction.query(
        'sale_lot_allocations',
        where: 'sale_item_id = ?',
        whereArgs: <Object?>[saleItemId],
        orderBy: 'allocation_no',
      );
      final consumptions = await transaction.query(
        'cost_layer_consumptions',
        where: 'sale_item_id = ?',
        whereArgs: <Object?>[saleItemId],
        orderBy: 'consumption_no',
      );
      if (allocations.isEmpty || consumptions.isEmpty) {
        throw const SaleDataIntegrityException(
          'Setiap item penjualan harus memiliki alokasi FEFO dan konsumsi biaya FIFO sebelum disinkronkan.',
        );
      }
      item['allocations'] = allocations.map(Map<String, Object?>.from).toList(growable: false);
      item['cost_consumptions'] =
          consumptions.map(Map<String, Object?>.from).toList(growable: false);
      items.add(item);
    }

    final journals = await transaction.query(
      'journals',
      where: 'transaction_id = ?',
      whereArgs: <Object?>[transactionId],
      limit: 1,
    );
    if (journals.length != 1) {
      throw const SaleDataIntegrityException('Jurnal penjualan tidak ditemukan untuk outbox.');
    }
    final journal = Map<String, Object?>.from(journals.first);
    journal['lines'] = (await transaction.query(
      'journal_lines',
      where: 'journal_id = ?',
      whereArgs: <Object?>[journal['id']],
      orderBy: 'line_no',
    )).map(Map<String, Object?>.from).toList(growable: false);

    final inventoryMovements = (await transaction.query(
      'inventory_movements',
      where: 'reference_id = ?',
      whereArgs: <Object?>[transactionId],
      orderBy: 'id',
    )).map(Map<String, Object?>.from).toList(growable: false);

    final stockMovements = (await transaction.query(
      'stock_movements',
      where: 'reference_id = ?',
      whereArgs: <Object?>[transactionId],
      orderBy: 'id',
    )).map(Map<String, Object?>.from).toList(growable: false);

    final sale = Map<String, Object?>.from(sales.single);
    return <String, Object?>{
      'payload_version': 1,
      'event_id': eventId,
      'event_type': 'sale',
      'entity_id': saleId,
      'transaction_id': transactionId,
      'sale': sale,
      'items': items,
      'inventory_movements': inventoryMovements,
      'stock_movements': stockMovements,
      'journal': journal,
    };
  }

  Future<List<FefoAllocation>> _consumeFefo({
    required Transaction transaction,
    required String transactionId,
    required int lineIndex,
    required Product product,
    required int quantity,
    required DateTime businessDate,
    required DateTime occurredAtUtc,
  }) async {
    final rows = await transaction.rawQuery(
      '''
      SELECT l.*
      FROM inventory_lots l
      WHERE l.product_id = ?
        AND l.status = 'saleable'
        AND (l.on_hand_qty - l.reserved_qty) > 0
        AND NOT EXISTS (
          SELECT 1
          FROM lot_holds h
          WHERE h.lot_id = l.id
            AND h.active = 1
        )
      ORDER BY
        CASE WHEN l.expiry_date IS NULL THEN 1 ELSE 0 END,
        l.expiry_date,
        l.first_received_at_utc,
        l.id
      ''',
      <Object?>[product.id],
    );

    final candidates = rows
        .map(
          (row) => FefoLotCandidate(
            id: row['id']! as String,
            availableQty:
                (row['on_hand_qty']! as int) - (row['reserved_qty']! as int),
            firstReceivedAtUtc:
                DateTime.parse(row['first_received_at_utc']! as String).toUtc(),
            expiryDate: row['expiry_date'] == null
                ? null
                : DateTime.parse(row['expiry_date']! as String),
          ),
        )
        .toList(growable: false);

    late final FefoAllocationResult result;
    try {
      result = FefoEngine.allocate(
        candidates: candidates,
        requestedQuantity: quantity,
        businessDate: businessDate,
        trackExpiry: product.trackExpiry,
        minShelfLifeDays: product.minShelfLifeDays,
      );
    } on FefoInsufficientStockException catch (error) {
      throw InsufficientStockException(
        productName: product.nameId,
        available: error.available,
        requested: error.requested,
      );
    }

    for (var index = 0; index < result.allocations.length; index++) {
      final allocation = result.allocations[index];
      final changed = await transaction.rawUpdate(
        '''
        UPDATE inventory_lots
        SET on_hand_qty = on_hand_qty - ?
        WHERE id = ?
          AND status = 'saleable'
          AND (on_hand_qty - reserved_qty) >= ?
        ''',
        <Object?>[
          allocation.quantity,
          allocation.lotId,
          allocation.quantity,
        ],
      );
      if (changed != 1) {
        throw InventoryDataIntegrityException(
          'Lot FEFO "${allocation.lotId}" berubah saat checkout.',
        );
      }

      await transaction.insert(
        'inventory_movements',
        <String, Object?>{
          'id': 'inventory:$transactionId:$lineIndex:$index',
          'product_id': product.id,
          'lot_id': allocation.lotId,
          'reference_id': transactionId,
          'movement_type': 'sale',
          'quantity_delta': -allocation.quantity,
          'occurred_at_utc': occurredAtUtc.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    return result.allocations;
  }

  Future<List<FefoAllocation>> _consumeReservedFefo({
    required Transaction transaction,
    required String transactionId,
    required String reservationId,
    required int lineIndex,
    required Product product,
    required int quantity,
    required DateTime businessDate,
    required DateTime occurredAtUtc,
  }) async {
    final reservations = await transaction.query(
      'inventory_reservations',
      where: 'id = ? AND transaction_id = ? AND status = ?',
      whereArgs: <Object?>[reservationId, transactionId, 'active'],
      limit: 1,
    );
    if (reservations.isEmpty) {
      throw const ReservationCheckoutException(
        'Reservasi tidak aktif atau tidak cocok dengan transaksi.',
      );
    }

    final expiresAtUtc = DateTime.parse(
      reservations.single['expires_at_utc']! as String,
    ).toUtc();
    if (!expiresAtUtc.isAfter(occurredAtUtc)) {
      throw const ReservationCheckoutException(
        'Reservasi sudah kedaluwarsa.',
      );
    }

    final rows = await transaction.query(
      'inventory_reservation_lines',
      where: 'reservation_id = ? AND line_no = ? AND product_id = ?',
      whereArgs: <Object?>[reservationId, lineIndex, product.id],
      orderBy: 'allocation_no',
    );

    final reservedQuantity = rows.fold<int>(
      0,
      (sum, row) => sum + (row['quantity']! as int),
    );
    if (reservedQuantity != quantity) {
      throw ReservationCheckoutException(
        'Jumlah reservasi untuk "${product.nameId}" tidak cocok '
        'dengan checkout.',
      );
    }

    final allocations = <FefoAllocation>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      final lotId = row['lot_id']! as String;
      final allocatedQuantity = row['quantity']! as int;

      final lots = await transaction.rawQuery(
        '''
        SELECT
          l.*,
          EXISTS(
            SELECT 1
            FROM lot_holds h
            WHERE h.lot_id = l.id
              AND h.active = 1
          ) AS has_active_hold
        FROM inventory_lots l
        WHERE l.id = ? AND l.product_id = ?
        ''',
        <Object?>[lotId, product.id],
      );
      if (lots.isEmpty) {
        throw ReservationCheckoutException(
          'Lot reservasi "$lotId" tidak ditemukan.',
        );
      }
      final lot = lots.single;
      if (lot['status'] != 'saleable' ||
          (lot['has_active_hold']! as int) == 1) {
        throw ReservationCheckoutException(
          'Lot reservasi "$lotId" tidak lagi dapat dijual.',
        );
      }

      try {
        FefoEngine.allocate(
          candidates: <FefoLotCandidate>[
            FefoLotCandidate(
              id: lotId,
              availableQty: allocatedQuantity,
              firstReceivedAtUtc: DateTime.parse(
                lot['first_received_at_utc']! as String,
              ).toUtc(),
              expiryDate: lot['expiry_date'] == null
                  ? null
                  : DateTime.parse(lot['expiry_date']! as String),
            ),
          ],
          requestedQuantity: allocatedQuantity,
          businessDate: businessDate,
          trackExpiry: product.trackExpiry,
          minShelfLifeDays: product.minShelfLifeDays,
        );
      } on FefoException {
        throw ReservationCheckoutException(
          'Lot reservasi "$lotId" tidak lagi memenuhi aturan FEFO.',
        );
      }

      final changed = await transaction.rawUpdate(
        '''
        UPDATE inventory_lots
        SET
          on_hand_qty = on_hand_qty - ?,
          reserved_qty = reserved_qty - ?
        WHERE id = ?
          AND status = 'saleable'
          AND on_hand_qty >= ?
          AND reserved_qty >= ?
        ''',
        <Object?>[
          allocatedQuantity,
          allocatedQuantity,
          lotId,
          allocatedQuantity,
          allocatedQuantity,
        ],
      );
      if (changed != 1) {
        throw ReservationCheckoutException(
          'Kuantitas lot reservasi "$lotId" berubah saat checkout.',
        );
      }

      await transaction.insert(
        'inventory_movements',
        <String, Object?>{
          'id': 'inventory:$transactionId:$lineIndex:$index',
          'product_id': product.id,
          'lot_id': lotId,
          'reference_id': transactionId,
          'movement_type': 'sale',
          'quantity_delta': -allocatedQuantity,
          'occurred_at_utc': occurredAtUtc.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      allocations.add(
        FefoAllocation(
          lotId: lotId,
          quantity: allocatedQuantity,
        ),
      );
    }

    return allocations;
  }

  Future<FifoCostResult> _consumeFifoCost({
    required Transaction transaction,
    required String transactionId,
    required int lineIndex,
    required Product product,
    required int quantity,
    required DateTime occurredAtUtc,
  }) async {
    final rows = await transaction.query(
      'inventory_cost_layers',
      where: 'product_id = ? AND remaining_qty > 0',
      whereArgs: <Object?>[product.id],
      orderBy: 'acquired_at_utc, id',
    );

    final layers = rows
        .map(
          (row) => FifoCostLayerCandidate(
            id: row['id']! as String,
            remainingQty: row['remaining_qty']! as int,
            unitCost: row['unit_cost']! as int,
            acquiredAtUtc:
                DateTime.parse(row['acquired_at_utc']! as String).toUtc(),
          ),
        )
        .toList(growable: false);

    late final FifoCostResult result;
    try {
      result = FifoCostEngine.allocate(
        layers: layers,
        requestedQuantity: quantity,
      );
    } on FifoCostDataIntegrityException catch (error) {
      throw InventoryDataIntegrityException(
        'Layer FIFO untuk "${product.nameId}" hanya ${error.available}, '
        'sedangkan FEFO meminta ${error.requested}.',
      );
    }

    for (var index = 0; index < result.consumptions.length; index++) {
      final consumption = result.consumptions[index];
      final changed = await transaction.rawUpdate(
        '''
        UPDATE inventory_cost_layers
        SET remaining_qty = remaining_qty - ?
        WHERE id = ? AND remaining_qty >= ?
        ''',
        <Object?>[
          consumption.quantity,
          consumption.costLayerId,
          consumption.quantity,
        ],
      );
      if (changed != 1) {
        throw InventoryDataIntegrityException(
          'Layer FIFO "${consumption.costLayerId}" berubah saat checkout.',
        );
      }

      await transaction.insert(
        'stock_movements',
        <String, Object?>{
          'id': 'stock:$transactionId:$lineIndex:$index',
          'product_id': product.id,
          'reference_id': transactionId,
          'movement_type': 'sale',
          'quantity_delta': -consumption.quantity,
          'unit_cost': consumption.unitCost,
          'total_cost': consumption.totalCost,
          'occurred_at_utc': occurredAtUtc.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
    }

    return result;
  }

  Future<void> _decrementProductStock({
    required Transaction transaction,
    required Product product,
    required int quantity,
  }) async {
    final updatedRows = await transaction.rawUpdate(
      '''
      UPDATE products
      SET stock_qty = stock_qty - ?
      WHERE id = ? AND stock_qty >= ?
      ''',
      <Object?>[quantity, product.id, quantity],
    );

    if (updatedRows != 1) {
      throw InsufficientStockException(
        productName: product.nameId,
        available: product.stockQty,
        requested: quantity,
      );
    }
  }

  JournalEntry _buildSaleJournal({
    required PaymentRequest request,
    required String transactionId,
    required SaleCalculation calculation,
    required int totalCogs,
    required String businessDate,
  }) {
    final lines = <JournalLine>[];

    if (calculation.grandTotal > 0) {
      lines.add(
        JournalLine(
          accountCode: _paymentAccountCode(request.method),
          debit: calculation.grandTotal,
          credit: 0,
        ),
      );
    }

    if (calculation.discountAmount > 0) {
      lines.add(
        JournalLine(
          accountCode: CoaAccounts.salesDiscounts.code,
          debit: calculation.discountAmount,
          credit: 0,
        ),
      );
    }

    lines.add(
      JournalLine(
        accountCode: CoaAccounts.sales.code,
        debit: 0,
        credit: calculation.grossAmount,
      ),
    );

    if (calculation.ppnAmount > 0) {
      lines.add(
        JournalLine(
          accountCode: CoaAccounts.ppnPayable.code,
          debit: 0,
          credit: calculation.ppnAmount,
        ),
      );
    }

    if (totalCogs > 0) {
      lines
        ..add(
          JournalLine(
            accountCode: CoaAccounts.cogs.code,
            debit: totalCogs,
            credit: 0,
          ),
        )
        ..add(
          JournalLine(
            accountCode: CoaAccounts.inventory.code,
            debit: 0,
            credit: totalCogs,
          ),
        );
    }

    return JournalEntry(
      id: 'journal:sale:$transactionId',
      date: request.occurredAtUtc.toUtc(),
      transactionId: transactionId,
      businessDate: businessDate,
      timezone: request.timezone,
      lines: lines,
    );
  }

  String _paymentAccountCode(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return CoaAccounts.cash.code;
      case PaymentMethod.qris:
        return CoaAccounts.qris.code;
      case PaymentMethod.transfer:
        return CoaAccounts.bankTransfer.code;
    }
  }

  Product _productFromRow(Map<String, Object?> row) {
    return Product(
      id: row['id']! as String,
      sku: row['sku']! as String,
      barcode: row['barcode'] as String?,
      nameId: row['name_id']! as String,
      price: row['price']! as int,
      ppnExempt: (row['ppn_exempt']! as int) == 1,
      stockQty: row['stock_qty']! as int,
      trackExpiry: (row['track_expiry']! as int) == 1,
      minShelfLifeDays: row['min_shelf_life_days']! as int,
      requiresReview: (row['requires_review']! as int) == 1,
    );
  }

  String _fingerprint(PaymentRequest request) {
    return jsonEncode(
      <String, Object?>{
        'transactionId': request.transactionId.trim(),
        'method': request.method.name,
        'occurredAtUtc':
            request.occurredAtUtc.toUtc().toIso8601String(),
        'transactionDiscountAmount':
            request.transactionDiscountAmount,
        'reservationId': request.reservationId?.trim(),
        'timezone': request.timezone,
        'lines': request.lines
            .map(
              (line) => <String, Object?>{
                'productId': line.productId.trim(),
                'quantity': line.quantity,
                'itemDiscountAmount': line.itemDiscountAmount,
              },
            )
            .toList(growable: false),
      },
    );
  }

  PaymentResult _resultFromRow({
    required Map<String, Object?> saleRow,
    required JournalEntry journal,
    required bool alreadyProcessed,
  }) {
    return PaymentResult(
      saleId: saleRow['id']! as String,
      journalEntry: journal,
      grossAmount: saleRow['gross_amount']! as int,
      discountAmount: saleRow['discount_amount']! as int,
      taxableDpp: saleRow['taxable_dpp']! as int,
      exemptDpp: saleRow['exempt_dpp']! as int,
      ppnAmount: saleRow['ppn_amount']! as int,
      grandTotal: saleRow['grand_total']! as int,
      cogsAmount: saleRow['cogs_amount']! as int,
      businessDate: saleRow['business_date']! as String,
      alreadyProcessed: alreadyProcessed,
    );
  }
}

class SaleRepositoryException implements Exception {
  const SaleRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class InsufficientStockException extends SaleRepositoryException {
  InsufficientStockException({
    required String productName,
    required int available,
    required int requested,
  }) : super(
          'Stok "$productName" tidak cukup. '
          'Tersedia $available, diminta $requested.',
        );
}

class InventoryDataIntegrityException extends SaleRepositoryException {
  const InventoryDataIntegrityException(super.message);
}

class ReservationCheckoutException extends SaleRepositoryException {
  const ReservationCheckoutException(super.message);
}

class SaleDataIntegrityException extends SaleRepositoryException {
  const SaleDataIntegrityException(super.message);
}
