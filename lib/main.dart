import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pdfrx/pdfrx.dart';

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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await addAppMeta();

  if (kIsWeb) {
    AppLogger().i('Running on web platform');
  } else {
    AppLogger().i('Running on ${defaultTargetPlatform.name} platform');
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
  AppLogger().i('App version: $version.$buildNum');
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
        AppLogger().d('[AppInitializer] Firebase init...');
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).timeout(const Duration(seconds: 15));
        AppLogger().d('[AppInitializer] Firebase init done');
      } catch (e) {
        AppLogger().w('[AppInitializer] Firebase init failed or timed out: $e');
      }
    }

    try {
      AppLogger().d('[AppInitializer] pdfrx init...');
      await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true)
          .timeout(const Duration(seconds: 15));
      AppLogger().d('[AppInitializer] pdfrx init done');
    } catch (e) {
      AppLogger().w('[AppInitializer] pdfrx init failed or timed out: $e');
    }

    AppLogger().d('[AppInitializer] AppConfig init...');
    await AppConfig.init();

    // Start end-of-day log upload service (file system not available on web)
    if (!kIsWeb) {
      LogUploadService(logOutput: AppLogger().serverLogOutput).start();
    }

    AppState().localDB = AppConfig.mode == AppMode.server;

    initDb();

    AppLogger().d('[AppInitializer] Database open...');
    await DatabaseHelper().database;
    AppLogger().d('[AppInitializer] Database open done');

    await AppConfig.load();

    ApiService.configure(baseUrl: AppConfig.apiBaseUrl);
    await AuthService().loadFromPrefs();

    AppLogger().d('[AppInitializer] ServerConfiguration init...');
    await ServerConfiguration.init();

    AppLogger().d('[AppInitializer] Notification service init...');
    await notificationService.initialize();
    notificationService.setNavigatorKey(navigatorKey);
    await notificationService.handleLaunchNotification();
    AppLogger().d('[AppInitializer] Startup complete');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          AppLogger().e(
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