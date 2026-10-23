import 'package:berkahtigaputeri_pos/features/home/legacy_import_failure_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy-import UI copy never reflects raw exception details', () {
    const sensitiveDetails = <String>[
      'DatabaseException(no such table: legacy_sale_items_archive)',
      'SqliteException at /data/user/0/example/databases/berkah_pos.db',
      'StateError: simulated import failure; stack trace at importer.dart:88',
      'Authorization: Bearer 1|secret-token-value',
    ];

    for (final details in sensitiveDetails) {
      final message = safeLegacyImportFailureMessage(details);
      expect(message, contains('Database sumber tetap dipertahankan.'));
      expect(message, contains('Periksa penyimpanan perangkat'));
      expect(message, isNot(contains(details)));
      expect(message, isNot(contains('no such table')));
      expect(message, isNot(contains('/data/user/0')));
      expect(message, isNot(contains('secret-token-value')));
    }
  });
}
