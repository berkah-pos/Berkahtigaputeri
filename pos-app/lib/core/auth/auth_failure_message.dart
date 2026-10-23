import 'laravel_auth_service.dart';

/// Maps authentication failures to stable UI guidance.
/// Never reflect a remote error message or internal server error code.
String safeAuthFailureMessage(Object error) {
  if (error is AuthFailure) {
    switch (error.code) {
      case 'tenant_selection_required':
        return 'Pilih tenant aktif untuk melanjutkan.';
      case 'invalid_credentials':
        return 'Email atau kata sandi tidak valid. Periksa data masuk lalu coba lagi.';
      case 'account_has_no_active_membership':
      case 'tenant_membership_denied':
        return 'Akun ini tidak memiliki akses ke tenant aktif yang dipilih. '
            'Hubungi administrator.';
      case 'device_identity_conflict':
      case 'device_proof_invalid':
        return 'Identitas atau bukti perangkat tidak cocok. Hubungi administrator.';
      case 'device_revoked':
      case 'device_not_usable':
        return 'Perangkat ini tidak diizinkan untuk akses cloud. '
            'Hubungi administrator.';
      case 'device_approval_requires_signin':
        return 'Perangkat sudah disetujui. Masuk kembali untuk mengaktifkan sesi cloud.';
      case 'api_not_configured':
        return 'Login cloud belum tersedia pada build ini. Gunakan mode lokal '
            'sampai API dikonfigurasi.';
      case 'network_timeout':
        return 'Permintaan login terlalu lama. Periksa koneksi lalu coba lagi.';
      case 'network_error':
        return 'Tidak dapat menghubungi layanan cloud. Periksa koneksi lalu coba lagi.';
      case 'local_session_cleanup_failed':
        return 'Sesi perangkat belum dapat dibersihkan. Akses cloud tetap dikunci; '
            'coba bersihkan sesi lagi.';
    }

    if (error.statusCode == 429 || error.code == 'http_429') {
      return 'Terlalu banyak percobaan login. Tunggu sebentar lalu coba lagi.';
    }
    if (error.statusCode == 401) {
      return 'Email atau kata sandi tidak valid, atau sesi sudah berakhir.';
    }
    if (error.statusCode == 403) {
      return 'Akun atau perangkat belum diizinkan untuk akses cloud. '
          'Hubungi administrator.';
    }
    if (error.statusCode == 409) {
      return 'Status akun atau perangkat berubah. Periksa kembali atau hubungi administrator.';
    }
    if (error.statusCode == 422) {
      return 'Data login atau perangkat belum valid. Periksa isian lalu coba lagi.';
    }
  }

  return 'Login belum berhasil. Periksa koneksi dan data masuk, lalu coba kembali.';
}
