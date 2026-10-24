import 'package:berkahtigaputeri_pos/features/pos/checkout/payment_service.dart';
import 'package:berkahtigaputeri_pos/features/pos/checkout_screen.dart';
import 'package:berkahtigaputeri_pos/features/products/models/product.dart';
import 'package:berkahtigaputeri_pos/features/products/repositories/sqlite_product_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_database.dart';

class _UnexpectedFailureSaleRepository implements SaleRepository {
  @override
  Future<PaymentResult> processPayment(PaymentRequest request) async {
    throw StateError(
      'SQLITE_ERROR no such table: sales '
      'path=/data/user/0/app.db token=Bearer-test-secret',
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pump();
}

void main() {
  testWidgets(
    'unexpected payment exception shows safe copy, not SQLite details',
    (tester) async {
      final database = (await tester.runAsync(openTestDatabase))!;
      addTearDown(() async {
        await tester.runAsync(database.close);
      });

      final products = SqliteProductRepository(database);
      await tester.runAsync(() async {
        await products.upsert(
          const Product(
            id: 'P-CHECKOUT-ERROR',
            sku: 'SKU-CHECKOUT-ERROR',
            barcode: null,
            nameId: 'Produk Uji Checkout',
            price: 25000,
            ppnExempt: false,
            stockQty: 0,
          ),
        );
        await products.addInventoryLot(
          id: 'LOT-CHECKOUT-ERROR',
          productId: 'P-CHECKOUT-ERROR',
          quantity: 2,
          unitCost: 10000,
          acquiredAtUtc: DateTime.utc(2026, 10, 20),
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CheckoutScreen(
            productsRepository: products,
            paymentService: PaymentService(
              repository: _UnexpectedFailureSaleRepository(),
            ),
            onSaleSaved: () {},
          ),
        ),
      );
      await _settle(tester);

      expect(find.text('Produk Uji Checkout'), findsOneWidget);
      await tester.tap(find.byTooltip('Tambahkan ke keranjang'));
      await _settle(tester);

      await tester.tap(find.text('Selesaikan checkout'));
      await _settle(tester);

      expect(
        find.text(
          'Checkout belum dapat dikonfirmasi. Periksa riwayat transaksi '
          'sebelum mencoba kembali; hubungi dukungan jika statusnya tidak jelas.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('SQLITE_ERROR'), findsNothing);
      expect(find.textContaining('no such table'), findsNothing);
      expect(find.textContaining('/data/user/0/app.db'), findsNothing);
      expect(find.textContaining('Bearer-test-secret'), findsNothing);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
