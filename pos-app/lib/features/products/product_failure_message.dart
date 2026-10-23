import 'repositories/sqlite_product_repository.dart';

/// Failure location used to select stable product-catalogue guidance.
enum ProductFailureOperation {
  load,
  verifyHistory,
  save,
  delete,
}

/// Returns safe UI copy without reflecting SQLite, filesystem, or exception text.
///
/// [ProductValidationException] contains fixed, locally-authored business
/// validation guidance; all other exception details stay out of the UI.
String safeProductFailureMessage(
  Object error, {
  required ProductFailureOperation operation,
}) {
  if (error is ProductValidationException) {
    return error.message;
  }

  switch (operation) {
    case ProductFailureOperation.load:
      return 'Produk tidak dapat dimuat. Periksa penyimpanan perangkat, '
          'lalu coba lagi.';
    case ProductFailureOperation.verifyHistory:
      return 'Riwayat persediaan produk tidak dapat diverifikasi. '
          'Coba lagi sebelum mengubah pengaturan kedaluwarsa.';
    case ProductFailureOperation.save:
      return 'Produk gagal disimpan. Periksa isian, lalu coba lagi. '
          'Jika masalah berulang, hubungi dukungan.';
    case ProductFailureOperation.delete:
      return 'Produk tidak dapat dihapus saat ini. Periksa riwayat transaksi '
          'dan persediaan, lalu coba lagi.';
  }
}
