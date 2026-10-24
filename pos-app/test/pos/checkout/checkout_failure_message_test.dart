import 'package:berkahtigaputeri_pos/features/pos/checkout_failure_message.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeCheckoutFailureMessage', () {
    test('does not reflect unexpected details for either operation', () {
      final error = StateError(
        'no such table: products path=/data/user/0/app.db '
        'authorization=Bearer-super-secret response=internal-db stack=frame-1',
      );

      for (final operation in CheckoutFailureOperation.values) {
        final message = safeCheckoutFailureMessage(
          error,
          operation: operation,
        );

        expect(message, isNot(contains('no such table')));
        expect(message, isNot(contains('/data/user/0/app.db')));
        expect(message, isNot(contains('Bearer-super-secret')));
        expect(message, isNot(contains('internal-db')));
        expect(message, isNot(contains('frame-1')));
        expect(message, isNot(contains('authorization=')));
      }
    });

    test('uses different recovery guidance for catalogue and checkout', () {
      final load = safeCheckoutFailureMessage(
        StateError('private load detail'),
        operation: CheckoutFailureOperation.loadProducts,
      );
      final checkout = safeCheckoutFailureMessage(
        StateError('private payment detail'),
        operation: CheckoutFailureOperation.processPayment,
      );

      expect(load, contains('Katalog produk tidak dapat dimuat'));
      expect(load, contains('Periksa penyimpanan perangkat'));
      expect(checkout, contains('Checkout belum dapat dikonfirmasi'));
      expect(checkout, contains('Periksa riwayat transaksi'));
      expect(load, isNot(checkout));
    });

    test('preserves locally authored payment validation guidance', () {
      const error = PaymentValidationException(
        'Jumlah produk harus lebih dari nol.',
      );

      expect(
        safeCheckoutFailureMessage(
          error,
          operation: CheckoutFailureOperation.processPayment,
        ),
        'Jumlah produk harus lebih dari nol.',
      );
    });
  });
}
