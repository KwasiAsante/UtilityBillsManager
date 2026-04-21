import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'firebase_options.dart';
import 'config/app_config.dart';
import 'config/server_configuration.dart';
import 'data/models/app_state.dart';
import 'database/db_factory.dart';
import 'factory/notification/notification_service_factory.dart';
import 'helpers/database/database_helper.dart';
import 'screens/main_tab_screen.dart';
import 'services/api/api_service.dart';
import 'utils/app_logger.dart';


/// Application entry point.
///
/// Startup sequence:
/// 1. Initialise Flutter bindings.
/// 2. Initialise the `pdfrx` WASM engine (used for PDF email-attachment parsing).
/// 3. Load optional `local_secrets.json` configuration via [AppConfig.init].
/// 4. Set up the correct `sqflite` database factory for the current platform
///    (web → FFI web, desktop → FFI, mobile → default native).
/// 5. Open the database (runs migrations if needed).
/// 6. Set [AppState.localDB] and configure [ApiService.baseUrl].
/// 7. Start the local shelf HTTP server when running in server mode.
/// 8. Launch the Flutter widget tree.

final navigatorKey = GlobalKey<NavigatorState>();
final notificationService = createNotificationService();
void main() async {
  final s = const String.fromEnvironment('BUILD_TARGET');
  AppLogger().i('BUILD_TARGET: $s');
  
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase is not configured for Linux. Wrap in a platform guard to avoid
  // a runtime exception when running on Linux during development.
  if (defaultTargetPlatform != TargetPlatform.linux) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  // PDF text extraction (email attachments) uses pdfrx on web/mobile/desktop
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);

  await AppConfig.init();

  AppState().localDB = AppConfig.mode == AppMode.server;

  initDb(); // automatically picks the right implementation

  // Initialize local database on all platforms (including web with FFI web)
  await DatabaseHelper().database;

  await AppConfig.load();

  ApiService.configure(baseUrl: AppConfig.apiBaseUrl);

  await ServerConfiguration.init();

  await notificationService.initialize();

  notificationService.setNavigatorKey(navigatorKey);
  await notificationService.handleLaunchNotification();

  runApp(const MyApp());
}
/// Root [StatelessWidget] that configures the [MaterialApp] and injects
/// the deep-purple colour scheme.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Utility Bill Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        cardTheme: CardThemeData(
          elevation: 1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const MainTabScreen(),
    );
  }
}

/// Unused Flutter starter-template scaffold — kept for reference only.
/// The app's real entry point is [MainTabScreen].
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
