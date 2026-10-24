import 'dart:io';

import 'package:sqflite/sqflite.dart';

/// Imports the previous trial application's database into archive/catalog
/// tables without treating incomplete legacy financial data as full journals.
class LegacyTrialImporter {
  const LegacyTrialImporter._();

  static const String migrationKey = 'berkah-pos-trial-v1-import';

  static Future<Map<String, int>?> importIfPresent({
    required Database target,
    required String legacyPath,
    DatabaseFactory? factory,
  }) async {
    final file = File(legacyPath);
    if (!await file.exists()) return null;

    final runs = await target.query(
      'legacy_import_runs',
      where: 'migration_key = ?',
      whereArgs: <Object?>[migrationKey],
      limit: 1,
    );
    if (runs.isNotEmpty) {
      return <String, int>{
        'products': runs.single['imported_products']! as int,
        'sales': runs.single['archived_sales']! as int,
        'saleItems': runs.single['archived_sale_items']! as int,
        'alreadyImported': 1,
      };
    }

    final selectedFactory = factory ?? databaseFactory;
    final legacy = await selectedFactory.openDatabase(
      legacyPath,
      options: OpenDatabaseOptions(
        // The source is archival input only: it must never be migrated or
        // changed as a side effect of opening it for import.
        readOnly: true,
        singleInstance: false,
      ),
    );

    try {
      final tableRows = await legacy.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final tableNames = tableRows
          .map((row) => row['name']?.toString() ?? '')
          .toSet();
      if (!tableNames.contains('products')) {
        throw const FormatException(
          'The old berkah_pos.db file has no products table and does not '
          'match the expected trial schema; it was left unchanged for manual '
          'recovery.',
        );
      }
      if (!tableNames.contains('sales') ||
          !tableNames.contains('sale_items')) {
        throw const FormatException(
          'The old berkah_pos.db file does not match the expected trial '
          'schema; it was left unchanged for manual recovery.',
        );
      }

      final oldProducts = await legacy.query('products', orderBy: 'id');
      final oldSales = await legacy.query('sales', orderBy: 'id');
      final oldSaleItems = await legacy.query('sale_items', orderBy: 'id');
      final importedAt = DateTime.now().toUtc().toIso8601String();

      final counts = <String, int>{
        'products': 0,
        'sales': 0,
        'saleItems': 0,
      };

      await target.transaction<void>((transaction) async {
        final existingRun = await transaction.query(
          'legacy_import_runs',
          where: 'migration_key = ?',
          whereArgs: <Object?>[migrationKey],
          limit: 1,
        );
        if (existingRun.isNotEmpty) return;

        final skuRows = await transaction.query(
          'products',
          columns: <String>['sku'],
        );
        final usedSkus = skuRows
            .map((row) => row['sku']?.toString() ?? '')
            .where((sku) => sku.isNotEmpty)
            .toSet();
        final mappedProductIds = <int, String>{};

        for (final old in oldProducts) {
          final originalId = _requiredInteger(old['id'], 'product.id');
          final productId = 'legacy-product-$originalId';
          mappedProductIds[originalId] = productId;

          final exists = await transaction.query(
            'products',
            where: 'id = ?',
            whereArgs: <Object?>[productId],
            limit: 1,
          );
          if (exists.isEmpty) {
            final originalSku = old['sku']?.toString().trim() ?? '';
            final baseSku = originalSku.isEmpty
                ? 'LEGACY-$originalId'
                : originalSku;
            var sku = baseSku;
            var suffix = 1;
            while (usedSkus.contains(sku)) {
              sku = '$baseSku-LEGACY-$originalId-$suffix';
              suffix++;
            }
            usedSkus.add(sku);

            final originalName = old['name']?.toString().trim() ?? '';
            await transaction.insert(
              'products',
              <String, Object?>{
                'id': productId,
                'sku': sku,
                'barcode': null,
                'name_id': originalName.isEmpty
                    ? 'Produk trial $originalId'
                    : originalName,
                'price': _nonNegativeInteger(old['price'], 'product.price'),
                // Legacy records did not carry tax classification. Keep the
                // product blocked until the owner explicitly reviews it.
                'ppn_exempt': 0,
                'stock_qty': 0,
                'track_expiry': 0,
                'min_shelf_life_days': 0,
                'requires_review': 1,
              },
            );
            counts['products'] = counts['products']! + 1;
          }

          final stockRows = await transaction.query(
            'legacy_product_stock_archive',
            where: 'original_product_id = ?',
            whereArgs: <Object?>[originalId],
            limit: 1,
          );
          if (stockRows.isEmpty) {
            final originalQuantity =
                _nonNegativeInteger(old['stock'], 'product.stock');
            await transaction.insert(
              'legacy_product_stock_archive',
              <String, Object?>{
                'product_id': productId,
                'original_product_id': originalId,
                'original_quantity': originalQuantity,
                'status': originalQuantity > 0
                    ? 'needs_review'
                    : 'no_opening_stock',
                'imported_at_utc': importedAt,
                'reviewed_at_utc': null,
              },
            );
          }
        }

        final archivedSaleIds = <int>{};
        for (final old in oldSales) {
          final saleId = _requiredInteger(old['id'], 'sale.id');
          final created = old['created']?.toString().trim() ?? '';
          await transaction.insert(
            'legacy_sales_archive',
            <String, Object?>{
              'id': 'legacy-sale-$saleId',
              'original_sale_id': saleId,
              'total_amount': _nonNegativeInteger(old['total'], 'sale.total'),
              'item_count': _nonNegativeInteger(old['item_count'], 'sale.item_count'),
              'email': old['email']?.toString() ?? '',
              'created_at': created.isEmpty ? importedAt : created,
            },
          );
          archivedSaleIds.add(saleId);
          counts['sales'] = counts['sales']! + 1;
        }

        for (final old in oldSaleItems) {
          final itemId = _requiredInteger(old['id'], 'sale_item.id');
          final saleId = _requiredInteger(old['sale_id'], 'sale_item.sale_id');
          if (!archivedSaleIds.contains(saleId)) {
            throw const FormatException(
              'Legacy import stopped: a sale item has no matching legacy sale. '
              'The source file was not changed and the import was rolled back.',
            );
          }

          final oldProductId =
              _requiredInteger(old['product_id'], 'sale_item.product_id');
          final productId = mappedProductIds[oldProductId];
          await transaction.insert(
            'legacy_sale_items_archive',
            <String, Object?>{
              'id': 'legacy-sale-item-$itemId',
              'original_item_id': itemId,
              'original_sale_id': saleId,
              'product_id': productId,
              'product_name': old['name']?.toString() ?? '',
              'quantity': _positiveInteger(old['qty'], 'sale_item.quantity'),
              'unit_price': _nonNegativeInteger(old['price'], 'sale_item.price'),
              'subtotal': _nonNegativeInteger(old['subtotal'], 'sale_item.subtotal'),
            },
          );
          counts['saleItems'] = counts['saleItems']! + 1;
        }

        await transaction.insert(
          'legacy_import_runs',
          <String, Object?>{
            'migration_key': migrationKey,
            'source_file': file.path,
            'completed_at_utc': importedAt,
            'imported_products': counts['products'],
            'archived_sales': counts['sales'],
            'archived_sale_items': counts['saleItems'],
          },
        );
      });

      return counts;
    } finally {
      await legacy.close();
    }
  }

  /// Converts only exact whole-number values. The source trial schema uses
  /// REAL for several currency/quantity fields, so rounding here would silently
  /// corrupt legacy history. Any invalid required value aborts the surrounding
  /// target transaction; the legacy source remains untouched.
  static int _requiredInteger(Object? value, String field) {
    if (value is int) return value;
    if (value is num) {
      if (value.isFinite && value == value.truncateToDouble()) {
        return value.toInt();
      }
    } else if (value is String) {
      final text = value.trim();
      final integer = int.tryParse(text);
      if (integer != null) return integer;
      final numeric = double.tryParse(text);
      if (numeric != null &&
          numeric.isFinite &&
          numeric == numeric.truncateToDouble()) {
        return numeric.toInt();
      }
    }

    throw FormatException(
      'Legacy import stopped: $field must be a finite whole number. '
      'The source file was not changed and the import was rolled back.',
    );
  }

  static int _nonNegativeInteger(Object? value, String field) {
    final parsed = _requiredInteger(value, field);
    if (parsed < 0) {
      throw FormatException(
        'Legacy import stopped: $field must not be negative. '
        'The source file was not changed and the import was rolled back.',
      );
    }
    return parsed;
  }

  static int _positiveInteger(Object? value, String field) {
    final parsed = _requiredInteger(value, field);
    if (parsed <= 0) {
      throw FormatException(
        'Legacy import stopped: $field must be greater than zero. '
        'The source file was not changed and the import was rolled back.',
      );
    }
    return parsed;
  }
}
