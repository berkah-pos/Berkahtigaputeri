// lib/features/pos/cart/sale_calculator.dart

/// Pricing input for one sale line.
class SalePricingLine {
  const SalePricingLine({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.itemDiscountAmount,
    required this.ppnExempt,
  });

  final String productId;
  final int quantity;
  final int unitPrice;
  final int itemDiscountAmount;
  final bool ppnExempt;

  int get grossAmount => quantity * unitPrice;

  int get netBeforeTransactionDiscount =>
      grossAmount - itemDiscountAmount;
}

/// Calculated immutable sale line.
class CalculatedSaleLine {
  const CalculatedSaleLine({
    required this.source,
    required this.transactionDiscountAmount,
    required this.dpp,
  });

  final SalePricingLine source;
  final int transactionDiscountAmount;
  final int dpp;

  int get grossAmount => source.grossAmount;
  int get itemDiscountAmount => source.itemDiscountAmount;
  int get discountAmount =>
      itemDiscountAmount + transactionDiscountAmount;
  bool get ppnExempt => source.ppnExempt;
}

/// Invoice-level sale totals.
///
/// PPN is rounded once at invoice level from taxable DPP after all discounts.
class SaleCalculation {
  SaleCalculation({
    required List<CalculatedSaleLine> lines,
    required this.grossAmount,
    required this.itemDiscountAmount,
    required this.transactionDiscountAmount,
    required this.taxableDpp,
    required this.exemptDpp,
    required this.ppnAmount,
  }) : lines = List<CalculatedSaleLine>.unmodifiable(lines);

  final List<CalculatedSaleLine> lines;
  final int grossAmount;
  final int itemDiscountAmount;
  final int transactionDiscountAmount;
  final int taxableDpp;
  final int exemptDpp;
  final int ppnAmount;

  int get discountAmount =>
      itemDiscountAmount + transactionDiscountAmount;

  int get dpp => taxableDpp + exemptDpp;

  int get grandTotal => dpp + ppnAmount;
}

/// Pure Dart sale calculator for integer Rupiah.
class SaleCalculator {
  const SaleCalculator._();

  static const int ppnRatePercent = 11;

  static SaleCalculation calculate({
    required List<SalePricingLine> lines,
    int transactionDiscountAmount = 0,
  }) {
    if (lines.isEmpty) {
      throw const SaleCalculationException(
        'Keranjang tidak boleh kosong.',
      );
    }
    if (transactionDiscountAmount < 0) {
      throw const SaleCalculationException(
        'Diskon transaksi tidak boleh negatif.',
      );
    }

    var grossAmount = 0;
    var itemDiscountAmount = 0;
    var netBeforeTransactionDiscount = 0;

    for (final line in lines) {
      _validateLine(line);
      grossAmount += line.grossAmount;
      itemDiscountAmount += line.itemDiscountAmount;
      netBeforeTransactionDiscount +=
          line.netBeforeTransactionDiscount;
    }

    if (grossAmount <= 0) {
      throw const SaleCalculationException(
        'Nilai penjualan harus lebih dari nol.',
      );
    }

    if (transactionDiscountAmount > netBeforeTransactionDiscount) {
      throw const SaleCalculationException(
        'Diskon transaksi melebihi nilai setelah diskon item.',
      );
    }

    final allocations = _allocateTransactionDiscount(
      lines: lines,
      totalNet: netBeforeTransactionDiscount,
      discount: transactionDiscountAmount,
    );

    final calculated = <CalculatedSaleLine>[];
    var taxableDpp = 0;
    var exemptDpp = 0;

    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final allocatedDiscount = allocations[index];
      final dpp =
          line.netBeforeTransactionDiscount - allocatedDiscount;

      final calculatedLine = CalculatedSaleLine(
        source: line,
        transactionDiscountAmount: allocatedDiscount,
        dpp: dpp,
      );
      calculated.add(calculatedLine);

      if (line.ppnExempt) {
        exemptDpp += dpp;
      } else {
        taxableDpp += dpp;
      }
    }

    final ppnAmount = calculatePpn(taxableDpp);
    final grandTotal = taxableDpp + exemptDpp + ppnAmount;
    if (grandTotal <= 0) {
      throw const SaleCalculationException(
        'Total transaksi harus lebih dari nol. Diskon penuh memerlukan '
        'alur kompensasi yang disetujui.',
      );
    }

    return SaleCalculation(
      lines: calculated,
      grossAmount: grossAmount,
      itemDiscountAmount: itemDiscountAmount,
      transactionDiscountAmount: transactionDiscountAmount,
      taxableDpp: taxableDpp,
      exemptDpp: exemptDpp,
      ppnAmount: ppnAmount,
    );
  }

  /// Calculates 11% PPN without multiplying the full amount by 11 first.
  static int calculatePpn(int taxableDpp) {
    if (taxableDpp < 0) {
      throw const SaleCalculationException(
        'DPP kena pajak tidak boleh negatif.',
      );
    }

    final hundreds = taxableDpp ~/ 100;
    final remainder = taxableDpp % 100;
    return (hundreds * ppnRatePercent) +
        (((remainder * ppnRatePercent) + 50) ~/ 100);
  }

  static List<int> _allocateTransactionDiscount({
    required List<SalePricingLine> lines,
    required int totalNet,
    required int discount,
  }) {
    if (discount == 0) {
      return List<int>.filled(lines.length, 0);
    }

    if (totalNet <= 0) {
      throw const SaleCalculationException(
        'Diskon transaksi tidak dapat dialokasikan.',
      );
    }

    final allocations = List<int>.filled(lines.length, 0);
    final remainders = <_AllocationRemainder>[];
    var allocated = 0;

    for (var index = 0; index < lines.length; index++) {
      final net = lines[index].netBeforeTransactionDiscount;
      final numerator = discount * net;
      final base = numerator ~/ totalNet;
      allocations[index] = base;
      allocated += base;
      remainders.add(
        _AllocationRemainder(
          index: index,
          remainder: numerator % totalNet,
        ),
      );
    }

    remainders.sort((left, right) {
      final byRemainder = right.remainder.compareTo(left.remainder);
      if (byRemainder != 0) {
        return byRemainder;
      }
      return left.index.compareTo(right.index);
    });

    var remaining = discount - allocated;
    for (final item in remainders) {
      if (remaining == 0) {
        break;
      }
      final maxForLine =
          lines[item.index].netBeforeTransactionDiscount;
      if (allocations[item.index] < maxForLine) {
        allocations[item.index]++;
        remaining--;
      }
    }

    if (remaining != 0) {
      throw const SaleCalculationException(
        'Alokasi diskon transaksi tidak seimbang.',
      );
    }

    return allocations;
  }

  static void _validateLine(SalePricingLine line) {
    if (line.productId.trim().isEmpty) {
      throw const SaleCalculationException('ID produk wajib diisi.');
    }
    if (line.quantity <= 0) {
      throw const SaleCalculationException(
        'Jumlah produk harus lebih dari nol.',
      );
    }
    if (line.unitPrice < 0) {
      throw const SaleCalculationException(
        'Harga produk tidak boleh negatif.',
      );
    }
    if (line.itemDiscountAmount < 0) {
      throw const SaleCalculationException(
        'Diskon item tidak boleh negatif.',
      );
    }
    if (line.itemDiscountAmount > line.grossAmount) {
      throw const SaleCalculationException(
        'Diskon item melebihi nilai item.',
      );
    }
  }
}

class _AllocationRemainder {
  const _AllocationRemainder({
    required this.index,
    required this.remainder,
  });

  final int index;
  final int remainder;
}

class SaleCalculationException implements Exception {
  const SaleCalculationException(this.message);

  final String message;

  @override
  String toString() => message;
}
