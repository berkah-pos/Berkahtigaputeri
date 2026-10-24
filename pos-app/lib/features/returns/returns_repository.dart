import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/database/pos_database.dart';
import '../../core/sync/outbox_event_writer.dart';
import '../../core/time/business_date.dart';
import '../accounting/models/coa_account.dart';
import '../accounting/models/journal_entry.dart';
import '../accounting/repositories/sqlite_journal_repository.dart';
import '../accounting/services/journal_service.dart';

enum SaleReturnType { returnItems, voidSale }

extension SaleReturnTypeName on SaleReturnType {
  String get wireValue => this == SaleReturnType.voidSale ? 'void' : 'return';
}

class ReturnsRepository {
  ReturnsRepository({required PosDatabase database, required this.actorId, required this.deviceId})
      : _database = database;

  final PosDatabase _database;
  final String actorId;
  final String deviceId;

  Future<List<Map<String, Object?>>> listReturnableSales() async {
    final sales = await _database.database.query('sales',
        orderBy: 'created_at_utc DESC, transaction_id DESC', limit: 100);
    final result = <Map<String, Object?>>[];
    for (final sale in sales) {
      final saleId = sale['id']! as String;
      final lines = await _database.database.rawQuery('''
        SELECT si.*, p.name_id AS product_name,
          COALESCE((SELECT SUM(ri.quantity) FROM sale_return_items ri
            WHERE ri.original_sale_id = si.sale_id AND ri.sale_item_id = si.id), 0) AS returned_qty
        FROM sale_items si JOIN products p ON p.id = si.product_id
        WHERE si.sale_id = ? ORDER BY si.line_no, si.id
      ''', <Object?>[saleId]);
      final returns = (await _database.database.rawQuery(
        'SELECT COUNT(*) AS n FROM sale_returns WHERE original_sale_id = ?',
        <Object?>[saleId],
      )).single['n']! as int;
      if (lines.any((line) =>
              (line['quantity']! as num).toInt() > (line['returned_qty']! as num).toInt()) ||
          (returns == 0 && lines.isNotEmpty)) {
        result.add(<String, Object?>{
          ...sale,
          'items': lines,
          'has_return': returns > 0,
        });
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> listLotsForDisposition() {
    return _database.database.rawQuery('''
      SELECT l.*, p.name_id AS product_name, p.track_expiry, p.min_shelf_life_days
      FROM inventory_lots l JOIN products p ON p.id = l.product_id
      ORDER BY CASE l.status WHEN 'quarantine' THEN 0 WHEN 'saleable' THEN 1 ELSE 2 END,
        l.expiry_date, l.first_received_at_utc, l.id
    ''');
  }

  Future<Map<String, Object?>> processReturn({
    required String saleId,
    required Map<String, int> quantities,
    required SaleReturnType type,
    required String reason,
    String? returnId,
  }) async {
    final saleKey = saleId.trim();
    final cleanReason = reason.trim();
    if (saleKey.isEmpty || cleanReason.isEmpty || cleanReason.length > 500 || quantities.isEmpty) {
      throw const ReturnsValidationException('Penjualan, alasan, dan kuantitas retur wajib valid.');
    }
    final opId = (returnId ?? _newId('return')).trim();
    final eventId = 'outbox:sale_return:$opId';
    final sortedItems = quantities.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final fingerprint = _hash(jsonEncode(<String, Object?>{
      'sale_id': saleKey,
      'type': type.wireValue,
      'reason': cleanReason,
      'items': sortedItems.map((e) => <String, Object?>{
        'sale_item_id': e.key, 'quantity': e.value,
      }).toList(growable: false),
    }));

    return _database.transaction<Map<String, Object?>>((tx) async {
      final existing = await tx.query('sale_returns', where: 'id = ?', whereArgs: <Object?>[opId], limit: 1);
      if (existing.isNotEmpty) {
        if (existing.single['request_fingerprint'] != fingerprint) {
          throw ReturnIdempotencyConflictException(opId);
        }
        return <String, Object?>{
          'return_id': opId,
          'refund_total': existing.single['refund_total'],
          'cogs_amount': existing.single['cogs_amount'],
          'already_processed': true,
        };
      }
      final saleRows = await tx.query('sales', where: 'id = ?', whereArgs: <Object?>[saleKey], limit: 1);
      if (saleRows.isEmpty) throw const ReturnsValidationException('Penjualan asal tidak ditemukan.');
      final sale = saleRows.single;
      final transactionId = sale['transaction_id']! as String;
      final payMethod = sale['payment_method']! as String;
      final payAccount = _paymentAccount(payMethod);
      final time = DateTime.now().toUtc();
      final at = time.toIso8601String();
      final date = BusinessDate.fromUtc(time);
      final actor = actorId.trim().isEmpty
          ? 'device:' + deviceId.trim()
          : actorId.trim();
      if (actor == 'device:') throw const ReturnsValidationException('Identitas operator/perangkat tidak tersedia.');

      final originalJournals = await tx.query('journals', where: 'transaction_id = ?', whereArgs: <Object?>[transactionId], limit: 1);
      if (originalJournals.isEmpty) throw const ReturnsDataIntegrityException('Jurnal penjualan asal tidak ditemukan.');
      final originalJournal = originalJournals.single;
      final originalJournalId = originalJournal['id']! as String;
      final oldReturns = (await tx.rawQuery(
        'SELECT COUNT(*) AS n FROM sale_returns WHERE original_sale_id = ?', <Object?>[saleKey],
      )).single['n']! as int;
      if (type == SaleReturnType.voidSale) {
        final reversal = await tx.query('journals', where: 'reversal_of_id = ?', whereArgs: <Object?>[originalJournalId], limit: 1);
        if (oldReturns != 0 || reversal.isNotEmpty) {
          throw const ReturnsValidationException('Void penuh tidak diizinkan setelah retur/reversal sebelumnya.');
        }
      }

      final lines = await tx.query('sale_items', where: 'sale_id = ?', whereArgs: <Object?>[saleKey], orderBy: 'line_no, id');
      if (lines.isEmpty) throw const ReturnsDataIntegrityException('Rincian penjualan asal kosong.');
      final lineMap = <String, Map<String, Object?>>{for (final row in lines) row['id']! as String: row};
      for (final e in quantities.entries) {
        if (!lineMap.containsKey(e.key) || e.value <= 0) {
          throw const ReturnsValidationException('Baris atau kuantitas retur tidak valid.');
        }
      }
      if (type == SaleReturnType.voidSale) {
        if (quantities.length != lines.length) throw const ReturnsValidationException('Void harus mencakup seluruh baris penjualan.');
        for (final row in lines) {
          final id = row['id']! as String;
          if (quantities[id] != (row['quantity']! as num).toInt()) {
            throw const ReturnsValidationException('Void harus membalik seluruh kuantitas penjualan.');
          }
        }
      }

      final prepared = <Map<String, Object?>>[];
      var gross = 0, discount = 0;
      var dpp = 0, taxable = 0, exempt = 0, cogs = 0;
      for (final request in sortedItems) {
        final id = request.key;
        final quantity = request.value;
        final line = lineMap[id]!;
        final soldQty = (line['quantity']! as num).toInt();
        final previous = (await tx.rawQuery('''
          SELECT COALESCE(SUM(quantity),0) AS qty, COALESCE(SUM(refund_gross),0) AS gross,
            COALESCE(SUM(refund_item_discount_amount),0) AS item_disc,
            COALESCE(SUM(refund_transaction_discount_amount),0) AS tx_disc,
            COALESCE(SUM(refund_dpp),0) AS dpp
          FROM sale_return_items WHERE original_sale_id = ? AND sale_item_id = ?
        ''', <Object?>[saleKey, id])).single;
        final oldQty = (previous['qty']! as num).toInt();
        final cumulative = oldQty + quantity;
        if (cumulative > soldQty || (type == SaleReturnType.voidSale && (oldQty != 0 || cumulative != soldQty))) {
          throw const ReturnsValidationException('Kuantitas retur melebihi kuantitas yang tersisa.');
        }
        int pr(int amount) => cumulative == soldQty ? amount : amount * cumulative ~/ soldQty;
        final lineGross = pr((line['gross_amount']! as num).toInt()) - (previous['gross']! as num).toInt();
        final lineItemDiscount = pr((line['item_discount_amount']! as num).toInt()) - (previous['item_disc']! as num).toInt();
        final lineTxDiscount = pr((line['transaction_discount_amount']! as num).toInt()) - (previous['tx_disc']! as num).toInt();
        final lineDiscount = lineItemDiscount + lineTxDiscount;
        final lineDpp = (pr((line['gross_amount']! as num).toInt()) -
              pr((line['item_discount_amount']! as num).toInt()) -
              pr((line['transaction_discount_amount']! as num).toInt())) -
            (previous['dpp']! as num).toInt();
        if (lineGross < 0 || lineDiscount < 0 || lineDpp < 0 || lineGross - lineDiscount != lineDpp) {
          throw const ReturnsDataIntegrityException('Nominal item retur tidak seimbang.');
        }

        final physical = await tx.query('sale_lot_allocations',
          where: 'sale_item_id = ?', whereArgs: <Object?>[id], orderBy: 'allocation_no');
        var unassignedPhysical = quantity;
        final physicalPrepared = <Map<String, Object?>>[];
        for (final allocation in physical) {
          if (unassignedPhysical <= 0) break;
          final sourceLotId = allocation['lot_id']! as String;
          final soldFromLot = (allocation['quantity']! as num).toInt();
          final previousQty = (await tx.rawQuery('''
            SELECT COALESCE(SUM(quantity),0) AS n FROM sale_return_lot_allocations
            WHERE original_sale_id = ? AND original_sale_item_id = ? AND source_lot_id = ?
          ''', <Object?>[saleKey, id, sourceLotId])).single['n']! as num;
          final availableFromLot = soldFromLot > previousQty.toInt() ? soldFromLot - previousQty.toInt() : 0;
          final take = unassignedPhysical < availableFromLot ? unassignedPhysical : availableFromLot;
          if (take <= 0) continue;
          final lotRows = await tx.query('inventory_lots', where: 'id = ?', whereArgs: <Object?>[sourceLotId], limit: 1);
          if (lotRows.isEmpty) throw ReturnsDataIntegrityException('Lot fisik asal $sourceLotId tidak ditemukan.');
          final lot = lotRows.single;
          physicalPrepared.add(<String, Object?>{
            'source_lot_id': sourceLotId,
            'expiry_date': lot['expiry_date'],
            'unit_cost': (lot['unit_cost']! as num).toInt(),
            'quantity': take,
          });
          unassignedPhysical -= take;
        }
        if (unassignedPhysical != 0) throw ReturnsDataIntegrityException('Kuantitas retur tidak cocok dengan alokasi FEFO asal $id.');

        final costs = await tx.query('cost_layer_consumptions',
          where: 'sale_item_id = ?', whereArgs: <Object?>[id], orderBy: 'consumption_no DESC');
        var unassignedCost = quantity;
        var lineCogs = 0;
        final costPrepared = <Map<String, Object?>>[];
        for (final consumed in costs) {
          if (unassignedCost <= 0) break;
          final sourceLayerId = consumed['cost_layer_id']! as String;
          final soldFromLayer = (consumed['quantity']! as num).toInt();
          final prior = (await tx.rawQuery('''
            SELECT COALESCE(SUM(quantity),0) AS n FROM sale_return_cost_layers
            WHERE original_sale_id = ? AND original_sale_item_id = ? AND source_cost_layer_id = ?
          ''', <Object?>[saleKey, id, sourceLayerId])).single['n']! as num;
          final availableFromLayer = soldFromLayer > prior.toInt() ? soldFromLayer - prior.toInt() : 0;
          final take = unassignedCost < availableFromLayer ? unassignedCost : availableFromLayer;
          if (take <= 0) continue;
          final layerRows = await tx.query('inventory_cost_layers', where: 'id = ?', whereArgs: <Object?>[sourceLayerId], limit: 1);
          if (layerRows.isEmpty) throw ReturnsDataIntegrityException('Cost layer FIFO asal $sourceLayerId tidak ditemukan.');
          final unitCost = (consumed['unit_cost']! as num).toInt();
          final totalCost = take * unitCost;
          costPrepared.add(<String, Object?>{
            'source_cost_layer_id': sourceLayerId,
            'financial_lot_id': layerRows.single['lot_id']! as String,
            'quantity': take,
            'unit_cost': unitCost,
            'total_cost': totalCost,
          });
          lineCogs += totalCost;
          unassignedCost -= take;
        }
        if (unassignedCost != 0) throw ReturnsDataIntegrityException('Kuantitas retur tidak cocok dengan konsumsi FIFO asal $id.');

        final isExempt = (line['ppn_exempt']! as num).toInt() == 1;
        prepared.add(<String, Object?>{
          'line_id': id, 'line': line, 'quantity': quantity,
          'gross': lineGross, 'item_discount': lineItemDiscount,
          'transaction_discount': lineTxDiscount, 'discount': lineDiscount,
          'dpp': lineDpp, 'ppn_exempt': isExempt, 'cogs': lineCogs,
          'physical': physicalPrepared, 'costs': costPrepared,
        });
        gross += lineGross;
        discount += lineDiscount;
        dpp += lineDpp; if (isExempt) { exempt += lineDpp; } else { taxable += lineDpp; }
        cogs += lineCogs;
      }

      final taxRows = (await tx.rawQuery(
        'SELECT COALESCE(SUM(refund_taxable_dpp),0) AS taxable, COALESCE(SUM(refund_ppn_amount),0) AS ppn FROM sale_returns WHERE original_sale_id = ?',
        <Object?>[saleKey],
      )).single;
      final oldTaxable = (taxRows['taxable']! as num).toInt();
      final oldPpn = (taxRows['ppn']! as num).toInt();
      final originalTaxable = (sale['taxable_dpp']! as num).toInt();
      final originalPpn = (sale['ppn_amount']! as num).toInt();
      final newTaxable = oldTaxable + taxable;
      if (newTaxable > originalTaxable) throw const ReturnsValidationException('DPP retur melebihi penjualan asal.');
      final targetPpn = originalTaxable == 0 || newTaxable == 0
          ? 0 : newTaxable >= originalTaxable
              ? originalPpn : (originalPpn * newTaxable + originalTaxable ~/ 2) ~/ originalTaxable;
      final ppn = targetPpn - oldPpn;
      if (ppn < 0) throw const ReturnsDataIntegrityException('Alokasi PPN retur tidak konsisten.');
      final refundTotal = dpp + ppn;
      final approvedAt = DateTime.now().toUtc().toIso8601String();

      await tx.insert('sale_returns', <String, Object?>{
        'id': opId, 'event_id': eventId, 'original_sale_id': saleKey,
        'original_transaction_id': transactionId, 'return_type': type.wireValue,
        'refund_method': payMethod, 'reason': cleanReason, 'business_date': date,
        'occurred_at_utc': at, 'timezone': BusinessDate.timezoneId,
        'actor_id': actor, 'approved_by_user_id': actor, 'approval_mode': 'self',
        'approved_at_utc': approvedAt, 'origin_actor_id': actor,
        'request_fingerprint': fingerprint, 'refund_gross': gross,
        'refund_discount_amount': discount, 'refund_dpp': dpp,
        'refund_taxable_dpp': taxable, 'refund_exempt_dpp': exempt,
        'refund_ppn_amount': ppn, 'refund_total': refundTotal, 'cogs_amount': cogs,
        'journal_entry_id': null, 'original_journal_entry_id': originalJournalId,
        'status': 'accepted',
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final productQty = <String, int>{};
      for (var i = 0; i < prepared.length; i++) {
        final entry = prepared[i];
        final lineId = entry['line_id']! as String;
        final line = entry['line']! as Map<String, Object?>;
        final returnItemId = 'return-item:$opId:$i';
        await tx.insert('sale_return_items', <String, Object?>{
          'id': returnItemId, 'sale_return_id': opId, 'original_sale_id': saleKey,
          'sale_item_id': lineId, 'product_id': line['product_id']! as String,
          'quantity': entry['quantity']! as int, 'refund_gross': entry['gross']! as int,
          'refund_item_discount_amount': entry['item_discount']! as int,
          'refund_transaction_discount_amount': entry['transaction_discount']! as int,
          'refund_discount_amount': entry['discount']! as int, 'refund_dpp': entry['dpp']! as int,
          'ppn_exempt': entry['ppn_exempt']! as bool ? 1 : 0, 'cogs_amount': entry['cogs']! as int,
        }, conflictAlgorithm: ConflictAlgorithm.abort);

        final physical = entry['physical']! as List<Map<String, Object?>>;
        for (var pi = 0; pi < physical.length; pi++) {
          final allocation = physical[pi];
          final sourceLotId = allocation['source_lot_id']! as String;
          final quarantineLot = 'return-lot:$opId:$i:$pi';
          final batchNo = 'RET-' + _hash('$opId|$sourceLotId|$pi').substring(0, 28);
          await tx.insert('inventory_lots', <String, Object?>{
            'id': quarantineLot, 'product_id': line['product_id']! as String,
            'batch_no': batchNo, 'expiry_date': allocation['expiry_date'],
            'first_received_at_utc': at, 'on_hand_qty': allocation['quantity']! as int,
            'reserved_qty': 0, 'status': 'quarantine', 'origin_lot_id': sourceLotId,
            'source_return_id': opId,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
          await tx.insert('sale_return_lot_allocations', <String, Object?>{
            'id': 'return-physical:$opId:$i:$pi', 'sale_return_item_id': returnItemId,
            'original_sale_id': saleKey, 'original_sale_item_id': lineId,
            'source_lot_id': sourceLotId, 'quarantine_lot_id': quarantineLot,
            'quantity': allocation['quantity']! as int,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
          await tx.insert('inventory_movements', <String, Object?>{
            'id': 'inventory:return:$opId:$i:$pi', 'product_id': line['product_id']! as String,
            'lot_id': quarantineLot, 'reference_id': opId,
            'movement_type': type == SaleReturnType.voidSale ? 'void_quarantine' : 'return_quarantine',
            'quantity_delta': allocation['quantity']! as int, 'occurred_at_utc': at,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
        }

        final costList = entry['costs']! as List<Map<String, Object?>>;
        for (var ci = 0; ci < costList.length; ci++) {
          final cost = costList[ci];
          final sourceLayer = cost['source_cost_layer_id']! as String;
          final returnedLayer = sourceLayer;
          final changedLayer = await tx.rawUpdate(
            'UPDATE inventory_cost_layers SET remaining_qty = remaining_qty + ? WHERE id = ? AND product_id = ? AND unit_cost = ?',
            <Object?>[cost['quantity'], sourceLayer, line['product_id'], cost['unit_cost']],
          );
          if (changedLayer != 1) {
            throw const ReturnsDataIntegrityException('Cost layer FIFO asal berubah saat retur.');
          }
          await tx.insert('sale_return_cost_layers', <String, Object?>{
            'id': 'return-cost-map:$opId:$i:$ci', 'sale_return_item_id': returnItemId,
            'original_sale_id': saleKey, 'original_sale_item_id': lineId,
            'source_cost_layer_id': sourceLayer, 'returned_cost_layer_id': returnedLayer,
            'quantity': cost['quantity']! as int, 'unit_cost': cost['unit_cost']! as int,
            'total_cost': cost['total_cost']! as int,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
          await tx.insert('stock_movements', <String, Object?>{
            'id': 'stock:return:$opId:$i:$ci', 'product_id': line['product_id']! as String,
            'reference_id': opId, 'movement_type': 'return_fifo_cogs',
            'quantity_delta': cost['quantity']! as int, 'unit_cost': cost['unit_cost']! as int,
            'total_cost': cost['total_cost']! as int, 'occurred_at_utc': at,
          }, conflictAlgorithm: ConflictAlgorithm.abort);
        }
        final pid = line['product_id']! as String;
        productQty[pid] = (productQty[pid] ?? 0) + (entry['quantity']! as int);
      }

      for (final e in productQty.entries) {
        if (await tx.rawUpdate('UPDATE products SET stock_qty = stock_qty + ? WHERE id = ?',
            <Object?>[e.value, e.key]) != 1) {
          throw const ReturnsDataIntegrityException('Stok produk tidak dapat dikembalikan.');
        }
      }

      final journalService = JournalService(SqliteJournalRepository(_database, executor: tx));
      late final List<JournalLine> journalLines;
      if (type == SaleReturnType.voidSale) {
        final orig = await tx.query('journal_lines', where: 'journal_id = ?', whereArgs: <Object?>[originalJournalId], orderBy: 'line_no');
        if (orig.length < 2) throw const ReturnsDataIntegrityException('Jurnal asal tidak dapat dibalik.');
        journalLines = orig.map((row) => JournalLine(
          accountCode: row['account_code']! as String,
          debit: (row['credit']! as num).toInt(),
          credit: (row['debit']! as num).toInt(),
        )).toList(growable: false);
      } else {
        journalLines = <JournalLine>[
          if (dpp > 0) JournalLine(accountCode: CoaAccounts.salesReturns.code, debit: dpp, credit: 0),
          if (ppn > 0) JournalLine(accountCode: CoaAccounts.ppnPayable.code, debit: ppn, credit: 0),
          if (refundTotal > 0) JournalLine(accountCode: payAccount, debit: 0, credit: refundTotal),
          if (cogs > 0) JournalLine(accountCode: CoaAccounts.inventory.code, debit: cogs, credit: 0),
          if (cogs > 0) JournalLine(accountCode: CoaAccounts.cogs.code, debit: 0, credit: cogs),
        ];
      }
      final journal = await journalService.post(JournalEntry(
        id: 'journal:return:$opId', date: time, transactionId: 'return:$opId',
        businessDate: date, timezone: BusinessDate.timezoneId, lines: journalLines,
      ));
      if (type == SaleReturnType.voidSale) {
        final changed = await tx.update('journals', <String, Object?>{'reversal_of_id': originalJournalId},
          where: 'id = ? AND reversal_of_id IS NULL', whereArgs: <Object?>[journal.id]);
        if (changed != 1) throw const ReturnsDataIntegrityException('Jurnal reversal tidak dapat ditautkan.');
      }
      await tx.update('sale_returns', <String, Object?>{'journal_entry_id': journal.id},
        where: 'id = ?', whereArgs: <Object?>[opId]);

      await enqueueOutboxEvent(tx, eventId: eventId, entityType: 'sale_return',
        entityId: opId, createdAtUtc: at,
        eventPayload: <String, Object?>{
          'return': <String, Object?>{
            'id': opId, 'original_sale_id': saleKey, 'return_type': type.wireValue,
            'refund_method': payMethod, 'reason': cleanReason, 'business_date': date,
            'occurred_at_utc': at, 'timezone': BusinessDate.timezoneId,
            'request_fingerprint': fingerprint, 'origin_actor_id': actor,
          },
          'items': sortedItems.map((e) => <String, Object?>{'sale_item_id': e.key, 'quantity': e.value}).toList(growable: false),
        });
      return <String, Object?>{'return_id': opId, 'refund_total': refundTotal, 'cogs_amount': cogs, 'already_processed': false};
    });
  }

  Future<String> adjustDisposition({
    required String lotId, required String action, required String reason,
    String? inspectionNote, String? inspectionResult, String? adjustmentId,
  }) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 500) {
      throw const ReturnsValidationException('Alasan penyesuaian wajib diisi dan maksimal 500 karakter.');
    }
    final id = (adjustmentId ?? _newId('adjustment')).trim();
    final eventId = 'outbox:stock_adjustment:$id';
    final fingerprint = _hash(jsonEncode(<String, Object?>{
      'lot_id': lotId, 'action': action, 'reason': cleanReason,
      'inspection_note': inspectionNote?.trim(), 'inspection_result': inspectionResult?.trim(),
    }));
    final allowed = <String, List<String>>{
      'quarantine': <String>['saleable', 'quarantine'],
      'release_quarantine': <String>['quarantine', 'saleable'],
      'mark_damaged': <String>['saleable', 'damaged'],
      'mark_recall': <String>['saleable', 'recall'],
      'mark_expired': <String>['saleable', 'expired'],
    };
    return _database.transaction<String>((tx) async {
      final existing = await tx.query('stock_adjustments', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
      if (existing.isNotEmpty) {
        if (existing.single['request_fingerprint'] != fingerprint) throw ReturnIdempotencyConflictException(id);
        return id;
      }
      final lots = await tx.query('inventory_lots', where: 'id = ?', whereArgs: <Object?>[lotId], limit: 1);
      if (lots.isEmpty) throw const ReturnsValidationException('Lot tidak ditemukan.');
      final lot = lots.single;
      var transition = allowed[action];
      if ((action == 'mark_damaged' || action == 'mark_recall' || action == 'mark_expired') &&
          lot['status'] == 'quarantine') {
        transition = <String>['quarantine',
          action == 'mark_damaged' ? 'damaged' : action == 'mark_recall' ? 'recall' : 'expired'];
      }
      if (transition == null || transition[0] != lot['status']) throw const ReturnsValidationException('Transisi status lot tidak diizinkan.');
      if ((lot['reserved_qty']! as num).toInt() != 0) throw const ReturnsValidationException('Lot masih memiliki kuantitas reservasi.');
      final now = DateTime.now().toUtc();
      final at = now.toIso8601String();
      final date = BusinessDate.fromUtc(now);
      final expiry = lot['expiry_date'] as String?;
      if (action == 'mark_expired' && (expiry == null || expiry.compareTo(date) >= 0)) {
        throw const ReturnsValidationException('Lot hanya boleh ditandai kedaluwarsa setelah tanggal expiry.');
      }
      final productRows = await tx.query('products', where: 'id = ?', whereArgs: <Object?>[lot['product_id']], limit: 1);
      if (productRows.isEmpty) throw const ReturnsDataIntegrityException('Produk lot tidak ditemukan.');
      final product = productRows.single;
      if (action == 'release_quarantine') {
        if ((inspectionNote ?? '').trim().isEmpty || (inspectionResult ?? '').toLowerCase().trim() != 'passed') {
          throw const ReturnsValidationException('Pelepasan karantina memerlukan catatan inspeksi lulus.');
        }
        if (expiry != null && expiry.compareTo(date) < 0) throw const ReturnsValidationException('Lot kedaluwarsa tidak dapat dilepas.');
        if ((product['track_expiry']! as num).toInt() == 1) {
          if (expiry == null) throw const ReturnsValidationException('Tanggal kedaluwarsa lot wajib ada.');
          final minDate = BusinessDate.fromUtc(now.add(Duration(days: (product['min_shelf_life_days']! as num).toInt())));
          if (expiry.compareTo(minDate) < 0) throw const ReturnsValidationException('Sisa umur simpan tidak memenuhi kebijakan produk.');
        }
      }
      final actor = actorId.trim().isEmpty ? 'device:' + deviceId.trim() : actorId.trim();
      if (actor == 'device:') throw const ReturnsValidationException('Identitas operator/perangkat tidak tersedia.');
      final toStatus = transition[1];
      if (await tx.update('inventory_lots', <String, Object?>{'status': toStatus},
          where: 'id = ? AND status = ?', whereArgs: <Object?>[lotId, lot['status']]) != 1) {
        throw const ReturnsDataIntegrityException('Status lot berubah selama operasi.');
      }
      await tx.insert('stock_adjustments', <String, Object?>{
        'id': id, 'event_id': eventId, 'product_id': lot['product_id'], 'lot_id': lotId,
        'action': action, 'from_status': transition[0], 'to_status': toStatus, 'quantity_delta': 0,
        'reason': cleanReason, 'inspection_note': inspectionNote?.trim(), 'inspection_result': inspectionResult?.trim(),
        'business_date': date, 'occurred_at_utc': at, 'timezone': BusinessDate.timezoneId,
        'actor_id': actor, 'approved_by_user_id': actor, 'approval_mode': 'self',
        'approved_at_utc': at, 'origin_actor_id': actor, 'request_fingerprint': fingerprint,
      }, conflictAlgorithm: ConflictAlgorithm.abort);
      await enqueueOutboxEvent(tx, eventId: eventId, entityType: 'stock_adjustment',
        entityId: id, createdAtUtc: at, eventPayload: <String, Object?>{
          'adjustment': <String, Object?>{
            'id': id, 'product_id': lot['product_id']! as String, 'lot_id': lotId,
            'action': action, 'from_status': transition[0], 'to_status': toStatus,
            'quantity_delta': 0, 'reason': cleanReason, 'inspection_note': inspectionNote?.trim(),
            'inspection_result': inspectionResult?.trim(), 'business_date': date,
            'occurred_at_utc': at, 'timezone': BusinessDate.timezoneId,
            'request_fingerprint': fingerprint, 'origin_actor_id': actor,
          },
        });
      return id;
    });
  }

  String _paymentAccount(String method) {
    switch (method) {
      case 'cash': return CoaAccounts.cash.code;
      case 'qris': return CoaAccounts.qris.code;
      case 'transfer':
      case 'bankTransfer':
      case 'bank_transfer':
      case 'bank-transfer': return CoaAccounts.bankTransfer.code;
      default: throw ReturnsValidationException('Metode pembayaran asal tidak didukung: $method');
    }
  }

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  String _newId(String prefix) {
    final now = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
    final random = List<int>.generate(16, (_) => Random.secure().nextInt(256))
        .map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix:$now:$random';
  }
}

class ReturnsValidationException implements Exception {
  const ReturnsValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}
class ReturnsDataIntegrityException implements Exception {
  const ReturnsDataIntegrityException(this.message);
  final String message;
  @override
  String toString() => message;
}
class ReturnIdempotencyConflictException implements Exception {
  ReturnIdempotencyConflictException(String id) : message = 'ID operasi "$id" dipakai dengan payload berbeda.';
  final String message;
  @override
  String toString() => message;
}
