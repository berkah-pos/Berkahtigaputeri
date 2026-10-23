import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/laravel_auth_service.dart';
import 'core/config/app_identity_store.dart';
import 'core/database/pos_database.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

const String _laravelApiBaseUrl = String.fromEnvironment('BERKAH_API_BASE_URL');

typedef PreferencesLoader = Future<SharedPreferences> Function();
typedef PosDatabaseLoader = Future<PosDatabase> Function();

Future<SharedPreferences> _loadPreferences() => SharedPreferences.getInstance();

Future<PosDatabase> _openDefaultDatabase() => PosDatabase.openDefault();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BerkahTigaPuteriBootstrapApp());
}

/// Keeps initialization failures inside the UI so a locked, unavailable, or
/// otherwise unhealthy local database does not terminate the app before it can
/// explain the problem or offer a retry. Business data is never deleted here.
class BerkahTigaPuteriBootstrapApp extends StatefulWidget {
  const BerkahTigaPuteriBootstrapApp({
    super.key,
    this.loadPreferences = _loadPreferences,
    this.openDatabase = _openDefaultDatabase,
    this.apiBaseUrl = _laravelApiBaseUrl,
  });

  final PreferencesLoader loadPreferences;
  final PosDatabaseLoader openDatabase;
  final String apiBaseUrl;

  @override
  State<BerkahTigaPuteriBootstrapApp> createState() =>
      _BerkahTigaPuteriBootstrapAppState();
}

class _BerkahTigaPuteriBootstrapAppState
    extends State<BerkahTigaPuteriBootstrapApp> {
  bool _loading = true;
  String? _error;
  PosDatabase? _database;
  LaravelAuthService? _authService;
  AppIdentityStore? _identityStore;
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    PosDatabase? openedDatabase;
    try {
      final preferences = await widget.loadPreferences();
      openedDatabase = await widget.openDatabase();
      final identityStore = AppIdentityStore(preferences);
      final deviceId = await identityStore.ensureDeviceId();
      final authService = LaravelAuthService(
        baseUrl: widget.apiBaseUrl,
        vault: const FlutterSecureVault(),
      );

      if (!mounted) {
        await openedDatabase.close();
        return;
      }

      setState(() {
        _database = openedDatabase;
        _identityStore = identityStore;
        _deviceId = deviceId;
        _authService = authService;
        _loading = false;
        _error = null;
      });
    } catch (error, stackTrace) {
      if (openedDatabase != null) {
        try {
          await openedDatabase.close();
        } catch (_) {
          // Keep the original startup failure visible.
        }
      }
      debugPrint(
        'Berkah POS startup failed (' + error.runtimeType.toString() + '): ' +
            stackTrace.toString(),
      );
      if (!mounted) return;
      setState(() {
        _database = null;
        _identityStore = null;
        _deviceId = null;
        _authService = null;
        _loading = false;
        _error = 'Startup failed (' + error.runtimeType.toString() + '). '
            'Your existing local data was not deleted by this recovery flow. '
            'Check device storage, then retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final database = _database;
    final authService = _authService;
    final identityStore = _identityStore;
    final deviceId = _deviceId;

    if (database != null &&
        authService != null &&
        identityStore != null &&
        deviceId != null) {
      return BerkahTigaPuteriApp(
        database: database,
        authService: authService,
        identityStore: identityStore,
        deviceId: deviceId,
      );
    }

    return MaterialApp(
      title: 'Berkah Tiga Puteri POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF137A4B),
        useMaterial3: true,
      ),
      home: _loading
          ? const Scaffold(
              body: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Menyiapkan data lokal Berkah POS...'),
                    ],
                  ),
                ),
              ),
            )
          : _BootstrapFailureScreen(
              message: _error ?? 'Aplikasi belum dapat dimulai.',
              onRetry: _initialize,
            ),
    );
  }
}

class _BootstrapFailureScreen extends StatelessWidget {
  const _BootstrapFailureScreen({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Berkah POS')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(
                    Icons.storage_rounded,
                    size: 56,
                    color: Color(0xFF137A4B),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Data lokal belum siap',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Coba lagi'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Jangan hapus data aplikasi untuk mengatasi masalah ini. '
                    'Jika percobaan ulang gagal, catat pesan kesalahan dan '
                    'hubungi dukungan.',
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
  String? _restoreError;
  bool _sessionCleanupPending = false;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    AuthSession? session;
    String? restoreError;
    var cleanupPending = false;
    try {
      if (widget.identityStore.sessionCleanupPending) {
        // Do not even read/restore a potentially leftover token until an
        // explicit retry confirms that secure-storage deletion succeeded.
        cleanupPending = true;
        restoreError = 'Logout sebelumnya belum dapat memastikan bahwa sesi '
            'cloud terhapus dari perangkat. Akses cloud tetap dikunci. Coba '
            'bersihkan sesi lagi atau lanjutkan dalam mode lokal.';
      } else {
        session = await widget.authService.restoreSession();
        if (session != null && session.tenantId.isNotEmpty) {
          await widget.identityStore.setTenantId(session.tenantId);
        }
      }
    } catch (error, stackTrace) {
      // A secure-storage/platform exception must not strand the UI on the
      // restoring spinner. Fail closed for cloud access but preserve local POS.
      debugPrint(
        'Berkah POS session restore failed (' +
            error.runtimeType.toString() +
            '): ' +
            stackTrace.toString(),
      );
      session = null;
      restoreError = 'Sesi cloud tidak dapat dipulihkan dari penyimpanan '
          'perangkat. Data lokal tetap tersedia. Coba masuk kembali atau '
          'lanjutkan dalam mode lokal.';
    }

    if (!mounted) return;
    setState(() {
      _session = session;
      _restoreError = restoreError;
      _sessionCleanupPending = cleanupPending;
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
      _restoreError = null;
      _sessionCleanupPending = false;
    });
  }

  Future<void> _signOut() async {
    var lockPersisted = false;

    // Hide cloud features immediately and persist the fail-closed latch before
    // attempting token deletion, so a failed delete cannot auto-login on restart.
    if (mounted) {
      setState(() {
        _session = null;
        _localOnly = false;
        _restoring = false;
        _sessionCleanupPending = true;
        _restoreError = 'Sedang membersihkan sesi cloud secara aman...';
      });
    }

    try {
      await widget.identityStore.setSessionCleanupPending(true);
      lockPersisted = true;
    } catch (error, stackTrace) {
      debugPrint(
        'Berkah POS could not persist logout lock (' +
            error.runtimeType.toString() +
            '): ' +
            stackTrace.toString(),
      );
    }

    try {
      await widget.authService.logout();
    } catch (error, stackTrace) {
      debugPrint(
        'Berkah POS local logout cleanup failed (' +
            error.runtimeType.toString() +
            '): ' +
            stackTrace.toString(),
      );
      if (!mounted) return;
      setState(() {
        _session = null;
        _localOnly = false;
        _restoring = false;
        _sessionCleanupPending = true;
        _restoreError = lockPersisted
            ? 'Sesi lokal belum dapat dihapus dari penyimpanan aman. Akses '
                'cloud tetap dikunci. Periksa penyimpanan perangkat lalu '
                'coba bersihkan sesi lagi.'
            : 'Sesi lokal belum dapat dikonfirmasi terhapus, dan penanda '
                'keamanan tidak dapat disimpan. Akses cloud dikunci untuk '
                'sesi aplikasi ini. Periksa penyimpanan perangkat lalu coba '
                'bersihkan sesi lagi.';
      });
      return;
    }

    try {
      await widget.identityStore.setSessionCleanupPending(false);
    } catch (error, stackTrace) {
      // The token has been removed, but retain the in-memory lock until the
      // persistent marker can be reset on a retry.
      debugPrint(
        'Berkah POS could not reset logout lock (' +
            error.runtimeType.toString() +
            '): ' +
            stackTrace.toString(),
      );
      if (!mounted) return;
      setState(() {
        _session = null;
        _localOnly = false;
        _restoring = false;
        _sessionCleanupPending = true;
        _restoreError = 'Token sesi sudah dihapus dari perangkat, tetapi '
            'penanda logout belum dapat direset. Coba bersihkan sesi lagi.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _session = null;
      _localOnly = false;
      _restoring = false;
      _sessionCleanupPending = false;
      _restoreError = null;
    });
  }

  Widget _home({required bool localOnly}) {
    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      authService: localOnly ? null : widget.authService,
      // Cloud config is now fetchable through Laravel; transaction sync remains separate.
      onSignOut: _sessionCleanupPending || (!localOnly && _session?.deviceIsActive == true)
          ? _signOut
          : null,
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
      initialRestoreMessage: _restoreError,
      sessionCleanupPending: _sessionCleanupPending,
      onAuthenticated: _authenticated,
      onContinueLocal: _continueLocalOnly,
      // Pending-device cleanup must work before the app gate owns an active session.
      onSignOut: _signOut,
    );
  }
}
