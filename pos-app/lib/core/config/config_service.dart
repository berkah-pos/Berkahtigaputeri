import 'package:berkahtigaputeri_pos/core/auth/identity_service.dart';

class TenantFeatures {
  final bool pos;
  final bool akuntansi;

  const TenantFeatures({
    required this.pos,
    required this.akuntansi,
  });

  factory TenantFeatures.fromJson(Map<String, dynamic> json) {
    return TenantFeatures(
      pos: json['pos'] == true,
      akuntansi: json['akuntansi'] == true,
    );
  }

  factory TenantFeatures.fromEffectiveConfig(Map<String, dynamic> config) {
    final rawFeatures = config['features'];
    if (rawFeatures is Map) {
      return TenantFeatures.fromJson(Map<String, dynamic>.from(rawFeatures));
    }

    if (config.containsKey('pos_enabled') ||
        config.containsKey('akuntansi_enabled')) {
      return TenantFeatures(
        pos: config['pos_enabled'] == true,
        akuntansi: config['akuntansi_enabled'] == true,
      );
    }

    throw const FormatException(
      'Effective app_config does not contain tenant feature flags',
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'pos': pos,
        'akuntansi': akuntansi,
      };
}

class EffectiveConfigResult {
  final Map<String, dynamic> value;
  final bool fromCache;

  const EffectiveConfigResult({
    required this.value,
    required this.fromCache,
  });
}

/// Effective configuration now goes through the server-verified Laravel
/// identity service. No browser/mobile Supabase client or client-side table
/// reads are allowed. Until the Laravel effective-config endpoint is deployed,
/// this method fails closed rather than silently switching backends.
class ConfigService {
  ConfigService(this._identityService);

  final IdentityService _identityService;

  bool get hasAuthenticatedSession =>
      _identityService.currentSession?.isDeviceSession == true;

  Future<EffectiveConfigResult> getEffectiveConfig({
    required String tenantId,
    required String deviceId,
    required String service,
  }) async {
    final session = _identityService.currentSession;
    if (session == null || !session.isDeviceSession) {
      throw StateError(
        'A server-verified Laravel device session is required for effective configuration.',
      );
    }

    if (tenantId != session.tenantId || deviceId != session.deviceId) {
      throw StateError(
        'Local tenant/device selectors do not match the verified server session.',
      );
    }

    final effective = await _identityService.getEffectiveConfig(
      tenantId: session.tenantId,
      deviceId: session.deviceId,
      service: service,
    );
    return EffectiveConfigResult(value: effective, fromCache: false);
  }

  static Map<String, dynamic> mergeLayers(
    Iterable<Map<String, dynamic>> layers,
  ) {
    final merged = <String, dynamic>{};
    for (final layer in layers) {
      merged.addAll(layer);
    }
    return merged;
  }
}
