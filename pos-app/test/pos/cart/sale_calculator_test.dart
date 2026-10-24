// test/pos/cart/sale_calculator_test.dart

import 'package:berkahtigaputeri_pos/features/pos/cart/sale_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaleCalculator', () {
    test('PPN 11% dihitung dari DPP kena pajak setelah semua diskon', () {
      final result = SaleCalculator.calculate(
        lines: const <SalePricingLine>[
          SalePricingLine(
            productId: 'P-001',
            quantity: 1,
            unitPrice: 100000,
            itemDiscountAmount: 10000,
            ppnExempt: false,
          ),
        ],
        transactionDiscountAmount: 10000,
      );

      expect(result.grossAmount, 100000);
      expect(result.itemDiscountAmount, 10000);
      expect(result.transactionDiscountAmount, 10000);
      expect(result.discountAmount, 20000);
      expect(result.taxableDpp, 80000);
      expect(result.ppnAmount, 8800);
      expect(result.grandTotal, 88800);
    });

    test('diskon transaksi dialokasikan proporsional ke cart campuran', () {
      final result = SaleCalculator.calculate(
        lines: const <SalePricingLine>[
          SalePricingLine(
            productId: 'P-TAX',
            quantity: 1,
            unitPrice: 100000,
            itemDiscountAmount: 0,
            ppnExempt: false,
          ),
          SalePricingLine(
            productId: 'P-EXEMPT',
            quantity: 1,
            unitPrice: 50000,
            itemDiscountAmount: 0,
            ppnExempt: true,
          ),
        ],
        transactionDiscountAmount: 15000,
      );

      expect(result.lines[0].transactionDiscountAmount, 10000);
      expect(result.lines[0].dpp, 90000);
      expect(result.lines[1].transactionDiscountAmount, 5000);
      expect(result.lines[1].dpp, 45000);
      expect(result.taxableDpp, 90000);
      expect(result.exemptDpp, 45000);
      expect(result.ppnAmount, 9900);
      expect(result.grandTotal, 144900);
    });

    test('sisa alokasi Rupiah dibagikan deterministik', () {
      final result = SaleCalculator.calculate(
        lines: const <SalePricingLine>[
          SalePricingLine(
            productId: 'A',
            quantity: 1,
            unitPrice: 100,
            itemDiscountAmount: 0,
            ppnExempt: false,
          ),
          SalePricingLine(
            productId: 'B',
            quantity: 1,
            unitPrice: 100,
            itemDiscountAmount: 0,
            ppnExempt: false,
          ),
          SalePricingLine(
            productId: 'C',
            quantity: 1,
            unitPrice: 100,
            itemDiscountAmount: 0,
            ppnExempt: false,
          ),
        ],
        transactionDiscountAmount: 1,
      );

      expect(
        result.lines
            .map((line) => line.transactionDiscountAmount)
            .toList(),
        <int>[1, 0, 0],
      );
      expect(result.dpp, 299);
      expect(result.ppnAmount, 33);
    });

    test('pembulatan PPN menggunakan integer Rupiah half-up', () {
      expect(SaleCalculator.calculatePpn(4), 0);
      expect(SaleCalculator.calculatePpn(5), 1);
      expect(SaleCalculator.calculatePpn(999), 110);
      expect(SaleCalculator.calculatePpn(1000), 110);
    });

    test('diskon item penuh ditolak jika total yang harus dibayar nol', () {
      expect(
        () => SaleCalculator.calculate(
          lines: const <SalePricingLine>[
            SalePricingLine(
              productId: 'P-FREE',
              quantity: 1,
              unitPrice: 10000,
              itemDiscountAmount: 10000,
              ppnExempt: false,
            ),
          ],
        ),
        throwsA(isA<SaleCalculationException>()),
      );
    });

    test('diskon transaksi penuh ditolak jika total yang harus dibayar nol', () {
      expect(
        () => SaleCalculator.calculate(
          lines: const <SalePricingLine>[
            SalePricingLine(
              productId: 'P-001',
              quantity: 1,
              unitPrice: 10000,
              itemDiscountAmount: 2000,
              ppnExempt: false,
            ),
          ],
          transactionDiscountAmount: 8000,
        ),
        throwsA(isA<SaleCalculationException>()),
      );
    });

    test('diskon transaksi tidak boleh melebihi nilai net', () {
      expect(
        () => SaleCalculator.calculate(
          lines: const <SalePricingLine>[
            SalePricingLine(
              productId: 'P-001',
              quantity: 1,
              unitPrice: 10000,
              itemDiscountAmount: 1000,
              ppnExempt: false,
            ),
          ],
          transactionDiscountAmount: 9001,
        ),
        throwsA(isA<SaleCalculationException>()),
      );
    });
  });
}
