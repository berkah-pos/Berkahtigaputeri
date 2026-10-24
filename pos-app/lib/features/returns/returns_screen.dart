import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/time/business_date.dart';
import 'returns_repository.dart';

class ReturnsScreen extends StatefulWidget {
  const ReturnsScreen({super.key, required this.repository});
  final ReturnsRepository repository;

  @override
  State<ReturnsScreen> createState() => _ReturnsScreenState();
}

class _ReturnsScreenState extends State<ReturnsScreen> {
  final _reasonController = TextEditingController();
  final Map<String, int> _quantities = <String, int>{};
  List<Map<String, Object?>> _sales = <Map<String, Object?>>[];
  List<Map<String, Object?>> _lots = <Map<String, Object?>>[];
  String? _selectedSaleId;
  String _returnType = 'return';
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
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final sales = await widget.repository.listReturnableSales();
      final lots = await widget.repository.listLotsForDisposition();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _lots = lots;
        if (_selectedSaleId == null || !sales.any((sale) => sale['id'] == _selectedSaleId)) {
          _selectedSaleId = sales.isEmpty ? null : sales.first['id']! as String;
        }
        if (sales.isEmpty) _returnType = 'return';
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = error.toString(); });
    }
  }

  Map<String, Object?>? get _selectedSale {
    for (final sale in _sales) {
      if (sale['id'] == _selectedSaleId) return sale;
    }
    return null;
  }

  List<Map<String, Object?>> get _selectedLines {
    final raw = _selectedSale?['items'];
    if (raw is! List) return const <Map<String, Object?>>[];
    return raw.cast<Map<String, Object?>>();
  }

  String _money(Object? value) {
    final amount = (value as num?)?.toInt() ?? 0;
    final digits = amount.toString();
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    return 'Rp $b';
  }

  Future<void> _submitReturn() async {
    final sale = _selectedSale;
    if (sale == null || _saving) return;
    final reason = _reasonController.text.trim();
    if (reason.isEmpty) { _message('Alasan retur wajib diisi.'); return; }
    final quantities = <String, int>{};
    for (final line in _selectedLines) {
      final id = line['id']! as String;
      final sold = (line['quantity']! as num).toInt();
      final returned = (line['returned_qty']! as num).toInt();
      final amount = _returnType == 'void' ? sold : (_quantities[id] ?? 0);
      if (amount > 0) {
        if (amount > sold - returned) { _message('Jumlah retur melebihi kuantitas yang tersisa.'); return; }
        quantities[id] = amount;
      }
    }
    if (quantities.isEmpty) { _message('Masukkan jumlah minimal satu barang yang akan diretur.'); return; }

    setState(() => _saving = true);
    try {
      final result = await widget.repository.processReturn(
        saleId: sale['id']! as String,
        quantities: quantities,
        type: _returnType == 'void' ? SaleReturnType.voidSale : SaleReturnType.returnItems,
        reason: reason,
      );
      _reasonController.clear();
      _quantities.clear();
      await _reload();
      _message(
        (result['already_processed'] == true ? 'Operasi sudah diproses. ' : 'Retur tersimpan. ') +
        'Refund ' + _money(result['refund_total']) + '; HPP ' + _money(result['cogs_amount']) +
        '. Barang yang kembali masuk karantina.',
      );
    } catch (error) {
      _message('Retur gagal: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'quarantine': return 'Karantina';
      case 'release_quarantine': return 'Lulus inspeksi → Saleable';
      case 'mark_damaged': return 'Tandai rusak';
      case 'mark_recall': return 'Tandai recall';
      case 'mark_expired': return 'Tandai kedaluwarsa';
      default: return action;
    }
  }

  List<String> _actionsFor(Map<String, Object?> lot) {
    final status = lot['status']! as String;
    final expiry = lot['expiry_date'] as String?;
    final date = BusinessDate.fromUtc(DateTime.now().toUtc());
    final actions = <String>[];
    if (status == 'saleable') actions.add('quarantine');
    if (status == 'quarantine') actions.add('release_quarantine');
    if (status == 'saleable' || status == 'quarantine') {
      actions.addAll(<String>['mark_damaged', 'mark_recall']);
      if (expiry != null && expiry.compareTo(date) < 0) actions.add('mark_expired');
    }
    return actions;
  }

  Future<void> _changeDisposition(Map<String, Object?> lot, String action) async {
    final reason = TextEditingController();
    final note = TextEditingController();
    var inspectionPassed = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_actionLabel(action)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text('Batch ' + (lot['batch_no'] ?? '').toString() + ' · ' + (lot['product_name'] ?? '').toString()),
                const SizedBox(height: 12),
                TextField(controller: reason, maxLength: 500, decoration: const InputDecoration(
                  labelText: 'Alasan wajib', border: OutlineInputBorder())),
                if (action == 'release_quarantine') ...<Widget>[
                  const SizedBox(height: 8),
                  TextField(controller: note, maxLength: 500, decoration: const InputDecoration(
                    labelText: 'Catatan inspeksi wajib', border: OutlineInputBorder())),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: inspectionPassed,
                    onChanged: (value) => setDialogState(() => inspectionPassed = value ?? false),
                    title: const Text('Saya telah memeriksa batch dan menyatakan lulus'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Batal')),
            FilledButton(
              onPressed: () {
                if (reason.text.trim().isEmpty ||
                    (action == 'release_quarantine' &&
                        (note.text.trim().isEmpty || !inspectionPassed))) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Catat'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) {
      reason.dispose();
      note.dispose();
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.adjustDisposition(
        lotId: lot['id']! as String, action: action, reason: reason.text.trim(),
        inspectionNote: action == 'release_quarantine' ? note.text.trim() : null,
        inspectionResult: action == 'release_quarantine' ? 'passed' : null,
      );
      await _reload();
      _message('Penyesuaian tersimpan dan masuk antrean sinkronisasi.');
    } catch (error) {
      _message('Penyesuaian gagal: $error');
    } finally {
      reason.dispose(); note.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text('Data retur/stok gagal dimuat: $_error'),
          TextButton(onPressed: _reload, child: const Text('Coba lagi')),
        ],
      );
    }
    return DefaultTabController(
      length: 2,
      child: Column(children: <Widget>[
        const TabBar(tabs: <Widget>[
          Tab(icon: Icon(Icons.assignment_return_outlined), text: 'Retur & void'),
          Tab(icon: Icon(Icons.fact_check_outlined), text: 'Karantina & stok'),
        ]),
        Expanded(child: TabBarView(children: <Widget>[_buildReturnPane(), _buildStockPane()])),
      ]),
    );
  }

  Widget _buildReturnPane() {
    final sale = _selectedSale;
    final hasPriorReturn = sale?['has_return'] == true;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('Full void membalik seluruh penjualan. Retur dapat mencakup sebagian kuantitas dan tidak boleh melebihi kuantitas yang belum diretur.'),
        const SizedBox(height: 12),
        if (_sales.isEmpty)
          const Card(child: ListTile(title: Text('Tidak ada penjualan yang masih dapat diretur.')))
        else ...<Widget>[
          DropdownButtonFormField<String>(
            initialValue: _selectedSaleId, isExpanded: true,
            decoration: const InputDecoration(labelText: 'Penjualan asal', border: OutlineInputBorder()),
            items: _sales.map((row) => DropdownMenuItem<String>(
              value: row['id']! as String,
              child: Text((row['transaction_id'] ?? '').toString() + ' · ' +
                  (row['business_date'] ?? '').toString() + ' · ' + _money(row['grand_total']),
              overflow: TextOverflow.ellipsis),
            )).toList(growable: false),
            onChanged: _saving ? null : (value) => setState(() {
              _selectedSaleId = value; _quantities.clear(); _returnType = 'return';
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _returnType,
            decoration: const InputDecoration(labelText: 'Jenis operasi', border: OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[
              const DropdownMenuItem(value: 'return', child: Text('Retur barang (penuh/sebagian)')),
              DropdownMenuItem(value: 'void', enabled: !hasPriorReturn,
                child: const Text('Void penuh seluruh penjualan')),
            ],
            onChanged: _saving ? null : (value) => setState(() {
              _returnType = value ?? 'return'; _quantities.clear();
            }),
          ),
          const SizedBox(height: 12),
          ..._selectedLines.map((line) {
            final id = line['id']! as String;
            final sold = (line['quantity']! as num).toInt();
            final returned = (line['returned_qty']! as num).toInt();
            final left = sold - returned;
            return Card(child: ListTile(
              title: Text((line['product_name'] ?? line['product_id']).toString()),
              subtitle: Text('Terjual $sold · Sudah diretur $returned · Tersisa $left · ' + _money(line['unit_price'])),
              trailing: _returnType == 'void'
                  ? Text(sold.toString(), style: Theme.of(context).textTheme.titleMedium)
                  : SizedBox(width: 88, child: TextFormField(
                      key: ValueKey<String>('return-qty-$id-$_selectedSaleId'),
                      initialValue: (_quantities[id] ?? 0).toString(),
                      enabled: !_saving && left > 0,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Jumlah'),
                      onChanged: (value) => _quantities[id] = int.tryParse(value) ?? 0,
                    )),
            ));
          }),
          const SizedBox(height: 8),
          TextField(controller: _reasonController, maxLength: 500, enabled: !_saving,
            decoration: const InputDecoration(labelText: 'Alasan retur/void (wajib)',
              alignLabelWithHint: true, border: OutlineInputBorder()),
            minLines: 2, maxLines: 3),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _saving || sale == null ? null : _submitReturn,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline),
            label: Text(_saving ? 'Menyimpan…' : (_returnType == 'void' ? 'Void seluruh penjualan' : 'Simpan retur')),
          ),
          const SizedBox(height: 8),
          Text('Self-approval aktif sesuai kebijakan owner. Barang yang kembali selalu masuk karantina; retur tidak otomatis menjadi stok saleable.',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }

  Widget _buildStockPane() {
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        const Text('Perubahan status tidak mengubah kuantitas atau membuat jurnal. Koreksi jumlah/write-off diblokir sampai akun lawan yang disetujui tersedia.'),
        const SizedBox(height: 12),
        if (_lots.isEmpty) const Card(child: ListTile(title: Text('Belum ada lot persediaan.'))),
        ..._lots.map((lot) {
          final actions = _actionsFor(lot);
          return Card(child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text((lot['product_name'] ?? '').toString(), style: Theme.of(context).textTheme.titleMedium),
              Text('Batch ' + (lot['batch_no'] ?? '').toString() + ' · Lot ' + (lot['id'] ?? '').toString()),
              Text('Status ' + (lot['status'] ?? '').toString() +
                ' · Fisik ' + (lot['on_hand_qty'] ?? 0).toString() +
                ' · Reservasi ' + (lot['reserved_qty'] ?? 0).toString() +
                ' · Expiry ' + (lot['expiry_date'] ?? '—').toString()),
              if (actions.isNotEmpty) Wrap(
                spacing: 8, runSpacing: 4,
                children: actions.map((action) => OutlinedButton(
                  onPressed: _saving ? null : () => _changeDisposition(lot, action),
                  child: Text(_actionLabel(action)),
                )).toList(growable: false),
              ),
            ]),
          ));
        }),
      ]),
    );
  }
}
