import 'package:berkahtigaputeri_pos/features/products/product_failure_message.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeProductFailureMessage', () {
    test('never reflects technical exception details for any operation', () {
      final error = StateError(
        'no such table: products path=/data/user/0/app.db '
        'authorization=Bearer-super-secret stack=internal-frame',
      );

      for (final operation in ProductFailureOperation.values) {
        final message = safeProductFailureMessage(
          error,
          operation: operation,
        );

        expect(message, isNot(contains('no such table')));
        expect(message, isNot(contains('/data/user/0/app.db')));
        expect(message, isNot(contains('Bearer-super-secret')));
        expect(message, isNot(contains('internal-frame')));
        expect(message, isNot(contains('authorization=')));
      }
    });

    test('provides distinct recovery guidance for each failure area', () {
      final messages = ProductFailureOperation.values
          .map(
            (operation) => safeProductFailureMessage(
              StateError('internal failure'),
              operation: operation,
            ),
          )
          .toSet();

      expect(messages, hasLength(ProductFailureOperation.values.length));
      expect(
        safeProductFailureMessage(
          StateError('internal failure'),
          operation: ProductFailureOperation.load,
        ),
        contains('Periksa penyimpanan perangkat'),
      );
      expect(
        safeProductFailureMessage(
          StateError('internal failure'),
          operation: ProductFailureOperation.verifyHistory,
        ),
        contains('Riwayat persediaan produk tidak dapat diverifikasi'),
      );
      expect(
        safeProductFailureMessage(
          StateError('internal failure'),
          operation: ProductFailureOperation.save,
        ),
        contains('Produk gagal disimpan'),
      );
      expect(
        safeProductFailureMessage(
          StateError('internal failure'),
          operation: ProductFailureOperation.delete,
        ),
        contains('Produk tidak dapat dihapus'),
      );
    });

    test('preserves locally authored product validation guidance', () {
      const error = ProductValidationException('SKU wajib diisi.');

      expect(
        safeProductFailureMessage(
          error,
          operation: ProductFailureOperation.save,
        ),
        'SKU wajib diisi.',
      );
    });
  });
}
