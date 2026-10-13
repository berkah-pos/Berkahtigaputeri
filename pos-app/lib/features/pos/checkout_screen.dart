import 'package:flutter/material.dart';

import '../products/models/product.dart';
import '../products/repositories/sqlite_product_repository.dart';
import 'cart/sale_calculator.dart';
import 'checkout/payment_service.dart';
import 'checkout/sqlite_sale_repository.dart';

/// Cashier UI powered by the modular atomic payment/inventory/accounting layer.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({
    super.key,
    required this.productsRepository,
    required this.paymentService,
    required this.onSaleSaved,
  });

  final SqliteProductRepository productsRepository;
  final PaymentService paymentService;
  final VoidCallback onSaleSaved;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  List<Product> _products = const <Product>[];
  final Map<String, int> _cart = <String, int>{};
  PaymentMethod _method = PaymentMethod.cash;
  bool _loading = true;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final products = await widget.productsRepository.listAll();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
        _error = null;
        _cart.removeWhere((id, _) => !products.any((product) => product.id == id));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Product? _product(String id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  SaleCalculation? get _calculation {
    if (_cart.isEmpty) return null;
    final lines = <SalePricingLine>[];
    for (final entry in _cart.entries) {
      final product = _product(entry.key);
      if (product == null) continue;
      lines.add(
        SalePricingLine(
          productId: product.id,
          quantity: entry.value,
          unitPrice: product.price,
          itemDiscountAmount: 0,
          ppnExempt: product.ppnExempt,
        ),
      );
    }
    if (lines.isEmpty) return null;
    try {
      return SaleCalculator.calculate(lines: lines);
    } on SaleCalculationException {
      // A malformed/zero-value catalogue item must not crash widget build.
      // Invalid totals keep checkout disabled until the product is corrected.
      return null;
    }
  }

  void _changeQuantity(Product product, int delta) {
    if (product.requiresReview) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tinjau klasifikasi PPN produk ' + product.nameId +
            ' sebelum checkout.',
          ),
        ),
      );
      return;
    }
    final next = (_cart[product.id] ?? 0) + delta;
    setState(() {
      if (next <= 0) {
        _cart.remove(product.id);
      } else if (next <= product.stockQty) {
        _cart[product.id] = next;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Stok lokal ' + product.nameId + ' hanya ' +
              product.stockQty.toString() + '.',
            ),
          ),
        );
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty || _processing) return;
    setState(() => _processing = true);
    final transactionId =
        'TRX-' + DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    try {
      final result = await widget.paymentService.process(
        PaymentRequest(
          transactionId: transactionId,
          method: _method,
          occurredAtUtc: DateTime.now().toUtc(),
          lines: _cart.entries
              .map(
                (entry) => PaymentLineInput(
                  productId: entry.key,
                  quantity: entry.value,
                ),
              )
              .toList(growable: false),
        ),
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _processing = false;
      });
      await _reload();
      widget.onSaleSaved();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Transaksi tersimpan'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.check_circle, color: Colors.green, size: 44),
              const SizedBox(height: 12),
              Text('ID: ' + result.saleId),
              Text('Total: ' + _money(result.grandTotal)),
              Text('PPN: ' + _money(result.ppnAmount)),
              const SizedBox(height: 12),
              const Text(
                'Tersimpan di perangkat. Sinkronisasi cloud belum aktif '
                'pada build ini; transaksi menunggu di antrean lokal.',
              ),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Selesai'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checkout gagal; transaksi tidak dikonfirmasi: $error')),
      );
    }
  }

  String _money(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(digits[index]);
    }
    return 'Rp ' + buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final calculation = _calculation;
    return RefreshIndicator(
      onRefresh: _reload,
      child: _loading
          ? ListView(
              children: const <Widget>[
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            )
          : _error != null
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: <Widget>[
                    Text('Produk gagal dimuat: ' + _error!),
                    TextButton(
                      onPressed: _reload,
                      child: const Text('Coba lagi'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: <Widget>[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Keranjang (' + _cart.length.toString() + ' produk)',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            if (_cart.isEmpty)
                              const Text('Pilih produk di bawah untuk memulai.'),
                            ..._cart.entries.map((entry) {
                              final product = _product(entry.key);
                              if (product == null) return const SizedBox.shrink();
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(product.nameId),
                                subtitle: Text(
                                  _money(product.price) + ' × ' +
                                  entry.value.toString(),
                                ),
                                leading: IconButton(
                                  tooltip: 'Kurangi',
                                  onPressed: _processing
                                      ? null
                                      : () => _changeQuantity(product, -1),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    Text(entry.value.toString()),
                                    IconButton(
                                      tooltip: 'Tambah',
                                      onPressed: _processing ||
                                              entry.value >= product.stockQty
                                          ? null
                                          : () => _changeQuantity(product, 1),
                                      icon: const Icon(Icons.add_circle_outline),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            if (_cart.isNotEmpty && calculation == null)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Total tidak valid. Periksa harga produk pada katalog.',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            const Divider(),
                            DropdownButtonFormField<PaymentMethod>(
                              value: _method,
                              decoration: const InputDecoration(
                                labelText: 'Metode pembayaran',
                                border: OutlineInputBorder(),
                              ),
                              items: PaymentMethod.values
                                  .map(
                                    (method) => DropdownMenuItem<PaymentMethod>(
                                      value: method,
                                      child: Text(method.labelId),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: _processing
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        setState(() => _method = value);
                                      }
                                    },
                            ),
                            const SizedBox(height: 12),
                            _SummaryLine(
                              label: 'DPP',
                              value: _money(calculation?.dpp ?? 0),
                            ),
                            _SummaryLine(
                              label: 'PPN',
                              value: _money(calculation?.ppnAmount ?? 0),
                            ),
                            _SummaryLine(
                              label: 'TOTAL',
                              value: _money(calculation?.grandTotal ?? 0),
                              emphasized: true,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _cart.isEmpty ||
                                        _processing ||
                                        calculation == null
                                    ? null
                                    : _checkout,
                                icon: _processing
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.point_of_sale),
                                label: Text(_processing
                                    ? 'Memproses...'
                                    : 'Selesaikan checkout'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Katalog produk',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_products.isEmpty)
                      const Text('Tambahkan produk melalui menu Produk.'),
                    ..._products.map(
                      (product) => Card(
                        child: ListTile(
                          title: Text(product.nameId),
                          subtitle: Text(
                            product.sku + ' · ' + _money(product.price) +
                            ' · Stok ' + product.stockQty.toString() +
                            (product.requiresReview ? ' · PERLU TINJAU PPN' : ''),
                          ),
                          trailing: IconButton(
                            tooltip: 'Tambahkan ke keranjang',
                            onPressed: _processing ||
                                    product.requiresReview ||
                                    product.stockQty <= (_cart[product.id] ?? 0)
                                ? null
                                : () => _changeQuantity(product, 1),
                            icon: const Icon(Icons.add_shopping_cart),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            )
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }
}
