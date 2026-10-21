// test/inventory/database_migration_test.dart

import 'dart:io';

import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('schema v1 inventory migrates into physical lot and FIFO cost layer',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkahtigaputeri-migration-');
    addTearDown(() => directory.delete(recursive: true));

    final path = p.join(directory.path, 'legacy.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              sku TEXT NOT NULL UNIQUE,
              barcode TEXT,
              name_id TEXT NOT NULL,
              price INTEGER NOT NULL CHECK(price >= 0),
              ppn_exempt INTEGER NOT NULL CHECK(ppn_exempt IN (0, 1)),
              stock_qty INTEGER NOT NULL CHECK(stock_qty >= 0)
            )
          ''');

          // Schema v1 already had a durable outbox. New retry/receipt fields
          // are added by the v4 migration and must not discard existing events.
          await database.execute('''
            CREATE TABLE outbox_events (
              id TEXT PRIMARY KEY,
              entity_type TEXT NOT NULL,
              entity_id TEXT NOT NULL,
              payload TEXT NOT NULL,
              status TEXT NOT NULL,
              retry_count INTEGER NOT NULL DEFAULT 0,
              created_at_utc TEXT NOT NULL
            )
          ''');
          await database.execute('''
            CREATE INDEX idx_outbox_status
            ON outbox_events(status, created_at_utc)
          ''');

          await database.execute('''
            CREATE TABLE inventory_lots (
              id TEXT PRIMARY KEY,
              product_id TEXT NOT NULL,
              acquired_at_utc TEXT NOT NULL,
              remaining_qty INTEGER NOT NULL CHECK(remaining_qty >= 0),
              unit_cost INTEGER NOT NULL CHECK(unit_cost >= 0),
              FOREIGN KEY(product_id) REFERENCES products(id)
            )
          ''');

          await database.execute('''
            CREATE INDEX idx_inventory_lots_fifo
            ON inventory_lots(product_id, acquired_at_utc, id)
          ''');
        },
      ),
    );

    await legacy.insert(
      'products',
      <String, Object?>{
        'id': 'P-LEGACY',
        'sku': 'SKU-LEGACY',
        'barcode': null,
        'name_id': 'Produk Legacy',
        'price': 25000,
        'ppn_exempt': 0,
        'stock_qty': 2,
      },
    );
    await legacy.insert(
      'outbox_events',
      <String, Object?>{
        'id': 'OUTBOX-LEGACY',
        'entity_type': 'sale',
        'entity_id': 'TXN-LEGACY',
        'payload': '{"legacy":true}',
        'status': 'pending',
        'retry_count': 2,
        'created_at_utc': DateTime.utc(2026, 9, 1).toIso8601String(),
      },
    );
    await legacy.insert(
      'inventory_lots',
      <String, Object?>{
        'id': 'LOT-LEGACY',
        'product_id': 'P-LEGACY',
        'acquired_at_utc': DateTime.utc(2026, 9, 1).toIso8601String(),
        'remaining_qty': 2,
        'unit_cost': 10000,
      },
    );
    await legacy.close();

    final migrated = await PosDatabase.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(migrated.close);

    final version = await migrated.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], PosDatabase.schemaVersion);

    final product = (await migrated.database.query('products')).single;
    expect(product['track_expiry'], 0);
    expect(product['min_shelf_life_days'], 0);
    expect(product['requires_review'], 0);
    expect(product['stock_qty'], 2);

    final lot = (await migrated.database.query('inventory_lots')).single;
    expect(lot['id'], 'LOT-LEGACY');
    expect(lot['batch_no'], 'LOT-LEGACY');
    expect(lot['expiry_date'], isNull);
    expect(lot['on_hand_qty'], 2);
    expect(lot['reserved_qty'], 0);
    expect(lot['status'], 'saleable');

    final costLayer =
        (await migrated.database.query('inventory_cost_layers')).single;
    expect(costLayer['id'], 'LOT-LEGACY');
    expect(costLayer['lot_id'], 'LOT-LEGACY');
    expect(costLayer['remaining_qty'], 2);
    expect(costLayer['unit_cost'], 10000);

    final opening =
        (await migrated.database.query('inventory_movements')).single;
    expect(opening['movement_type'], 'opening_balance');
    expect(opening['quantity_delta'], 2);

    final outbox = (await migrated.database.query('outbox_events')).single;
    expect(outbox['id'], 'OUTBOX-LEGACY');
    expect(outbox['status'], 'pending');
    expect(outbox['retry_count'], 2);
    expect(outbox['last_error'], isNull);
    expect(outbox['next_retry_at_utc'], isNull);
    expect(outbox['acked_at_utc'], isNull);
    expect(outbox['server_receipt_id'], isNull);

    expect(await migrated.database.query('legacy_import_runs'), isEmpty);
    expect(await migrated.database.query('legacy_sales_archive'), isEmpty);
  });
}
