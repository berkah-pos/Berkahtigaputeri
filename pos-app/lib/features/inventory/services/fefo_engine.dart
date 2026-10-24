// lib/features/inventory/services/fefo_engine.dart

/// Read-only lot candidate used by the deterministic FEFO allocator.
class FefoLotCandidate {
  const FefoLotCandidate({
    required this.id,
    required this.availableQty,
    required this.firstReceivedAtUtc,
    required this.expiryDate,
  });

  final String id;
  final int availableQty;
  final DateTime firstReceivedAtUtc;
  final DateTime? expiryDate;
}

class FefoAllocation {
  const FefoAllocation({
    required this.lotId,
    required this.quantity,
  });

  final String lotId;
  final int quantity;
}

class FefoAllocationResult {
  FefoAllocationResult({
    required List<FefoAllocation> allocations,
  }) : allocations = List<FefoAllocation>.unmodifiable(allocations);

  final List<FefoAllocation> allocations;

  int get quantity => allocations.fold<int>(
        0,
        (sum, allocation) => sum + allocation.quantity,
      );
}

/// Pure FEFO policy.
///
/// Physical allocation is intentionally independent from FIFO financial cost
/// valuation. Held/non-saleable lots must be removed by the repository before
/// candidates reach this policy.
class FefoEngine {
  const FefoEngine._();

  static FefoAllocationResult allocate({
    required List<FefoLotCandidate> candidates,
    required int requestedQuantity,
    required DateTime businessDate,
    required bool trackExpiry,
    required int minShelfLifeDays,
  }) {
    if (requestedQuantity <= 0) {
      throw const FefoValidationException(
        'Jumlah FEFO harus lebih dari nol.',
      );
    }
    if (minShelfLifeDays < 0) {
      throw const FefoValidationException(
        'Minimum shelf life tidak boleh negatif.',
      );
    }

    final dateOnly = DateTime(
      businessDate.year,
      businessDate.month,
      businessDate.day,
    );
    final minimumExpiry = dateOnly.add(Duration(days: minShelfLifeDays));

    final eligible = candidates.where((candidate) {
      if (candidate.availableQty <= 0) {
        return false;
      }

      final expiry = candidate.expiryDate;
      final expiryOnly = expiry == null
          ? null
          : DateTime(expiry.year, expiry.month, expiry.day);

      // A stored expiry date is authoritative even when product-level expiry
      // tracking is disabled. Maintenance jobs update lot status for inventory
      // visibility; checkout must remain safe if such a job has not run.
      if (expiryOnly != null && expiryOnly.isBefore(dateOnly)) {
        return false;
      }

      if (!trackExpiry) {
        return true;
      }
      if (expiryOnly == null) {
        return false;
      }
      return !expiryOnly.isBefore(minimumExpiry);
    }).toList(growable: false)
      ..sort((left, right) {
        if (trackExpiry) {
          final leftExpiry = left.expiryDate!;
          final rightExpiry = right.expiryDate!;
          final expiryCompare = DateTime(
            leftExpiry.year,
            leftExpiry.month,
            leftExpiry.day,
          ).compareTo(DateTime(
            rightExpiry.year,
            rightExpiry.month,
            rightExpiry.day,
          ));
          if (expiryCompare != 0) {
            return expiryCompare;
          }
        }

        final receivedCompare =
            left.firstReceivedAtUtc.compareTo(right.firstReceivedAtUtc);
        if (receivedCompare != 0) {
          return receivedCompare;
        }
        return left.id.compareTo(right.id);
      });

    final available = eligible.fold<int>(
      0,
      (sum, candidate) => sum + candidate.availableQty,
    );
    if (available < requestedQuantity) {
      throw FefoInsufficientStockException(
        available: available,
        requested: requestedQuantity,
      );
    }

    var remaining = requestedQuantity;
    final allocations = <FefoAllocation>[];
    for (final candidate in eligible) {
      if (remaining == 0) {
        break;
      }
      final take = remaining < candidate.availableQty
          ? remaining
          : candidate.availableQty;
      allocations.add(FefoAllocation(lotId: candidate.id, quantity: take));
      remaining -= take;
    }

    return FefoAllocationResult(allocations: allocations);
  }
}

class FefoException implements Exception {
  const FefoException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FefoValidationException extends FefoException {
  const FefoValidationException(super.message);
}

class FefoInsufficientStockException extends FefoException {
  FefoInsufficientStockException({
    required this.available,
    required this.requested,
  }) : super(
          'Stok FEFO tidak cukup. Tersedia $available, diminta $requested.',
        );

  final int available;
  final int requested;
}