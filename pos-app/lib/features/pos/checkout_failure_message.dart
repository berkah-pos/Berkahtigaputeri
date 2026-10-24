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

/// Maps known local domain errors to their authored guidance and replaces
/// unexpected SQLite, filesystem, transport, and implementation exceptions
/// with stable copy. Exception strings from unknown types are never reflected.
String safeCheckoutFailureMessage(
  Object error, {
  required CheckoutFailureOperation operation,
}) {
  if (error is PaymentServiceException ||
      error is SaleRepositoryException ||
      error is ProductRepositoryException ||
      error is AccountingException ||
      error is FefoException ||
      error is FifoCostException ||
      error is SaleCalculationException) {
    return (error as dynamic).message as String;
  }

  switch (operation) {
    case CheckoutFailureOperation.loadProducts:
      return 'Katalog produk tidak dapat dimuat. Periksa penyimpanan perangkat, '
          'lalu coba lagi.';
    case CheckoutFailureOperation.processPayment:
      return 'Checkout belum dapat dikonfirmasi. Periksa riwayat transaksi '
          'sebelum mencoba kembali; hubungi dukungan jika statusnya tidak jelas.';
  }
}
