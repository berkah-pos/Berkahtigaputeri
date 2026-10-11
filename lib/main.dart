import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const appName = 'Berkah POS';
const companyName = 'PT Berkah Tiga Puteri';
const privacyUrl = 'https://berkahtigaputeri.co.id/privacy';
const deleteUrl = 'https://berkahtigaputeri.co.id/delete-account';
const statusUrl = 'https://api.berkahtigaputeri.co.id/check-status';
const salesWhatsAppNumber =
    String.fromEnvironment('SALES_WHATSAPP_NUMBER', defaultValue: '');
const trialDays = 14;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LocalStore.instance.database;
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
          scaffoldBackgroundColor: const Color(0xFFF6F8F7),
          inputDecorationTheme:
              const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: const AppRoot(),
      );
}

enum AccessState { active, trial, inactive }

class Access {
  const Access(this.state, [this.daysLeft = 0]);
  final AccessState state;
  final int daysLeft;
}

class AccessService {
  static Future<Access> check(String email) async {
    try {
      final uri = Uri.parse(statusUrl).replace(
        queryParameters: {'email': email.trim().toLowerCase()},
      );
      final response = await http
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final status = (decoded['status'] ??
                  decoded['subscription_status'] ??
                  '')
              .toString()
              .toLowerCase()
              .trim();
          if (['inactive', 'expired', 'suspended'].contains(status) ||
              decoded['active'] == false) {
            return const Access(AccessState.inactive);
          }
          if (status == 'active' || decoded['active'] == true) {
            return const Access(AccessState.active);
          }
          if (status == 'trial') {
            final raw = decoded['trial_days_remaining'];
            final days = raw is num ? raw.toInt() : trialDays;
            if (days > 0) {
              return Access(AccessState.trial, days.clamp(1, trialDays).toInt());
            }
            return const Access(AccessState.inactive);
          }
        }
      }
    } catch (_) {
      // Use the limited local trial while the status service is unavailable.
    }
    return _localTrial(email);
  }

  static Future<Access> _localTrial(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'berkah_trial_start_${email.trim().toLowerCase()}';
    var saved = prefs.getString(key);
    if (saved == null) {
      saved = DateTime.now().toUtc().toIso8601String();
      await prefs.setString(key, saved);
    }
    final started = DateTime.tryParse(saved)?.toUtc();
    if (started == null) return const Access(AccessState.inactive);
    final elapsed = DateTime.now().toUtc().difference(started);
    if (elapsed.isNegative) return const Access(AccessState.inactive);
    final remaining = trialDays - elapsed.inDays;
    if (remaining > 0) {
      return Access(AccessState.trial, remaining.clamp(1, trialDays).toInt());
    }
    return const Access(AccessState.inactive);
  }
}

Future<bool> contactSales([String? email]) async {
  final text = email == null
      ? 'Halo Sales Berkah POS, saya ingin informasi produk.'
      : 'Halo Sales Berkah POS, mohon bantuan aktivasi akun Berkah POS untuk email: ${email.trim()}.';
  final number = salesWhatsAppNumber.replaceAll(RegExp(r'[^0-9]'), '');
  final uri = number.isEmpty
      ? Uri.https('wa.me', '/', {'text': text})
      : Uri.https('wa.me', '/$number', {'text': text});
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> openExternal(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  String? email;
  Access? access;
  bool loading = false;

  Future<void> login(String value) async {
    setState(() => loading = true);
    final result = await AccessService.check(value);
    if (!mounted) return;
    setState(() {
      email = value.trim().toLowerCase();
      access = result;
      loading = false;
    });
  }

  void logout() => setState(() {
        email = null;
        access = null;
      });

  @override
  Widget build(BuildContext context) {
    if (email != null && access != null) {
      if (access!.state == AccessState.inactive) {
        return InactivePage(email: email!, onLogout: logout);
      }
      return MainShell(email: email!, access: access!, onLogout: logout);
    }
    return LoginPage(loading: loading, onLogin: login);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.loading, required this.onLogin, super.key});
  final bool loading;
  final Future<void> Function(String) onLogin;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final keyForm = GlobalKey<FormState>();
  final emailController = TextEditingController();
  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

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
                      key: keyForm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.point_of_sale_rounded,
                              size: 64, color: Color(0xFF087F5B)),
                          const SizedBox(height: 12),
                          Text(appName,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium),
                          const SizedBox(height: 4),
                          const Text(companyName, textAlign: TextAlign.center),
                          const SizedBox(height: 24),
                          const Text(
                            'Masukkan email untuk memeriksa status akses. '
                            'Mode trial tersedia gratis.',
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) => RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(value?.trim() ?? '')
                                ? null
                                : 'Masukkan email yang valid.',
                          ),
                          const SizedBox(height: 18),
                          FilledButton(
                            onPressed: widget.loading
                                ? null
                                : () {
                                    if (keyForm.currentState!.validate()) {
                                      widget.onLogin(emailController.text);
                                    }
                                  },
                            child: widget.loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Lanjutkan — Trial Gratis'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: widget.loading
                                ? null
                                : () => contactSales(emailController.text),
                            icon: const Icon(Icons.chat_outlined),
                            label: const Text('Hubungi Sales via WhatsApp'),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tidak ada pembayaran di dalam aplikasi. Trial '
                            'lokal hingga 14 hari digunakan bila API tidak '
                            'dapat dihubungi.',
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

class InactivePage extends StatelessWidget {
  const InactivePage({required this.email, required this.onLogout, super.key});
  final String email;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Aktivasi akun')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 56),
                  const SizedBox(height: 16),
                  Text(
                    'Akun Belum Aktif, hubungi tim Berkah POS untuk aktivasi',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(email),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => contactSales(email),
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Hubungi Sales via WhatsApp'),
                  ),
                  TextButton(
                    onPressed: onLogout,
                    child: const Text('Kembali ke login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class MainShell extends StatefulWidget {
  const MainShell({
    required this.email,
    required this.access,
    required this.onLogout,
    super.key,
  });
  final String email;
  final Access access;
  final VoidCallback onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardPage(access: widget.access),
      const ProductsPage(),
      const CheckoutPage(),
      const ReportsPage(),
      const SettingsPage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.account_circle_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(widget.email, overflow: TextOverflow.ellipsis)),
                Chip(
                  label: Text(widget.access.state == AccessState.trial
                      ? 'Trial ${widget.access.daysLeft} hari'
                      : 'Aktif'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Expanded(child: IndexedStack(index: index, children: pages)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Produk'),
          NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Kasir'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), label: 'Laporan'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
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
  const Sale({required this.id, required this.total, required this.created, required this.items});
  final int id;
  final int total;
  final String created;
  final int items;
  factory Sale.fromMap(Map<String, Object?> map) => Sale(
        id: map['id'] as int,
        total: map['total'] as int,
        created: map['created_at'] as String,
        items: map['item_count'] as int,
      );
}

class LocalStore {
  LocalStore._();
  static final instance = LocalStore._();
  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'berkah_pos.db'),
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            price INTEGER NOT NULL CHECK(price >= 0),
            stock INTEGER NOT NULL CHECK(stock >= 0),
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sales(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total INTEGER NOT NULL CHECK(total >= 0),
            created_at TEXT NOT NULL,
            item_count INTEGER NOT NULL CHECK(item_count > 0)
          )
        ''');
        await db.execute('''
          CREATE TABLE sale_items(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
            product_name TEXT NOT NULL,
            quantity INTEGER NOT NULL CHECK(quantity > 0),
            unit_price INTEGER NOT NULL CHECK(unit_price >= 0),
            subtotal INTEGER NOT NULL CHECK(subtotal >= 0)
          )
        ''');
        await db.execute('CREATE INDEX idx_sales_created ON sales(created_at)');
        await db.execute('CREATE INDEX idx_items_sale ON sale_items(sale_id)');
      },
    );
    return _db!;
  }

  Future<List<Product>> products() async =>
      (await (await database).query('products', orderBy: 'name COLLATE NOCASE'))
          .map(Product.fromMap)
          .toList();

  Future<void> saveProduct({int? id, required String name, required int price, required int stock}) async {
    if (name.trim().isEmpty || price < 0 || stock < 0) {
      throw ArgumentError('Nama wajib diisi; harga dan stok tidak boleh negatif.');
    }
    final db = await database;
    if (id == null) {
      await db.insert('products', {
        'name': name.trim(),
        'price': price,
        'stock': stock,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    } else {
      final rows = await db.update(
        'products',
        {'name': name.trim(), 'price': price, 'stock': stock},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows == 0) throw StateError('Produk tidak ditemukan.');
    }
  }

  Future<void> deleteProduct(int id) async =>
      (await database).delete('products', where: 'id = ?', whereArgs: [id]);

  Future<List<Sale>> sales() async =>
      (await (await database).query('sales', orderBy: 'id DESC'))
          .map(Sale.fromMap)
          .toList();

  Future<List<Map<String, Object?>>> saleItems(int id) async =>
      (await database).query('sale_items', where: 'sale_id = ?', whereArgs: [id]);

  Future<List<int>> summary() async {
    final db = await database;
    final product = await db.rawQuery('SELECT COUNT(*) AS n FROM products');
    final sales = await db.rawQuery(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS revenue FROM sales',
    );
    return [
      product.first['n'] as int,
      sales.first['n'] as int,
      sales.first['revenue'] as int,
    ];
  }

  Future<void> checkout(Map<int, int> cart) async {
    if (cart.isEmpty || cart.values.any((quantity) => quantity <= 0)) {
      throw ArgumentError('Keranjang kosong atau kuantitas tidak valid.');
    }
    final db = await database;
    await db.transaction((txn) async {
      var total = 0;
      var itemCount = 0;
      final items = <Map<String, Object?>>[];
      for (final entry in cart.entries) {
        final rows = await txn.query('products', where: 'id = ?', whereArgs: [entry.key], limit: 1);
        if (rows.isEmpty) throw StateError('Produk tidak ditemukan.');
        final product = Product.fromMap(rows.first);
        if (product.stock < entry.value) {
          throw StateError('Stok ${product.name} tidak mencukupi.');
        }
        final subtotal = product.price * entry.value;
        total += subtotal;
        itemCount += entry.value;
        items.add({
          'product_name': product.name,
          'quantity': entry.value,
          'unit_price': product.price,
          'subtotal': subtotal,
        });
        await txn.update(
          'products',
          {'stock': product.stock - entry.value},
          where: 'id = ?',
          whereArgs: [product.id],
        );
      }
      final saleId = await txn.insert('sales', {
        'total': total,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'item_count': itemCount,
      });
      for (final item in items) {
        await txn.insert('sale_items', {'sale_id': saleId, ...item});
      }
    });
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({required this.access, super.key});
  final Access access;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<int>>(
        future: LocalStore.instance.summary(),
        builder: (context, snapshot) {
          final values = snapshot.data ?? [0, 0, 0];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selamat datang', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Text(access.state == AccessState.trial
                          ? 'Trial gratis — ${access.daysLeft} hari tersisa'
                          : 'Akses aktif'),
                      const SizedBox(height: 8),
                      const Text('Produk dan transaksi disimpan lokal di perangkat.'),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _MetricCard('Produk', '${values[0]}', Icons.inventory_2_outlined),
                  _MetricCard('Transaksi', '${values[1]}', Icons.receipt_long_outlined),
                  _MetricCard('Penjualan', formatRupiah(values[2]), Icons.payments_outlined),
                ],
              ),
            ],
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.title, this.value, this.icon);
  final String title, value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: const Color(0xFF087F5B)),
                const SizedBox(height: 8),
                Text(title),
                Text(value, style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
          ),
        ),
      );
}

class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});
  @override
  State<ProductsPage> createState() => _ProductsPageState();
}
class _ProductsPageState extends State<ProductsPage> {
  late Future<List<Product>> future;
  @override
  void initState() { super.initState(); reload(); }
  void reload() { future = LocalStore.instance.products(); }

  Future<void> edit([Product? product]) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ProductEditor(product: product),
    );
    if (result == true && mounted) setState(reload);
  }

  Future<void> remove(Product product) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus produk?'),
        content: Text('Produk "${product.name}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (yes != true) return;
    await LocalStore.instance.deleteProduct(product.id);
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => edit(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah produk'),
        ),
        body: FutureBuilder<List<Product>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) return Center(child: Text('Gagal: ${snapshot.error}'));
            final products = snapshot.data ?? [];
            if (products.isEmpty) return const Center(child: Text('Belum ada produk.'));
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
              itemCount: products.length,
              itemBuilder: (context, index) {
                final product = products[index];
                return Card(
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text('Stok: ${product.stock}'),
                    leading: const Icon(Icons.inventory_2_outlined),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(formatRupiah(product.price)),
                        IconButton(onPressed: () => edit(product), icon: const Icon(Icons.edit_outlined)),
                        IconButton(onPressed: () => remove(product), icon: const Icon(Icons.delete_outline)),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
}

class ProductEditor extends StatefulWidget {
  const ProductEditor({this.product, super.key});
  final Product? product;
  @override
  State<ProductEditor> createState() => _ProductEditorState();
}
class _ProductEditorState extends State<ProductEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.product?.name ?? '');
  late final price = TextEditingController(text: widget.product?.price.toString() ?? '');
  late final stock = TextEditingController(text: widget.product?.stock.toString() ?? '');
  bool saving = false;
  @override
  void dispose() { name.dispose(); price.dispose(); stock.dispose(); super.dispose(); }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await LocalStore.instance.saveProduct(
        id: widget.product?.id,
        name: name.text,
        price: int.parse(price.text),
        stock: int.parse(stock.text),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $error')));
    }
  }

  String? integerValidator(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed != null && parsed >= 0 ? null : 'Masukkan bilangan bulat nol atau lebih.';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.product == null ? 'Tambah produk' : 'Edit produk'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Nama produk'),
                  validator: (value) => (value?.trim().isNotEmpty ?? false) ? null : 'Nama wajib diisi.',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Harga (rupiah)'),
                  validator: integerValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: stock,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok'),
                  validator: integerValidator,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(context, false), child: const Text('Batal')),
          FilledButton(
            onPressed: saving ? null : save,
            child: saving ? const CircularProgressIndicator() : const Text('Simpan'),
          ),
        ],
      );
}

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}
class _CheckoutPageState extends State<CheckoutPage> {
  late Future<List<Product>> future;
  final cart = <int, int>{};
  bool saving = false;
  @override
  void initState() { super.initState(); reload(); }
  void reload() { future = LocalStore.instance.products(); }

  Future<void> checkout() async {
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keranjang masih kosong.')));
      return;
    }
    setState(() => saving = true);
    try {
      await LocalStore.instance.checkout(Map<int, int>.from(cart));
      if (!mounted) return;
      setState(() { cart.clear(); saving = false; reload(); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaksi tersimpan lokal.')));
    } catch (error) {
      if (!mounted) return;
      setState(() { saving = false; reload(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transaksi gagal: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Product>>(
        future: future,
        builder: (context, snapshot) {
          final products = snapshot.data ?? [];
          final total = products.fold<int>(
            0,
            (sum, product) => sum + product.price * (cart[product.id] ?? 0),
          );
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('Kasir', style: Theme.of(context).textTheme.headlineSmall),
              if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
              if (snapshot.hasError) Text('Gagal memuat produk: ${snapshot.error}'),
              if (snapshot.connectionState == ConnectionState.done && products.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('Tambahkan produk dahulu.')),
              ...products.map((product) {
                final quantity = cart[product.id] ?? 0;
                return Card(
                  child: ListTile(
                    title: Text(product.name),
                    subtitle: Text('${formatRupiah(product.price)} • stok ${product.stock}'),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        IconButton(
                          onPressed: quantity == 0 ? null : () => setState(() {
                            if (quantity == 1) { cart.remove(product.id); } else { cart[product.id] = quantity - 1; }
                          }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Text('$quantity'),
                        IconButton(
                          onPressed: quantity >= product.stock ? null : () => setState(() => cart[product.id] = quantity + 1),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const Divider(height: 28),
              Text('Total: ${formatRupiah(total)}', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: saving ? null : checkout,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(saving ? 'Menyimpan...' : 'Selesaikan transaksi'),
              ),
            ],
          );
        },
      );
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Sale>>(
        future: LocalStore.instance.sales(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Laporan gagal dimuat: ${snapshot.error}'));
          final sales = snapshot.data ?? [];
          final total = sales.fold<int>(0, (sum, sale) => sum + sale.total);
          if (sales.isEmpty) return const Center(child: Text('Belum ada transaksi lokal.'));
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('Laporan Penjualan Lokal', style: Theme.of(context).textTheme.headlineSmall),
              Card(child: ListTile(title: const Text('Total penjualan'), trailing: Text(formatRupiah(total)))),
              Card(child: ListTile(title: const Text('Jumlah transaksi'), trailing: Text('${sales.length}'))),
              Text('Riwayat', style: Theme.of(context).textTheme.titleLarge),
              ...sales.map((sale) {
                final date = DateTime.tryParse(sale.created)?.toLocal();
                return Card(
                  child: ListTile(
                    title: Text('Transaksi #${sale.id}'),
                    subtitle: Text('${sale.items} item • ${date == null ? sale.created : _dateText(date)}'),
                    trailing: Text(formatRupiah(sale.total)),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      builder: (_) => SaleDetails(sale: sale),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      );
}

class SaleDetails extends StatelessWidget {
  const SaleDetails({required this.sale, super.key});
  final Sale sale;
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, Object?>>>(
        future: LocalStore.instance.saleItems(sale.id),
        builder: (context, snapshot) {
          final rows = snapshot.data ?? [];
          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Text('Detail transaksi #${sale.id}', style: Theme.of(context).textTheme.titleLarge),
                if (snapshot.connectionState != ConnectionState.done) const LinearProgressIndicator(),
                ...rows.map((row) => ListTile(
                  title: Text(row['product_name'] as String),
                  subtitle: Text('${row['quantity']} × ${formatRupiah(row['unit_price'] as int)}'),
                  trailing: Text(formatRupiah(row['subtotal'] as int)),
                )),
                const Divider(),
                ListTile(title: const Text('Total'), trailing: Text(formatRupiah(sale.total))),
              ],
            ),
          );
        },
      );
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy / Kebijakan Privasi'),
              subtitle: const Text(privacyUrl),
              onTap: () => openExternal(privacyUrl),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_remove_outlined),
              title: const Text('Hapus Akun'),
              subtitle: const Text('Buka halaman penghapusan akun'),
              onTap: () => openExternal(deleteUrl),
            ),
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Produk dan transaksi disimpan lokal di perangkat. '
                'Pemeriksaan akses mengirim email ke layanan status Berkah POS.',
              ),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.business_outlined),
              title: Text(companyName),
              subtitle: Text('Berkah POS • Mode trial gratis'),
            ),
          ),
        ],
      );
}

String _dateText(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year} '
    '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

String formatRupiah(int value) {
  final negative = value < 0;
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  final prefix = negative ? '-Rp' : 'Rp';
  return '$prefix$buffer';
}
