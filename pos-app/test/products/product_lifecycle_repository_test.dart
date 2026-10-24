import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  test('ordinary edits preserve inactive status and stale edits are rejected', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final repository = SqliteProductRepository(database);
    const initial = Product(
      id: 'P-STATUS',
      sku: 'SKU-STATUS',
      barcode: null,
      nameId: 'Produk Status',
      price: 8000,
      ppnExempt: false,
      stockQty: 0,
    );
    await repository.upsert(initial);

    final stale = (await repository.findById('P-STATUS'))!;
    await repository.setActiveStatus(
      stale,
      isActive: false,
      reason: 'Alasan penonaktifan',
    );
    final inactive = (await repository.findById('P-STATUS'))!;
    expect(inactive.isActive, isFalse);
    expect(inactive.version, 2);

    await repository.upsert(inactive.copyWith(nameId: 'Nama diperbarui'));
    final updated = (await repository.findById('P-STATUS'))!;
    expect(updated.isActive, isFalse);
    expect(updated.version, 3);

    await expectLater(
      repository.upsert(stale.copyWith(nameId: 'Edit usang')),
      throwsA(isA<ProductConcurrencyException>()),
    );
    expect((await repository.findById('P-STATUS'))!.nameId, 'Nama diperbarui');
    expect((await repository.listAll()).single.isActive, isFalse);
    expect((await repository.listAll()).single.syncStatus, isNotNull);
  });
}
