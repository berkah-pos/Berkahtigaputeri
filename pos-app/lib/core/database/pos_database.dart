// lib/core/database/pos_database.dart

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'legacy_trial_importer.dart';

/// SQLite database for the local-first POS.
///
/// Schema changes must increment [schemaVersion] and provide a migration.
class PosDatabase {
  PosDatabase._(this.database);

  String? _legacyTrialPath;
  String? _legacyImportError;

  String? get legacyImportError => _legacyImportError;

  static const int schemaVersion = 4;
  static const String fileName = 'berkahtigaputeri_pos.db';

  final Database database;

  static Future<PosDatabase> openDefault({
    DatabaseFactory? factory,
  }) async {
    final root = await getDatabasesPath();
    final selectedFactory = factory ?? databaseFactory;
    final target = await openAt(
      p.join(root, fileName),
      factory: selectedFactory,
    );
    target._legacyTrialPath = p.join(root, 'berkah_pos.db');
    // Keep the POS shell available if legacy import needs attention, but
    // expose an explicit warning. The old file is never deleted or modified.
    try {
      await target.retryLegacyTrialImport(factory: selectedFactory);
    } catch (_) {
      // retryLegacyTrialImport retains the user-visible error on this object.
    }
    return target;
  }

  static Future<PosDatabase> openAt(
    String path, {
    DatabaseFactory? factory,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final db = await selectedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _createSchema,
        onUpgrade: _upgradeSchema,
      ),
    );
    final target = PosDatabase._(db);
    await target._recoverInterruptedOutbox();
    return target;
  }

  Future<T> transaction<T>(
    Future<T> Function(Transaction transaction) action,
  ) {
    return database.transaction<T>(action, exclusive: true);
  }

  /// Retries the one-time import from the older trial database. Errors are
  /// rethrown to the caller and also retained for display in the UI.
  Future<void> retryLegacyTrialImport({
    DatabaseFactory? factory,
  }) async {
    final path = _legacyTrialPath;
    if (path == null) return;
    try {
      await LegacyTrialImporter.importIfPresent(
        target: database,
        legacyPath: path,
        factory: factory,
      );
      _legacyImportError = null;
    } catch (error) {
      _legacyImportError = error.toString();
      rethrow;
    }
  }

  /// Recover rows claimed by a process that exited before server acceptance.
  Future<void> _recoverInterruptedOutbox() async {
    await database.transaction<void>((transaction) async {
      final rows = await transaction.query(
        'outbox_events',
        columns: <String>['id', 'retry_count'],
        where: 'status = ?',
        whereArgs: <Object?>['syncing'],
      );
      for (final row in rows) {
        await transaction.update(
          'outbox_events',
          <String, Object?>{
            'status': 'pending',
            'retry_count': (row['retry_count'] as num).toInt() + 1,
            'last_error':
                'Recovered interrupted sync; server acknowledgement was not confirmed.',
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[row['id'], 'syncing'],
        );
      }
    });
  }

  Future<void> close() => database.close();

  static Future<void> _createSchema(
    Database database,
    int version,
  ) async {
    await database.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY,
        sku TEXT NOT NULL UNIQUE,
        barcode TEXT,
        name_id TEXT NOT NULL,
        price INTEGER NOT NULL CHECK(price >= 0),
        ppn_exempt INTEGER NOT NULL CHECK(ppn_exempt IN (0, 1)),
        stock_qty INTEGER NOT NULL CHECK(stock_qty >= 0),
        track_expiry INTEGER NOT NULL DEFAULT 0 CHECK(track_expiry IN (0, 1)),
        min_shelf_life_days INTEGER NOT NULL DEFAULT 0 CHECK(min_shelf_life_days >= 0),
        requires_review INTEGER NOT NULL DEFAULT 0 CHECK(requires_review IN (0, 1))
      )
    ''');

    await _createInventorySchema(database);
    await _createSalesAndAccountingSchema(database);
    await _createLegacyArchiveTables(database);
  }

  static Future<void> _upgradeSchema(
    Database database,
    int oldVersion,
    int newVersion,
  ) async {
    var current = oldVersion;

    if (current < 2) {
      await _migrateV1ToV2(database);
      current = 2;
    }

    if (current < 3) {
      await database.execute('''
        ALTER TABLE products
        ADD COLUMN requires_review INTEGER NOT NULL DEFAULT 0
        CHECK(requires_review IN (0, 1))
      ''');
      await _createLegacyArchiveTables(database);
      current = 3;
    }

    if (current < 4) {
      final outboxColumns = await database.rawQuery(
        "PRAGMA table_info('outbox_events')",
      );
      if (outboxColumns.isEmpty) {
        // Older inventory-only databases may predate the checkout outbox.
        // Create it during upgrade rather than failing with ALTER TABLE.
        await database.execute('''
          CREATE TABLE outbox_events (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL,
            payload TEXT NOT NULL,
            status TEXT NOT NULL,
            retry_count INTEGER NOT NULL DEFAULT 0,
            created_at_utc TEXT NOT NULL,
            last_error TEXT,
            last_attempt_at_utc TEXT
          )
        ''');
        await database.execute(
          'CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox_events(status, created_at_utc)',
        );
      } else {
        final names = outboxColumns
            .map((row) => row['name'] as String)
            .toSet();
        if (!names.contains('last_error')) {
          await database.execute(
            'ALTER TABLE outbox_events ADD COLUMN last_error TEXT',
          );
        }
        if (!names.contains('last_attempt_at_utc')) {
          await database.execute(
            'ALTER TABLE outbox_events ADD COLUMN last_attempt_at_utc TEXT',
          );
        }
      }
      current = 4;
    }

    if (current != newVersion) {
      throw StateError(
        'Unsupported database migration: $oldVersion -> $newVersion.',
      );
    }
  }

  static Future<void> _migrateV1ToV2(Database database) async {
    await database.execute('''
      ALTER TABLE products
      ADD COLUMN track_expiry INTEGER NOT NULL DEFAULT 0
      CHECK(track_expiry IN (0, 1))
    ''');
    await database.execute('''
      ALTER TABLE products
      ADD COLUMN min_shelf_life_days INTEGER NOT NULL DEFAULT 0
      CHECK(min_shelf_life_days >= 0)
    ''');

    await database.execute(
      'ALTER TABLE inventory_lots RENAME TO inventory_cost_layers_v1',
    );
    await database.execute('DROP INDEX IF EXISTS idx_inventory_lots_fifo');

    await _createPhysicalLotTables(database);

    await database.execute('''
      INSERT INTO inventory_lots(
        id,
        product_id,
        batch_no,
        expiry_date,
        first_received_at_utc,
        on_hand_qty,
        reserved_qty,
        status
      )
      SELECT
        id,
        product_id,
        id,
        NULL,
        acquired_at_utc,
        remaining_qty,
        0,
        'saleable'
      FROM inventory_cost_layers_v1
    ''');

    await _createCostLayerTable(database);

    await database.execute('''
      INSERT INTO inventory_cost_layers(
        id,
        product_id,
        lot_id,
        acquired_at_utc,
        remaining_qty,
        unit_cost
      )
      SELECT
        id,
        product_id,
        id,
        acquired_at_utc,
        remaining_qty,
        unit_cost
      FROM inventory_cost_layers_v1
    ''');

    await database.execute('DROP TABLE inventory_cost_layers_v1');
    await _createInventoryAuditTables(database);

    await database.execute('''
      INSERT INTO inventory_movements(
        id,
        product_id,
        lot_id,
        reference_id,
        movement_type,
        quantity_delta,
        occurred_at_utc
      )
      SELECT
        'migration:v2:' || id,
        product_id,
        id,
        'schema-v2',
        'opening_balance',
        on_hand_qty,
        first_received_at_utc
      FROM inventory_lots
      WHERE on_hand_qty > 0
    ''');
  }

  static Future<void> _createInventorySchema(Database database) async {
    await _createPhysicalLotTables(database);
    await _createCostLayerTable(database);
    await _createInventoryAuditTables(database);
  }

  static Future<void> _createPhysicalLotTables(Database database) async {
    await database.execute('''
      CREATE TABLE inventory_lots (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        batch_no TEXT NOT NULL,
        expiry_date TEXT,
        first_received_at_utc TEXT NOT NULL,
        on_hand_qty INTEGER NOT NULL CHECK(on_hand_qty >= 0),
        reserved_qty INTEGER NOT NULL DEFAULT 0 CHECK(reserved_qty >= 0),
        status TEXT NOT NULL DEFAULT 'saleable'
          CHECK(status IN ('saleable', 'quarantine', 'damaged', 'expired', 'recall')),
        CHECK(reserved_qty <= on_hand_qty),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE UNIQUE INDEX idx_inventory_lot_identity
      ON inventory_lots(product_id, batch_no, IFNULL(expiry_date, ''))
    ''');

    await database.execute('''
      CREATE INDEX idx_inventory_lots_fefo
      ON inventory_lots(
        product_id,
        status,
        expiry_date,
        first_received_at_utc,
        id
      )
    ''');

    await database.execute('''
      CREATE TABLE lot_holds (
        id TEXT PRIMARY KEY,
        lot_id TEXT NOT NULL,
        hold_type TEXT NOT NULL,
        reason TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
        created_at_utc TEXT NOT NULL,
        released_at_utc TEXT,
        FOREIGN KEY(lot_id) REFERENCES inventory_lots(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_lot_holds_active
      ON lot_holds(lot_id, active)
    ''');

    await database.execute('''
      CREATE TABLE inventory_reservations (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL UNIQUE,
        request_fingerprint TEXT NOT NULL,
        status TEXT NOT NULL
          CHECK(status IN ('active', 'committed', 'released', 'expired')),
        expires_at_utc TEXT NOT NULL,
        created_at_utc TEXT NOT NULL,
        committed_at_utc TEXT,
        released_at_utc TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_inventory_reservations_status_expiry
      ON inventory_reservations(status, expires_at_utc)
    ''');

    await database.execute('''
      CREATE TABLE inventory_reservation_lines (
        reservation_id TEXT NOT NULL,
        line_no INTEGER NOT NULL,
        allocation_no INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        lot_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        PRIMARY KEY(reservation_id, line_no, allocation_no),
        FOREIGN KEY(reservation_id) REFERENCES inventory_reservations(id),
        FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(lot_id) REFERENCES inventory_lots(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_inventory_reservation_lines_lot
      ON inventory_reservation_lines(lot_id, reservation_id)
    ''');
  }

  static Future<void> _createCostLayerTable(Database database) async {
    await database.execute('''
      CREATE TABLE inventory_cost_layers (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        lot_id TEXT NOT NULL,
        acquired_at_utc TEXT NOT NULL,
        remaining_qty INTEGER NOT NULL CHECK(remaining_qty >= 0),
        unit_cost INTEGER NOT NULL CHECK(unit_cost >= 0),
        FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(lot_id) REFERENCES inventory_lots(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_inventory_cost_layers_fifo
      ON inventory_cost_layers(product_id, acquired_at_utc, id)
    ''');
  }

  static Future<void> _createInventoryAuditTables(Database database) async {
    await database.execute('''
      CREATE TABLE inventory_movements (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        lot_id TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        occurred_at_utc TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id),
        FOREIGN KEY(lot_id) REFERENCES inventory_lots(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_inventory_movements_product
      ON inventory_movements(product_id, occurred_at_utc, id)
    ''');

    await database.execute('''
      CREATE TABLE sale_lot_allocations (
        sale_item_id TEXT NOT NULL,
        allocation_no INTEGER NOT NULL,
        lot_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        PRIMARY KEY(sale_item_id, allocation_no),
        FOREIGN KEY(sale_item_id) REFERENCES sale_items(id),
        FOREIGN KEY(lot_id) REFERENCES inventory_lots(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE cost_layer_consumptions (
        sale_item_id TEXT NOT NULL,
        consumption_no INTEGER NOT NULL,
        cost_layer_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_cost INTEGER NOT NULL CHECK(unit_cost >= 0),
        total_cost INTEGER NOT NULL CHECK(total_cost >= 0),
        PRIMARY KEY(sale_item_id, consumption_no),
        FOREIGN KEY(sale_item_id) REFERENCES sale_items(id),
        FOREIGN KEY(cost_layer_id) REFERENCES inventory_cost_layers(id)
      )
    ''');
  }

  static Future<void> _createSalesAndAccountingSchema(Database database) async {
    await database.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL UNIQUE,
        request_fingerprint TEXT NOT NULL,
        occurred_at_utc TEXT NOT NULL,
        business_date TEXT NOT NULL,
        timezone TEXT NOT NULL,
        gross_amount INTEGER NOT NULL,
        item_discount_amount INTEGER NOT NULL,
        transaction_discount_amount INTEGER NOT NULL,
        discount_amount INTEGER NOT NULL,
        taxable_dpp INTEGER NOT NULL,
        exempt_dpp INTEGER NOT NULL,
        dpp INTEGER NOT NULL,
        ppn_amount INTEGER NOT NULL,
        grand_total INTEGER NOT NULL,
        cogs_amount INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        created_at_utc TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        line_no INTEGER NOT NULL,
        product_id TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price INTEGER NOT NULL CHECK(unit_price >= 0),
        gross_amount INTEGER NOT NULL,
        item_discount_amount INTEGER NOT NULL,
        transaction_discount_amount INTEGER NOT NULL,
        discount_amount INTEGER NOT NULL,
        dpp INTEGER NOT NULL,
        ppn_exempt INTEGER NOT NULL CHECK(ppn_exempt IN (0, 1)),
        cogs_amount INTEGER NOT NULL,
        FOREIGN KEY(sale_id) REFERENCES sales(id),
        FOREIGN KEY(product_id) REFERENCES products(id),
        UNIQUE(sale_id, line_no)
      )
    ''');

    await database.execute('''
      CREATE TABLE journals (
        id TEXT PRIMARY KEY,
        transaction_id TEXT NOT NULL UNIQUE,
        occurred_at_utc TEXT NOT NULL,
        business_date TEXT NOT NULL,
        timezone TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE journal_lines (
        journal_id TEXT NOT NULL,
        line_no INTEGER NOT NULL,
        account_code TEXT NOT NULL,
        debit INTEGER NOT NULL CHECK(debit >= 0),
        credit INTEGER NOT NULL CHECK(credit >= 0),
        PRIMARY KEY(journal_id, line_no),
        FOREIGN KEY(journal_id) REFERENCES journals(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity_delta INTEGER NOT NULL,
        unit_cost INTEGER NOT NULL CHECK(unit_cost >= 0),
        total_cost INTEGER NOT NULL CHECK(total_cost >= 0),
        occurred_at_utc TEXT NOT NULL,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_stock_movements_product
      ON stock_movements(product_id, occurred_at_utc)
    ''');

    await database.execute('''
      CREATE TABLE outbox_events (
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        created_at_utc TEXT NOT NULL,
        last_error TEXT,
        last_attempt_at_utc TEXT
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_outbox_status
      ON outbox_events(status, created_at_utc)
    ''');
  }

  /// Archive area for legacy trial history. These records are intentionally
  /// not treated as complete accounting journals because the trial schema did
  /// not store tax, payment-method, or acquisition-cost details.
  static Future<void> _createLegacyArchiveTables(Database database) async {
    await database.execute('''
      CREATE TABLE legacy_import_runs (
        migration_key TEXT PRIMARY KEY,
        source_file TEXT NOT NULL,
        completed_at_utc TEXT NOT NULL,
        imported_products INTEGER NOT NULL,
        archived_sales INTEGER NOT NULL,
        archived_sale_items INTEGER NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE legacy_product_stock_archive (
        product_id TEXT PRIMARY KEY,
        original_product_id INTEGER NOT NULL UNIQUE,
        original_quantity INTEGER NOT NULL CHECK(original_quantity >= 0),
        status TEXT NOT NULL CHECK(status IN ('needs_review', 'reviewed', 'no_opening_stock')),
        imported_at_utc TEXT NOT NULL,
        reviewed_at_utc TEXT,
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE legacy_sales_archive (
        id TEXT PRIMARY KEY,
        original_sale_id INTEGER NOT NULL UNIQUE,
        total_amount INTEGER NOT NULL CHECK(total_amount >= 0),
        item_count INTEGER NOT NULL CHECK(item_count >= 0),
        email TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE legacy_sale_items_archive (
        id TEXT PRIMARY KEY,
        original_item_id INTEGER NOT NULL UNIQUE,
        original_sale_id INTEGER NOT NULL,
        product_id TEXT,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        unit_price INTEGER NOT NULL CHECK(unit_price >= 0),
        subtotal INTEGER NOT NULL CHECK(subtotal >= 0),
        FOREIGN KEY(original_sale_id)
          REFERENCES legacy_sales_archive(original_sale_id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE INDEX idx_legacy_sales_archive_created
      ON legacy_sales_archive(created_at DESC, original_sale_id DESC)
    ''');

    await database.execute('''
      CREATE INDEX idx_legacy_stock_review
      ON legacy_product_stock_archive(status, product_id)
    ''');
  }
}
