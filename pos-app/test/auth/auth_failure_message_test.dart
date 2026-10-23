import 'package:flutter_test/flutter_test.dart';
import 'package:berkahtigaputeri_pos/core/auth/auth_failure_message.dart';
import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';

void main() {
  group('safeAuthFailureMessage', () {
    test('does not reflect unknown server diagnostics or internal codes', () {
      const failure = AuthFailure(
        message: 'database=pg-private token=super-secret customer=jane@example.test',
        code: 'internal_exception:database',
        statusCode: 500,
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('Login belum berhasil'));
      expect(message, isNot(contains('pg-private')));
      expect(message, isNot(contains('super-secret')));
      expect(message, isNot(contains('jane@example.test')));
      expect(message, isNot(contains('internal_exception')));
    });

    test('preserves tenant-selection guidance without exposing server text', () {
      const failure = AuthFailure(
        message: 'private server diagnostic',
        code: 'tenant_selection_required',
        statusCode: 422,
        memberships: <TenantChoice>[
          TenantChoice(id: 'tenant-a', label: 'Toko A'),
        ],
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, 'Pilih tenant aktif untuk melanjutkan.');
      expect(message, isNot(contains('private server diagnostic')));
      expect(failure.memberships.single.id, 'tenant-a');
    });

    test('maps rejected credentials to fixed guidance', () {
      const failure = AuthFailure(
        message: 'raw backend detail',
        code: 'invalid_credentials',
        statusCode: 401,
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('Email atau kata sandi tidak valid'));
      expect(message, isNot(contains('raw backend detail')));
    });

    test('maps device conflict without showing device or server internals', () {
      const failure = AuthFailure(
        message: 'device secret=private; host=pg-private',
        code: 'device_identity_conflict',
        statusCode: 409,
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('Hubungi administrator'));
      expect(message, isNot(contains('private')));
      expect(message, isNot(contains('pg-private')));
    });

    test('maps throttling to retry guidance', () {
      const failure = AuthFailure(
        message: 'internal throttle details',
        code: 'http_429',
        statusCode: 429,
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('Terlalu banyak percobaan login'));
      expect(message, isNot(contains('internal throttle details')));
    });

    test('maps connection failure without exposing exception contents', () {
      const failure = AuthFailure(
        message: 'internal DNS name and trace',
        code: 'network_timeout',
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('Periksa koneksi'));
      expect(message, isNot(contains('internal DNS name')));
      expect(message, isNot(contains('trace')));
    });

    test('maps validation error without exposing server validation text', () {
      const failure = AuthFailure(
        message: 'The device_secret field failed at private.php:77',
        code: 'http_422',
        statusCode: 422,
      );

      final message = safeAuthFailureMessage(failure);

      expect(message, contains('belum valid'));
      expect(message, isNot(contains('private.php')));
      expect(message, isNot(contains('device_secret')));
    });
  });
}
