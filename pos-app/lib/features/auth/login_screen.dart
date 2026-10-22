import 'package:flutter/material.dart';

import '../../core/auth/identity_service.dart';

/// Laravel Central API login. Local-only mode never receives cloud authority.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.api,
    required this.onAuthenticated,
    required this.onContinueLocal,
    this.configurationMessage,
  });

  final IdentityService? api;
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
  String? _message;
  bool _messageIsError = true;
  List<TenantMembershipInfo> _tenantChoices = const <TenantMembershipInfo>[];
  String? _selectedTenantId;
  SignInStatus? _lastStatus;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final api = widget.api;
    if (api == null ||
        !(_formKey.currentState?.validate() ?? false) ||
        _loading) {
      return;
    }

    if (_tenantChoices.isNotEmpty &&
        (_selectedTenantId == null || _selectedTenantId!.isEmpty)) {
      setState(() {
        _message = 'Pilih tenant yang tersedia pada akun Anda.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    final result = await api.signIn(
      email: _email.text.trim(),
      password: _password.text,
      tenantId: _selectedTenantId,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _lastStatus = result.status;
      _message = result.message;
      _messageIsError = result.status == SignInStatus.failed ||
          result.status == SignInStatus.deviceRevoked;
      if (result.status == SignInStatus.tenantSelectionRequired) {
        _tenantChoices = result.memberships;
        _selectedTenantId =
            result.memberships.length == 1 ? result.memberships.first.tenantId : null;
      }
    });

    if (result.isAuthenticated &&
        api.currentSession != null &&
        api.currentSession!.isDeviceSession) {
      widget.onAuthenticated();
    }
  }

  Future<void> _replaceRevokedDevice() async {
    final api = widget.api;
    if (api == null || _loading) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    final result = await api.replaceRevokedDeviceAndRequestEnrollment(
      email: _email.text.trim(),
      password: _password.text,
      tenantId: _selectedTenantId,
    );

    if (!mounted) return;
    setState(() {
      _loading = false;
      _lastStatus = result.status;
      _message = result.message;
      _messageIsError = result.status == SignInStatus.failed ||
          result.status == SignInStatus.deviceRevoked;
      if (result.status == SignInStatus.tenantSelectionRequired) {
        _tenantChoices = result.memberships;
        _selectedTenantId =
            result.memberships.length == 1 ? result.memberships.first.tenantId : null;
      }
    });

    if (result.isAuthenticated &&
        api.currentSession != null &&
        api.currentSession!.isDeviceSession) {
      widget.onAuthenticated();
    }
  }

  Future<void> _requestEmailVerification() async {
    final api = widget.api;
    final email = _email.text.trim();
    if (api == null || email.isEmpty || _loading) return;

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await api.requestEmailVerification(email);
      if (!mounted) return;
      setState(() {
        _message =
            'Jika akun memerlukan verifikasi, tautan akan dikirim ke email tersebut.';
        _messageIsError = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _message =
            'Permintaan verifikasi tidak dapat dikirim sekarang. Coba lagi nanti.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final api = widget.api;
    final email = _email.text.trim();
    if (api == null || email.isEmpty || _loading) return;

    if (!email.contains('@') || email.startsWith('@') || email.endsWith('@')) {
      setState(() {
        _message = 'Masukkan alamat email terlebih dahulu.';
        _messageIsError = true;
      });
      return;
    }

    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await api.requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _message =
            'Jika akun memenuhi syarat, tautan reset kata sandi akan dikirim ke alamat tersebut.';
        _messageIsError = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _message =
            'Permintaan reset kata sandi tidak dapat dikirim sekarang. Coba lagi nanti.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
                      child: widget.api == null
                          ? _buildLocalOnlyNotice(context)
                          : _buildLoginForm(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Login hanya membuktikan identitas akun. Sesi cloud kasir '
                    'memerlukan membership aktif dan perangkat yang disetujui '
                    'server Laravel.',
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
              'BERKAH_API_BASE_URL belum diatur untuk build ini.',
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
          'Data tetap tersimpan di perangkat ini. Tidak ada akses cloud yang '
          'diberikan dari ID tenant atau perangkat lokal.',
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
            'Gunakan akun yang disediakan administrator. Membership dan '
            'status perangkat diperiksa server sebelum sesi cloud dibuka.',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _email,
            enabled: !_loading,
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
          if (_tenantChoices.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey<String>('tenant-selector'),
              initialValue: _selectedTenantId,
              decoration: const InputDecoration(
                labelText: 'Tenant',
                prefixIcon: Icon(Icons.business_outlined),
                border: OutlineInputBorder(),
              ),
              items: _tenantChoices
                  .map((membership) => DropdownMenuItem<String>(
                        value: membership.tenantId,
                        child: Text(
                          membership.tenantId + ' · ' + membership.role,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(growable: false),
              onChanged: _loading
                  ? null
                  : (value) => setState(() {
                        _selectedTenantId = value;
                        _message = null;
                      }),
            ),
          ],
          if (_message != null) ...<Widget>[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                ),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _requestPasswordReset,
              child: const Text('Lupa kata sandi?'),
            ),
          ),
          if (_lastStatus == SignInStatus.emailVerificationRequired) ...<Widget>[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _loading ? null : _requestEmailVerification,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('Kirim tautan verifikasi email'),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _loading ? null : _signIn,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_lastStatus == SignInStatus.devicePendingApproval
                    ? Icons.refresh
                    : Icons.login),
            label: Text(
              _loading
                  ? 'Memeriksa akun...'
                  : _lastStatus == SignInStatus.devicePendingApproval
                      ? 'Coba lagi setelah perangkat disetujui'
                      : _tenantChoices.isNotEmpty
                          ? 'Pilih tenant & masuk'
                          : 'Masuk',
            ),
          ),
          if (_lastStatus == SignInStatus.deviceRevoked) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loading ? null : _replaceRevokedDevice,
              icon: const Icon(Icons.devices_other_outlined),
              label: const Text('Daftarkan ulang dengan ID perangkat baru'),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'ID baru tetap menunggu persetujuan administrator sebelum akses cloud diberikan.',
              ),
            ),
          ],
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
