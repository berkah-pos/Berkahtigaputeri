import 'package:flutter/material.dart';

import '../../core/auth/identity_service.dart';

/// Laravel Central API sign-in gate.
///
/// A local-only route remains available for offline POS use, but it never
/// receives an authenticated cloud service or cached bearer token.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.identityService,
    required this.onAuthenticated,
    required this.onContinueLocal,
    this.configurationMessage,
  });

  final IdentityService? identityService;
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
  bool _sendingRecoveryEmail = false;
  bool _feedbackIsError = true;
  String? _feedback;
  String? _selectedTenantId;
  List<TenantMembershipInfo> _memberships = const <TenantMembershipInfo>[];

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final identityService = widget.identityService;
    if (identityService == null ||
        !(_formKey.currentState?.validate() ?? false) ||
        _loading) {
      return;
    }

    setState(() {
      _loading = true;
      _feedback = null;
    });

    final result = await identityService.signIn(
      email: _email.text.trim(),
      password: _password.text,
      tenantId: _selectedTenantId,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _feedback = result.message;
      _feedbackIsError = result.status != SignInStatus.authenticated &&
          result.status != SignInStatus.devicePendingApproval;
      if (result.status == SignInStatus.tenantSelectionRequired) {
        _memberships = result.memberships;
        if (_selectedTenantId == null ||
            !_memberships.any((entry) => entry.tenantId == _selectedTenantId)) {
          _selectedTenantId =
              _memberships.isNotEmpty ? _memberships.first.tenantId : null;
        }
      } else if (result.status == SignInStatus.authenticated) {
        _memberships = const <TenantMembershipInfo>[];
      }
    });

    if (result.status == SignInStatus.authenticated) {
      widget.onAuthenticated();
    }
  }

  Future<void> _requestEmailVerification() async {
    final service = widget.identityService;
    if (service == null || _sendingRecoveryEmail) return;

    setState(() {
      _sendingRecoveryEmail = true;
      _feedback = null;
    });

    try {
      await service.requestEmailVerification(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _feedbackIsError = false;
        _feedback =
            'Jika akun memerlukan verifikasi, tautan akan dikirim ke email. '
            'Periksa kotak masuk dan folder spam.';
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _feedbackIsError = false;
        // Keep the same outward message to avoid account enumeration.
        _feedback =
            'Jika akun memerlukan verifikasi, tautan akan dikirim ke email. '
            'Periksa kotak masuk dan folder spam.';
      });
    } finally {
      if (mounted) setState(() => _sendingRecoveryEmail = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final service = widget.identityService;
    if (service == null || _sendingRecoveryEmail) return;

    final email = _email.text.trim();
    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      setState(() {
        _feedbackIsError = true;
        _feedback = 'Masukkan email yang valid terlebih dahulu.';
      });
      return;
    }

    setState(() {
      _sendingRecoveryEmail = true;
      _feedback = null;
    });

    try {
      await service.requestPasswordReset(email);
    } on Object {
      // The response intentionally does not reveal whether an account exists.
    } finally {
      if (!mounted) return;
      setState(() {
        _sendingRecoveryEmail = false;
        _feedbackIsError = false;
        _feedback =
            'Jika akun terdaftar dan dapat dipulihkan, instruksi reset '
            'kata sandi akan dikirim ke email.';
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
                      child: widget.identityService == null
                          ? _buildLocalOnlyNotice(context)
                          : _buildLoginForm(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Login memverifikasi identitas ke Central API. Akses SaaS '
                    'baru aktif setelah membership tenant dan perangkat '
                    'disetujui server.',
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
              'BERKAH_API_BASE_URL belum dikonfigurasi.',
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
          'Data disimpan di perangkat ini. Mode lokal tidak memberikan '
          'membership tenant, entitlement cloud, atau sinkronisasi SaaS.',
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
            'Gunakan akun yang disediakan administrator. Identitas dan akses '
            'tenant akan diverifikasi oleh server.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            enabled: !_loading && !_sendingRecoveryEmail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const <String>[
              AutofillHints.username,
              AutofillHints.email,
            ],
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
            enabled: !_loading && !_sendingRecoveryEmail,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.password],
            onFieldSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              labelText: 'Kata sandi',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _showPassword
                    ? 'Sembunyikan kata sandi'
                    : 'Tampilkan kata sandi',
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
          if (_memberships.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedTenantId,
              decoration: const InputDecoration(
                labelText: 'Pilih tenant',
                prefixIcon: Icon(Icons.store_outlined),
                border: OutlineInputBorder(),
              ),
              items: _memberships
                  .map(
                    (membership) => DropdownMenuItem<String>(
                      value: membership.tenantId,
                      child: Text(
                        '${membership.tenantId} · ${membership.role}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _loading
                  ? null
                  : (value) => setState(() => _selectedTenantId = value),
            ),
          ],
          if (_feedback != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              _feedback!,
              style: TextStyle(
                color: _feedbackIsError
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
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
          if (_feedback != null &&
              _feedbackIsError &&
              _feedback!.toLowerCase().contains('verifikasi')) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sendingRecoveryEmail
                  ? null
                  : _requestEmailVerification,
              icon: _sendingRecoveryEmail
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.mark_email_read_outlined),
              label: const Text('Kirim ulang email verifikasi'),
            ),
          ],
          TextButton(
            onPressed: _loading || _sendingRecoveryEmail
                ? null
                : _requestPasswordReset,
            child: const Text('Lupa kata sandi?'),
          ),
          const SizedBox(height: 4),
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
