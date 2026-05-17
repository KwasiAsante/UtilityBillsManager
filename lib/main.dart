import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:utility_bills_manager/services/logs/server_log_output.dart';

import 'firebase_options.dart';
import 'config/app_config.dart';
import 'config/server_configuration.dart';
import 'data/models/app_state.dart';
import 'database/db_factory.dart';
import 'factory/notification/notification_service_factory.dart';
import 'factory/windows/tray_manager_service_factory_native.dart';
import 'factory/windows/windows_manager_service_factory_native.dart';
import 'helpers/database/database_helper.dart';
import 'screens/main_tab_screen.dart';
import 'services/api/api_service.dart';
import 'services/auth/auth_service.dart';
import 'services/logs/log_upload_service.dart';
import 'utils/app_logger.dart';
import 'utils/windows/data_migration.dart';

/// Application entry point.
///
/// Startup sequence:
/// 1. Initialise Flutter bindings.
/// 2. On Windows: init window manager (shows the window) and tray manager.
/// 3. Call runApp() immediately so the window renders a loading screen.
/// 4. AppInitializer widget completes the rest of the startup sequence:
///    pdfrx, Firebase, sqflite, config, notifications.

final navigatorKey = GlobalKey<NavigatorState>();
final notificationService = createNotificationService();
AppLogger _logger = AppLogger();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // No .env asset — all config falls back to hard-coded defaults.
  }

  _logger.d('[AppInitializer] AppConfig init...', toFile: true, toServer: false);
  await AppConfig.init();

  var deviceId = await AppConfig.deviceId;
  _logger.i("Device Id: $deviceId", toFile: false, toServer: false);

  await addAppMeta();

  if (kIsWeb) {
   _logger.i('Running on web platform');
  } else {
   _logger.i('Running on ${defaultTargetPlatform.name} platform');
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await DataMigration.runIfNeeded();
      await initWindowManager();
      await initTrayManager();
    }
  }

  // runApp is called here so the window immediately renders a loading screen
  // instead of staying blank while async initialization runs.
  runApp(const MyApp());
}

dynamic addAppMeta() async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  String version = packageInfo.version;
  String buildNum = packageInfo.buildNumber;
 _logger.i('App version: $version.$buildNum');
}

/// Runs all async startup steps inside the widget tree.
///
/// Wrapping initialization here means the window always shows real content
/// (a loading spinner) rather than a blank white screen while awaiting
/// network-dependent calls like Firebase or pdfrx.
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  late final Future<void> _initFuture = _initialize();

  Future<void> _initialize() async {
    // Firebase is not configured for Linux.
    if (defaultTargetPlatform != TargetPlatform.linux) {
      try {
       _logger.d('[AppInitializer] Firebase init...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 15));
       _logger.d('[AppInitializer] Firebase init done');
      } catch (e) {
       _logger.w('[AppInitializer] Firebase init failed or timed out: $e');
      }
    }

    try {
     _logger.d('[AppInitializer] pdfrx init...');
      await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true)
          .timeout(const Duration(seconds: 15));
     _logger.d('[AppInitializer] pdfrx init done');
    } catch (e) {
     _logger.w('[AppInitializer] pdfrx init failed or timed out: $e');
    }

    // Start end-of-day log upload service (file system not available on web)
    if (!kIsWeb) {
      LogUploadService(logOutput:ServerLogOutput()).start();
    }

    AppState().localDB = AppConfig.mode == AppMode.server;

    initDb();

   _logger.d('[AppInitializer] Database open...');
    await DatabaseHelper().database;
   _logger.d('[AppInitializer] Database open done');

    await AppConfig.load();

    ApiService.configure(baseUrl: AppConfig.apiBaseUrl);
    await AuthService().loadFromPrefs();

   _logger.d('[AppInitializer] ServerConfiguration init...');
    await ServerConfiguration.init();

   _logger.d('[AppInitializer] Notification service init...');
    await notificationService.initialize();
    notificationService.setNavigatorKey(navigatorKey);
    await notificationService.handleLaunchNotification();
   _logger.d('[AppInitializer] Startup complete');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
         _logger.e(
            '[AppInitializer] Fatal init error: ${snapshot.error}',
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const MainTabScreen();
      },
    );
  }
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.shade50,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const AppInitializer(),
    );
  }
}