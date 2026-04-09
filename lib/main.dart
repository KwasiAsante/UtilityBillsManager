import 'package:flutter/material.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pdfrx/pdfrx.dart';

import '../config/app_config.dart';
import '../screens/main_tab_screen.dart';
import '../data/models/app_state.dart';
import '../helpers/database/database_helper.dart';
import '../services/api/api_service.dart';
import '../services/api/local_server_stub.dart'
    if (dart.library.io) '../services/api/local_server.dart';
import 'database/db_factory.dart';

// final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

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
/// 8. Initialise the local-notifications plugin.
/// 9. Launch the Flutter widget tree.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // PDF text extraction (email attachments) uses pdfrx on web/mobile/desktop
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  await AppConfig.init();

  initDb(); // automatically picks the right implementation

  // Initialize local database on all platforms (including web with FFI web)
  await DatabaseHelper().database;

  final mode = AppConfig.mode;
  AppState().localDB = mode == AppMode.server;
  ApiService.configure(baseUrl: AppConfig.apiBaseUrl);

  if (mode == AppMode.server) {
    await startServer(); // runs local API server

    // final db = DatabaseHelper();
    // // Sample Data for Testing
    // await db.createBill(
    //   Bill(
    //     company: 'Electricity Co.',
    //     type: BillType.electric,
    //     amount: 120.50,
    //     dueDate: '2025-04-01',
    //     status: PaymentStatus.unpaid,
    //     notes: 'March billing cycle',
    //   ),
    // );

    // await db.createBill(
    //   Bill(
    //     company: 'Water Utility',
    //     type: BillType.water,
    //     amount: 45.75,
    //     dueDate: '2025-03-28',
    //     status: PaymentStatus.paid,
    //     notes: 'February billing cycle',
    //   ),
    // );
  }

  // const initializationSettingsAndroid = AndroidInitializationSettings(
  //   '@mipmap/ic_launcher',
  // );
  // const darwinSettings = DarwinInitializationSettings();
  // const WindowsInitializationSettings windowsSettings =
  //     WindowsInitializationSettings(
  //       appName: 'Utility Bills Manager',
  //       appUserModelId: "com.kwasi.utility_bills_manager",
  //       guid: '94e9c1ef-2491-447e-90fe-cc3eddf2b4c6',
  //     );
  // const initializationSettings = InitializationSettings(
  //   android: initializationSettingsAndroid,
  //   iOS: darwinSettings,
  //   macOS: darwinSettings,
  //   windows: windowsSettings,
  // );
  //
  // await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  runApp(const MyApp());
}
/// Root [StatelessWidget] that configures the [MaterialApp] and injects
/// the deep-purple colour scheme.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
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
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
