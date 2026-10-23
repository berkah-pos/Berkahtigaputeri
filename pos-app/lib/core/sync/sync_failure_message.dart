import '../auth/laravel_auth_service.dart';

/// Maps sync exceptions to approved user-facing guidance.
/// Raw server response text and transport diagnostics are never interpolated.
String safeSyncFailureMessage(Object error) {
  if (error is AuthFailure) {
    if (error.code == 'api_not_configured') {
      return 'Sinkronisasi cloud belum dikonfigurasi pada build ini. '
          'Penjualan tetap tersimpan lokal.';
    }
    if (error.statusCode == 401) {
      return 'Sesi cloud tidak tersedia atau sudah berakhir. Masuk kembali '
          'setelah sesi perangkat siap. Data tetap tersimpan lokal.';
    }
    if (error.statusCode == 403) {
      return 'Perangkat atau akses tenant belum diizinkan untuk sinkronisasi. '
          'Hubungi administrator. Data tetap tersimpan lokal.';
    }
  }

  return 'Sinkronisasi belum berhasil. Data tetap tersimpan lokal. '
      'Periksa koneksi lalu coba lagi; jika masalah berulang, hubungi dukungan.';
}
