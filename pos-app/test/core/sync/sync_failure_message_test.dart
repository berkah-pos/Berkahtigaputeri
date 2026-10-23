import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/core/sync/sync_failure_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('safeSyncFailureMessage', () {
    test('does not expose raw transport exception details', () {
      final message = safeSyncFailureMessage(
        StateError('authorization=Bearer-super-secret host=internal-db'),
      );

      expect(message, contains('Data tetap tersimpan lokal'));
      expect(message, isNot(contains('Bearer-super-secret')));
      expect(message, isNot(contains('internal-db')));
      expect(message, isNot(contains('authorization=')));
    });

    test('maps missing API configuration to safe guidance', () {
      final message = safeSyncFailureMessage(
        const AuthFailure(
          message: 'Raw config secret must never be shown',
          code: 'api_not_configured',
        ),
      );

      expect(message, contains('belum dikonfigurasi'));
      expect(message, contains('tersimpan lokal'));
      expect(message, isNot(contains('Raw config secret')));
    });

    test('maps authentication expiry without displaying server message', () {
      final message = safeSyncFailureMessage(
        const AuthFailure(
          message: 'Raw bearer token and server trace',
          code: 'session_missing',
          statusCode: 401,
        ),
      );

      expect(message, contains('Masuk kembali'));
      expect(message, isNot(contains('Raw bearer token')));
      expect(message, isNot(contains('server trace')));
    });

    test('maps denied device access without displaying response body', () {
      final message = safeSyncFailureMessage(
        const AuthFailure(
          message: 'DB hostname=pg-private; token=secret',
          code: 'device_not_approved',
          statusCode: 403,
        ),
      );

      expect(message, contains('Hubungi administrator'));
      expect(message, isNot(contains('pg-private')));
      expect(message, isNot(contains('token=secret')));
    });

    test('uses generic safe guidance for unknown errors', () {
      final message = safeSyncFailureMessage(
        Exception('stack trace with customer email jane@example.test'),
      );

      expect(message, contains('Periksa koneksi'));
      expect(message, isNot(contains('jane@example.test')));
      expect(message, isNot(contains('stack trace')));
    });
  });
}
