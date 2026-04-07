import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'; // Desktop
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'; // Web
import 'package:utility_bills_manager/config/app_config.dart';
import 'package:utility_bills_manager/screens/main_tab_screen.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';
import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/services/api/local_server_stub.dart'
    if (dart.library.io) 'package:utility_bills_manager/services/api/local_server.dart';

final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // PDF text extraction (email attachments) uses pdfrx on web/mobile/desktop
  await pdfrxFlutterInitialize(dismissPdfiumWasmWarnings: true);
  await AppConfig.init();

  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    // Desktop only — mobile must keep sqlite default native factory
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

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

  const initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const darwinSettings = DarwinInitializationSettings();
  const WindowsInitializationSettings windowsSettings =
      WindowsInitializationSettings(
        appName: 'Utility Bills Manager',
        appUserModelId: "com.kwasi.utility_bills_manager",
        guid: '94e9c1ef-2491-447e-90fe-cc3eddf2b4c6',
      );
  const initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: darwinSettings,
    macOS: darwinSettings,
    windows: windowsSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Utility Bill Manager',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
