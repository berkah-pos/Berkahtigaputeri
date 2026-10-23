import '../auth/laravel_auth_service.dart';

/// Maps configuration failures to stable user-facing guidance.
/// Never reflect server-provided response text or internal error codes.
String safeConfigFailureMessage(Object error) {
  if (error is AuthFailure) {
    if (error.code == 'api_not_configured') {
      return 'Konfigurasi cloud belum tersedia pada build ini. '
          'Data lokal tetap tersedia.';
    }
    if (error.statusCode == 401) {
      return 'Sesi cloud tidak tersedia atau sudah berakhir. Masuk kembali '
          'untuk memuat konfigurasi.';
    }
    if (error.statusCode == 403 || error.code == 'identity_mismatch') {
      return 'Perangkat atau akses tenant belum diizinkan untuk konfigurasi. '
          'Hubungi administrator. Data lokal tetap tersedia.';
    }
    if (error.code == 'invalid_config_response' ||
        error.statusCode == 502) {
      return 'Konfigurasi dari server tidak dapat diverifikasi saat ini. '
          'Coba lagi atau hubungi administrator.';
    }
    if (error.code == 'invalid_service' || error.statusCode == 422) {
      return 'Layanan konfigurasi yang diminta tidak valid.';
    }
  }

  return 'Konfigurasi cloud belum dapat dimuat. Coba lagi nanti. '
      'Pengaturan lokal tetap tersedia.';
}
