import 'dart:io';

import 'package:berkahtigaputeri_pos/core/database/legacy_trial_importer.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('imports old trial products safely and archives incomplete sales once',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkah-trial-import-');
    addTearDown(() => directory.delete(recursive: true));

    final legacyPath = p.join(directory.path, 'berkah_pos.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sku TEXT NOT NULL,
              price REAL NOT NULL,
              stock INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              item_count INTEGER NOT NULL,
              email TEXT NOT NULL,
              created TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty INTEGER NOT NULL,
              price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
        },
      ),
    );

    final productId = await oldDb.insert('products', <String, Object?>{
      'name': 'Kopi Lama',
      'sku': 'KOPI-01',
      'price': 25000.0,
      'stock': 5,
    });
    final saleId = await oldDb.insert('sales', <String, Object?>{
      'total': 50000.0,
      'item_count': 2,
      'email': 'cashier@example.test',
      'created': '2026-10-01T08:30:00.000Z',
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId,
      'product_id': productId,
      'name': 'Kopi Lama',
      'qty': 2,
      'price': 25000.0,
      'subtotal': 50000.0,
    });
    await oldDb.close();
    final sourceBytesBeforeImport = await File(legacyPath).readAsBytes();

    final target = await PosDatabase.openAt(
      p.join(directory.path, 'berkahtigaputeri_pos.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(target.close);

    // Two callers can pass the initial marker check before either import
    // transaction starts. The transaction-level recheck must return the
    // already-completed counts rather than reporting a false zero import.
    final results = await Future.wait<Map<String, int>?>([
      LegacyTrialImporter.importIfPresent(
        target: target.database,
        legacyPath: legacyPath,
        factory: databaseFactoryFfi,
      ),
      LegacyTrialImporter.importIfPresent(
        target: target.database,
        legacyPath: legacyPath,
        factory: databaseFactoryFfi,
      ),
    ]);

    expect(results, hasLength(2));
    expect(
      results.every(
        (result) =>
            result?['products'] == 1 &&
            result?['sales'] == 1 &&
            result?['saleItems'] == 1,
      ),
      isTrue,
    );
    expect(
      results.where((result) => result?['alreadyImported'] == 1),
      hasLength(1),
    );

    final product = (await target.database.query('products')).single;
    expect(product['id'], 'legacy-product-1');
    expect(product['sku'], 'KOPI-01');
    expect(product['price'], 25000);
    expect(product['stock_qty'], 0);
    expect(product['requires_review'], 1);

    final archivedStock =
        (await target.database.query('legacy_product_stock_archive')).single;
    expect(archivedStock['original_quantity'], 5);
    expect(archivedStock['status'], 'needs_review');

    final archivedSale =
        (await target.database.query('legacy_sales_archive')).single;
    expect(archivedSale['total_amount'], 50000);
    expect(archivedSale['item_count'], 2);
    expect(archivedSale['email'], 'cashier@example.test');

    final archivedItem =
        (await target.database.query('legacy_sale_items_archive')).single;
    expect(archivedItem['product_id'], 'legacy-product-1');
    expect(archivedItem['quantity'], 2);
    expect(archivedItem['subtotal'], 50000);

    // Legacy financial rows must not masquerade as complete new sales/journals.
    expect(await target.database.query('sales'), isEmpty);
    expect(await target.database.query('journals'), isEmpty);

    // Opening the source read-only must preserve the database byte-for-byte.
    expect(await File(legacyPath).exists(), isTrue);
    expect(
      await File(legacyPath).readAsBytes(),
      orderedEquals(sourceBytesBeforeImport),
    );
    final rerun = await LegacyTrialImporter.importIfPresent(
      target: target.database,
      legacyPath: legacyPath,
      factory: databaseFactoryFfi,
    );
    expect(rerun?['alreadyImported'], 1);
    expect(await target.database.query('legacy_sales_archive'), hasLength(1));
    expect(await target.database.query('products'), hasLength(1));
  });

  test('rejects fractional legacy amounts without rounding or partial import',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkah-trial-fractional-');
    addTearDown(() => directory.delete(recursive: true));

    final legacyPath = p.join(directory.path, 'berkah_pos.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sku TEXT NOT NULL,
              price REAL NOT NULL,
              stock INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              item_count INTEGER NOT NULL,
              email TEXT NOT NULL,
              created TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty INTEGER NOT NULL,
              price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
        },
      ),
    );
    final productId = await oldDb.insert('products', <String, Object?>{
      'name': 'Produk Trial',
      'sku': 'TRIAL-01',
      'price': 25000.0,
      'stock': 5,
    });
    final saleId = await oldDb.insert('sales', <String, Object?>{
      'total': 50000.5,
      'item_count': 2,
      'email': 'cashier@example.test',
      'created': '2026-10-01T08:30:00.000Z',
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId,
      'product_id': productId,
      'name': 'Produk Trial',
      'qty': 2,
      'price': 25000.0,
      'subtotal': 50000.0,
    });
    await oldDb.close();

    final target = await PosDatabase.openAt(
      p.join(directory.path, 'berkahtigaputeri_pos.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(target.close);

    await expectLater(
      LegacyTrialImporter.importIfPresent(
        target: target.database,
        legacyPath: legacyPath,
        factory: databaseFactoryFfi,
      ),
      throwsA(isA<FormatException>()),
    );

    // Validation runs inside one target transaction; no product, archive row,
    // or completion marker is left behind after a malformed amount.
    expect(await target.database.query('products'), isEmpty);
    expect(await target.database.query('legacy_product_stock_archive'), isEmpty);
    expect(await target.database.query('legacy_sales_archive'), isEmpty);
    expect(await target.database.query('legacy_sale_items_archive'), isEmpty);
    expect(await target.database.query('legacy_import_runs'), isEmpty);

    // The old database remains available with the exact original amount.
    expect(await File(legacyPath).exists(), isTrue);
    final source = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false),
    );
    expect((await source.query('sales')).single['total'], 50000.5);
    await source.close();
  });


  test('rejects orphaned legacy sale items without marking import complete',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkah-trial-orphan-item-');
    addTearDown(() => directory.delete(recursive: true));

    final legacyPath = p.join(directory.path, 'berkah_pos.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sku TEXT NOT NULL,
              price REAL NOT NULL,
              stock INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              item_count INTEGER NOT NULL,
              email TEXT NOT NULL,
              created TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty INTEGER NOT NULL,
              price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
        },
      ),
    );

    final productId = await oldDb.insert('products', <String, Object?>{
      'name': 'Produk Warisan',
      'sku': 'WARISAN-01',
      'price': 25000.0,
      'stock': 5,
    });
    final saleId = await oldDb.insert('sales', <String, Object?>{
      'total': 50000.0,
      'item_count': 2,
      'email': 'cashier@example.test',
      'created': '2026-10-01T08:30:00.000Z',
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId,
      'product_id': productId,
      'name': 'Produk Warisan',
      'qty': 1,
      'price': 25000.0,
      'subtotal': 25000.0,
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId + 1000,
      'product_id': productId,
      'name': 'Item tanpa transaksi',
      'qty': 1,
      'price': 25000.0,
      'subtotal': 25000.0,
    });
    await oldDb.close();
    final sourceBytesBeforeImport = await File(legacyPath).readAsBytes();

    final target = await PosDatabase.openAt(
      p.join(directory.path, 'berkahtigaputeri_pos.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(target.close);

    await expectLater(
      LegacyTrialImporter.importIfPresent(
        target: target.database,
        legacyPath: legacyPath,
        factory: databaseFactoryFfi,
      ),
      throwsA(isA<FormatException>()),
    );

    // The good rows are also rolled back: no partial catalog/archive state or
    // completion marker can hide the source inconsistency from a future retry.
    expect(await target.database.query('products'), isEmpty);
    expect(await target.database.query('legacy_product_stock_archive'), isEmpty);
    expect(await target.database.query('legacy_sales_archive'), isEmpty);
    expect(await target.database.query('legacy_sale_items_archive'), isEmpty);
    expect(await target.database.query('legacy_import_runs'), isEmpty);

    expect(await File(legacyPath).readAsBytes(), orderedEquals(sourceBytesBeforeImport));
    final source = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(version: 1, singleInstance: false, readOnly: true),
    );
    expect(await source.query('sale_items'), hasLength(2));
    await source.close();
  });

  
  test('legacy product ID collision does not reuse an unrelated target product',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkah-trial-id-collision-');
    addTearDown(() => directory.delete(recursive: true));

    final legacyPath = p.join(directory.path, 'berkah_pos.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sku TEXT NOT NULL,
              price REAL NOT NULL,
              stock INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              item_count INTEGER NOT NULL,
              email TEXT NOT NULL,
              created TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty INTEGER NOT NULL,
              price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
        },
      ),
    );
    final sourceProductId = await oldDb.insert('products', <String, Object?>{
      'name': 'Produk Sumber',
      'sku': 'SRC-01',
      'price': 12000.0,
      'stock': 3,
    });
    final saleId = await oldDb.insert('sales', <String, Object?>{
      'total': 12000.0,
      'item_count': 1,
      'email': 'cashier@example.test',
      'created': '2026-10-01T08:30:00.000Z',
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId,
      'product_id': sourceProductId,
      'name': 'Produk Sumber',
      'qty': 1,
      'price': 12000.0,
      'subtotal': 12000.0,
    });
    await oldDb.close();
    final sourceBytesBeforeImport = await File(legacyPath).readAsBytes();

    final target = await PosDatabase.openAt(
      p.join(directory.path, 'berkahtigaputeri_pos.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(target.close);

    await target.database.insert('products', <String, Object?>{
      'id': 'legacy-product-$sourceProductId',
      'sku': 'TARGET-COLLISION',
      'barcode': null,
      'name_id': 'Produk Target Tidak Terkait',
      'price': 99000,
      'ppn_exempt': 1,
      'stock_qty': 0,
      'track_expiry': 0,
      'min_shelf_life_days': 0,
      'requires_review': 0,
    });

    final result = await LegacyTrialImporter.importIfPresent(
      target: target.database,
      legacyPath: legacyPath,
      factory: databaseFactoryFfi,
    );
    expect(result, <String, int>{
      'products': 1,
      'sales': 1,
      'saleItems': 1,
    });

    final products = await target.database.query('products', orderBy: 'id');
    expect(products, hasLength(2));
    final existingProduct = products.singleWhere(
      (row) => row['sku'] == 'TARGET-COLLISION',
    );
    expect(existingProduct['id'], 'legacy-product-$sourceProductId');
    expect(existingProduct['name_id'], 'Produk Target Tidak Terkait');
    expect(existingProduct['price'], 99000);
    expect(existingProduct['requires_review'], 0);

    final importedProduct = products.singleWhere(
      (row) => row['sku'] == 'SRC-01',
    );
    expect(
      importedProduct['id'],
      'legacy-product-$sourceProductId-legacy-1',
    );
    expect(importedProduct['name_id'], 'Produk Sumber');
    expect(importedProduct['price'], 12000);
    expect(importedProduct['stock_qty'], 0);
    expect(importedProduct['requires_review'], 1);

    final archivedStock =
        (await target.database.query('legacy_product_stock_archive')).single;
    expect(archivedStock['product_id'], importedProduct['id']);
    expect(archivedStock['original_product_id'], sourceProductId);
    expect(archivedStock['original_quantity'], 3);

    final archivedItem =
        (await target.database.query('legacy_sale_items_archive')).single;
    expect(archivedItem['product_id'], importedProduct['id']);
    expect(archivedItem['product_name'], 'Produk Sumber');
    expect(await target.database.query('sales'), isEmpty);
    expect(await target.database.query('journals'), isEmpty);
    expect(await target.database.query('legacy_import_runs'), hasLength(1));
    expect(
      await File(legacyPath).readAsBytes(),
      orderedEquals(sourceBytesBeforeImport),
    );
  });



  test('rejects conflicting legacy stock archive without completing import',
      () async {
    sqfliteFfiInit();
    final directory =
        await Directory.systemTemp.createTemp('berkah-trial-stock-collision-');
    addTearDown(() => directory.delete(recursive: true));

    final legacyPath = p.join(directory.path, 'berkah_pos.db');
    final oldDb = await databaseFactoryFfi.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              sku TEXT NOT NULL,
              price REAL NOT NULL,
              stock INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sales (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              item_count INTEGER NOT NULL,
              email TEXT NOT NULL,
              created TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sale_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              sale_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty INTEGER NOT NULL,
              price REAL NOT NULL,
              subtotal REAL NOT NULL
            )
          ''');
        },
      ),
    );
    final sourceProductId = await oldDb.insert('products', <String, Object?>{
      'name': 'Produk Sumber',
      'sku': 'SRC-STOCK-01',
      'price': 12000.0,
      'stock': 3,
    });
    final saleId = await oldDb.insert('sales', <String, Object?>{
      'total': 12000.0,
      'item_count': 1,
      'email': 'cashier@example.test',
      'created': '2026-10-01T08:30:00.000Z',
    });
    await oldDb.insert('sale_items', <String, Object?>{
      'sale_id': saleId,
      'product_id': sourceProductId,
      'name': 'Produk Sumber',
      'qty': 1,
      'price': 12000.0,
      'subtotal': 12000.0,
    });
    await oldDb.close();
    final sourceBytesBeforeImport = await File(legacyPath).readAsBytes();

    final target = await PosDatabase.openAt(
      p.join(directory.path, 'berkahtigaputeri_pos.db'),
      factory: databaseFactoryFfi,
    );
    addTearDown(target.close);

    await target.database.insert('products', <String, Object?>{
      'id': 'unrelated-product',
      'sku': 'TARGET-STOCK-ARCHIVE',
      'barcode': null,
      'name_id': 'Arsip Stok yang Sudah Ada',
      'price': 99000,
      'ppn_exempt': 1,
      'stock_qty': 0,
      'track_expiry': 0,
      'min_shelf_life_days': 0,
      'requires_review': 0,
    });
    await target.database.insert('legacy_product_stock_archive',
        <String, Object?>{
      'product_id': 'unrelated-product',
      'original_product_id': sourceProductId,
      'original_quantity': 41,
      'status': 'needs_review',
      'imported_at_utc': '2026-10-02T00:00:00.000Z',
      'reviewed_at_utc': null,
    });

    await expectLater(
      LegacyTrialImporter.importIfPresent(
        target: target.database,
        legacyPath: legacyPath,
        factory: databaseFactoryFfi,
      ),
      throwsA(isA<FormatException>()),
    );

    // A pre-existing stock archive with this source ID belongs to a different
    // target product. Do not call the import complete while losing source stock.
    final products = await target.database.query('products');
    expect(products, hasLength(1));
    expect(products.single['id'], 'unrelated-product');
    expect(products.single['name_id'], 'Arsip Stok yang Sudah Ada');
    final stockArchive =
        (await target.database.query('legacy_product_stock_archive')).single;
    expect(stockArchive['product_id'], 'unrelated-product');
    expect(stockArchive['original_quantity'], 41);
    expect(await target.database.query('legacy_sales_archive'), isEmpty);
    expect(await target.database.query('legacy_sale_items_archive'), isEmpty);
    expect(await target.database.query('legacy_import_runs'), isEmpty);
    expect(await target.database.query('sales'), isEmpty);
    expect(await target.database.query('journals'), isEmpty);
    expect(
      await File(legacyPath).readAsBytes(),
      orderedEquals(sourceBytesBeforeImport),
    );
  });

}
