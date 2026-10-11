import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const String companyName = 'PT Berkah Tiga Puteri';
const String appName = 'Berkah POS';
const String deleteAccountUrl = 'https://berkahtigaputeri.co.id/delete-account';
const String privacyUrl = 'https://berkahtigaputeri.co.id/privacy';
const String subscriptionStatusUrl = 'https://api.berkahtigaputeri.co.id/check-status';
const String _salesWhatsAppNumber = String.fromEnvironment('SALES_WHATSAPP_NUMBER', defaultValue: '');
const int localTrialDurationDays = 14;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalDatabase.instance.database;
  runApp(const BerkahPosApp());
}

class BerkahPosApp extends StatelessWidget {
  const BerkahPosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F5B)),
      scaffoldBackgroundColor: const Color(0xFFF7F9F8),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE7ECE9)),
        ),
      ),
    ),
    home: const AppRoot(),
  );
}

enum AccessStatus { active, trial, inactive }

class AccessResult {
  const AccessResult(this.status, {this.trialDaysRemaining = localTrialDurationDays});
  final AccessStatus status;
  final int trialDaysRemaining;
}

class SubscriptionService {
  static Future<AccessResult> check(String email, SharedPreferences prefs) async {
    try {
      final uri = Uri.parse(subscriptionStatusUrl).replace(
        queryParameters: {'email': email.trim().toLowerCase()},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      final decoded = jsonDecode(response.body);
      final successful = response.statusCode >= 200 && response.statusCode < 300;
      if (decoded is Map<String, dynamic>) {
        final status = (decoded['status'] ?? decoded['subscription_status'] ?? '').toString().toLowerCase();
        if (status == 'inactive' || status == 'expired' || status == 'suspended' || decoded['active'] == false) {
          return const AccessResult(AccessStatus.inactive, trialDaysRemaining: 0);
        }
        if (successful && (status == 'active' || decoded['active'] == true)) {
          return const AccessResult(AccessStatus.active);
        }
        if (successful && status == 'trial') return const AccessResult(AccessStatus.trial);
      }
    } catch (_) {
      // When the status API is unavailable, only a bounded local trial is available.
    }
    return _localTrial(email, prefs);
  }

  static Future<AccessResult> _localTrial(String email, SharedPreferences prefs) async {
    final key = 'trial_started_at_${email.trim().toLowerCase()}';
    var startedAt = prefs.getString(key);
    if (startedAt == null) {
      startedAt = DateTime.now().toUtc().toIso8601String();
      await prefs.setString(key, startedAt);
    }
    final start = DateTime.tryParse(startedAt)?.toLocal();
    if (start == null) return const AccessResult(AccessStatus.inactive, trialDaysRemaining: 0);
    final elapsed = DateTime.now().difference(start);
    final remaining = localTrialDurationDays - elapsed.inDays;
    if (elapsed.isNegative || remaining > 0) {
      return AccessResult(AccessStatus.trial, trialDaysRemaining: remaining.clamp(1, localTrialDurationDays).toInt());
    }
    return const AccessResult(AccessStatus.inactive, trialDaysRemaining: 0);
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  String? _email;
  AccessResult? _access;
  bool _loading = false;
  String? _error;

  Future<void> _login(String email) async {
    setState(() { _loading = true; _error = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      final access = await SubscriptionService.check(email, prefs);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _email = email.trim().toLowerCase();
        _access = access;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Tidak dapat memeriksa status akun. Silakan coba lagi.'; });
    }
  }

  void _logout() => setState(() { _email = null; _access = null; _error = null; });

  @override
  Widget build(BuildContext context) {
    if (_email != null && _access != null) {
      if (_access!.status == AccessStatus.inactive) return AccessRequiredPage(email: _email!, onLogout: _logout);
      return PosHomePage(email: _email!, access: _access!, onLogout: _logout);
    }
    return LoginPage(onLogin: _login, loading: _loading, error: _error);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onLogin, required this.loading, required this.error, super.key});
  final Future<void> Function(String) onLogin;
  final bool loading;
  final String? error;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  @override
  void dispose() { _email.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.point_of_sale, size: 64, color: Color(0xFF087F5B)),
                      const SizedBox(height: 12),
                      Text(appName, style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                      Text(companyName, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      const Text('Masuk dengan email untuk memeriksa akses aplikasi.'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ? null : 'Masukkan alamat email yang valid.';
                        },
                      ),
                      if (widget.error != null) ...[
                        const SizedBox(height: 12),
                        Text(widget.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: widget.loading ? null : () {
                          if (_formKey.currentState!.validate()) widget.onLogin(_email.text);
                        },
                        child: widget.loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Lanjutkan'),
                      ),
                      const SizedBox(height: 16),
                      Text('Trial lokal hingga 14 hari hanya fallback jika layanan status tidak dapat dihubungi.', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AccessRequiredPage extends StatelessWidget {
  const AccessRequiredPage({required this.email, required this.onLogout, super.key});
  final String email;
  final VoidCallback onLogout;

  Future<void> _contactSales() async {
    final message = Uri.encodeComponent('Halo PT Berkah Tiga Puteri, saya ingin mengaktifkan Berkah POS. Email: $email');
    final target = _salesWhatsAppNumber.isNotEmpty
        ? Uri.parse('https://wa.me/$_salesWhatsAppNumber?text=$message')
        : Uri.parse('https://wa.me/?text=$message');
    await launchUrl(target, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Aktivasi diperlukan')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 56),
              const SizedBox(height: 16),
              Text('Akses belum aktif', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Status untuk $email belum aktif. Hubungi tim Berkah POS untuk bantuan aktivasi.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: _contactSales, icon: const Icon(Icons.chat), label: const Text('Hubungi WhatsApp')),
              TextButton(onPressed: onLogout, child: const Text('Gunakan email lain')),
            ],
          ),
        ),
      ),
    ),
  );
}

class PosHomePage extends StatefulWidget {
  const PosHomePage({required this.email, required this.access, required this.onLogout, super.key});
  final String email;
  final AccessResult access;
  final VoidCallback onLogout;
  @override
  State<PosHomePage> createState() => _PosHomePageState();
}

class _PosHomePageState extends State<PosHomePage> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [DashboardPage(access: widget.access), const ProductsPage(), const CheckoutPage(), const SalesHistoryPage(), const SettingsPage()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Berkah POS'),
        actions: [
          Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(widget.email, style: Theme.of(context).textTheme.labelSmall))),
          IconButton(tooltip: 'Keluar', onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
        ],
      ),
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Ringkasan'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Produk'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), selectedIcon: Icon(Icons.point_of_sale), label: 'Kasir'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Transaksi'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.access, super.key});
  final AccessResult access;
  @override
  Widget build(BuildContext context) => FutureBuilder<DashboardStats>(
    future: LocalDatabase.instance.dashboardStats(),
    builder: (context, snapshot) {
      final stats = snapshot.data ?? const DashboardStats(products: 0, sales: 0, revenue: 0);
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Selamat datang', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(access.status == AccessStatus.trial ? 'Mode trial — ${access.trialDaysRemaining} hari tersisa' : 'Akses aktif'),
          ]))),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: [
            _StatCard(title: 'Produk', value: '${stats.products}', icon: Icons.inventory_2),
            _StatCard(title: 'Transaksi', value: '${stats.sales}', icon: Icons.receipt_long),
            _StatCard(title: 'Penjualan', value: formatRupiah(stats.revenue), icon: Icons.payments),
          ]),
        ],
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value, required this.icon});
  final String title;
  final String value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: const Color(0xFF087F5B)),
      const SizedBox(height: 10),
      Text(title),
      const SizedBox(height: 4),
      Text(value, style: Theme.of(context).textTheme.headlineSmall),
    ]))),
  );
}

class Product {
  const Product({required this.id, required this.name, required this.price, required this.stock});
  final int id;
  final String name;
  final int price;
  final int stock;
  factory Product.fromMap(Map<String, Object?> map) => Product(
    id: map['id'] as int,
    name: map['name'] as String,
    price: map['price'] as int,
    stock: map['stock'] as int,
  );
}

class Sale {
  const Sale({required this.id, required this.total, required this.createdAt, required this.itemCount});
  final int id;
  final int total;
  final String createdAt;
  final int itemCount;
  factory Sale.fromMap(Map<String, Object?> map) => Sale(
    id: map['id'] as int,
    total: map['total'] as int,
    createdAt: map['created_at'] as String,
    itemCount: map['item_count'] as int,
  );
}

class DashboardStats {
  const DashboardStats({required this.products, required this.sales, required this.revenue});
  final int products;
  final int sales;
  final int revenue;
}

class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final databasesPath = await getDatabasesPath();
    _database = await openDatabase(path.join(databasesPath, 'berkah_pos.db'), version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE, price INTEGER NOT NULL CHECK(price >= 0), stock INTEGER NOT NULL CHECK(stock >= 0), created_at TEXT NOT NULL)');
      await db.execute('CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, total INTEGER NOT NULL CHECK(total >= 0), created_at TEXT NOT NULL, item_count INTEGER NOT NULL CHECK(item_count > 0))');
      await db.execute('CREATE TABLE sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL REFERENCES sales(id), product_id INTEGER NOT NULL, product_name TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity > 0), unit_price INTEGER NOT NULL CHECK(unit_price >= 0), subtotal INTEGER NOT NULL CHECK(subtotal >= 0))');
      await db.execute('CREATE INDEX idx_sales_created_at ON sales(created_at)');
      await db.execute('CREATE INDEX idx_sale_items_sale_id ON sale_items(sale_id)');
    });
    return _database!;
  }

  Future<List<Product>> getProducts() async {
    final rows = await (await database).query('products', orderBy: 'name COLLATE NOCASE');
    return rows.map(Product.fromMap).toList();
  }

  Future<void> saveProduct({int? id, required String name, required int price, required int stock}) async {
    final db = await database;
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Nama produk wajib diisi.');
    if (price < 0 || stock < 0) throw ArgumentError('Harga dan stok tidak boleh negatif.');
    if (id == null) {
      await db.insert('products', {'name': trimmed, 'price': price, 'stock': stock, 'created_at': DateTime.now().toUtc().toIso8601String()});
    } else {
      final count = await db.update('products', {'name': trimmed, 'price': price, 'stock': stock}, where: 'id = ?', whereArgs: [id]);
      if (count == 0) throw StateError('Produk tidak ditemukan.');
    }
  }

  Future<void> deleteProduct(int id) async => (await database).delete('products', where: 'id = ?', whereArgs: [id]);

  Future<DashboardStats> dashboardStats() async {
    final db = await database;
    final products = await db.rawQuery('SELECT COUNT(*) AS count FROM products');
    final sales = await db.rawQuery('SELECT COUNT(*) AS count, COALESCE(SUM(total), 0) AS revenue FROM sales');
    return DashboardStats(products: products.first['count'] as int, sales: sales.first['count'] as int, revenue: sales.first['revenue'] as int);
  }

  Future<List<Sale>> getSales() async {
    final rows = await (await database).rawQuery('SELECT id, total, created_at, item_count FROM sales ORDER BY id DESC');
    return rows.map(Sale.fromMap).toList();
  }

  Future<void> checkout(Map<int, int> quantities) async {
    if (quantities.isEmpty || quantities.values.any((qty) => qty <= 0)) throw ArgumentError('Keranjang kosong atau kuantitas tidak valid.');
    final db = await database;
    await db.transaction((txn) async {
      var total = 0;
      var count = 0;
      final items = <Map<String, Object?>>[];
      for (final entry in quantities.entries) {
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [entry.key], limit: 1);
        if (rows.isEmpty) throw StateError('Produk tidak ditemukan.');
        final product = Product.fromMap(rows.first);
        if (product.stock < entry.value) throw StateError('Stok ${product.name} tidak mencukupi.');
        final subtotal = product.price * entry.value;
        total += subtotal;
        count += entry.value;
        items.add({'product_id': product.id, 'product_name': product.name, 'quantity': entry.value, 'unit_price': product.price, 'subtotal': subtotal});
        await txn.update('products', {'stock': product.stock - entry.value}, where: 'id = ?', whereArgs: [product.id]);
      }
      final saleId = await txn.insert('sales', {'total': total, 'created_at': DateTime.now().toUtc().toIso8601String(), 'item_count': count});
      for (final item in items) {
        await txn.insert('sale_items', {'sale_id': saleId, ...item});
      }
    });
  }

  Future<List<Map<String, Object?>>> getSaleItems(int id) async => (await database).query('sale_items', where: 'sale_id = ?', whereArgs: [id], orderBy: 'id');
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  Future<void> _edit([Product? product]) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => ProductDialog(product: product));
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _delete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text('Produk "${product.name}" akan dihapus dari inventaris.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await LocalDatabase.instance.deleteProduct(product.id);
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) _message('Produk gagal dihapus: $error');
    }
  }

  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Produk')),
    body: FutureBuilder<List<Product>>(
      future: LocalDatabase.instance.getProducts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Gagal memuat produk: ${snapshot.error}'));
        final products = snapshot.data ?? [];
        if (products.isEmpty) return const Center(child: Text('Belum ada produk. Tambahkan produk pertama Anda.'));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: products.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final product = products[index];
            return Card(
              child: ListTile(
                title: Text(product.name),
                subtitle: Text('Stok: ${product.stock}'),
                leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatRupiah(product.price), style: Theme.of(context).textTheme.titleSmall),
                  IconButton(tooltip: 'Edit', onPressed: () => _edit(product), icon: const Icon(Icons.edit_outlined)),
                  IconButton(tooltip: 'Hapus', onPressed: () => _delete(product), icon: const Icon(Icons.delete_outline)),
                ]),
              ),
            );
          },
        );
      },
    ),
  );
}

class ProductDialog extends StatefulWidget {
  const ProductDialog({this.product, super.key});
  final Product? product;
  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.product?.name ?? '');
    _price = TextEditingController(text: widget.product?.price.toString() ?? '');
    _stock = TextEditingController(text: widget.product?.stock.toString() ?? '');
  }
  @override
  void dispose() { _name.dispose(); _price.dispose(); _stock.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await LocalDatabase.instance.saveProduct(id: widget.product?.id, name: _name.text, price: int.parse(_price.text), stock: int.parse(_stock.text));
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.product == null ? 'Tambah produk' : 'Edit produk'),
    content: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Nama produk'), validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : 'Nama wajib diisi.'),
          const SizedBox(height: 12),
          TextFormField(controller: _price, decoration: const InputDecoration(labelText: 'Harga (rupiah)'), keyboardType: TextInputType.number, validator: _nonNegativeInteger),
          const SizedBox(height: 12),
          TextFormField(controller: _stock, decoration: const InputDecoration(labelText: 'Stok'), keyboardType: TextInputType.number, validator: _nonNegativeInteger),
        ]),
      ),
    ),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
      FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Simpan')),
    ],
  );
}

String? _nonNegativeInteger(String? value) {
  final number = int.tryParse(value ?? '');
  return number != null && number >= 0 ? null : 'Masukkan bilangan bulat nol atau lebih.';
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final Map<int, int> _cart = {};
  bool _checkingOut = false;
  void _message(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _checkout() async {
    if (_cart.isEmpty) { _message('Keranjang masih kosong.'); return; }
    setState(() => _checkingOut = true);
    try {
      await LocalDatabase.instance.checkout(Map<int, int>.from(_cart));
      if (!mounted) return;
      setState(() { _cart.clear(); _checkingOut = false; });
      _message('Transaksi berhasil disimpan.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _checkingOut = false);
      _message('Transaksi gagal: $error');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
    future: LocalDatabase.instance.getProducts(),
    builder: (context, snapshot) {
      final products = snapshot.data ?? [];
      final total = products.where((p) => _cart.containsKey(p.id)).fold<int>(0, (sum, p) => sum + p.price * _cart[p.id]!);
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Pilih produk', style: Theme.of(context).textTheme.titleLarge),
          if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
          if (products.isEmpty && snapshot.connectionState == ConnectionState.done) const Padding(padding: EdgeInsets.all(24), child: Text('Tambahkan produk pada menu Produk sebelum checkout.')),
          ...products.map((product) {
            final qty = _cart[product.id] ?? 0;
            final canAdd = qty < product.stock;
            return Card(
              child: ListTile(
                title: Text(product.name),
                subtitle: Text('${formatRupiah(product.price)} • stok ${product.stock}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: qty > 0 ? () => setState(() { if (qty == 1) { _cart.remove(product.id); } else { _cart[product.id] = qty - 1; } }) : null, icon: const Icon(Icons.remove_circle_outline)),
                  Text('$qty'),
                  IconButton(onPressed: canAdd ? () => setState(() => _cart[product.id] = qty + 1) : null, icon: const Icon(Icons.add_circle_outline)),
                ]),
              ),
            );
          }),
          const Divider(height: 28),
          Text('Total: ${formatRupiah(total)}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _checkingOut ? null : _checkout, icon: const Icon(Icons.check), label: Text(_checkingOut ? 'Menyimpan...' : 'Selesaikan transaksi')),
        ],
      );
    },
  );
}

class SalesHistoryPage extends StatelessWidget {
  const SalesHistoryPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Sale>>(
    future: LocalDatabase.instance.getSales(),
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return Center(child: Text('Gagal memuat transaksi: ${snapshot.error}'));
      final sales = snapshot.data ?? [];
      if (sales.isEmpty) return const Center(child: Text('Belum ada transaksi.'));
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: sales.length,
        itemBuilder: (context, index) {
          final sale = sales[index];
          final date = DateTime.tryParse(sale.createdAt)?.toLocal();
          return Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.receipt_long)),
              title: Text('Transaksi #${sale.id}'),
              subtitle: Text('${sale.itemCount} item • ${date == null ? sale.createdAt : _formatDate(date)}'),
              trailing: Text(formatRupiah(sale.total), style: Theme.of(context).textTheme.titleSmall),
              onTap: () => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (_) => SaleDetailSheet(sale: sale)),
            ),
          );
        },
      );
    },
  );
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class SaleDetailSheet extends StatelessWidget {
  const SaleDetailSheet({required this.sale, super.key});
  final Sale sale;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
    future: LocalDatabase.instance.getSaleItems(sale.id),
    builder: (context, snapshot) {
      final rows = snapshot.data ?? [];
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text('Detail transaksi #${sale.id}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
            ...rows.map((row) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(row['product_name'] as String),
              subtitle: Text('${row['quantity']} × ${formatRupiah(row['unit_price'] as int)}'),
              trailing: Text(formatRupiah(row['subtotal'] as int)),
            )),
            const Divider(),
            ListTile(title: const Text('Total'), trailing: Text(formatRupiah(sale.total), style: Theme.of(context).textTheme.titleLarge)),
          ],
        ),
      );
    },
  );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  Future<void> _open(String url) async => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(12),
    children: [
      Card(child: ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Kebijakan privasi'), subtitle: const Text(privacyUrl), onTap: () => _open(privacyUrl))),
      Card(child: ListTile(leading: const Icon(Icons.person_remove_outlined), title: const Text('Hapus akun'), subtitle: const Text('Petunjuk penghapusan akun'), onTap: () => _open(deleteAccountUrl))),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Data produk dan transaksi tersimpan secara lokal di perangkat ini. Pastikan URL kebijakan privasi dan penghapusan akun dikelola oleh perusahaan sebelum rilis.'))),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Berkah POS • PT Berkah Tiga Puteri'))),
    ],
  );
}

String formatRupiah(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${negative ? '-Rp' : 'Rp'}$buffer';
}
