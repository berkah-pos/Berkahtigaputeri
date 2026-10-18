import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_identity_store.dart';
import 'core/config/central_api_client.dart';
import 'core/config/config_service.dart';
import 'core/database/pos_database.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';

const String _centralApiBaseUrl =
    String.fromEnvironment('CENTRAL_API_BASE_URL');
const String _configSourceModeName = String.fromEnvironment(
  'CONFIG_SOURCE_MODE',
  defaultValue: 'laravel',
);
const bool _configSourceKillSwitch = bool.fromEnvironment(
  'CONFIG_SOURCE_KILL_SWITCH',
  defaultValue: false,
);
const String _dualModeStartedAtUtc = String.fromEnvironment(
  'CONFIG_DUAL_MODE_STARTED_AT_UTC',
  defaultValue: '2026-10-15T00:00:00Z',
);
const String _dualModeDeadlineUtc = String.fromEnvironment(
  'CONFIG_DUAL_MODE_DEADLINE_UTC',
  defaultValue: '2026-11-12T00:00:00Z',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final database = await PosDatabase.openDefault();
  final identityStore = AppIdentityStore(preferences);

  CentralApiClient? apiClient;
  ConfigService? configService;
  String cloudConfigurationMessage;

  if (_centralApiBaseUrl.trim().isEmpty) {
    cloudConfigurationMessage =
        'Laravel Central API belum dikonfigurasi pada build ini. '
        'Atur CENTRAL_API_BASE_URL saat build. Mode lokal tetap tersedia.';
  } else {
    apiClient = CentralApiClient(
      baseUrl: _centralApiBaseUrl,
      preferences: preferences,
      secureStorage: const FlutterSecureStorage(),
    );
    await apiClient.hydrateSession();
    configService = ConfigService(
      apiClient,
      preferences,
      sourceMode: ConfigSourceMode.parse(_configSourceModeName),
      killSwitch: _configSourceKillSwitch,
      dualModeStartedAt: DateTime.tryParse(_dualModeStartedAtUtc),
      dualModeDeadline: DateTime.tryParse(_dualModeDeadlineUtc),
    );
    cloudConfigurationMessage = '';
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
  final CentralApiClient? apiClient;
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
              apiClient: apiClient,
              configService: configService,
              identityStore: identityStore!,
              cloudConfigurationMessage: cloudConfigurationMessage,
            ),
    );
  }
}

/// Keeps the cloud/local-mode switch inside one stable route.
class _AppGate extends StatefulWidget {
  const _AppGate({
    required this.database,
    required this.apiClient,
    required this.configService,
    required this.identityStore,
    required this.cloudConfigurationMessage,
  });

  final PosDatabase database;
  final CentralApiClient? apiClient;
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
    try {
      await widget.apiClient?.signOut();
    } finally {
      if (mounted) setState(() => _localOnly = false);
    }
  }

  Widget _home({required bool localOnly}) {
    return HomeScreen(
      database: widget.database,
      identityStore: widget.identityStore,
      configService: localOnly ? null : widget.configService,
      onSignOut: !localOnly && widget.apiClient != null ? _signOut : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_localOnly) return _home(localOnly: true);

    final client = widget.apiClient;
    if (client == null || !client.hasSession) {
      return LoginScreen(
        client: client,
        configurationMessage: widget.cloudConfigurationMessage,
        onAuthenticated: _authenticated,
        onContinueLocal: _continueLocalOnly,
      );
    }

    return _home(localOnly: false);
  }
}
