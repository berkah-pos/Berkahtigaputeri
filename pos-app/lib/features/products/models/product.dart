// lib/features/products/models/product.dart

/// Product master used by the POS and inventory modules.
///
/// Monetary values use integer Rupiah. Status and version are persisted
/// product-master fields; lifecycle changes go through the repository's
/// audited status-transition method.
class Product {
  const Product({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.nameId,
    required this.price,
    required this.ppnExempt,
    required this.stockQty,
    this.trackExpiry = false,
    this.minShelfLifeDays = 0,
    this.requiresReview = false,
    this.isActive = true,
    this.version = 1,
    this.syncStatus,
  });

  final String id;
  final String sku;
  final String? barcode;
  final String nameId;
  final int price;
  final bool ppnExempt;
  final int stockQty;
  final bool trackExpiry;
  final int minShelfLifeDays;
  final bool requiresReview;
  final bool isActive;
  final int version;
  final String? syncStatus;

  Product copyWith({
    String? id,
    String? sku,
    String? barcode,
    bool clearBarcode = false,
    String? nameId,
    int? price,
    bool? ppnExempt,
    int? stockQty,
    bool? trackExpiry,
    int? minShelfLifeDays,
    bool? requiresReview,
    bool? isActive,
    int? version,
    String? syncStatus,
    bool clearSyncStatus = false,
  }) {
    return Product(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      nameId: nameId ?? this.nameId,
      price: price ?? this.price,
      ppnExempt: ppnExempt ?? this.ppnExempt,
      stockQty: stockQty ?? this.stockQty,
      trackExpiry: trackExpiry ?? this.trackExpiry,
      minShelfLifeDays: minShelfLifeDays ?? this.minShelfLifeDays,
      requiresReview: requiresReview ?? this.requiresReview,
      isActive: isActive ?? this.isActive,
      version: version ?? this.version,
      syncStatus: clearSyncStatus ? null : (syncStatus ?? this.syncStatus),
    );
  }
}
