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
  String cloudConfigurationMessage;

  if (_apiBaseUrl.trim().isEmpty) {
    cloudConfigurationMessage =
        'BERKAH_API_BASE_URL belum dikonfigurasi pada build ini. '
        'Mode lokal tetap tersedia.';
  } else {
    try {
      identityService = IdentityService(
        baseUrl: _apiBaseUrl,
        identityStore: identityStore,
      );
      configService = ConfigService(identityService, preferences);
      try {
        await identityService.restoreSession();
        cloudConfigurationMessage = '';
      } on IdentityApiException {
        // A saved token remains in secure storage when the network is
        // unavailable, but it is never treated as authenticated until the
        // Central API verifies it successfully.
        cloudConfigurationMessage =
            'Sesi cloud tidak dapat diverifikasi. Periksa koneksi API; '
            'mode lokal tetap tersedia.';
      }
    } on Object {
      identityService = null;
      configService = null;
      cloudConfigurationMessage =
          'Alamat Central API tidak valid atau belum menggunakan HTTPS. '
          'Periksa BERKAH_API_BASE_URL pada konfigurasi build.';
    }
  }

  runApp(
    BerkahTigaPuteriApp(
      database: database,
      identityService: identityService,
      configService: configService,
      identityStore: identityStore,
      cloudConfigurationMessage: cloudConfigurationMessage,
    ),
  );
}

class BerkahTigaPuteriApp extends StatelessWidget {
  const BerkahTigaPuteriApp({
    super.key,
    this.database,
    this.identityService,
    this.configService,
    this.identityStore,
    this.cloudConfigurationMessage,
  });

  final PosDatabase? database;
  final IdentityService? identityService;
  final ConfigService? configService;
  final AppIdentityStore? identityStore;
  final String? cloudConfigurationMessage;

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
              identityService: identityService,
              configService: configService,
              identityStore: identityStore!,
              cloudConfigurationMessage: cloudConfigurationMessage,
            ),
    );
  }
}

/// Keeps the auth/local-mode switch inside one stable route. Login/logout
/// therefore replaces the app's current screen without leaving Settings on top
/// of an obsolete authenticated route.
class _AppGate extends StatefulWidget {
  const _AppGate({
    required this.database,
    required this.identityService,
    required this.configService,
    required this.identityStore,
    required this.cloudConfigurationMessage,
  });

  final PosDatabase database;
  final IdentityService? identityService;
  final ConfigService? configService;
  final AppIdentityStore identityStore;
  final String? cloudConfigurationMessage;

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _localOnly = false;

  void _continueLocalOnly() {
    setState(() => _localOnly = true);
  }

  void _authenticated() {
    setState(() => _localOnly = false);
  }

  Future<void> _signOut() async {
    try {
      await widget.identityService?.signOut();
    } finally {
      if (mounted) {
        // IdentityService always clears the local bearer token even when the
        // remote revocation endpoint cannot be reached.
        setState(() => _localOnly = false);
      }
    }
  }

  Widget _home({required bool localOnly}) {
    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      configService: localOnly ? null : widget.configService,
      onSignOut: !localOnly &&
              widget.identityService?.hasAuthenticatedSession == true
          ? _signOut
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) return _home(localOnly: true);

    if (widget.identityService?.hasAuthenticatedSession == true) {
      return _home(localOnly: false);
    }

    return LoginScreen(
      identityService: widget.identityService,
      configurationMessage: widget.cloudConfigurationMessage,
      onAuthenticated: _authenticated,
      onContinueLocal: _continueLocalOnly,
    );
  }
}
