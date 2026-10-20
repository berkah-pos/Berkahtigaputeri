import 'package:flutter/material.dart';
import '../../core/api/laravel_api_client.dart';
import '../../core/config/app_identity_store.dart';

/// Authenticated entry point for cloud-backed use.
///
/// A local-only path is available for offline/demo work. It deliberately does
/// not pass a cloud configuration service to the POS shell.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.apiClient,
    required this.identityStore,
    required this.onAuthenticated,
    required this.onContinueLocal,
    this.configurationMessage,
  });

  final LaravelApiClient? apiClient;
  final AppIdentityStore identityStore;
  final VoidCallback onAuthenticated;
  final VoidCallback onContinueLocal;
  final String? configurationMessage;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (widget.apiClient == null ||
        !(_formKey.currentState?.validate() ?? false) ||
        _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await widget.apiClient!.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      final tenantId = user['tenant_id']?.toString().trim() ?? '';
      if (tenantId.isEmpty) {
        await widget.apiClient!.logout();
        throw const ApiException(
          403,
          'tenant_not_entitled',
          'Akun belum ditautkan ke tenant aktif. Hubungi administrator.',
        );
      }
      await widget.identityStore.setTenantId(tenantId);
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onAuthenticated();
    } catch (error) {
      if (!mounted) return;
      var message = 'Login gagal. Periksa email dan kata sandi.';
      if (error is ApiException) {
        message = error.statusCode == 401
            ? 'Email atau kata sandi tidak cocok.'
            : error.message;
      } else if (error is ApiTransportException) {
        message = error.message;
      }
      setState(() {
        _loading = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(
                    Icons.point_of_sale_rounded,
                    size: 68,
                    color: Color(0xFF137A4B),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Berkah POS',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PT Berkah Tiga Puteri',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: widget.apiClient == null
                          ? _buildLocalOnlyNotice(context)
                          : _buildLoginForm(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Masuk hanya membuktikan identitas akun. Akses cloud '
                    'tetap memerlukan membership tenant dan enrollment '
                    'perangkat yang diverifikasi server.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocalOnlyNotice(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Icon(Icons.cloud_off_outlined, size: 42),
        const SizedBox(height: 12),
        Text(
          'Mode cloud belum tersedia pada build ini',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          widget.configurationMessage ??
              'BERKAH_API_BASE_URL belum diatur.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : widget.onContinueLocal,
          icon: const Icon(Icons.point_of_sale),
          label: const Text('Lanjutkan sebagai kasir lokal'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Data akan disimpan di perangkat ini saja. Sinkronisasi cloud, '
          'membership tenant, dan subscription belum aktif pada mode lokal.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Masuk ke akun Berkah POS',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          const Text(
            'Gunakan akun yang disediakan administrator. Aplikasi tidak '
            'menggunakan alamat email saja sebagai bukti kepemilikan akun.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            enabled: !_loading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[AutofillHints.username, AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final normalized = value?.trim() ?? '';
              if (!normalized.contains('@') ||
                  normalized.startsWith('@') ||
                  normalized.endsWith('@')) {
                return 'Masukkan email yang valid.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            enabled: !_loading,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            onFieldSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Kata sandi',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi',
                onPressed: _loading
                    ? null
                    : () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword ? Icons.visibility_off : Icons.visibility,
                ),
              ),
            ),
            validator: (value) =>
                (value ?? '').isEmpty ? 'Kata sandi wajib diisi.' : null,
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (widget.configurationMessage != null &&
              widget.configurationMessage!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              widget.configurationMessage!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _signIn,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(_loading ? 'Memeriksa akun...' : 'Masuk'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : widget.onContinueLocal,
            icon: const Icon(Icons.wifi_off),
            label: const Text('Lanjutkan lokal tanpa akun'),
          ),
        ],
      ),
    );
  }
}
