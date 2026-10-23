import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/laravel_auth_service.dart';
import 'core/config/app_identity_store.dart';
import 'core/database/pos_database.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

const String _laravelApiBaseUrl = String.fromEnvironment('BERKAH_API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final database = await PosDatabase.openDefault();
  final identityStore = AppIdentityStore(preferences);
  final deviceId = await identityStore.ensureDeviceId();
  final authService = LaravelAuthService(
    baseUrl: _laravelApiBaseUrl,
    vault: const FlutterSecureVault(),
  );

  runApp(
    BerkahTigaPuteriApp(
      database: database,
      authService: authService,
      identityStore: identityStore,
      deviceId: deviceId,
    ),
  );
}

class BerkahTigaPuteriApp extends StatelessWidget {
  const BerkahTigaPuteriApp({
    super.key,
    this.database,
    this.authService,
    this.identityStore,
    this.deviceId,
  });

  final PosDatabase? database;
  final LaravelAuthService? authService;
  final AppIdentityStore? identityStore;
  final String? deviceId;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Berkah Tiga Puteri POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF137A4B),
        useMaterial3: true,
      ),
      home: database == null ||
              identityStore == null ||
              authService == null ||
              deviceId == null
          ? const Scaffold(
              body: Center(child: Text('Berkah Tiga Puteri POS')),
            )
          : _AppGate(
              database: database!,
              authService: authService!,
              identityStore: identityStore!,
              deviceId: deviceId!,
            ),
    );
  }
}

/// Cloud UI is enabled only for a server-verified active membership + device.
/// SQLite POS remains available independently when the API is unavailable.
class _AppGate extends StatefulWidget {
  const _AppGate({
    required this.database,
    required this.authService,
    required this.identityStore,
    required this.deviceId,
  });

  final PosDatabase database;
  final LaravelAuthService authService;
  final AppIdentityStore identityStore;
  final String deviceId;

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _localOnly = false;
  bool _restoring = true;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await widget.authService.restoreSession();
    if (!mounted) return;
    if (session != null && session.tenantId.isNotEmpty) {
      await widget.identityStore.setTenantId(session.tenantId);
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _restoring = false;
    });
  }

  void _continueLocalOnly() {
    setState(() => _localOnly = true);
  }

  Future<void> _authenticated(AuthSession session) async {
    if (!session.deviceIsActive) return;
    await widget.identityStore.setTenantId(session.tenantId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _localOnly = false;
    });
  }

  Future<void> _signOut() async {
    try {
      await widget.authService.logout();
    } catch (_) {
      // Local token deletion still happens in logout's finally block.
    } finally {
      if (mounted) {
        setState(() {
          _session = null;
          _localOnly = false;
          _restoring = false;
        });
      }
    }
  }

  Widget _home({required bool localOnly}) {
    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      // Configuration/sync parity is a separate gate: identity alone must
      // not route to the legacy Supabase RPC or imply cloud synchronization.
      configService: null,
      onSignOut: !localOnly && _session?.deviceIsActive == true ? _signOut : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) return _home(localOnly: true);

    if (_restoring) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = _session;
    if (session?.deviceIsActive == true) return _home(localOnly: false);

    return LoginScreen(
      authService: widget.authService,
      deviceId: widget.deviceId,
      initialDeviceStatus: session?.deviceStatus,
      onAuthenticated: _authenticated,
      onContinueLocal: _continueLocalOnly,
      onSignOut: session == null ? null : _signOut,
    );
  }
}
