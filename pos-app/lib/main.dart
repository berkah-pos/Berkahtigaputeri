import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const String appName = 'Berkah POS';
const String companyName = 'PT Berkah Tiga Puteri';
const String statusApi = 'https://api.berkahtigaputeri.co.id/check-status';
const String deleteAccountUrl = 'https://berkahtigaputeri.co.id/delete-account';
const String privacyUrl = 'https://berkahtigaputeri.co.id/privacy';
const String salesWhatsAppUrl = String.fromEnvironment(
  'SALES_WHATSAPP_URL',
  defaultValue: 'https://wa.me/?text=Halo%20Sales%20Berkah%20POS',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.instance.database;
  runApp(const BerkahPosApp());
}

class BerkahPosApp extends StatelessWidget {
  const BerkahPosApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF126B4B)),
          useMaterial3: true,
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const LoginScreen(),
      );
}

class Product {
  const Product({
    this.id,
    required this.name,
    required this.price,
    required this.stock,
  });

  final int? id;
  final String name;
  final int price;
  final int stock;

  factory Product.fromMap(Map<String, Object?> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        price: (map['price'] as num).toInt(),
        stock: (map['stock'] as num).toInt(),
      );
}

class CartEntry {
  CartEntry(this.product, {this.quantity = 1});
  final Product product;
  int quantity;
  int get subtotal => product.price * quantity;
}

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final dbPath = path.join(await getDatabasesPath(), 'berkah_pos_trial.db');
    _database = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE products (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'name TEXT NOT NULL, price INTEGER NOT NULL CHECK(price >= 0), '
          'stock INTEGER NOT NULL DEFAULT 0 CHECK(stock >= 0), '
          'created_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE sales (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'total INTEGER NOT NULL, created_at TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE TABLE sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, '
          'product_name TEXT NOT NULL, quantity INTEGER NOT NULL, '
          'unit_price INTEGER NOT NULL, subtotal INTEGER NOT NULL, '
          'FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE CASCADE)',
        );
      },
    );
    return _database!;
  }

  Future<List<Product>> listProducts() async {
    final rows = await (await database)
        .query('products', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Product.fromMap).toList();
  }

  Future<void> saveProduct(Product product) async {
    final db = await database;
    final values = <String, Object?>{
      'name': product.name.trim(),
      'price': product.price,
      'stock': product.stock,
    };
    if (product.id == null) {
      values['created_at'] = DateTime.now().toIso8601String();
      await db.insert('products', values);
    } else {
      await db.update('products', values,
          where: 'id = ?', whereArgs: <Object?>[product.id]);
    }
  }

  Future<void> deleteProduct(int id) async {
    await (await database)
        .delete('products', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> checkout(List<CartEntry> entries) async {
    if (entries.isEmpty) throw StateError('Keranjang masih kosong.');
    final db = await database;
    await db.transaction((txn) async {
      for (final entry in entries) {
        final rows = await txn.query(
          'products',
          columns: <String>['stock'],
          where: 'id = ?',
          whereArgs: <Object?>[entry.product.id],
          limit: 1,
        );
        if (rows.isEmpty) {
          throw StateError('Produk ' + entry.product.name + ' tidak ditemukan.');
        }
        final available = (rows.first['stock'] as num).toInt();
        if (available < entry.quantity) {
          throw StateError('Stok ' + entry.product.name + ' tidak mencukupi.');
        }
      }
      final total = entries.fold<int>(0, (sum, item) => sum + item.subtotal);
      final saleId = await txn.insert('sales', <String, Object?>{
        'total': total,
        'created_at': DateTime.now().toIso8601String(),
      });
      for (final entry in entries) {
        await txn.insert('sale_items', <String, Object?>{
          'sale_id': saleId,
          'product_id': entry.product.id,
          'product_name': entry.product.name,
          'quantity': entry.quantity,
          'unit_price': entry.product.price,
          'subtotal': entry.subtotal,
        });
        await txn.rawUpdate(
          'UPDATE products SET stock = stock - ? WHERE id = ?',
          <Object?>[entry.quantity, entry.product.id],
        );
      }
    });
  }

  Future<Map<String, dynamic>> summary() async {
    final db = await database;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day).toIso8601String();
    final productCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM products')) ??
            0;
    final stockCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COALESCE(SUM(stock), 0) FROM products')) ??
        0;
    final today = await db.rawQuery(
      'SELECT COUNT(*) AS count, COALESCE(SUM(total), 0) AS total '
      'FROM sales WHERE created_at >= ?',
      <Object?>[midnight],
    );
    final lifetime = await db.rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS total FROM sales',
    );
    final recent = await db.query('sales', orderBy: 'created_at DESC', limit: 30);
    return <String, dynamic>{
      'productCount': productCount,
      'stockCount': stockCount,
      'todaySalesCount': (today.first['count'] as num).toInt(),
      'todayTotal': (today.first['total'] as num).toInt(),
      'lifetimeTotal': (lifetime.first['total'] as num).toInt(),
      'recentSales': recent,
    };
  }
}

String rupiah(int value) {
  final digits = value.toString();
  final output = StringBuffer('Rp ');
  for (var i = 0; i < digits.length; i++) {
    output.write(digits[i]);
    final remaining = digits.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) output.write('.');
  }
  return output.toString();
}

String formatDate(Object? value) {
  if (value == null) return '-';
  final date = DateTime.tryParse(value.toString())?.toLocal();
  if (date == null) return value.toString();
  String two(int number) => number.toString().padLeft(2, '0');
  return two(date.day) +
      '/' +
      two(date.month) +
      '/' +
      date.year.toString() +
      ' ' +
      two(date.hour) +
      ':' +
      two(date.minute);
}

Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Tautan tidak dapat dibuka pada perangkat ini.')),
      );
    }
  }
}

Future<bool?> checkSubscription(String email) async {
  try {
    final uri = Uri.parse(statusApi)
        .replace(queryParameters: <String, String>{'email': email});
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final status = (decoded['status'] ?? decoded['subscription_status'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (decoded['active'] == true || status == 'active' || status == 'trial') {
      return true;
    }
    const inactive = <String>[
      'inactive',
      'expired',
      'pending',
      'disabled',
      'suspended'
    ];
    if (decoded['active'] == false || inactive.contains(status)) return false;
    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      final dataStatus = (data['status'] ?? '').toString().toLowerCase();
      if (data['active'] == true || dataStatus == 'active') return true;
      if (data['active'] == false || inactive.contains(dataStatus)) return false;
    }
    return null;
  } catch (_) {
    // The local trial remains available when the status API cannot be reached.
    return null;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _checking = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _checking = true);
    final email = _emailController.text.trim();
    final status = await checkSubscription(email);
    if (!mounted) return;
    setState(() => _checking = false);
    if (status == true) {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => HomeShell(email: email),
      ));
    } else {
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ActivationScreen(
          email: email,
          verificationFailed: status == null,
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Icon(Icons.storefront, size: 56),
                          const SizedBox(height: 12),
                          Text(appName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          const Text(companyName, textAlign: TextAlign.center),
                          const SizedBox(height: 28),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const <String>[AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              final email = (value ?? '').trim();
                              if (!email.contains('@') || email.endsWith('@')) {
                                return 'Masukkan alamat email yang valid.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _checking ? null : _signIn,
                            icon: _checking
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.login),
                            label: Text(_checking
                                ? 'Memeriksa status…'
                                : 'Masuk / Cek Status'),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () =>
                                openExternal(context, salesWhatsAppUrl),
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('Hubungi Sales via WhatsApp'),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Mode trial lokal tersedia tanpa pembayaran. Produk, '
                            'keranjang, transaksi, dan laporan tersimpan di perangkat ini.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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

class ActivationScreen extends StatelessWidget {
  const ActivationScreen({
    super.key,
    required this.email,
    required this.verificationFailed,
  });

  final String email;
  final bool verificationFailed;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text(appName)),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Icon(
                          verificationFailed
                              ? Icons.cloud_off
                              : Icons.lock_outline,
                          size: 52,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          verificationFailed
                              ? 'Status akun belum dapat diverifikasi'
                              : 'Akun Belum Aktif, hubungi tim Berkah POS untuk aktivasi',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          verificationFailed
                              ? 'Layanan status tidak dapat dijangkau saat ini. Anda tetap '
                                  'dapat menggunakan mode trial lokal tanpa pembayaran.'
                              : 'Email: ' +
                                  email +
                                  '\nAnda dapat menghubungi tim Berkah POS atau '
                                      'melanjutkan mode trial lokal.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () =>
                              openExternal(context, salesWhatsAppUrl),
                          icon: const Icon(Icons.chat),
                          label: const Text('Hubungi Sales via WhatsApp'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  HomeShell(email: email, trialMode: true),
                            ),
                          ),
                          child: const Text('Lanjutkan Mode Trial Lokal'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute<void>(
                                builder: (_) => const LoginScreen()),
                            (route) => false,
                          ),
                          child: const Text('Kembali ke Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.email, this.trialMode = false});
  final String email;
  final bool trialMode;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  Widget _page() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardScreen();
      case 1:
        return const ProductsScreen();
      case 2:
        return const CashierScreen();
      case 3:
        return const ReportsScreen();
      default:
        return SettingsScreen(email: widget.email);
    }
  }

  @override
  Widget build(BuildContext context) {
    const destinations = <NavigationDestination>[
      NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Beranda'),
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Produk'),
      NavigationDestination(icon: Icon(Icons.point_of_sale), label: 'Kasir'),
      NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Laporan'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: <Widget>[
          if (widget.trialMode)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Center(child: Chip(label: Text('TRIAL'))),
            ),
          IconButton(
            tooltip: 'Keluar',
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              (route) => false,
            ),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: destinations,
        onDestinationSelected: (value) => setState(() => _selectedIndex = value),
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: AppDatabase.instance.summary(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('Ringkasan lokal belum dapat dimuat.'));
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Ringkasan Toko',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text('Data disimpan secara lokal di perangkat ini.'),
              const SizedBox(height: 16),
              _SummaryTile(
                title: 'Jenis Produk',
                value: data['productCount'].toString(),
                icon: Icons.inventory_2_outlined,
              ),
              _SummaryTile(
                title: 'Total Stok',
                value: data['stockCount'].toString(),
                icon: Icons.warehouse_outlined,
              ),
              _SummaryTile(
                title: 'Penjualan Hari Ini',
                value: rupiah(data['todayTotal'] as int),
                icon: Icons.payments_outlined,
              ),
              _SummaryTile(
                title: 'Total Penjualan',
                value: rupiah(data['lifetimeTotal'] as int),
                icon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.shopping_cart_outlined),
                  title: const Text('Kasir siap digunakan'),
                  subtitle: Text(
                      data['todaySalesCount'].toString() + ' transaksi hari ini'),
                ),
              ),
            ],
          );
        },
      );
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(child: Icon(icon)),
          title: Text(title),
          trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late Future<List<Product>> _products;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _products = AppDatabase.instance.listProducts();
  }

  Future<void> _editProduct([Product? initial]) async {
    final nameController = TextEditingController(text: initial?.name ?? '');
    final priceController =
        TextEditingController(text: initial == null ? '' : initial.price.toString());
    final stockController =
        TextEditingController(text: initial == null ? '0' : initial.stock.toString());
    final formKey = GlobalKey<FormState>();
    final product = await showDialog<Product>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(initial == null ? 'Tambah Produk' : 'Edit Produk'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Nama produk'),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? 'Nama wajib diisi.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga (Rp)'),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 0
                        ? 'Harga tidak valid.'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok'),
                  validator: (value) {
                    final number = int.tryParse(value ?? '');
                    return number == null || number < 0
                        ? 'Stok tidak valid.'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(
                dialogContext,
                Product(
                  id: initial?.id,
                  name: nameController.text.trim(),
                  price: int.parse(priceController.text),
                  stock: int.parse(stockController.text),
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    nameController.dispose();
    priceController.dispose();
    stockController.dispose();
    if (product == null || !mounted) return;
    await AppDatabase.instance.saveProduct(product);
    if (mounted) setState(_reload);
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text('Produk "' + product.name + '" akan dihapus dari katalog.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppDatabase.instance.deleteProduct(product.id!);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Produk belum dapat dimuat.'));
          }
          final products = snapshot.data ?? <Product>[];
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Kelola Produk (' + products.length.toString() + ')',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Muat ulang',
                      onPressed: () => setState(_reload),
                      icon: const Icon(Icons.refresh),
                    ),
                    FilledButton.icon(
                      onPressed: () => _editProduct(),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: products.isEmpty
                    ? const Center(
                        child: Text('Belum ada produk. Tambahkan produk pertama.'))
                    : ListView.separated(
                        itemCount: products.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = products[index];
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.inventory_2)),
                            title: Text(product.name),
                            subtitle: Text(rupiah(product.price) +
                                ' • Stok: ' +
                                product.stock.toString()),
                            trailing: Wrap(
                              spacing: 0,
                              children: <Widget>[
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () => _editProduct(product),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Hapus',
                                  onPressed: () => _deleteProduct(product),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      );
}

class CashierScreen extends StatefulWidget {
  const CashierScreen({super.key});
  @override
  State<CashierScreen> createState() => _CashierScreenState();
}

class _CashierScreenState extends State<CashierScreen> {
  late Future<List<Product>> _products;
  final Map<int, CartEntry> _cart = <int, CartEntry>{};

  @override
  void initState() {
    super.initState();
    _reloadProducts();
  }

  void _reloadProducts() {
    _products = AppDatabase.instance.listProducts();
  }

  int get _total =>
      _cart.values.fold<int>(0, (sum, entry) => sum + entry.subtotal);

  void _add(Product product) {
    final id = product.id!;
    final existing = _cart[id];
    if ((existing?.quantity ?? 0) >= product.stock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok ' + product.name + ' tidak mencukupi.')),
      );
      return;
    }
    setState(() {
      if (existing == null) {
        _cart[id] = CartEntry(product);
      } else {
        existing.quantity++;
      }
    });
  }

  void _removeOne(int id) {
    final entry = _cart[id];
    if (entry == null) return;
    setState(() {
      if (entry.quantity <= 1) {
        _cart.remove(id);
      } else {
        entry.quantity--;
      }
    });
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Keranjang masih kosong.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Selesaikan transaksi?'),
        content: Text('Total pembayaran: ' + rupiah(_total)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Simpan transaksi'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await AppDatabase.instance.checkout(_cart.values.toList());
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _reloadProducts();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaksi tersimpan di perangkat.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
      );
      setState(_reloadProducts);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
        future: _products,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Katalog tidak dapat dimuat.'));
          }
          final products = snapshot.data ?? <Product>[];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Kasir', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Pilih produk untuk memasukkannya ke keranjang.'),
              const SizedBox(height: 8),
              if (products.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Katalog masih kosong'),
                    subtitle: Text(
                        'Tambahkan produk melalui menu Produk terlebih dahulu.'),
                  ),
                )
              else
                ...products.map(
                  (product) => Card(
                    child: ListTile(
                      title: Text(product.name),
                      subtitle: Text(rupiah(product.price) +
                          ' • Stok: ' +
                          product.stock.toString()),
                      trailing: IconButton(
                        tooltip: 'Tambah ke keranjang',
                        onPressed: product.stock > 0 ? () => _add(product) : null,
                        icon: const Icon(Icons.add_shopping_cart),
                      ),
                    ),
                  ),
                ),
              const Divider(height: 32),
              Text('Keranjang', style: Theme.of(context).textTheme.titleLarge),
              if (_cart.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Belum ada barang di keranjang.'),
                )
              else
                ..._cart.entries.map(
                  (entry) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(entry.value.product.name),
                    subtitle: Text(entry.value.quantity.toString() +
                        ' × ' +
                        rupiah(entry.value.product.price)),
                    leading: IconButton(
                      tooltip: 'Kurangi jumlah',
                      onPressed: () => _removeOne(entry.key),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    trailing: Text(rupiah(entry.value.subtotal),
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('TOTAL',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                trailing: Text(rupiah(_total),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _cart.isEmpty ? null : _checkout,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Simpan Transaksi Lokal'),
              ),
            ],
          );
        },
      );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Map<String, dynamic>>(
        future: AppDatabase.instance.summary(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const Center(child: Text('Laporan tidak dapat dimuat.'));
          }
          final report = snapshot.data!;
          final sales =
              (report['recentSales'] as List).cast<Map<String, dynamic>>();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('Laporan Lokal',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.today_outlined),
                  title: const Text('Penjualan hari ini'),
                  subtitle:
                      Text(report['todaySalesCount'].toString() + ' transaksi'),
                  trailing: Text(rupiah(report['todayTotal'] as int)),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.all_inclusive),
                  title: const Text('Total penjualan tersimpan'),
                  trailing: Text(rupiah(report['lifetimeTotal'] as int)),
                ),
              ),
              const SizedBox(height: 12),
              Text('Transaksi Terbaru',
                  style: Theme.of(context).textTheme.titleLarge),
              if (sales.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('Belum ada transaksi.'),
                )
              else
                ...sales.map(
                  (sale) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text('Transaksi #' + sale['id'].toString()),
                      subtitle: Text(formatDate(sale['created_at'])),
                      trailing: Text(rupiah((sale['total'] as num).toInt())),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.email});
  final String email;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Email'),
              subtitle: Text(email),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat_outlined),
              title: const Text('Hubungi Sales via WhatsApp'),
              subtitle: const Text('Membuka WhatsApp di luar aplikasi.'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openExternal(context, salesWhatsAppUrl),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_remove_alt_1_outlined),
              title: const Text('Hapus Akun'),
              subtitle: const Text('Buka halaman penghapusan akun di browser.'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openExternal(context, deleteAccountUrl),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy'),
              subtitle: const Text('Kebijakan privasi Berkah POS.'),
              trailing: const Icon(Icons.open_in_new),
              onTap: () => openExternal(context, privacyUrl),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Mode trial menyimpan produk dan transaksi di database SQLite pada '
            'perangkat. Data lokal tidak otomatis tersinkron ke server.',
          ),
        ],
      );
}
