import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/laravel_auth_service.dart';
import '../../core/config/app_identity_store.dart';
import '../../core/config/config_failure_message.dart';
import '../../core/database/pos_database.dart';
import '../../core/sync/outbox_sync_service.dart';
import '../../core/sync/sync_failure_message.dart';
import '../inventory/inventory_screen.dart';
import '../pos/checkout/payment_service.dart';
import '../pos/checkout/sqlite_sale_repository.dart';
import '../pos/checkout_screen.dart';
import '../products/product_screen.dart';
import '../products/repositories/sqlite_product_repository.dart';
import 'legacy_import_failure_message.dart';
import 'reports_screen.dart';
import '../returns/returns_repository.dart';
import '../returns/returns_screen.dart';

const String _salesWhatsAppNumber = String.fromEnvironment(
  'BERKAH_WHATSAPP_NUMBER',
  defaultValue: '',
);
const String _privacyUrl = 'https://berkahtigaputeri.co.id/privacy';
const String _deleteAccountUrl = 'https://berkahtigaputeri.co.id/delete-account';

/// Canonical combined app shell. The trial app's everyday POS flows use the
/// stronger local inventory/accounting services from pos-app.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.database,
    required this.identityStore,
    this.authService,
    this.onSignOut,
    this.onReturnToCloudLogin,
    this.cloudApiConfigured = false,
    this.actorId = '',
  });

  final PosDatabase database;
  final AppIdentityStore identityStore;
  final LaravelAuthService? authService;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onReturnToCloudLogin;
  final bool cloudApiConfigured;
  final String actorId;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SqliteProductRepository _products;
  late final PaymentService _payments;
  int _selectedIndex = 0;
  int _refreshCounter = 0;
  final Set<int> _visitedIndices = <int>{0};
  OutboxSyncService? _syncService;
  bool _syncing = false;
  String? _syncMessage;

  static const _titles = <String>[
    'Beranda', 'Produk', 'Kasir', 'Stok', 'Laporan', 'Retur',
  ];

  @override
  void initState() {
    super.initState();
    _products = SqliteProductRepository(widget.database);
    _payments = PaymentService(
      repository: SqliteSaleRepository(widget.database),
    );
    final authService = widget.authService;
    if (authService != null) {
      _syncService = OutboxSyncService(
        database: widget.database,
        authService: authService,
        appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: 'unknown'),
      );
    }
  }

  Future<void> _runOutboxSync() async {
    final service = _syncService;
    if (service == null || _syncing) return;
    setState(() {
      _syncing = true;
      _syncMessage = null;
    });
    try {
      final report = await service.syncPending();
      if (mounted) setState(() => _syncMessage = report.summary);
    } catch (error) {
      if (mounted) {
        setState(() => _syncMessage = safeSyncFailureMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _syncing = false;
          _refreshCounter++;
        });
      }
    }
  }

  void _refreshLocalViews() {
    setState(() => _refreshCounter++);
  }

  void _selectTab(int index) {
    setState(() {
      _selectedIndex = index;
      _visitedIndices.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Build tab content only after its first visit. This avoids starting
    // multiple database reads and loading animations for off-screen tabs.
    final tabPages = List<Widget>.generate(_titles.length, (index) {
      if (!_visitedIndices.contains(index)) {
        return const SizedBox.shrink();
      }
      switch (index) {
        case 0:
          return _DashboardScreen(
            key: ValueKey<String>('dashboard-$_refreshCounter'),
            database: widget.database,
            onOpenProducts: () => _selectTab(1),
            onOpenCheckout: () => _selectTab(2),
            onOpenInventory: () => _selectTab(3),
            onOpenReports: () => _selectTab(4),
            syncEnabled: _syncService != null,
            isSyncing: _syncing,
            syncMessage: _syncMessage,
            onSync: _syncService == null ? null : _runOutboxSync,
          );
        case 1:
          return ProductScreen(
            key: ValueKey<String>('products-$_refreshCounter'),
            repository: _products,
            onChanged: _refreshLocalViews,
          );
        case 2:
          return CheckoutScreen(
            productsRepository: _products,
            paymentService: _payments,
            onSaleSaved: _refreshLocalViews,
          );
        case 3:
          return InventoryScreen(
            key: ValueKey<String>('inventory-$_refreshCounter'),
            repository: _products,
            onChanged: _refreshLocalViews,
          );
        case 4:
          return ReportsScreen(
            key: ValueKey<String>('reports-$_refreshCounter'),
            database: widget.database,
            authService: widget.authService,
          );
        case 5:
          return ReturnsScreen(
            key: ValueKey<String>('returns-$_refreshCounter'),
            repository: ReturnsRepository(
              database: widget.database,
              actorId: widget.actorId,
              deviceId: widget.identityStore.deviceId,
            ),
          );
        default:
          return const SizedBox.shrink();
      }
    });
    final pages = List<Widget>.generate(tabPages.length, (index) {
      if (!_visitedIndices.contains(index)) return tabPages[index];
      return TickerMode(
        enabled: index == _selectedIndex,
        child: tabPages[index],
      );
    });


    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Berkah Tiga Puteri POS'),
            Text(
              _titles[_selectedIndex] + ' · Data lokal',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pengaturan tenant dan cloud',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => _ConfigurationScreen(
                  identityStore: widget.identityStore,
                  authService: widget.authService,
                  onSignOut: widget.onSignOut,
                  onReturnToCloudLogin: widget.onReturnToCloudLogin,
                  cloudApiConfigured: widget.cloudApiConfigured,
                ),
              ),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _selectTab,
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Produk',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Kasir',
          ),
          NavigationDestination(
            icon: Icon(Icons.warehouse_outlined),
            selectedIcon: Icon(Icons.warehouse),
            label: 'Stok',
          ),
          NavigationDestination(
            icon: Icon(Icons.assessment_outlined),
            selectedIcon: Icon(Icons.assessment),
            label: 'Laporan',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_return_outlined),
            selectedIcon: Icon(Icons.assignment_return),
            label: 'Retur',
          ),
        ],
      ),
    );
  }
}

class _DashboardScreen extends StatefulWidget {
  const _DashboardScreen({
    super.key,
    required this.database,
    required this.onOpenProducts,
    required this.onOpenCheckout,
    required this.onOpenInventory,
    required this.onOpenReports,
    required this.syncEnabled,
    required this.isSyncing,
    required this.onSync,
    this.syncMessage,
  });

  final PosDatabase database;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenCheckout;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenReports;
  final bool syncEnabled;
  final bool isSyncing;
  final VoidCallback? onSync;
  final String? syncMessage;

  @override
  State<_DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<_DashboardScreen> {
  Map<String, Object?> _summary = const <String, Object?>{};
  int _products = 0;
  int _pending = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final db = widget.database.database;
      final summary = (await db.rawQuery(
        'SELECT COUNT(*) AS sale_count, '
        'COALESCE(SUM(grand_total), 0) AS revenue FROM sales',
      )).single;
      final productCount =
          (await db.rawQuery('SELECT COUNT(*) AS value FROM products'))
              .single['value']! as int;
      final pendingCount = (await db.rawQuery(
        "SELECT COUNT(*) AS value FROM outbox_events WHERE status <> 'acknowledged'",
      )).single['value']! as int;
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _products = productCount;
        _pending = pendingCount;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Data lokal belum dapat dibaca. Periksa penyimpanan perangkat, lalu coba lagi.';
        _loading = false;
      });
    }
  }

  Future<void> _retryLegacyImport() async {
    setState(() => _loading = true);
    try {
      await widget.database.retryLegacyTrialImport();
    } catch (_) {
      // The database stores the error and the UI keeps the recovery warning.
    }
    await _reload();
  }

  int _number(String key) => (_summary[key] as num?)?.toInt() ?? 0;

  String _money(int amount) {
    final digits = amount.toString();
    final output = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && (digits.length - index) % 3 == 0) output.write('.');
      output.write(digits[index]);
    }
    return 'Rp ' + output.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text('Dashboard gagal dimuat: ' + _error!),
          TextButton(onPressed: _reload, child: const Text('Coba lagi')),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Selamat datang di Berkah POS',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kasir local-first. Perubahan katalog, penerimaan stok, dan transaksi '
                    'disimpan bersama antrean sinkronisasi di perangkat ini.',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.icon(
                        onPressed: widget.onOpenCheckout,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Buka kasir'),
                      ),
                      OutlinedButton.icon(
                        onPressed: widget.onOpenProducts,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Produk'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (widget.database.legacyImportError != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: const Text('Impor data trial belum selesai'),
                subtitle: Text(
                  safeLegacyImportFailureMessage(
                    widget.database.legacyImportError,
                  ),
                ),
                isThreeLine: true,
                trailing: IconButton(
                  tooltip: 'Coba impor lagi',
                  onPressed: _retryLegacyImport,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: <Widget>[
              _DashboardMetric(label: 'Produk', value: _products.toString(),
                  icon: Icons.inventory_2_outlined),
              _DashboardMetric(label: 'Transaksi lokal',
                  value: _number('sale_count').toString(),
                  icon: Icons.receipt_long),
              _DashboardMetric(label: 'Penjualan lokal',
                  value: _money(_number('revenue')),
                  icon: Icons.payments_outlined),
              _DashboardMetric(label: 'Antrean tertunda',
                  value: _pending.toString(), icon: Icons.sync_problem,
                  warning: _pending > 0),
            ],
          ),
          const SizedBox(height: 12),
          Text('Operasi', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.add_box_outlined),
                  title: const Text('Terima stok'),
                  subtitle: const Text('Lot, batch, biaya dan expiry/FEFO'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenInventory,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.assessment_outlined),
                  title: const Text('Laporan lokal'),
                  subtitle: const Text('Penjualan, HPP dan status outbox'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenReports,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.syncEnabled
                        ? 'Sinkronisasi antrean lokal'
                        : 'Sinkronisasi cloud belum aktif',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.syncEnabled
                        ? 'Kirim perubahan melalui sesi Laravel yang terautentikasi. '
                            'Event diakui hanya setelah server mengembalikan receipt; '
                            'konflik memerlukan tinjauan.'
                        : 'Data tetap tersimpan lokal. Masuk dengan akun cloud dan perangkat '
                            'yang disetujui untuk mengirim antrean ke API Laravel.',
                  ),
                  if (widget.syncEnabled) ...<Widget>[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.isSyncing ? null : widget.onSync,
                      icon: widget.isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(widget.isSyncing ? 'Menyinkronkan…' : 'Sinkronkan sekarang'),
                    ),
                  ],
                  if (widget.syncMessage != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(widget.syncMessage!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardMetric extends StatelessWidget {
  const _DashboardMetric({
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
              const SizedBox(height: 8),
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

class _ConfigurationScreen extends StatefulWidget {
  const _ConfigurationScreen({
    required this.identityStore,
    this.authService,
    this.onSignOut,
    this.onReturnToCloudLogin,
    this.cloudApiConfigured = false,
  });

  final AppIdentityStore identityStore;
  final LaravelAuthService? authService;
  final Future<void> Function()? onSignOut;
  final VoidCallback? onReturnToCloudLogin;
  final bool cloudApiConfigured;

  @override
  State<_ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<_ConfigurationScreen> {
  bool _configLoading = false;
  String? _configError;
  EffectiveConfigSnapshot? _cloudConfiguration;

  Future<void> _refreshCloudConfiguration(String service) async {
    final authService = widget.authService;
    if (authService == null) return;

    setState(() {
      _configLoading = true;
      _configError = null;
      _cloudConfiguration = null;
    });

    try {
      final snapshot = await authService.fetchEffectiveConfig(service: service);
      if (snapshot.tenantId != widget.identityStore.tenantId ||
          snapshot.deviceId != widget.identityStore.deviceId) {
        throw const AuthFailure(
          message: 'Identitas konfigurasi server tidak cocok dengan perangkat ini.',
          code: 'identity_mismatch',
          statusCode: 403,
        );
      }
      if (!mounted) return;
      setState(() => _cloudConfiguration = snapshot);
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _cloudConfiguration = null;
        _configError = safeConfigFailureMessage(failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cloudConfiguration = null;
        _configError = 'Konfigurasi server tidak dapat diverifikasi saat ini.';
      });
    } finally {
      if (mounted) setState(() => _configLoading = false);
    }
  }

  Future<void> _openExternal(String url) async {
    try {
      final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tautan tidak dapat dibuka.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tautan tidak dapat dibuka.')),
      );
    }
  }

  Future<void> _contactSales() async {
    final phone = _salesWhatsAppNumber.replaceAll(RegExp('[^0-9]'), '');
    final link = phone.isEmpty
        ? Uri.https('wa.me', '/', <String, String>{
            'text': 'Halo tim Berkah POS, saya ingin informasi aktivasi.',
          })
        : Uri.https('wa.me', '/$phone', <String, String>{
            'text': 'Halo tim Berkah POS, saya ingin informasi aktivasi.',
          });
    await _openExternal(link.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Identitas lokal', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const Text(
                    'ID tenant/perangkat yang tersimpan lokal bukan bukti autentikasi '
                    'atau izin akses. Server harus memverifikasi membership dan perangkat.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText('Tenant: ' + (widget.identityStore.tenantId.isEmpty
                      ? 'Belum terdaftar' : widget.identityStore.tenantId)),
                  SelectableText('Device: ' + (widget.identityStore.deviceId.isEmpty
                      ? 'Belum terdaftar' : widget.identityStore.deviceId)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Konfigurasi cloud', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Kontrak konfigurasi menggunakan GLOBAL → TEMPLATE → TENANT → SERVICE → DEVICE. '
                    'Permintaan konfigurasi mengambil satu layanan dari API Laravel yang memverifikasi '
                    'sesi, tenant, perangkat, langganan, dan versi konfigurasi. Sinkronisasi transaksi '
                    'dan laporan lintas perangkat tetap merupakan workstream terpisah.',
                  ),
                  const SizedBox(height: 12),
                  if (widget.authService?.isConfigured == true) ...<Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _configLoading
                                ? null
                                : () => _refreshCloudConfiguration('pos'),
                            icon: const Icon(Icons.point_of_sale_outlined),
                            label: const Text('Muat POS'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _configLoading
                                ? null
                                : () => _refreshCloudConfiguration('akuntansi'),
                            icon: const Icon(Icons.account_balance_outlined),
                            label: const Text('Muat Akuntansi'),
                          ),
                        ),
                      ],
                    ),
                    if (_configLoading) ...<Widget>[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_configError != null) ...<Widget>[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.cloud_off_outlined),
                        title: const Text('Konfigurasi belum diterima'),
                        subtitle: Text(_configError!),
                      ),
                    ],
                    if (_cloudConfiguration != null) ...<Widget>[
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.verified_outlined),
                        title: Text('Konfigurasi ${_cloudConfiguration!.service.toUpperCase()} diterima'),
                        subtitle: Text(
                          'Versi: ${_cloudConfiguration!.version}\n'
                          'Tenant: ${_cloudConfiguration!.tenantId}\n'
                          'Perangkat: ${_cloudConfiguration!.deviceId}',
                        ),
                      ),
                      SelectableText('SHA-256: ${_cloudConfiguration!.hash}'),
                    ],
                  ] else if (widget.cloudApiConfigured)
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('Mode lokal aktif; sesi cloud tidak aktif'),
                      subtitle: Text(
                        'API cloud sudah dikonfigurasi, tetapi akses cloud dinonaktifkan '
                        'dalam mode ini. Kembali ke login cloud untuk memulihkan sesi. '
                        'Penjualan tetap tersimpan lokal dan tidak otomatis tersinkron.',
                      ),
                    )
                  else
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text('API cloud belum dikonfigurasi'),
                      subtitle: Text(
                        'Bangun aplikasi dengan BERKAH_API_BASE_URL HTTPS. '
                        'Data penjualan lokal tetap tersimpan di SQLite dan tidak otomatis tersinkron.',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Kebijakan Privasi'),
                  subtitle: const Text('Buka kebijakan privasi Berkah POS'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternal(_privacyUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined),
                  title: const Text('Permintaan Hapus Akun'),
                  subtitle: const Text(
                    'Buka halaman resmi dan ikuti proses yang disediakan. '
                    'Permintaan ini tidak menghapus akun dari aplikasi secara langsung.',
                  ),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openExternal(_deleteAccountUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Hubungi Sales via WhatsApp'),
                  subtitle: Text(_salesWhatsAppNumber.trim().isEmpty
                      ? 'Nomor sales dapat dikonfigurasi saat build.'
                      : 'Minta informasi aktivasi atau paket berlangganan.'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: _contactSales,
                ),
              ],
            ),
          ),
          if (widget.onSignOut != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Keluar dari akun cloud'),
                subtitle: const Text(
                  'Akhiri sesi akun ini pada perangkat. Data lokal tetap tersimpan.',
                ),
                onTap: () async {
                  final signOut = widget.onSignOut;
                  Navigator.of(context).pop();
                  if (signOut != null) await signOut();
                },
              ),
            ),
          ],
          if (widget.onReturnToCloudLogin != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Kembali ke login cloud'),
                subtitle: const Text(
                  'Keluar dari mode lokal untuk membuka kembali login. '
                  'Akses cloud hanya aktif setelah sesi diverifikasi server.',
                ),
                onTap: () {
                  final returnToLogin = widget.onReturnToCloudLogin;
                  Navigator.of(context).pop();
                  returnToLogin?.call();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
