class TenantFeatures {
  final bool pos;
  final bool akuntansi;

  const TenantFeatures({required this.pos, required this.akuntansi});

  factory TenantFeatures.fromJson(Map<String, dynamic> json) => TenantFeatures(
        pos: json['pos'] == true,
        akuntansi: json['akuntansi'] == true,
      );

  factory TenantFeatures.fromEffectiveConfig(Map<String, dynamic> config) {
    final rawFeatures = config['features'];
    if (rawFeatures is Map) {
      return TenantFeatures.fromJson(Map<String, dynamic>.from(rawFeatures));
    }
    if (config.containsKey('pos_enabled') || config.containsKey('akuntansi_enabled')) {
      return TenantFeatures(
        pos: config['pos_enabled'] == true,
        akuntansi: config['akuntansi_enabled'] == true,
      );
    }
    throw const FormatException('Effective configuration has no feature flags');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{'pos': pos, 'akuntansi': akuntansi};
}

/// Pure local helper for fixtures and offline-only behavior. Authenticated
/// cloud configuration is fetched and validated by LaravelAuthService; this
/// helper is not a substitute for server authorization or sync.
class EffectiveConfigResolver {
  static Map<String, dynamic> mergeLayers(Iterable<Map<String, dynamic>> layers) {
    final merged = <String, dynamic>{};
    for (final layer in layers) {
      merged.addAll(layer);
    }
    return merged;
  }
}
