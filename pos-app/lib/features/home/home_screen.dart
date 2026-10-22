import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_identity_store.dart';
import '../../core/config/config_service.dart';
import '../../core/database/pos_database.dart';
import '../inventory/inventory_screen.dart';
import '../pos/checkout/payment_service.dart';
import '../pos/checkout/sqlite_sale_repository.dart';
import '../pos/checkout_screen.dart';
import '../products/product_screen.dart';
import '../products/repositories/sqlite_product_repository.dart';
import 'reports_screen.dart';

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
    this.configService,
    this.onSignOut,
  });

  final PosDatabase database;
  final AppIdentityStore identityStore;
  final ConfigService? configService;
  final Future<void> Function()? onSignOut;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final SqliteProductRepository _products;
  late final PaymentService _payments;
  int _selectedIndex = 0;
  int _refreshCounter = 0;
  final Set<int> _visitedIndices = <int>{0};

  static const _titles = <String>[
    'Beranda', 'Produk', 'Kasir', 'Stok', 'Laporan',
  ];

  @override
  void initState() {
    super.initState();
    _products = SqliteProductRepository(widget.database);
    _payments = PaymentService(
      repository: SqliteSaleRepository(widget.database),
    );
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
                  configService: widget.configService,
                  identityStore: widget.identityStore,
                  onSignOut: widget.onSignOut,
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
  });

  final PosDatabase database;
  final VoidCallback onOpenProducts;
  final VoidCallback onOpenCheckout;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenReports;

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
        _error = error.toString();
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
                    'Kasir local-first. Penjualan dan perubahan stok '
                    'tersimpan di perangkat ini; cloud sync menunggu layanan '
                    'terautentikasi yang belum terpasang.',
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
                  'Database lama tidak dihapus. Jangan menghapus data aplikasi. '
                  'Periksa penyebab lalu coba lagi. Detail: ' +
                  widget.database.legacyImportError!,
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
          const Card(
            child: ListTile(
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('Cloud sync belum aktif'),
              subtitle: Text(
                'Data perangkat bukan laporan konsolidasi. API Laravel, '
                'autentikasi dan sinkronisasi harus diuji sebelum SaaS '
                'multi-tenant digunakan.',
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
    required this.configService,
    required this.identityStore,
    this.onSignOut,
  });

  final ConfigService? configService;
  final AppIdentityStore identityStore;
  final Future<void> Function()? onSignOut;

  @override
  State<_ConfigurationScreen> createState() => _ConfigurationScreenState();
}

class _ConfigurationScreenState extends State<_ConfigurationScreen> {
  bool _loading = false;
  String? _status;
  Map<String, dynamic>? _configuration;
  TenantFeatures? _features;

  Future<void> _openExternal(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
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

  Future<void> _checkConfiguration() async {
    final service = widget.configService;
    if (service == null) {
      setState(() {
        _status = 'Central API belum tersedia pada build ini. '
            'Aplikasi tetap bisa bekerja lokal.';
      });
      return;
    }
    if (!service.hasAuthenticatedSession) {
      setState(() {
        _status = 'Akses cloud diblokir: belum ada sesi login yang '
            'terautentikasi. ID tenant/perangkat lokal bukan kredensial dan '
            'tidak menggantikan membership atau enrollment yang diverifikasi server.';
      });
      return;
    }
    final tenantId = widget.identityStore.tenantId.trim();
    final deviceId = widget.identityStore.deviceId.trim();
    if (tenantId.isEmpty || deviceId.isEmpty) {
      setState(() {
        _status = 'Tenant dan perangkat belum terdaftar oleh layanan '
            'enrollment. Hubungkan akun melalui alur enrollment resmi sebelum '
            'meminta konfigurasi cloud.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final config = await service.getEffectiveConfig(
        tenantId: tenantId,
        deviceId: deviceId,
        service: 'pos',
      );
      final features = TenantFeatures.fromEffectiveConfig(config.value);
      if (!mounted) return;
      setState(() {
        _configuration = config.value;
        _features = features;
        _status = config.fromCache
            ? 'Konfigurasi berasal dari cache lokal.'
            : 'Laravel Central API mengembalikan konfigurasi untuk sesi terverifikasi.';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Konfigurasi cloud tidak dapat diverifikasi. Periksa '
            'session autentikasi, enrollment device, dan konfigurasi environment. '
            'Detail: ' + error.toString();
        _loading = false;
      });
    }
  }

  String _effectiveMdr() {
    final configuration = _configuration;
    if (configuration == null) return '-';
    final rawConfig = configuration['config'];
    final effective = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig)
        : configuration;
    return (effective['mdr'] ?? effective['qris_mdr'] ?? '-').toString();
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
                  Text('Identitas lokal',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  const Text(
                    'ID lokal bukan kredensial login atau bukti kepemilikan '
                    'tenant. Jangan mengganti tenant/device untuk melewati '
                    'otorisasi server.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText('Tenant: ' +
                      (widget.identityStore.tenantId.isEmpty
                          ? 'Belum terdaftar'
                          : widget.identityStore.tenantId)),
                  SelectableText('Device: ' +
                      (widget.identityStore.deviceId.isEmpty
                          ? 'Belum terdaftar'
                          : widget.identityStore.deviceId)),
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
                  Text('Konfigurasi cloud',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Konfigurasi efektif mengikuti GLOBAL → TEMPLATE → '
                    'TENANT → SERVICE → DEVICE. Layanan cloud memerlukan '
                    'session yang sah dan device yang telah terdaftar.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _checkConfiguration,
                      icon: _loading
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.cloud_sync),
                      label: Text(_loading
                          ? 'Memeriksa...'
                          : 'Periksa konfigurasi'),
                    ),
                  ),
                  if (_status != null) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(_status!),
                  ],
                  if (_features != null) ...<Widget>[
                    const Divider(height: 24),
                    Text('POS aktif: ' + (_features!.pos ? 'Ya' : 'Tidak')),
                    Text('Akuntansi aktif: ' +
                        (_features!.akuntansi ? 'Ya' : 'Tidak')),
                  ],
                  if (_configuration != null) ...<Widget>[
                    const SizedBox(height: 8),
                    Text('MDR efektif POS: ' + _effectiveMdr()),
                  ],
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
                  subtitle: Text(
                    _salesWhatsAppNumber.trim().isEmpty
                        ? 'Nomor sales dapat dikonfigurasi saat build.'
                        : 'Minta informasi aktivasi atau paket berlangganan.',
                  ),
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
                  'Akhiri sesi akun ini pada perangkat. Data lokal tetap '
                  'tersimpan pada perangkat.',
                ),
                onTap: () async {
                  final signOut = widget.onSignOut;
                  Navigator.of(context).pop();
                  if (signOut != null) await signOut();
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
