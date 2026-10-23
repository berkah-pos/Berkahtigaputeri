/// User-facing guidance for a failed legacy import.
///
/// The importer retains its raw failure internally for recovery diagnostics, but
/// cashier-facing UI must not reflect SQLite messages, file paths or stack text.
String safeLegacyImportFailureMessage(String? _) =>
    'Impor data lama belum selesai. Database sumber tetap dipertahankan. '
    'Periksa penyimpanan perangkat, lalu coba lagi.';
