import '../accounting/exceptions/accounting_exceptions.dart';
import '../inventory/services/fefo_engine.dart';
import '../inventory/services/fifo_cost_engine.dart';
import '../products/repositories/sqlite_product_repository.dart';
import 'cart/sale_calculator.dart';
import 'checkout/payment_service.dart';
import 'checkout/sqlite_sale_repository.dart';

/// Operation being reported by the cashier checkout screen.
enum CheckoutFailureOperation {
  loadProducts,
  processPayment,
}

/// Maps locally authored domain errors to their guidance and replaces
/// unexpected SQLite, filesystem, transport, and implementation exceptions
/// with stable copy. Unknown exception strings are never reflected.
String safeCheckoutFailureMessage(
  Object error, {
  required CheckoutFailureOperation operation,
}) {
  if (error is PaymentServiceException) return error.message;
  if (error is SaleRepositoryException) return error.message;
  if (error is ProductRepositoryException) return error.message;
  if (error is AccountingException) return error.message;
  if (error is FefoException) return error.message;
  if (error is FifoCostException) return error.message;
  if (error is SaleCalculationException) return error.message;

  switch (operation) {
    case CheckoutFailureOperation.loadProducts:
      return 'Katalog produk tidak dapat dimuat. Periksa penyimpanan perangkat, '
          'lalu coba lagi.';
    case CheckoutFailureOperation.processPayment:
      return 'Checkout belum dapat dikonfirmasi. Periksa riwayat transaksi '
          'sebelum mencoba kembali; hubungi dukungan jika statusnya tidak jelas.';
  }
}
