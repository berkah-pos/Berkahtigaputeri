import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

const appName = 'Berkah POS';
const company = 'PT Berkah Tiga Puteri';
const statusApi = 'https://api.berkahtigaputeri.co.id/check-status';
const deleteUrl = 'https://berkahtigaputeri.co.id/delete-account';
const privacyUrl = 'https://berkahtigaputeri.co.id/privacy';
const salesNumber = String.fromEnvironment('BERKAH_WHATSAPP_NUMBER', defaultValue: '');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BerkahApp());
}

class BerkahApp extends StatelessWidget {
  const BerkahApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: appName,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF137A4B))),
    home: const LoginPage(),
  );
}

class Product {
  const Product({required this.id, required this.name, required this.sku, required this.price, required this.stock});
  final int id;
  final String name, sku;
  final double price;
  final int stock;
  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: (m['id'] as num).toInt(), name: m['name'] as String,
    sku: m['sku'] as String? ?? '', price: (m['price'] as num).toDouble(),
    stock: (m['stock'] as num).toInt(),
  );
}

class Store {
  Future<Database>? _db;
  Future<Database> get db => _db ??= _open();
  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(p.join(root, 'berkah_pos.db'), version: 1, onCreate: (db, _) async {
      await db.execute("CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sku TEXT NOT NULL, price REAL NOT NULL, stock INTEGER NOT NULL)");
      await db.execute("CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, total REAL NOT NULL, item_count INTEGER NOT NULL, email TEXT NOT NULL, created TEXT NOT NULL)");
      await db.execute("CREATE TABLE sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, product_id INTEGER NOT NULL, name TEXT NOT NULL, qty INTEGER NOT NULL, price REAL NOT NULL, subtotal REAL NOT NULL)");
    });
  }
  Future<List<Product>> products() async => (await (await db).query('products', orderBy: 'name COLLATE NOCASE')).map(Product.fromMap).toList();
  Future<void> save(Product? old, String name, String sku, double price, int stock) async {
    final d = await db;
    final values = {'name': name.trim(), 'sku': sku.trim(), 'price': price, 'stock': stock};
    if (old == null) { await d.insert('products', values); } else { await d.update('products', values, where: 'id=?', whereArgs: [old.id]); }
  }
  Future<void> remove(int id) async { await (await db).delete('products', where: 'id=?', whereArgs: [id]); }
  Future<int> checkout(Map<int, int> cart, String email) async {
    if (cart.isEmpty) throw StateError('Keranjang masih kosong.');
    return (await db).transaction((txn) async {
      final items = <Product>[];
      for (final row in cart.entries) {
        final matches = await txn.query('products', where: 'id=?', whereArgs: [row.key], limit: 1);
        if (matches.isEmpty) throw StateError('Produk tidak ditemukan.');
        final product = Product.fromMap(matches.first);
        if (row.value < 1 || row.value > product.stock) throw StateError('Stok ' + product.name + ' tidak mencukupi.');
        items.add(product);
      }
      final total = items.fold<double>(0, (sum, x) => sum + x.price * cart[x.id]!);
      final count = cart.values.fold<int>(0, (sum, n) => sum + n);
      final saleId = await txn.insert('sales', {'total': total, 'item_count': count, 'email': email, 'created': DateTime.now().toIso8601String()});
      for (final x in items) {
        final qty = cart[x.id]!;
        await txn.insert('sale_items', {'sale_id': saleId, 'product_id': x.id, 'name': x.name, 'qty': qty, 'price': x.price, 'subtotal': x.price * qty});
        await txn.update('products', {'stock': x.stock - qty}, where: 'id=?', whereArgs: [x.id]);
      }
      return saleId;
    });
  }
  Future<Map<String, dynamic>> report() async {
    final d = await db;
    final t = await d.rawQuery('SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS revenue, COALESCE(SUM(item_count),0) AS items FROM sales');
    return {'count': (t.first['n'] as num).toInt(), 'revenue': (t.first['revenue'] as num).toDouble(), 'items': (t.first['items'] as num).toInt(), 'recent': await d.query('sales', orderBy: 'id DESC', limit: 25)};
  }
}

Future<String> checkStatus(String email) async {
  try {
    final uri = Uri.parse(statusApi).replace(queryParameters: {'email': email});
    final res = await http.get(uri, headers: const {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) return 'unknown';
    final data = jsonDecode(res.body);
    if (data is! Map<String, dynamic>) return 'unknown';
    final status = (data['status'] ?? data['subscription_status'] ?? '').toString().toLowerCase();
    if (data['active'] == true || data['is_active'] == true || const {'active', 'trial', 'trialing'}.contains(status)) return 'active';
    if (data['active'] == false || data['is_active'] == false || const {'inactive', 'expired', 'suspended', 'disabled'}.contains(status)) return 'inactive';
  } catch (_) { /* Keep local trial available when the service is unreachable. */ }
  return 'unknown';
}

Future<void> openExternal(BuildContext context, String url) async {
  try {
    final result = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!result && context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan tidak dapat dibuka.')));
  } catch (_) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tautan tidak dapat dibuka.')));
  }
}
Future<void> openWhatsApp(BuildContext context) async {
  final phone = salesNumber.replaceAll(RegExp('[^0-9]'), '');
  final link = phone.isEmpty
    ? Uri.https('wa.me', '/', {'text': 'Halo tim Berkah POS, saya ingin informasi aktivasi.'})
    : Uri.https('wa.me', '/' + phone, {'text': 'Halo tim Berkah POS, saya ingin informasi aktivasi.'});
  await openExternal(context, link.toString());
}
String money(num n) => 'Rp ' + n.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final form = GlobalKey<FormState>();
  final store = Store();
  bool loading = false;
  @override
  void dispose() { email.dispose(); super.dispose(); }
  Future<void> login() async {
    if (!(form.currentState?.validate() ?? false)) return;
    setState(() => loading = true);
    final status = await checkStatus(email.text.trim());
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => PosPage(store: store, email: email.text.trim(), status: status)));
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.point_of_sale_rounded, size: 68, color: Color(0xFF137A4B)),
        Text(appName, style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
        Text(company, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        const Text('Kelola produk, kasir, dan laporan lokal. Aplikasi dapat dicoba tanpa pembayaran.'),
        const SizedBox(height: 20),
        Card(child: Padding(padding: const EdgeInsets.all(18), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => v != null && v.contains('@') && v.trim().length > 3 ? null : 'Masukkan email yang valid.'),
          const SizedBox(height: 12),
          FilledButton(onPressed: loading ? null : login, child: Text(loading ? 'Memeriksa status…' : 'Mulai Trial Gratis')),
          OutlinedButton.icon(onPressed: () => openWhatsApp(context), icon: const Icon(Icons.chat_outlined), label: const Text('Hubungi Sales via WhatsApp')),
        ])))),
        const SizedBox(height: 14),
        const Text('Pemeriksaan status tidak membatasi penggunaan data lokal.', textAlign: TextAlign.center),
      ])),
    ))),
  );
}

class PosPage extends StatefulWidget {
  const PosPage({super.key, required this.store, required this.email, required this.status});
  final Store store;
  final String email, status;
  @override
  State<PosPage> createState() => _PosPageState();
}
class _PosPageState extends State<PosPage> {
  int tab = 0;
  bool loading = true, saving = false;
  List<Product> products = [];
  Map<String, dynamic> stats = {'count': 0, 'revenue': 0.0, 'items': 0, 'recent': <Map<String, Object?>>[]};
  final cart = <int, int>{};
  final titles = const ['Dashboard', 'Kelola Produk', 'Kasir', 'Laporan', 'Pengaturan'];
  @override
  void initState() { super.initState(); refresh(); }
  Future<void> refresh() async {
    final items = await widget.store.products();
    final r = await widget.store.report();
    if (mounted) setState(() { products = items; stats = r; loading = false; });
  }
  Future<void> editProduct([Product? old]) async {
    final name = TextEditingController(text: old?.name ?? '');
    final sku = TextEditingController(text: old?.sku ?? '');
    final price = TextEditingController(text: old?.price.toString() ?? '');
    final stock = TextEditingController(text: old?.stock.toString() ?? '0');
    final key = GlobalKey<FormState>();
    final data = await showDialog<List<String>>(context: context, builder: (ctx) => AlertDialog(
      title: Text(old == null ? 'Tambah Produk' : 'Edit Produk'),
      content: Form(key: key, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Nama produk'), validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi.' : null),
        TextFormField(controller: sku, decoration: const InputDecoration(labelText: 'SKU (opsional)')),
        TextFormField(controller: price, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Harga Rp'), validator: (v) => double.tryParse((v ?? '').replaceAll(',', '.')) == null ? 'Harga tidak valid.' : null),
        TextFormField(controller: stock, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok'), validator: (v) { final n = int.tryParse(v ?? ''); return n == null || n < 0 ? 'Stok tidak valid.' : null; }),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')), FilledButton(onPressed: () { if (key.currentState?.validate() ?? false) Navigator.pop(ctx, [name.text, sku.text, price.text.replaceAll(',', '.'), stock.text]); }, child: const Text('Simpan'))],
    ));
    name.dispose(); sku.dispose(); price.dispose(); stock.dispose();
    if (data == null) return;
    await widget.store.save(old, data[0], data[1], double.parse(data[2]), int.parse(data[3]));
    await refresh();
  }
  Widget metric(String label, String value) => SizedBox(width: 160, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), const SizedBox(height: 6), Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))]))));
  Widget empty(String title, String message) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.inventory_2_outlined, size: 44), Text(title, style: Theme.of(context).textTheme.titleMedium), Text(message, textAlign: TextAlign.center)])));
  Widget dashboard() => RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(16), children: [
    Text('Selamat datang, ' + widget.email, style: Theme.of(context).textTheme.titleLarge),
    const SizedBox(height: 12),
    Wrap(spacing: 10, runSpacing: 10, children: [
      metric('Jenis Produk', products.length.toString()),
      metric('Total Stok', products.fold<int>(0, (n, p) => n + p.stock).toString()),
      metric('Transaksi', stats['count'].toString()),
      metric('Omzet Lokal', money(stats['revenue'] as num)),
    ]),
    const SizedBox(height: 14),
    const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Katalog, transaksi kasir, dan laporan utama disimpan secara lokal di perangkat.'))),
  ]));
  Widget productPage() => Column(children: [
    Padding(padding: const EdgeInsets.all(14), child: Row(children: [
      const Expanded(child: Text('Katalog produk', style: TextStyle(fontWeight: FontWeight.bold))),
      FilledButton.icon(onPressed: () => editProduct(), icon: const Icon(Icons.add), label: const Text('Tambah')),
    ])),
    Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : products.isEmpty ? empty('Belum ada produk', 'Tambahkan produk pertama untuk mulai berjualan.') : ListView(children: products.map((x) => Card(child: ListTile(
      title: Text(x.name), subtitle: Text((x.sku.isEmpty ? 'Tanpa SKU' : x.sku) + ' • Stok ' + x.stock.toString()),
      leading: CircleAvatar(child: Text(x.name[0].toUpperCase())),
      trailing: PopupMenuButton<String>(onSelected: (v) async { if (v == 'edit') await editProduct(x); if (v == 'delete') { await widget.store.remove(x.id); await refresh(); } }, itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Hapus'))]),
    ))).toList())),
  ]);
  Widget cashier() {
    final total = products.where((x) => cart.containsKey(x.id)).fold<double>(0, (sum, x) => sum + x.price * cart[x.id]!);
    final activeProducts = products.where((x) => x.stock > 0).toList();
    return Column(children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('Pilih produk untuk keranjang')),
      Expanded(child: activeProducts.isEmpty ? empty('Stok kosong', 'Tambahkan produk atau perbarui stok.') : ListView(children: activeProducts.map((x) => Card(child: ListTile(title: Text(x.name), subtitle: Text(money(x.price) + ' • Stok ' + x.stock.toString()), trailing: IconButton(onPressed: (cart[x.id] ?? 0) >= x.stock ? null : () => setState(() => cart[x.id] = (cart[x.id] ?? 0) + 1), icon: const Icon(Icons.add_circle_outline))))).toList())),
      Card(margin: const EdgeInsets.all(12), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
        Row(children: [const Expanded(child: Text('Total')), Text(money(total), style: const TextStyle(fontWeight: FontWeight.bold))]),
        ...cart.entries.where((e) => products.any((x) => x.id == e.key)).map((e) {
          final x = products.firstWhere((x) => x.id == e.key);
          return ListTile(dense: true, title: Text(x.name), subtitle: Text(e.value.toString() + ' × ' + money(x.price)), trailing: IconButton(onPressed: () => setState(() { if (e.value <= 1) { cart.remove(e.key); } else { cart[e.key] = e.value - 1; } }), icon: const Icon(Icons.remove_circle_outline)));
        }),
        FilledButton.icon(onPressed: cart.isEmpty || saving ? null : () async {
          setState(() => saving = true);
          try {
            final id = await widget.store.checkout(Map<int, int>.from(cart), widget.email);
            cart.clear();
            await refresh();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Transaksi #' + id.toString() + ' tersimpan.')));
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Bad state: ', ''))));
          }
          if (mounted) setState(() => saving = false);
        }, icon: const Icon(Icons.check), label: Text(saving ? 'Menyimpan…' : 'Simpan transaksi')),
      ]))),
    ]);
  }
  Widget reports() => RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.all(14), children: [
    Text('Laporan lokal', style: Theme.of(context).textTheme.titleLarge),
    metric('Total omzet', money(stats['revenue'] as num)),
    metric('Transaksi', stats['count'].toString()),
    metric('Item terjual', stats['items'].toString()),
    const SizedBox(height: 10),
    const Text('Transaksi terbaru', style: TextStyle(fontWeight: FontWeight.bold)),
    ...(stats['recent'] as List<Map<String, Object?>>).map((s) => Card(child: ListTile(
      title: Text(money(s['total'] as num)),
      subtitle: Text(s['item_count'].toString() + ' item • ' + (s['created'] as String).replaceFirst('T', ' ')),
      trailing: Text('#' + s['id'].toString()),
    ))),
  ]));
  Widget settings() => ListView(padding: const EdgeInsets.all(14), children: [
    Card(child: ListTile(leading: const Icon(Icons.person_outline), title: Text(widget.email), subtitle: const Text('Akun aplikasi'))),
    Card(child: Column(children: [
      ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Hapus Akun'), trailing: const Icon(Icons.open_in_new), onTap: () => openExternal(context, deleteUrl)),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacy'), trailing: const Icon(Icons.open_in_new), onTap: () => openExternal(context, privacyUrl)),
      const Divider(height: 1),
      ListTile(leading: const Icon(Icons.chat_outlined), title: const Text('Hubungi Sales via WhatsApp'), onTap: () => openWhatsApp(context)),
    ])),
    const SizedBox(height: 12),
    const Text('Versi 1.0.0 • PT Berkah Tiga Puteri', textAlign: TextAlign.center),
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(titles[tab])),
    body: Column(children: [
      if (widget.status == 'inactive') Material(color: const Color(0xFFFFF3DA), child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Expanded(child: Text('Akun Belum Aktif, hubungi tim Berkah POS untuk aktivasi')),
        TextButton(onPressed: () => openWhatsApp(context), child: const Text('WhatsApp')),
      ]))) else if (widget.status == 'unknown') const Padding(padding: EdgeInsets.all(8), child: Text('Mode trial lokal — status aktivasi belum dapat diverifikasi.')),
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) : [dashboard(), productPage(), cashier(), reports(), settings()][tab]),
    ]),
    bottomNavigationBar: NavigationBar(selectedIndex: tab, onDestinationSelected: (value) { setState(() => tab = value); if (value == 3) refresh(); }, destinations: const [
      NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Produk'),
      NavigationDestination(icon: Icon(Icons.point_of_sale_outlined), label: 'Kasir'),
      NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Laporan'),
      NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'Settings'),
    ]),
  );
}
