import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api/laravel_api_client.dart';
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

  LaravelApiClient? apiClient;
  ConfigService? configService;
  String cloudConfigurationMessage;

  if (_apiBaseUrl.trim().isEmpty) {
    cloudConfigurationMessage =
        'Backend Laravel belum dikonfigurasi pada build ini. '
        'Atur BERKAH_API_BASE_URL untuk mengaktifkan login cloud. '
        'Mode kasir lokal tetap tersedia.';
  } else {
    try {
      final sessionStore = ApiSessionStore();
      await sessionStore.restore();
      apiClient = LaravelApiClient(
        baseUri: Uri.parse(_apiBaseUrl.trim()),
        sessions: sessionStore,
      );
      configService = ConfigService(apiClient, preferences);
      cloudConfigurationMessage = '';
    } catch (_) {
      cloudConfigurationMessage =
          'Alamat backend Laravel tidak valid. Gunakan origin HTTPS resmi. '
          'Mode kasir lokal tetap tersedia.';
    }
  }

  runApp(
    BerkahTigaPuteriApp(
      database: database,
      apiClient: apiClient,
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
    this.apiClient,
    this.configService,
    this.identityStore,
    this.cloudConfigurationMessage,
  });

  final PosDatabase? database;
  final LaravelApiClient? apiClient;
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
          ? const Scaffold(body: Center(child: Text('Berkah Tiga Puteri POS')))
          : _AppGate(
              database: database!,
              apiClient: apiClient,
              configService: configService,
              identityStore: identityStore!,
              cloudConfigurationMessage: cloudConfigurationMessage,
            ),
    );
  }
}

/// Keeps the authenticated/local-mode switch inside one stable route.
class _AppGate extends StatefulWidget {
  const _AppGate({
    required this.database,
    required this.apiClient,
    required this.configService,
    required this.identityStore,
    required this.cloudConfigurationMessage,
  });

  final PosDatabase database;
  final LaravelApiClient? apiClient;
  final ConfigService? configService;
  final AppIdentityStore identityStore;
  final String? cloudConfigurationMessage;

  @override
  State<_AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<_AppGate> {
  bool _localOnly = false;

  void _continueLocalOnly() => setState(() => _localOnly = true);
  void _authenticated() => setState(() => _localOnly = false);

  Future<void> _signOut() async {
    await widget.apiClient?.logout();
    await widget.identityStore.setTenantId('');
    if (!mounted) return;
    setState(() => _localOnly = false);
  }

  Widget _home({required bool localOnly}) {
    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      configService: localOnly ? null : widget.configService,
      apiClient: localOnly ? null : widget.apiClient,
      onSignOut: !localOnly && widget.apiClient != null ? _signOut : null,
    );
  }

  @override
  void dispose() {
    widget.apiClient?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) return _home(localOnly: true);
    final client = widget.apiClient;
    if (client == null) {
      return LoginScreen(
        apiClient: null,
        identityStore: widget.identityStore,
        configurationMessage: widget.cloudConfigurationMessage,
        onAuthenticated: _authenticated,
        onContinueLocal: _continueLocalOnly,
      );
    }
    if (client.hasAuthenticatedSession) return _home(localOnly: false);
    return LoginScreen(
      apiClient: client,
      identityStore: widget.identityStore,
      configurationMessage: widget.cloudConfigurationMessage,
      onAuthenticated: _authenticated,
      onContinueLocal: _continueLocalOnly,
    );
  }
}
