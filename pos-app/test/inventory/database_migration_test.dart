// test/inventory/database_migration_test.dart

import 'dart:io';

import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('fresh schema defaults products to active version one', () async {
    sqfliteFfiInit();
    final database = await PosDatabase.openAt(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(database.close);

    await database.database.insert('products', <String, Object?>{
      'id': 'P-FRESH',
      'sku': 'SKU-FRESH',
      'barcode': null,
      'name_id': 'Produk instalasi baru',
      'price': 10000,
      'ppn_exempt': 0,
      'stock_qty': 0,
    });
    final product = (await database.database.query('products')).single;
    expect(product['is_active'], 1);
    expect(product['version'], 1);
    expect(await database.database.query('product_status_history'), isEmpty);
  });

  test('schema v4 adds active status and version without changing products', () async {
    sqfliteFfiInit();
    final directory = await Directory.systemTemp.createTemp('berkah-pos-v4-lifecycle-');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'legacy-v4.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              sku TEXT NOT NULL,
              barcode TEXT,
              name_id TEXT NOT NULL,
              price INTEGER NOT NULL,
              ppn_exempt INTEGER NOT NULL,
              stock_qty INTEGER NOT NULL,
              track_expiry INTEGER NOT NULL DEFAULT 0,
              min_shelf_life_days INTEGER NOT NULL DEFAULT 0,
              requires_review INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    await legacy.insert('products', <String, Object?>{
      'id': 'P-V4', 'sku': 'SKU-V4', 'barcode': null,
      'name_id': 'Produk V4', 'price': 25000,
      'ppn_exempt': 0, 'stock_qty': 3,
      'track_expiry': 0, 'min_shelf_life_days': 0, 'requires_review': 0,
    });
    await legacy.close();

    final migrated = await PosDatabase.openAt(path, factory: databaseFactoryFfi);
    addTearDown(migrated.close);
    final product = (await migrated.database.query('products')).single;
    expect(product['id'], 'P-V4');
    expect(product['stock_qty'], 3);
    expect(product['is_active'], 1);
    expect(product['version'], 1);
    expect(await migrated.database.query('product_status_history'), isEmpty);
    final version = await migrated.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], PosDatabase.schemaVersion);
  });

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
    expect(product['is_active'], 1);
    expect(product['version'], 1);
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

    expect(await migrated.database.query('legacy_import_runs'), isEmpty);
    expect(await migrated.database.query('legacy_sales_archive'), isEmpty);
  });


  test('schema v3 upgrades an existing outbox without losing queued events',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkahtigaputeri-outbox-v3-');
    addTearDown(() => directory.delete(recursive: true));

    final path = p.join(directory.path, 'legacy-v3.db');
    final versionThree = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (database, version) async {
          // Model the version 3 product schema as well as its durable outbox.
          // Version 3 predates the v4 outbox retry/acknowledgement columns and
          // the v5 product lifecycle fields.
          await database.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              sku TEXT NOT NULL UNIQUE,
              barcode TEXT,
              name_id TEXT NOT NULL,
              price INTEGER NOT NULL CHECK(price >= 0),
              ppn_exempt INTEGER NOT NULL CHECK(ppn_exempt IN (0, 1)),
              stock_qty INTEGER NOT NULL CHECK(stock_qty >= 0),
              track_expiry INTEGER NOT NULL DEFAULT 0
                CHECK(track_expiry IN (0, 1)),
              min_shelf_life_days INTEGER NOT NULL DEFAULT 0
                CHECK(min_shelf_life_days >= 0),
              requires_review INTEGER NOT NULL DEFAULT 0
                CHECK(requires_review IN (0, 1))
            )
          ''');
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
        },
      ),
    );

    await versionThree.insert('products', <String, Object?>{
      'id': 'P-V3',
      'sku': 'SKU-V3',
      'barcode': null,
      'name_id': 'Produk V3',
      'price': 22000,
      'ppn_exempt': 0,
      'stock_qty': 5,
      'track_expiry': 1,
      'min_shelf_life_days': 3,
      'requires_review': 1,
    });

    await versionThree.insert('outbox_events', <String, Object?>{
      'id': 'outbox:product:P-V3',
      'entity_type': 'product',
      'entity_id': 'P-V3',
      'payload': '{"product":{"id":"P-V3"}}',
      'status': 'retry',
      'retry_count': 3,
      'created_at_utc': '2026-10-20T10:00:00.000Z',
    });
    await versionThree.close();

    final migrated = await PosDatabase.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(migrated.close);

    final version = await migrated.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], PosDatabase.schemaVersion);

    final products = await migrated.database.query('products');
    expect(products, hasLength(1));
    expect(products.single['id'], 'P-V3');
    expect(products.single['sku'], 'SKU-V3');
    expect(products.single['stock_qty'], 5);
    expect(products.single['track_expiry'], 1);
    expect(products.single['min_shelf_life_days'], 3);
    expect(products.single['requires_review'], 1);
    expect(products.single['is_active'], 1);
    expect(products.single['version'], 1);

    final rows = await migrated.database.query('outbox_events');
    expect(rows, hasLength(1));
    final row = rows.single;
    expect(row['id'], 'outbox:product:P-V3');
    expect(row['entity_type'], 'product');
    expect(row['entity_id'], 'P-V3');
    expect(row['payload'], '{"product":{"id":"P-V3"}}');
    expect(row['status'], 'retry');
    expect(row['retry_count'], 3);
    expect(row['created_at_utc'], '2026-10-20T10:00:00.000Z');
    expect(row['last_error'], isNull);
    expect(row['next_retry_at_utc'], isNull);
    expect(row['acked_at_utc'], isNull);
    expect(row['server_receipt_id'], isNull);

    final columns = (await migrated.database.rawQuery(
      'PRAGMA table_info(outbox_events)',
    ))
        .map((column) => column['name'] as String)
        .toSet();
    expect(
      columns,
      containsAll(<String>{
        'id',
        'entity_type',
        'entity_id',
        'payload',
        'status',
        'retry_count',
        'created_at_utc',
        'last_error',
        'next_retry_at_utc',
        'acked_at_utc',
        'server_receipt_id',
      }),
    );

    final indexes = (await migrated.database.rawQuery(
      "PRAGMA index_list('outbox_events')",
    ))
        .map((index) => index['name'] as String)
        .toSet();
    expect(indexes, contains('idx_outbox_status'));
    expect(indexes, contains('idx_outbox_retry'));
  });


  test('schema v2 upgrades product review and outbox fields without data loss',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkahtigaputeri-v2-upgrade-');
    addTearDown(() => directory.delete(recursive: true));

    final path = p.join(directory.path, 'legacy-v2.db');
    final versionTwo = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              sku TEXT NOT NULL UNIQUE,
              barcode TEXT,
              name_id TEXT NOT NULL,
              price INTEGER NOT NULL CHECK(price >= 0),
              ppn_exempt INTEGER NOT NULL CHECK(ppn_exempt IN (0, 1)),
              stock_qty INTEGER NOT NULL CHECK(stock_qty >= 0),
              track_expiry INTEGER NOT NULL DEFAULT 0
                CHECK(track_expiry IN (0, 1)),
              min_shelf_life_days INTEGER NOT NULL DEFAULT 0
                CHECK(min_shelf_life_days >= 0)
            )
          ''');
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
        },
      ),
    );

    await versionTwo.insert('products', <String, Object?>{
      'id': 'P-V2',
      'sku': 'SKU-V2',
      'barcode': '899000000002',
      'name_id': 'Produk V2',
      'price': 35000,
      'ppn_exempt': 0,
      'stock_qty': 4,
      'track_expiry': 1,
      'min_shelf_life_days': 7,
    });
    await versionTwo.insert('outbox_events', <String, Object?>{
      'id': 'outbox:product:P-V2',
      'entity_type': 'product',
      'entity_id': 'P-V2',
      'payload': '{"product":{"id":"P-V2"}}',
      'status': 'pending',
      'retry_count': 0,
      'created_at_utc': '2026-10-21T08:00:00.000Z',
    });
    await versionTwo.close();

    final migrated = await PosDatabase.openAt(
      path,
      factory: databaseFactoryFfi,
    );
    addTearDown(migrated.close);

    final version = await migrated.database.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], PosDatabase.schemaVersion);

    final product = (await migrated.database.query('products')).single;
    expect(product['id'], 'P-V2');
    expect(product['sku'], 'SKU-V2');
    expect(product['price'], 35000);
    expect(product['stock_qty'], 4);
    expect(product['track_expiry'], 1);
    expect(product['min_shelf_life_days'], 7);
    expect(product['requires_review'], 0);

    final event = (await migrated.database.query('outbox_events')).single;
    expect(event['id'], 'outbox:product:P-V2');
    expect(event['payload'], '{"product":{"id":"P-V2"}}');
    expect(event['status'], 'pending');
    expect(event['retry_count'], 0);
    expect(event['last_error'], isNull);
    expect(event['next_retry_at_utc'], isNull);
    expect(event['acked_at_utc'], isNull);
    expect(event['server_receipt_id'], isNull);

    expect(await migrated.database.query('legacy_import_runs'), isEmpty);
    expect(await migrated.database.query('legacy_sales_archive'), isEmpty);

    final indexes = (await migrated.database.rawQuery(
      "PRAGMA index_list('outbox_events')",
    ))
        .map((index) => index['name'] as String)
        .toSet();
    expect(indexes, contains('idx_outbox_status'));
    expect(indexes, contains('idx_outbox_retry'));
  });
  
  test('v1 migration rejects product stock that disagrees with cost layers',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkahtigaputeri-stock-mismatch-');
    addTearDown(() => directory.delete(recursive: true));

    final path = p.join(directory.path, 'legacy-mismatch.db');
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

    await legacy.insert('products', <String, Object?>{
      'id': 'P-MISMATCH',
      'sku': 'SKU-MISMATCH',
      'barcode': null,
      'name_id': 'Produk Tidak Konsisten',
      'price': 25000,
      'ppn_exempt': 0,
      // The summary says 3 units, but the only cost layer contains 2.
      'stock_qty': 3,
    });
    await legacy.insert('inventory_lots', <String, Object?>{
      'id': 'LOT-MISMATCH',
      'product_id': 'P-MISMATCH',
      'acquired_at_utc': DateTime.utc(2026, 9, 1).toIso8601String(),
      'remaining_qty': 2,
      'unit_cost': 10000,
    });
    await legacy.close();

    await expectLater(
      PosDatabase.openAt(path, factory: databaseFactoryFfi),
      throwsA(isA<StateError>()),
    );

    // The rejected upgrade must leave the original v1 schema and rows intact
    // so an owner can reconcile the source before retrying.
    final original = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        readOnly: true,
        singleInstance: false,
      ),
    );
    addTearDown(original.close);

    final version = await original.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 1);

    final product = (await original.query('products')).single;
    expect(product['id'], 'P-MISMATCH');
    expect(product['stock_qty'], 3);

    final layer = (await original.query('inventory_lots')).single;
    expect(layer['id'], 'LOT-MISMATCH');
    expect(layer['remaining_qty'], 2);

    final columns = (await original.rawQuery(
      "PRAGMA table_info('inventory_lots')",
    )).map((column) => column['name'] as String).toSet();
    expect(columns, contains('remaining_qty'));
    expect(columns, isNot(contains('on_hand_qty')));

    final migratedCostLayers = await original.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('inventory_cost_layers', 'inventory_cost_layers_v1')",
    );
    expect(migratedCostLayers, isEmpty);
  });

  
  test('v1 migration rejects inventory layers that reference missing products', () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkahtigaputeri-orphan-layer-');
    addTearDown(() => directory.delete(recursive: true));

    final path = p.join(directory.path, 'legacy-orphan.db');
    // Deliberately create the historical v1 fixture without enabling FK
    // enforcement so it represents an existing database with a dangling row.
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
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
    await legacy.insert('inventory_lots', <String, Object?>{
      'id': 'LOT-ORPHAN',
      'product_id': 'P-MISSING',
      'acquired_at_utc': DateTime.utc(2026, 9, 1).toIso8601String(),
      'remaining_qty': 2,
      'unit_cost': 10000,
    });
    await legacy.close();

    await expectLater(
      PosDatabase.openAt(path, factory: databaseFactoryFfi),
      throwsA(isA<StateError>()),
    );

    // Failed upgrade must preserve the original v1 tables and dangling row so
    // the source can be repaired explicitly rather than partially converted.
    final original = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        readOnly: true,
        singleInstance: false,
      ),
    );
    addTearDown(original.close);

    final version = await original.rawQuery('PRAGMA user_version');
    expect(version.single['user_version'], 1);
    expect(await original.query('products'), isEmpty);

    final layer = (await original.query('inventory_lots')).single;
    expect(layer['id'], 'LOT-ORPHAN');
    expect(layer['product_id'], 'P-MISSING');
    expect(layer['remaining_qty'], 2);

    final columns = (await original.rawQuery(
      "PRAGMA table_info('inventory_lots')",
    )).map((column) => column['name'] as String).toSet();
    expect(columns, contains('remaining_qty'));
    expect(columns, isNot(contains('on_hand_qty')));
    final newLedger = await original.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name IN ('inventory_cost_layers', 'inventory_movements')",
    );
    expect(newLedger, isEmpty);
  });

}
