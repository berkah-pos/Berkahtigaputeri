import 'package:flutter/material.dart';

import 'models/product.dart';
import 'product_failure_message.dart';
import 'repositories/sqlite_product_repository.dart';

/// Product catalogue backed by the canonical local-first repository.
/// Opening stock is recorded through InventoryScreen so lot and cost layers
/// remain consistent with the checkout engine.
class ProductScreen extends StatefulWidget {
  const ProductScreen({
    super.key,
    required this.repository,
    required this.onChanged,
  });

  final SqliteProductRepository repository;
  final VoidCallback onChanged;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  List<Product> _products = const <Product>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await widget.repository.listAll();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = safeProductFailureMessage(
          error,
          operation: ProductFailureOperation.load,
        );
        _loading = false;
      });
    }
  }

  Future<void> _edit([Product? existing]) async {
    var expirySettingsEditable = true;
    if (existing != null) {
      try {
        expirySettingsEditable =
            !(await widget.repository.hasInventoryLots(existing.id));
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              safeProductFailureMessage(
                error,
                operation: ProductFailureOperation.verifyHistory,
              ),
            ),
          ),
        );
        return;
      }
    }
    if (!mounted) return;

    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductEditor(
        existing: existing,
        expirySettingsEditable: expirySettingsEditable,
      ),
    );
    if (product == null) return;

    try {
      await widget.repository.upsert(product);
      await _reload();
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(existing == null
              ? 'Produk disimpan secara lokal.'
              : 'Produk diperbarui secara lokal.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeProductFailureMessage(
              error,
              operation: ProductFailureOperation.save,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _changeActiveStatus(Product product) async {
    final controller = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(product.isActive ? 'Nonaktifkan produk?' : 'Aktifkan kembali produk?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.isActive
                      ? 'Produk tidak dapat dipilih untuk penjualan baru. Riwayat dan persediaan tetap disimpan.'
                      : 'Produk akan tersedia untuk penjualan setelah perubahan status tersinkron.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Alasan perubahan status (wajib)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: controller.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(dialogContext, controller.text.trim()),
                child: Text(product.isActive ? 'Nonaktifkan' : 'Aktifkan'),
              ),
            ],
          ),
        ),
      );
      if (reason == null || reason.trim().isEmpty) return;

      await widget.repository.setActiveStatus(
        product,
        isActive: !product.isActive,
        reason: reason,
      );
      await _reload();
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Status lokal tersimpan. Periksa antrean sinkronisasi untuk konfirmasi server.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeProductFailureMessage(
              error,
              operation: ProductFailureOperation.save,
            ),
          ),
        ),
      );
      await _reload();
    } finally {
      controller.dispose();
    }
  }

  Future<void> _delete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text(
          'Produk ' + product.nameId +
          ' hanya dapat dihapus jika belum memiliki riwayat atau persediaan terkait.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.deleteIfUnused(product.id);
      await _reload();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            safeProductFailureMessage(
              error,
              operation: ProductFailureOperation.delete,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah produk'),
      ),
      body: RefreshIndicator(
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
                      const Icon(Icons.error_outline, size: 44),
                      const SizedBox(height: 12),
                      Text('Gagal membaca produk: ' + _error!),
                      TextButton(
                        onPressed: _reload,
                        child: const Text('Coba lagi'),
                      ),
                    ],
                  )
                : _products.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.all(24),
                        children: const <Widget>[
                          SizedBox(height: 80),
                          Icon(Icons.inventory_2_outlined, size: 56),
                          SizedBox(height: 12),
                          Center(
                            child: Text(
                              'Belum ada produk. Tambahkan produk, lalu '
                              'terima stok melalui menu Stok.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                        itemCount: _products.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          final expiry = product.trackExpiry
                              ? ' · Pantau kedaluwarsa'
                              : '';
                          final review = product.requiresReview
                              ? ' · PERLU TINJAU PPN'
                              : '';
                          final activeLabel = product.isActive ? '' : ' · NONAKTIF';
                          final syncLabel = product.syncStatus == 'needs_attention'
                              ? ' · KONFLIK SINKRONISASI'
                              : (product.syncStatus == null ? '' : ' · SINKRONISASI MENUNGGU');
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(product.nameId.isEmpty
                                    ? '?'
                                    : product.nameId[0].toUpperCase()),
                              ),
                              title: Text(product.nameId),
                              subtitle: Text(
                                product.sku + ' · Stok ' +
                                product.stockQty.toString() +
                                    expiry +
                                    review +
                                    activeLabel +
                                    syncLabel,
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') _edit(product);
                                  if (value == 'delete') _delete(product);
                                  if (value == 'toggle-status') {
                                    _changeActiveStatus(product);
                                  }
                                },
                                itemBuilder: (_) => <PopupMenuEntry<String>>[
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Ubah'),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle-status',
                                    child: Text(
                                      product.isActive ? 'Nonaktifkan' : 'Aktifkan kembali',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Hapus jika belum digunakan'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}

class _ProductEditor extends StatefulWidget {
  const _ProductEditor({
    this.existing,
    required this.expirySettingsEditable,
  });

  final Product? existing;
  final bool expirySettingsEditable;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _minimumShelfLife;
  bool _ppnExempt = false;
  bool _trackExpiry = false;
  bool _taxReviewConfirmed = false;

  @override
  void initState() {
    super.initState();
    final product = widget.existing;
    _name = TextEditingController(text: product?.nameId ?? '');
    _sku = TextEditingController(text: product?.sku ?? '');
    _barcode = TextEditingController(text: product?.barcode ?? '');
    _price = TextEditingController(text: product?.price.toString() ?? '');
    _minimumShelfLife = TextEditingController(
      text: product?.minShelfLifeDays.toString() ?? '0',
    );
    _ppnExempt = product?.ppnExempt ?? false;
    _trackExpiry = product?.trackExpiry ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _price.dispose();
    _minimumShelfLife.dispose();
    super.dispose();
  }

  String? _required(String? value, String label) =>
      value == null || value.trim().isEmpty ? '$label wajib diisi.' : null;

  String? _nonNegativeInt(String? value, String label) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) {
      return '$label harus angka 0 atau lebih.';
    }
    return null;
  }

  String? _positiveInt(String? value, String label) {
    final parsed = int.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) {
      return '$label harus lebih dari 0.';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final existing = widget.existing;
    final shelfLife = int.parse(_minimumShelfLife.text.trim());
    Navigator.pop(
      context,
      Product(
        id: existing?.id ??
            'product-' + DateTime.now().microsecondsSinceEpoch.toString(),
        sku: _sku.text.trim(),
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        nameId: _name.text.trim(),
        price: int.parse(_price.text.trim()),
        ppnExempt: _ppnExempt,
        // Stock is changed only by inventory receipt/checkout records.
        stockQty: existing?.stockQty ?? 0,
        trackExpiry: _trackExpiry,
        minShelfLifeDays: _trackExpiry ? shelfLife : 0,
        requiresReview: existing?.requiresReview == true &&
            !_taxReviewConfirmed,
        isActive: existing?.isActive ?? true,
        version: existing?.version ?? 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Tambah produk' : 'Ubah produk'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nama produk'),
                  validator: (value) => _required(value, 'Nama produk'),
                  textCapitalization: TextCapitalization.words,
                ),
                TextFormField(
                  controller: _sku,
                  decoration: const InputDecoration(labelText: 'SKU unik'),
                  validator: (value) => _required(value, 'SKU'),
                  textCapitalization: TextCapitalization.characters,
                ),
                TextFormField(
                  controller: _barcode,
                  decoration: const InputDecoration(
                    labelText: 'Barcode (opsional)',
                  ),
                ),
                TextFormField(
                  controller: _price,
                  decoration: const InputDecoration(
                    labelText: 'Harga jual (Rupiah)',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) => _positiveInt(value, 'Harga'),
                ),
                if (widget.existing?.requiresReview == true) ...<Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Produk ini diimpor dari aplikasi trial. Data lama tidak '
                      'menyimpan klasifikasi PPN di format POS baru. Periksa '
                      'nama, SKU, harga jual, dan status PPN sebelum '
                      'mengaktifkannya untuk checkout.',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _taxReviewConfirmed,
                    onChanged: (value) => setState(
                      () => _taxReviewConfirmed = value ?? false,
                    ),
                    title: const Text(
                      'Saya sudah memeriksa nama, SKU, harga, dan status PPN',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _ppnExempt,
                  onChanged: (value) => setState(() => _ppnExempt = value),
                  title: const Text('Bebas PPN'),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _trackExpiry,
                  onChanged: widget.expirySettingsEditable
                      ? (value) => setState(() => _trackExpiry = value)
                      : null,
                  title: const Text('Lacak tanggal kedaluwarsa'),
                  subtitle: widget.expirySettingsEditable
                      ? null
                      : const Text(
                          'Tidak dapat diubah setelah lot persediaan dibuat.',
                        ),
                ),
                if (_trackExpiry && widget.expirySettingsEditable)
                  TextFormField(
                    controller: _minimumShelfLife,
                    decoration: const InputDecoration(
                      labelText: 'Minimal sisa masa simpan (hari)',
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) =>
                        _nonNegativeInt(value, 'Sisa masa simpan'),
                  )
                else if (_trackExpiry)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Minimal sisa masa simpan'),
                    subtitle: Text(
                      _minimumShelfLife.text + ' hari (tetap untuk lot yang ada)',
                    ),
                  ),
                if (widget.existing == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Stok awal harus dicatat melalui menu Stok agar '
                      'lot persediaan dan biaya HPP tercatat dengan benar.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
