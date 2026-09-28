import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sse_channel/sse_channel.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:utility_bills_manager/services/notification/sse_service_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AppLogger's server printer looks up AppConfig.deviceId, which reads
  // dotenv and shared_preferences — both loaded at real app startup, but
  // never in a plain unit test.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.testLoad(fileInput: '');
  });

  group('SseService.close', () {
    test(
        'does not throw when the active channel already self-closed '
        '(e.g. the OS dropped the connection while the app was backgrounded)',
        () {
      final controller = StreamChannelController<String?>();
      final channel = SseChannel(controller.foreign);
      // Simulate the transport tearing itself down independently of our
      // app's own close() call — e.g. a dropped network connection while
      // the app was backgrounded for the Android share sheet.
      channel.close();

      SseService.instance.debugActiveChannel = channel;

      expect(() => SseService.instance.close(), returnsNormally);
    });
  });
}
