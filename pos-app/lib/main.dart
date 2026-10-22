import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/identity_service.dart';
import 'core/config/app_identity_store.dart';
import 'core/config/config_service.dart';
import 'core/database/pos_database.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

const String _apiBaseUrl = String.fromEnvironment('BERKAH_API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final database = await PosDatabase.openDefault();
  final identityStore = AppIdentityStore(preferences);

  IdentityService? identityService;
  ConfigService? configService;
  var cloudConfigurationMessage = '';

  try {
    if (_apiBaseUrl.trim().isEmpty) {
      throw ArgumentError('BERKAH_API_BASE_URL is not configured.');
    }
    identityService = IdentityService(
      baseUrl: _apiBaseUrl,
      identityStore: identityStore,
    );
    configService = ConfigService(identityService);
  } catch (_) {
    cloudConfigurationMessage =
        'Cloud login belum dikonfigurasi pada build ini. Set '
        'BERKAH_API_BASE_URL ke origin HTTPS Laravel saat build. '
        'Mode lokal tetap tersedia.';
  }

  runApp(
    BerkahTigaPuteriApp(
      database: database,
      identityStore: identityStore,
      identityService: identityService,
      configService: configService,
      configurationMessage: cloudConfigurationMessage,
    ),
  );
}

class BerkahTigaPuteriApp extends StatelessWidget {
  const BerkahTigaPuteriApp({
    super.key,
    this.database,
    this.identityStore,
    this.identityService,
    this.configService,
    this.configurationMessage,
  });

  final PosDatabase? database;
  final AppIdentityStore? identityStore;
  final IdentityService? identityService;
  final ConfigService? configService;
  final String? configurationMessage;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Berkah Tiga Puteri POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF137A4B),
        useMaterial3: true,
      ),
      home: database == null || identityStore == null
          ? const Scaffold(
              body: Center(child: Text('Berkah Tiga Puteri POS')),
            )
          : _AppGate(
              database: database!,
              identityStore: identityStore!,
              identityService: identityService,
              configService: configService,
              configurationMessage: configurationMessage,
            ),
    );
  }
}

/// Restores cloud entry only after the Laravel API verifies the bearer token.
/// Local-only operation is deliberately kept as a separate, non-cloud state.
class _AppGate extends StatefulWidget {
  const _AppGate({
    required this.database,
    required this.identityStore,
    required this.identityService,
    required this.configService,
    required this.configurationMessage,
  });

  final PosDatabase database;
  final AppIdentityStore identityStore;
  final IdentityService? identityService;
  final ConfigService? configService;
  final String? configurationMessage;

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _localOnly = false;
  bool _checkingSession = true;
  String? _restoreError;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      final identityService = widget.identityService;
      if (identityService != null) {
        final session = await identityService.restoreSession();
        if (session != null && !session.isDeviceSession) {
          // Central admin credentials are never accepted as POS credentials.
          await identityService.signOut();
        }
      }
    } catch (_) {
      _restoreError =
          'Sesi cloud belum dapat diverifikasi. Coba masuk lagi saat server tersedia; mode lokal tetap bisa digunakan.';
    } finally {
      if (mounted) setState(() => _checkingSession = false);
    }
  }

  void _continueLocalOnly() {
    setState(() => _localOnly = true);
  }

  void _authenticated() {
    final session = widget.identityService?.currentSession;
    if (session == null || !session.isDeviceSession) {
      setState(() {
        _restoreError =
            'Sesi POS yang terikat tenant dan perangkat tidak tersedia. Akses cloud ditolak.';
      });
      return;
    }
    setState(() {
      _localOnly = false;
      _restoreError = null;
    });
  }

  Future<void> _signOut() async {
    final service = widget.identityService;
    if (service != null) await service.signOut();
    if (!mounted) return;
    setState(() {
      _localOnly = false;
      _restoreError = null;
    });
  }

  Widget _home({required bool localOnly}) {
    final session = widget.identityService?.currentSession;
    final verifiedCloudSession =
        !localOnly &&
        widget.identityService?.hasAuthenticatedSession == true &&
        session != null &&
        session.isDeviceSession;

    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      configService: verifiedCloudSession ? widget.configService : null,
      onSignOut: verifiedCloudSession ? _signOut : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) return _home(localOnly: true);

    if (_checkingSession) {
      return Scaffold(
        body: Center(
          child: Semantics(
            label: 'Memverifikasi sesi cloud',
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final session = widget.identityService?.currentSession;
    if (session != null && session.isDeviceSession) {
      return _home(localOnly: false);
    }

    return LoginScreen(
      api: widget.identityService,
      configurationMessage: _restoreError ??
          (widget.configurationMessage?.isNotEmpty == true
              ? widget.configurationMessage
              : null),
      onAuthenticated: _authenticated,
      onContinueLocal: _continueLocalOnly,
    );
  }
}
