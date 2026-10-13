import 'package:flutter/material.dart';

import '../products/models/product.dart';
import '../products/repositories/sqlite_product_repository.dart';

/// Inventory receipt screen; stock changes create physical lots and cost layers.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final SqliteProductRepository repository;
  final VoidCallback onChanged;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _quantity = TextEditingController();
  final _unitCost = TextEditingController();
  final _batchNo = TextEditingController();
  List<Product> _products = const <Product>[];
  List<Map<String, Object?>> _legacyStock = const <Map<String, Object?>>[];
  Product? _selected;
  DateTime? _expiryDate;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _unitCost.dispose();
    _batchNo.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final products = await widget.repository.listAll();
      final legacyStock = await widget.repository.legacyStockNeedsReview();
      if (!mounted) return;
      Product? selected;
      for (final product in products) {
        if (product.id == _selected?.id) {
          selected = product;
          break;
        }
      }
      selected ??= products.isEmpty ? null : products.first;
      setState(() {
        _products = products;
        _legacyStock = legacyStock;
        _selected = selected;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String? _positive(String? value, String label) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number <= 0) return '$label harus lebih dari 0.';
    return null;
  }

  String? _nonNegative(String? value, String label) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number < 0) return '$label harus 0 atau lebih.';
    return null;
  }

  Future<void> _chooseExpiryDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today.add(const Duration(days: 30)),
      firstDate: DateTime(today.year - 1),
      lastDate: DateTime(today.year + 20),
      helpText: 'Pilih tanggal kedaluwarsa',
    );
    if (selected != null && mounted) {
      setState(() => _expiryDate = selected);
    }
  }

  Future<void> _receiveStock() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _selected;
    if (product == null) return;
    if (product.trackExpiry && _expiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Produk ini mewajibkan tanggal kedaluwarsa.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final lotId = 'LOT-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    final batch = _batchNo.text.trim().isEmpty ? lotId : _batchNo.text.trim();
    try {
      await widget.repository.addInventoryLot(
        id: lotId,
        productId: product.id,
        quantity: int.parse(_quantity.text.trim()),
        unitCost: int.parse(_unitCost.text.trim()),
        acquiredAtUtc: DateTime.now().toUtc(),
        batchNo: batch,
        expiryDate: _expiryDate,
      );
      if (!mounted) return;
      setState(() {
        _quantity.clear();
        _unitCost.clear();
        _batchNo.clear();
        _expiryDate = null;
        _saving = false;
      });
      await _reload();
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Penerimaan stok dan layer biaya tersimpan lokal.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Penerimaan stok gagal: $error')),
      );
    }
  }

  Future<void> _reviewLegacyStock(Map<String, Object?> row) async {
    final productId = row['product_id']?.toString() ?? '';
    final name = row['name_id']?.toString() ?? productId;
    final originalQuantity = (row['original_quantity'] as num?)?.toInt() ?? 0;
    final currentQuantity = (row['current_stock_qty'] as num?)?.toInt() ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rekonsiliasi stok trial'),
        content: Text(
          'Produk: $name\n'
          'Kuantitas dari data lama: $originalQuantity\n'
          'Stok aktif di aplikasi baru: $currentQuantity\n\n'
          'Pastikan stok fisik sudah dihitung dan stok pembukaan yang benar '
          'sudah dicatat melalui penerimaan stok, dengan harga pokok dan '
          'lot/expiry yang benar. Jika stok fisik memang nol, pastikan itu '
          'sudah diverifikasi. Arsip lama tidak otomatis menjadi stok aktif.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Belum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Saya sudah memeriksa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repository.markLegacyStockReconciled(productId);
      await _reload();
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok lama ditandai sudah ditinjau.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rekonsiliasi belum selesai: $error')),
      );
    }
  }

  String _dateText(DateTime? date) {
    if (date == null) return 'Tidak ditentukan';
    return "${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text('Persediaan gagal dimuat: $_error'),
          TextButton(
            onPressed: _reload,
            child: const Text('Coba lagi'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Terima stok',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (_products.isEmpty)
                      const Text('Tambahkan produk terlebih dahulu.')
                    else
                      DropdownButtonFormField<Product>(
                        initialValue: _selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Produk',
                          border: OutlineInputBorder(),
                        ),
                        items: _products
                            .map(
                              (product) => DropdownMenuItem<Product>(
                                value: product,
                                child: Text(
                                  '${product.nameId} — stok ${product.stockQty}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _selected = value),
                      ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah diterima',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _positive(value, 'Jumlah'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _unitCost,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Harga pokok per unit (Rupiah)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => _nonNegative(value, 'Harga pokok'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _batchNo,
                      decoration: InputDecoration(
                        labelText: 'Nomor batch',
                        helperText: _selected?.trackExpiry == true
                            ? 'Wajib untuk produk dengan kedaluwarsa'
                            : 'Opsional; dapat dibuat otomatis',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => _selected?.trackExpiry == true &&
                              (value == null || value.trim().isEmpty)
                          ? 'Nomor batch wajib diisi.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _saving || _products.isEmpty
                          ? null
                          : _chooseExpiryDate,
                      icon: const Icon(Icons.event),
                      label: Text('Kedaluwarsa: ${_dateText(_expiryDate)}'),
                    ),
                    if (_selected?.trackExpiry == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Produk ini menggunakan FEFO; tanggal kedaluwarsa '
                          'wajib dan stok terlalu dekat kedaluwarsa tidak dijual.',
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving || _products.isEmpty
                            ? null
                            : _receiveStock,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_box_outlined),
                        label: Text(_saving ? 'Menyimpan...' : 'Catat penerimaan'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_legacyStock.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Stok trial perlu direkonsiliasi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Kuantitas lama disimpan sebagai arsip. Stok lama tidak '
                      'diaktifkan otomatis karena batch, expiry, dan HPP '
                      'tidak tersedia di database trial.',
                    ),
                    const SizedBox(height: 8),
                    ..._legacyStock.map((row) {
                      final name = row['name_id']?.toString() ?? '-';
                      final original = (row['original_quantity'] as num?)
                              ?.toInt() ??
                          0;
                      final current = (row['current_stock_qty'] as num?)
                              ?.toInt() ??
                          0;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(name),
                        subtitle: Text(
                          'Stok lama: $original · Stok aktif: $current',
                        ),
                        trailing: IconButton(
                          tooltip: 'Rekonsiliasi stok lama',
                          onPressed: _saving
                              ? null
                              : () => _reviewLegacyStock(row),
                          icon: const Icon(Icons.fact_check_outlined),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Ringkasan stok lokal',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          ..._products.map(
            (product) => Card(
              child: ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(product.nameId),
                subtitle: Text(
                  "${product.sku} · ${product.trackExpiry ? 'FEFO' : 'Tanpa pelacakan expiry'}",
                ),
                trailing: Text(
                  product.stockQty.toString(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Perubahan di halaman ini masih lokal pada perangkat. Sinkronisasi '
            'stok ke cloud belum aktif pada build ini.',
          ),
        ],
      ),
    );
  }
}
