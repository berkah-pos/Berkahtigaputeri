import 'package:flutter/material.dart';

import '../../core/database/pos_database.dart';

/// Local sales report. Values are device-local until a cloud sync service
/// acknowledges the pending outbox events.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.database,
    this.cloudSyncConfigured = false,
    this.cloudSyncStatus = 'Data laporan ini berasal dari perangkat lokal.',
  });

  final PosDatabase database;
  final bool cloudSyncConfigured;
  final String cloudSyncStatus;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Map<String, Object?> _summary = const <String, Object?>{};
  List<Map<String, Object?>> _recent = const <Map<String, Object?>>[];
  Map<String, Object?> _legacySummary = const <String, Object?>{};
  List<Map<String, Object?>> _legacyRecent = const <Map<String, Object?>>[];
  int _pendingSync = 0;
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
      final db = widget.database.database;
      final summary = (await db.rawQuery(
        '''
        SELECT
          COUNT(*) AS sale_count,
          COALESCE(SUM(grand_total), 0) AS revenue,
          COALESCE(SUM(cogs_amount), 0) AS cogs
        FROM sales
        ''',
      )).single;
      final recent = await db.query(
        'sales',
        columns: <String>[
          'id',
          'transaction_id',
          'business_date',
          'grand_total',
          'payment_method',
          'created_at_utc',
        ],
        orderBy: 'created_at_utc DESC',
        limit: 25,
      );
      final legacySummary = (await db.rawQuery(
        '''
        SELECT COUNT(*) AS sale_count,
               COALESCE(SUM(total_amount), 0) AS revenue
        FROM legacy_sales_archive
        '''
      )).single;
      final legacyRecent = await db.query(
        'legacy_sales_archive',
        columns: <String>[
          'original_sale_id',
          'total_amount',
          'item_count',
          'email',
          'created_at',
        ],
        orderBy: 'created_at DESC, original_sale_id DESC',
        limit: 25,
      );
      final pending = (await db.rawQuery(
        "SELECT COUNT(*) AS value FROM outbox_events WHERE status <> 'acknowledged'",
      )).single['value']! as int;
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _recent = recent;
        _legacySummary = legacySummary;
        _legacyRecent = legacyRecent;
        _pendingSync = pending;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  int _intValue(String key) => (_summary[key] as num?)?.toInt() ?? 0;

  int _intValueFrom(Map<String, Object?> source, String key) =>
      (source[key] as num?)?.toInt() ?? 0;

  String _money(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) buffer.write('.');
      buffer.write(digits[index]);
    }
    return 'Rp ' + buffer.toString();
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
          Text('Laporan gagal dimuat: ' + _error!),
          TextButton(onPressed: _reload, child: const Text('Coba lagi')),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _MetricCard(
                label: 'Transaksi lokal',
                value: _intValue('sale_count').toString(),
                icon: Icons.receipt_long,
              ),
              _MetricCard(
                label: 'Penjualan lokal',
                value: _money(_intValue('revenue')),
                icon: Icons.payments_outlined,
              ),
              _MetricCard(
                label: 'HPP lokal',
                value: _money(_intValue('cogs')),
                icon: Icons.inventory_2_outlined,
              ),
              _MetricCard(
                label: 'Belum sinkron',
                value: _pendingSync.toString(),
                icon: Icons.sync_problem,
                warning: _pendingSync > 0,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                _pendingSync == 0 ? Icons.cloud_done : Icons.cloud_off,
              ),
              title: Text(
                _pendingSync == 0
                    ? 'Tidak ada event tertunda'
                    : '$_pendingSync event menunggu sinkronisasi',
              ),
              subtitle: Text(
                cloudSyncConfigured
                    ? cloudSyncStatus
                    : 'Angka di atas adalah data lokal. Event hanya menjadi data cloud '
                        'setelah server mengembalikan receipt. ' + cloudSyncStatus,
              ),
              trailing: IconButton(
                tooltip: 'Muat ulang',
                onPressed: _reload,
                icon: const Icon(Icons.refresh),
              ),
            ),
          ),
          if (_intValueFrom(_legacySummary, 'sale_count') > 0) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              'Arsip riwayat dari aplikasi trial',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            const Text(
              'Data ini dipertahankan dari database lama dan ditampilkan '
              'terpisah. Skema trial tidak memiliki rincian pajak, metode '
              'pembayaran, biaya perolehan, atau jurnal lengkap; arsip ini '
              'bukan laporan akuntansi terverifikasi dan tidak akan dihitung '
              'ke dalam total transaksi aktif.',
            ),
            const SizedBox(height: 8),
            _MetricCard(
              label: 'Transaksi trial (arsip)',
              value: _intValueFrom(_legacySummary, 'sale_count').toString(),
              icon: Icons.history,
            ),
            _MetricCard(
              label: 'Total trial (arsip)',
              value: _money(_intValueFrom(_legacySummary, 'revenue')),
              icon: Icons.archive_outlined,
            ),
            ..._legacyRecent.map((sale) {
              final originalId =
                  (sale['original_sale_id'] as num?)?.toInt() ?? 0;
              final amount =
                  (sale['total_amount'] as num?)?.toInt() ?? 0;
              final itemCount =
                  (sale['item_count'] as num?)?.toInt() ?? 0;
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('TRIAL-$originalId'),
                  subtitle: Text(
                    (sale['created_at'] ?? '').toString() +
                    ' · $itemCount item · arsip trial',
                  ),
                  trailing: Text(_money(amount)),
                ),
              );
            }),
          ],
          const SizedBox(height: 16),
          Text(
            'Transaksi terbaru',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_recent.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Belum ada transaksi.'),
              ),
            ),
          ..._recent.map((sale) {
            final amount = (sale['grand_total'] as num?)?.toInt() ?? 0;
            final payment = (sale['payment_method'] ?? '').toString();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long),
                title: Text((sale['transaction_id'] ?? '').toString()),
                subtitle: Text(
                  (sale['business_date'] ?? '').toString() + ' · ' + payment,
                ),
                trailing: Text(_money(amount)),
              ),
            );
          }),
          const SizedBox(height: 12),
          Text(
            'Nilai laporan ini berasal dari SQLite pada perangkat ini. '
            'Jangan gunakan sebagai laporan konsolidasi multi-device sampai '
            'transaksi disinkronkan dan direkonsiliasi di server.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.warning = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: warning ? Colors.orange : null),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
