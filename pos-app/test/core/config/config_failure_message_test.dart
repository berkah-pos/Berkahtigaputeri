import 'package:flutter_test/flutter_test.dart';
import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/core/config/config_failure_message.dart';

void main() {
  group('safeConfigFailureMessage', () {
    test('does not reflect internal details from an unknown API error', () {
      const failure = AuthFailure(
        message: 'database=pg-private token=super-secret customer=jane@example.test',
        code: 'internal_exception:database',
        statusCode: 500,
      );

      final message = safeConfigFailureMessage(failure);

      expect(message, contains('Konfigurasi cloud belum dapat dimuat'));
      expect(message, isNot(contains('pg-private')));
      expect(message, isNot(contains('super-secret')));
      expect(message, isNot(contains('jane@example.test')));
      expect(message, isNot(contains('internal_exception')));
    });

    test('maps expired or missing session without exposing remote text', () {
      const failure = AuthFailure(
        message: 'raw bearer token secret',
        code: 'session_missing',
        statusCode: 401,
      );

      final message = safeConfigFailureMessage(failure);

      expect(message, contains('Masuk kembali'));
      expect(message, isNot(contains('raw bearer token')));
      expect(message, isNot(contains('secret')));
    });

    test('maps forbidden device access to stable administrator guidance', () {
      const failure = AuthFailure(
        message: 'private host pg-private and token=secret',
        code: 'device_not_approved',
        statusCode: 403,
      );

      final message = safeConfigFailureMessage(failure);

      expect(message, contains('Hubungi administrator'));
      expect(message, isNot(contains('pg-private')));
      expect(message, isNot(contains('token=secret')));
    });

    test('maps malformed server configuration response safely', () {
      const failure = AuthFailure(
        message: 'response contained an internal trace',
        code: 'invalid_config_response',
        statusCode: 502,
      );

      final message = safeConfigFailureMessage(failure);

      expect(message, contains('tidak dapat diverifikasi'));
      expect(message, isNot(contains('internal trace')));
    });

    test('maps a missing API setting without showing implementation details', () {
      const failure = AuthFailure(
        message: 'private deployment setting',
        code: 'api_not_configured',
      );

      final message = safeConfigFailureMessage(failure);

      expect(message, contains('Data lokal tetap tersedia'));
      expect(message, isNot(contains('private deployment setting')));
    });
  });
}
