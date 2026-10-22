import 'package:flutter/material.dart';

import '../../core/auth/laravel_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.authService,
    required this.deviceId,
    required this.onAuthenticated,
    required this.onContinueLocal,
    this.initialDeviceStatus,
    this.onSignOut,
  });

  final LaravelAuthService authService;
  final String deviceId;
  final Future<void> Function(AuthSession session) onAuthenticated;
  final VoidCallback onContinueLocal;
  final String? initialDeviceStatus;
  final Future<void> Function()? onSignOut;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _tenantId;
  List<TenantChoice> _tenantChoices = const <TenantChoice>[];
  bool _loading = false;
  String? _error;
  String? _pendingMessage;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false) || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _pendingMessage = null;
    });

    try {
      final session = await widget.authService.login(
        email: _email.text,
        password: _password.text,
        deviceId: widget.deviceId,
        tenantId: _tenantId,
      );
      if (!mounted) return;
      if (session.deviceIsActive) {
        await widget.onAuthenticated(session);
      } else {
        setState(() {
          _pendingMessage = 'Perangkat ini belum disetujui administrator. '
              'Data cloud tetap terkunci; kasir lokal tetap dapat digunakan. '
              'Setelah disetujui, masuk kembali untuk mengaktifkan sesi.';
        });
      }
    } on AuthFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        if (failure.code == 'tenant_selection_required') {
          _tenantChoices = failure.memberships;
          if (_tenantId != null &&
              !_tenantChoices.any((choice) => choice.id == _tenantId)) {
            _tenantId = null;
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Login gagal. Periksa koneksi lalu coba kembali.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOutPending() async {
    if (_loading || widget.onSignOut == null) return;
    setState(() => _loading = true);
    try {
      await widget.onSignOut!();
    } catch (_) {
      // Local credential cleanup is owned by the auth service.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.authService.isConfigured;
    final pending = widget.initialDeviceStatus == 'pending' ||
        widget.initialDeviceStatus == 'unregistered' ||
        _pendingMessage != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Berkah POS')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            Text(
              configured ? 'Masuk ke akun Berkah POS' : 'Mode lokal Berkah POS',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            if (!configured) ...<Widget>[
              const Text('Mode cloud belum tersedia pada build ini'),
              const SizedBox(height: 8),
              Text(widget.authService.configurationMessage ?? ''),
              const SizedBox(height: 16),
              const Text('Produk, penjualan, stok, dan laporan di mode ini '
                  'disimpan di perangkat. Mode lokal bukan sesi SaaS dan '
                  'tidak mengaktifkan sinkronisasi cloud.'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: widget.onContinueLocal,
                child: const Text('Lanjutkan sebagai kasir lokal'),
              ),
            ] else ...<Widget>[
              const Text(
                'Masuk memakai akun Laravel Berkah POS. Perangkat baru harus '
                'disetujui administrator sebelum mendapatkan akses cloud.',
              ),
              if (widget.initialDeviceStatus == 'pending' ||
                  widget.initialDeviceStatus == 'unregistered') ...<Widget>[
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Sesi tersimpan untuk perangkat yang belum aktif. '
                      'Cloud tetap dikunci sampai perangkat disetujui dan Anda masuk kembali.',
                    ),
                  ),
                ),
              ],
              if (_pendingMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_pendingMessage!),
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              Form(
                key: _formKey,
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if (text.isEmpty || !text.contains('@')) {
                          return 'Masukkan email yang valid.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Kata sandi',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').isEmpty
                          ? 'Kata sandi wajib diisi.'
                          : null,
                    ),
                    if (_tenantChoices.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _tenantId,
                        decoration: const InputDecoration(
                          labelText: 'Pilih tenant',
                          border: OutlineInputBorder(),
                        ),
                        items: _tenantChoices
                            .map((choice) => DropdownMenuItem<String>(
                                  value: choice.id,
                                  child: Text(choice.label),
                                ))
                            .toList(growable: false),
                        onChanged: _loading
                            ? null
                            : (value) => setState(() => _tenantId = value),
                        validator: (value) => value == null
                            ? 'Pilih tenant yang diberikan server.'
                            : null,
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _signIn,
                        child: Text(_loading ? 'Memproses…' : 'Masuk'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _loading ? null : widget.onContinueLocal,
                child: const Text('Lanjutkan lokal tanpa akun cloud'),
              ),
              if (pending && widget.onSignOut != null) ...<Widget>[
                TextButton(
                  onPressed: _loading ? null : _signOutPending,
                  child: const Text('Hapus sesi perangkat tertunda'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
