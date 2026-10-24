// lib/features/products/repositories/sqlite_product_repository.dart

import 'package:sqflite/sqflite.dart';

import '../../../core/database/pos_database.dart';
import '../../../core/sync/outbox_event_writer.dart';
import '../models/product.dart';

/// SQLite-backed product repository and inventory receiving boundary.
class SqliteProductRepository {
  SqliteProductRepository(this._database);

  final PosDatabase _database;

  Future<void> upsert(Product product) async {
    _validate(product);

    await _database.transaction<void>((transaction) async {
      final existingRows = await transaction.query(
        'products',
        where: 'id = ?',
        whereArgs: <Object?>[product.id],
        limit: 1,
      );
      if (existingRows.isEmpty && product.stockQty != 0) {
        throw const ProductValidationException(
          'Produk baru harus dibuat dengan stok nol. Catat stok awal melalui '
          'penerimaan persediaan agar lot dan biaya HPP tercatat.',
        );
      }

      Product? current;
      if (existingRows.isNotEmpty) {
        current = _fromRow(existingRows.single);
        if (product.version != current.version) {
          throw ProductConcurrencyException(
            productId: product.id,
            expectedVersion: current.version,
            receivedVersion: product.version,
          );
        }
        if (current.trackExpiry != product.trackExpiry) {
          final lotCount = await transaction.rawQuery(
            'SELECT COUNT(*) AS value FROM inventory_lots WHERE product_id = ?',
            <Object?>[product.id],
          );
          if ((lotCount.single['value']! as int) > 0) {
            throw const ProductValidationException(
              'Pelacakan kedaluwarsa tidak dapat diubah setelah lot persediaan '
              'tercatat. Selesaikan stok lama terlebih dahulu.',
            );
          }
        }
      }

      // Ordinary edits preserve activity. Only setActiveStatus() can change it.
      final isActive = current?.isActive ?? true;
      final nextVersion = current == null ? 1 : current.version + 1;
      await transaction.rawInsert(
        '''
        INSERT INTO products(
          id, sku, barcode, name_id, price, ppn_exempt, stock_qty,
          track_expiry, min_shelf_life_days, requires_review, is_active, version
        ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          sku = excluded.sku,
          barcode = excluded.barcode,
          name_id = excluded.name_id,
          price = excluded.price,
          ppn_exempt = excluded.ppn_exempt,
          track_expiry = excluded.track_expiry,
          min_shelf_life_days = excluded.min_shelf_life_days,
          requires_review = excluded.requires_review,
          is_active = excluded.is_active,
          version = excluded.version
        ''',
        <Object?>[
          product.id, product.sku, product.barcode, product.nameId,
          product.price, product.ppnExempt ? 1 : 0, product.stockQty,
          product.trackExpiry ? 1 : 0, product.minShelfLifeDays,
          product.requiresReview ? 1 : 0, isActive ? 1 : 0, nextVersion,
        ],
      );

      await enqueueOutboxEvent(
        transaction,
        entityType: 'product',
        entityId: product.id,
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
        eventPayload: <String, Object?>{
          'product': <String, Object?>{
            'id': product.id, 'sku': product.sku, 'barcode': product.barcode,
            'name_id': product.nameId, 'price': product.price,
            'ppn_exempt': product.ppnExempt, 'track_expiry': product.trackExpiry,
            'min_shelf_life_days': product.minShelfLifeDays,
            'requires_review': product.requiresReview,
            'is_active': isActive, 'version': nextVersion,
          },
        },
      );
    });
  }

  /// Changes activity atomically with an audit row and durable product event.
  /// The transition takes effect locally while offline; outbox state records
  /// whether server confirmation is pending or requires attention.
  Future<void> setActiveStatus(
    Product product, {
    required bool isActive,
    required String reason,
  }) async {
    final normalizedReason = reason.trim();
    if (normalizedReason.isEmpty || normalizedReason.length > 500) {
      throw const ProductValidationException(
        'Alasan perubahan status wajib diisi (maksimal 500 karakter).',
      );
    }

    await _database.transaction<void>((transaction) async {
      final rows = await transaction.query(
        'products', where: 'id = ?', whereArgs: <Object?>[product.id], limit: 1,
      );
      if (rows.isEmpty) throw ProductNotFoundException(product.id);
      final current = _fromRow(rows.single);
      if (current.version != product.version) {
        throw ProductConcurrencyException(
          productId: product.id,
          expectedVersion: current.version,
          receivedVersion: product.version,
        );
      }
      if (current.isActive == isActive) return;

      final changedAt = DateTime.now().toUtc().toIso8601String();
      final nextVersion = current.version + 1;
      final eventId =
          'outbox:product-status:${DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16)}:$nextVersion';
      final changed = await transaction.rawUpdate(
        '''
        UPDATE products SET is_active = ?, version = ?
        WHERE id = ? AND version = ?
        ''',
        <Object?>[isActive ? 1 : 0, nextVersion, product.id, current.version],
      );
      if (changed != 1) {
        throw ProductConcurrencyException(
          productId: product.id,
          expectedVersion: current.version,
          receivedVersion: product.version,
        );
      }

      await transaction.insert('product_status_history', <String, Object?>{
        'event_id': eventId, 'product_id': product.id,
        'from_active': current.isActive ? 1 : 0,
        'to_active': isActive ? 1 : 0,
        'product_version': nextVersion, 'reason': normalizedReason,
        'changed_at_utc': changedAt, 'sync_status': 'pending',
      });
      await enqueueOutboxEvent(
        transaction,
        eventId: eventId,
        entityType: 'product',
        entityId: product.id,
        createdAtUtc: changedAt,
        eventPayload: <String, Object?>{
          'product': <String, Object?>{
            'id': current.id, 'sku': current.sku, 'barcode': current.barcode,
            'name_id': current.nameId, 'price': current.price,
            'ppn_exempt': current.ppnExempt, 'track_expiry': current.trackExpiry,
            'min_shelf_life_days': current.minShelfLifeDays,
            'requires_review': current.requiresReview,
            'is_active': isActive, 'version': nextVersion,
            'status_change': <String, Object?>{
              'from_active': current.isActive, 'to_active': isActive,
              'reason': normalizedReason, 'changed_at_utc': changedAt,
            },
          },
        },
      );
    });
  }

  /// Lists products in deterministic display order.
  Future<List<Product>> listAll() async {
    final rows = await _database.database.rawQuery('''
      SELECT p.*,
        (SELECT e.status FROM outbox_events e
         WHERE e.entity_type = 'product' AND e.entity_id = p.id
           AND e.status <> 'acknowledged'
         ORDER BY e.created_at_utc DESC, e.id DESC LIMIT 1) AS sync_status
      FROM products p
      ORDER BY p.name_id COLLATE NOCASE, p.sku
    ''');
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<Product?> findById(String id) async {
    final rows = await _database.database.rawQuery(
      '''
      SELECT p.*,
        (SELECT e.status FROM outbox_events e
         WHERE e.entity_type = 'product' AND e.entity_id = p.id
           AND e.status <> 'acknowledged'
         ORDER BY e.created_at_utc DESC, e.id DESC LIMIT 1) AS sync_status
      FROM products p WHERE p.id = ? LIMIT 1
      ''',
      <Object?>[id],
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  /// Receives a new physical batch and creates its first FIFO financial layer.
  ///
  /// [id] is the physical lot ID. [costLayerId] defaults to `cost:<id>`.
  /// Expiry-tracked products require both [batchNo] and [expiryDate].
  Future<void> addInventoryLot({
    required String id,
    required String productId,
    required int quantity,
    required int unitCost,
    required DateTime acquiredAtUtc,
    String? batchNo,
    DateTime? expiryDate,
    String? costLayerId,
    String? counterAccountCode,
  }) async {
    if (id.trim().isEmpty) {
      throw const ProductValidationException('ID lot wajib diisi.');
    }
    if (productId.trim().isEmpty) {
      throw const ProductValidationException('ID produk wajib diisi.');
    }
    _validateReceipt(quantity: quantity, unitCost: unitCost);

    final normalizedLotId = id.trim();
    final normalizedProductId = productId.trim();
    final normalizedCostLayerId =
        (costLayerId ?? 'cost:$normalizedLotId').trim();
    if (normalizedCostLayerId.isEmpty) {
      throw const ProductValidationException('ID layer biaya wajib diisi.');
    }

    await _database.transaction((transaction) async {
      final product = await _loadProduct(transaction, normalizedProductId);
      final normalizedBatchNo = (batchNo ?? normalizedLotId).trim();

      if (product.trackExpiry && batchNo == null) {
        throw const ProductValidationException(
          'Nomor batch wajib untuk produk yang melacak kedaluwarsa.',
        );
      }
      if (normalizedBatchNo.isEmpty) {
        throw const ProductValidationException('Nomor batch wajib diisi.');
      }
      if (product.trackExpiry && expiryDate == null) {
        throw const ProductValidationException(
          'Tanggal kedaluwarsa wajib untuk produk yang melacak kedaluwarsa.',
        );
      }

      final receivedAt = acquiredAtUtc.toUtc().toIso8601String();
      final expiry = expiryDate == null ? null : _dateOnly(expiryDate);

      await transaction.insert(
        'inventory_lots',
        <String, Object?>{
          'id': normalizedLotId,
          'product_id': normalizedProductId,
          'batch_no': normalizedBatchNo,
          'expiry_date': expiry,
          'first_received_at_utc': receivedAt,
          'on_hand_qty': quantity,
          'reserved_qty': 0,
          'status': 'saleable',
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await transaction.insert(
        'inventory_cost_layers',
        <String, Object?>{
          'id': normalizedCostLayerId,
          'product_id': normalizedProductId,
          'lot_id': normalizedLotId,
          'acquired_at_utc': receivedAt,
          'remaining_qty': quantity,
          'unit_cost': unitCost,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await _increaseProductStock(
        transaction,
        productId: normalizedProductId,
        quantity: quantity,
      );

      await transaction.insert(
        'inventory_movements',
        <String, Object?>{
          'id': 'receipt:$normalizedCostLayerId',
          'product_id': normalizedProductId,
          'lot_id': normalizedLotId,
          'reference_id': normalizedCostLayerId,
          'movement_type': 'receipt',
          'quantity_delta': quantity,
          'occurred_at_utc': receivedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await enqueueOutboxEvent(
        transaction,
        entityType: 'inventory_receipt',
        entityId: normalizedProductId,
        createdAtUtc: receivedAt,
        eventPayload: <String, Object?>{
          'receipt': <String, Object?>{
            'product_id': normalizedProductId,
            'lot_id': normalizedLotId,
            'cost_layer_id': normalizedCostLayerId,
            'quantity': quantity,
            'unit_cost': unitCost,
            'counter_account_code': counterAccountCode,
            'batch_no': normalizedBatchNo,
            'expiry_date': expiry,
            'acquired_at_utc': receivedAt,
            'timezone': 'Asia/Jakarta',
          },
        },
      );
    });
  }

  /// Adds another receipt/cost layer into an existing physical batch.
  Future<void> addInventoryToExistingLot({
    required String lotId,
    required String costLayerId,
    required int quantity,
    required int unitCost,
    required DateTime acquiredAtUtc,
    String? counterAccountCode,
  }) async {
    if (lotId.trim().isEmpty || costLayerId.trim().isEmpty) {
      throw const ProductValidationException(
        'ID lot dan layer biaya wajib diisi.',
      );
    }
    _validateReceipt(quantity: quantity, unitCost: unitCost);

    final normalizedLotId = lotId.trim();
    final normalizedCostLayerId = costLayerId.trim();

    await _database.transaction((transaction) async {
      final lots = await transaction.query(
        'inventory_lots',
        where: 'id = ?',
        whereArgs: <Object?>[normalizedLotId],
        limit: 1,
      );
      if (lots.isEmpty) {
        throw InventoryLotNotFoundException(normalizedLotId);
      }

      final lot = lots.first;
      final productId = lot['product_id']! as String;
      final receivedAt = acquiredAtUtc.toUtc().toIso8601String();

      await transaction.insert(
        'inventory_cost_layers',
        <String, Object?>{
          'id': normalizedCostLayerId,
          'product_id': productId,
          'lot_id': normalizedLotId,
          'acquired_at_utc': receivedAt,
          'remaining_qty': quantity,
          'unit_cost': unitCost,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final changed = await transaction.rawUpdate(
        '''
        UPDATE inventory_lots
        SET on_hand_qty = on_hand_qty + ?
        WHERE id = ?
        ''',
        <Object?>[quantity, normalizedLotId],
      );
      if (changed != 1) {
        throw InventoryLotNotFoundException(normalizedLotId);
      }

      await _increaseProductStock(
        transaction,
        productId: productId,
        quantity: quantity,
      );

      await transaction.insert(
        'inventory_movements',
        <String, Object?>{
          'id': 'receipt:$normalizedCostLayerId',
          'product_id': productId,
          'lot_id': normalizedLotId,
          'reference_id': normalizedCostLayerId,
          'movement_type': 'receipt',
          'quantity_delta': quantity,
          'occurred_at_utc': receivedAt,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await enqueueOutboxEvent(
        transaction,
        entityType: 'inventory_receipt',
        entityId: productId,
        createdAtUtc: receivedAt,
        eventPayload: <String, Object?>{
          'receipt': <String, Object?>{
            'product_id': productId,
            'lot_id': normalizedLotId,
            'cost_layer_id': normalizedCostLayerId,
            'quantity': quantity,
            'unit_cost': unitCost,
            'counter_account_code': counterAccountCode,
            'batch_no': (lot['batch_no'] as String?) ?? normalizedLotId,
            'expiry_date': lot['expiry_date'] as String?,
            'acquired_at_utc': receivedAt,
            'timezone': 'Asia/Jakarta',
          },
        },
      );
    });
  }

  Future<Product> _loadProduct(
    Transaction transaction,
    String productId,
  ) async {
    final rows = await transaction.query(
      'products',
      where: 'id = ?',
      whereArgs: <Object?>[productId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ProductNotFoundException(productId);
    }
    return _fromRow(rows.first);
  }

  Future<void> _increaseProductStock(
    Transaction transaction, {
    required String productId,
    required int quantity,
  }) async {
    final changed = await transaction.rawUpdate(
      '''
      UPDATE products
      SET stock_qty = stock_qty + ?
      WHERE id = ?
      ''',
      <Object?>[quantity, productId],
    );
    if (changed != 1) {
      throw ProductNotFoundException(productId);
    }
  }

  /// Returns true once physical lot history exists for this product.
  /// Expiry-tracking rules should not be changed after lots are recorded.
  Future<bool> hasInventoryLots(String productId) async {
    final rows = await _database.database.rawQuery(
      'SELECT COUNT(*) AS value FROM inventory_lots WHERE product_id = ?',
      <Object?>[productId.trim()],
    );
    return (rows.single['value']! as int) > 0;
  }

  /// Lists trial-era stock quantities that must be physically checked and
  /// received into the live inventory ledger before being used in checkout.
  Future<List<Map<String, Object?>>> legacyStockNeedsReview() {
    return _database.database.rawQuery(
      '''
      SELECT
        p.id AS product_id,
        p.name_id,
        p.sku,
        p.stock_qty AS current_stock_qty,
        a.original_product_id,
        a.original_quantity
      FROM legacy_product_stock_archive a
      JOIN products p ON p.id = a.product_id
      WHERE a.status = 'needs_review'
        AND a.original_quantity > 0
      ORDER BY p.name_id COLLATE NOCASE, p.sku
      ''',
    );
  }

  /// Marks a legacy stock row reviewed only after the owner confirms physical
  /// stock was checked. The current product count must match its lot ledger.
  Future<void> markLegacyStockReconciled(String productId) async {
    final normalizedId = productId.trim();
    await _database.transaction<void>((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT p.stock_qty,
               COALESCE(SUM(l.on_hand_qty), 0) AS lot_qty
        FROM products p
        LEFT JOIN inventory_lots l ON l.product_id = p.id
        WHERE p.id = ?
        GROUP BY p.id, p.stock_qty
        ''',
        <Object?>[normalizedId],
      );
      if (rows.isEmpty) throw ProductNotFoundException(normalizedId);
      if ((rows.single['stock_qty']! as int) !=
          (rows.single['lot_qty']! as int)) {
        throw const ProductValidationException(
          'Stok produk tidak cocok dengan jumlah lot. Periksa persediaan '
          'sebelum menyelesaikan rekonsiliasi trial.',
        );
      }
      final changed = await transaction.update(
        'legacy_product_stock_archive',
        <String, Object?>{
          'status': 'reviewed',
          'reviewed_at_utc': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'product_id = ? AND status = ?',
        whereArgs: <Object?>[normalizedId, 'needs_review'],
      );
      if (changed != 1) {
        throw const ProductValidationException(
          'Arsip stok trial sudah direkonsiliasi atau tidak ditemukan.',
        );
      }
    });
  }

  /// Deletes a product only when no inventory or transaction history refers
  /// to it. The check and deletion are atomic to preserve auditability.
  Future<void> deleteIfUnused(String productId) async {
    final normalizedId = productId.trim();
    if (normalizedId.isEmpty) {
      throw const ProductValidationException('ID produk wajib diisi.');
    }

    await _database.transaction<void>((transaction) async {
      final references = await transaction.rawQuery(
        '''
        SELECT
          (SELECT COUNT(*) FROM sale_items WHERE product_id = ?) AS sale_count,
          (SELECT COUNT(*) FROM inventory_lots WHERE product_id = ?) AS lot_count,
          (SELECT COUNT(*) FROM stock_movements WHERE product_id = ?) AS movement_count,
          (SELECT COUNT(*) FROM legacy_sale_items_archive WHERE product_id = ?) AS legacy_item_count,
          (SELECT COUNT(*) FROM legacy_product_stock_archive WHERE product_id = ?) AS legacy_stock_count,
          (SELECT COUNT(*) FROM product_status_history WHERE product_id = ?) AS status_history_count
        ''',
        <Object?>[
          normalizedId,
          normalizedId,
          normalizedId,
          normalizedId,
          normalizedId,
          normalizedId,
        ],
      );
      final row = references.single;
      final used = (row['sale_count']! as int) > 0 ||
          (row['lot_count']! as int) > 0 ||
          (row['movement_count']! as int) > 0 ||
          (row['legacy_item_count']! as int) > 0 ||
          (row['legacy_stock_count']! as int) > 0 ||
          (row['status_history_count']! as int) > 0;
      if (used) {
        throw const ProductValidationException(
          'Produk memiliki riwayat transaksi atau persediaan. Nonaktifkan '
          'melalui kebijakan katalog setelah status nonaktif tersedia.',
        );
      }

      final queuedProductEvents = await transaction.query(
        'outbox_events',
        where: 'entity_id = ? AND entity_type = ?',
        whereArgs: <Object?>[normalizedId, 'product'],
      );
      // Never discard an event that may already have reached the server.
      final mayCancelUnsent = queuedProductEvents.every((event) =>
          (event['status'] == 'pending' || event['status'] == 'retry') &&
          (event['retry_count'] as int? ?? 0) == 0);
      if (!mayCancelUnsent) {
        throw const ProductValidationException(
          'Produk sudah memiliki status sinkronisasi yang ambigu atau diterima server. '
          'Penghapusan memerlukan alur penonaktifan server yang diaudit.',
        );
      }
      await transaction.delete(
        'outbox_events',
        where: 'entity_id = ? AND entity_type = ? AND status IN (?, ?)',
        whereArgs: <Object?>[normalizedId, 'product', 'pending', 'retry'],
      );

      final changed = await transaction.delete(
        'products',
        where: 'id = ?',
        whereArgs: <Object?>[normalizedId],
      );
      if (changed != 1) {
        throw ProductNotFoundException(normalizedId);
      }
    });
  }

  void _validateReceipt({
    required int quantity,
    required int unitCost,
  }) {
    if (quantity <= 0) {
      throw const ProductValidationException(
        'Jumlah lot harus lebih dari nol.',
      );
    }
    if (unitCost < 0) {
      throw const ProductValidationException(
        'Harga pokok tidak boleh negatif.',
      );
    }
  }

  void _validate(Product product) {
    if (product.id.trim().isEmpty) {
      throw const ProductValidationException('ID produk wajib diisi.');
    }
    if (product.sku.trim().isEmpty) {
      throw const ProductValidationException('SKU wajib diisi.');
    }
    if (product.nameId.trim().isEmpty) {
      throw const ProductValidationException('Nama produk wajib diisi.');
    }
    if (product.price < 0) {
      throw const ProductValidationException('Harga tidak boleh negatif.');
    }
    if (product.stockQty < 0) {
      throw const ProductValidationException('Stok tidak boleh negatif.');
    }
    if (product.minShelfLifeDays < 0) {
      throw const ProductValidationException(
        'Minimum shelf life tidak boleh negatif.',
      );
    }
  }

  Product _fromRow(Map<String, Object?> row) {
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
      isActive: (row['is_active']! as int) == 1,
      version: row['version']! as int,
      syncStatus: row['sync_status'] as String?,
    );
  }

  String _dateOnly(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}

class ProductRepositoryException implements Exception {
  const ProductRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ProductValidationException extends ProductRepositoryException {
  const ProductValidationException(super.message);
}

class ProductNotFoundException extends ProductRepositoryException {
  ProductNotFoundException(String productId)
      : super('Produk "$productId" tidak ditemukan.');
}

class ProductConcurrencyException extends ProductRepositoryException {
  ProductConcurrencyException({
    required String productId,
    required int expectedVersion,
    required int receivedVersion,
  }) : super(
          'Produk "$productId" sudah berubah (versi saat ini '
          '$expectedVersion, versi dibaca $receivedVersion). Muat ulang '
          'produk sebelum menyimpan.',
        );
}

class ProductInactiveException extends ProductRepositoryException {
  ProductInactiveException(String productName)
      : super('Produk "$productName" nonaktif dan tidak dapat dijual.');
}

class InventoryLotNotFoundException extends ProductRepositoryException {
  InventoryLotNotFoundException(String lotId)
      : super('Lot "$lotId" tidak ditemukan.');
}

class ProductRequiresReviewException extends ProductRepositoryException {
  ProductRequiresReviewException(String productName)
      : super(
          'Produk "$productName" belum dapat dijual sebelum klasifikasi PPN '
          'dan data migrasi ditinjau.',
        );
}
