import 'package:berkahtigaputeri_pos/core/config/config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EffectiveConfigResolver merge order', () {
    test('GLOBAL -> TEMPLATE -> TENANT -> SERVICE -> DEVICE', () {
      final merged = EffectiveConfigResolver.mergeLayers(<Map<String, dynamic>>[
        <String, dynamic>{'mdr': 0.1, 'theme': 'global', 'printer': 'none'},
        <String, dynamic>{'mdr': 0.15, 'theme': 'template'},
        <String, dynamic>{'mdr': 0.2, 'theme': 'tenant'},
        <String, dynamic>{'mdr': 0.5, 'qris_enabled': true},
        <String, dynamic>{'printer': 'PDF Preview'},
      ]);

      expect(merged['mdr'], 0.5);
      expect(merged['theme'], 'tenant');
      expect(merged['qris_enabled'], isTrue);
      expect(merged['printer'], 'PDF Preview');
    });

    test('tenant-scoped POS MDR values do not collide', () {
      final clientA = EffectiveConfigResolver.mergeLayers(<Map<String, dynamic>>[
        <String, dynamic>{'mdr': 0.1},
        <String, dynamic>{'tenant_id': 'clientA'},
        <String, dynamic>{'mdr': 0.5},
        const <String, dynamic>{},
      ]);
      final clientB = EffectiveConfigResolver.mergeLayers(<Map<String, dynamic>>[
        <String, dynamic>{'mdr': 0.1},
        <String, dynamic>{'tenant_id': 'clientB'},
        <String, dynamic>{'mdr': 0.7},
        const <String, dynamic>{},
      ]);

      expect(clientA['mdr'], 0.5);
      expect(clientB['mdr'], 0.7);
    });
  });

  group('TenantFeatures', () {
    test('clientA hides Akuntansi', () {
      final features = TenantFeatures.fromJson(
        <String, dynamic>{'pos': true, 'akuntansi': false},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('clientB shows POS and Akuntansi', () {
      final features = TenantFeatures.fromJson(
        <String, dynamic>{'pos': true, 'akuntansi': true},
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('feature flags are derived from effective app_config features', () {
      final features = TenantFeatures.fromEffectiveConfig(
        <String, dynamic>{
          'features': <String, dynamic>{'pos': true, 'akuntansi': false},
        },
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isFalse);
    });

    test('supports canonical flat feature flags in effective config', () {
      final features = TenantFeatures.fromEffectiveConfig(
        <String, dynamic>{
          'pos_enabled': true,
          'akuntansi_enabled': true,
        },
      );

      expect(features.pos, isTrue);
      expect(features.akuntansi, isTrue);
    });

    test('fails closed when effective app_config has no feature flags', () {
      expect(
        () => TenantFeatures.fromEffectiveConfig(<String, dynamic>{}),
        throwsFormatException,
      );
    });
  });
}
