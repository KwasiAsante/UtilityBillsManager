import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/config/app_config.dart';

/// Serves [assets] through the `flutter/assets` channel used by `rootBundle`.
/// Keys not in [assets] respond with null, which `rootBundle` reports as a
/// missing asset.
void _mockAssets(Map<String, String> assets) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    final content = assets[key];
    if (content == null) return null;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(content)));
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(dotenv.clean);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('AppConfig.loadEnv', () {
    test('loads entries from the env asset', () async {
      _mockAssets({'present.env': 'DEVICE_ID=abc\nAPP_MODE=client'});

      await AppConfig.loadEnv(fileName: 'present.env');

      expect(dotenv.env['DEVICE_ID'], 'abc');
      expect(dotenv.env['APP_MODE'], 'client');
    });

    test('falls back to no entries when the env asset is missing', () async {
      _mockAssets({});

      await AppConfig.loadEnv(fileName: 'missing.env');

      expect(dotenv.isInitialized, isTrue);
      expect(dotenv.env['DEVICE_ID'], isNull);
    });

    test('falls back to no entries when the env asset is empty', () async {
      _mockAssets({'empty.env': ''});

      await AppConfig.loadEnv(fileName: 'empty.env');

      expect(dotenv.isInitialized, isTrue);
      expect(dotenv.env['DEVICE_ID'], isNull);
    });
  });
}
