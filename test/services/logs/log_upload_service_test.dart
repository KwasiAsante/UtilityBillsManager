import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/services/logs/log_upload_service.dart';
import 'package:utility_bills_manager/services/logs/server_log_output.dart';

// ---------------------------------------------------------------------------
// Fake HTTP client
// ---------------------------------------------------------------------------

class _FakeHttpClient extends http.BaseClient {
  final int statusCode;
  final List<Map<String, dynamic>> captured = [];

  _FakeHttpClient({this.statusCode = 200});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    captured.add({
      'method': request.method,
      'path': request.url.path,
      'headers': Map<String, String>.from(request.headers),
      'body': body,
    });
    return http.StreamedResponse(
      Stream.fromIterable(<List<int>>[]),
      statusCode,
    );
  }
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

String _todayStr() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('LogUploadService.uploadGap', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('log_upload_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('POSTs content from byteOffset to EOF', () async {
      // Write 3 lines to today's log file; simulate that line1 was already sent.
      final today = _todayStr();
      final file = File('${tempDir.path}/$today.log');
      file.writeAsStringSync('line1\nline2\nline3\n');
      // 'line1\n' = 6 bytes in UTF-8

      final logOutput = ServerLogOutput(
        getDeviceId: () async => '',
        getBaseUrl: () => '',
      );
      logOutput.setByteOffset(6); // simulate 'line1\n' already sent

      final fakeClient = _FakeHttpClient(statusCode: 200);
      final service = LogUploadService(
        logOutput: logOutput,
        client: fakeClient,
        getDeviceId: () async => 'my-device',
        getBaseUrl: () => 'http://server',
        getLogsDir: () async => tempDir.path,
      );

      await service.uploadGap();

      expect(fakeClient.captured, hasLength(1));
      final req = fakeClient.captured.first;
      expect(req['path'], '/logs/device/upload');
      expect(req['method'], 'POST');
      expect(req['headers']['x-device-id'], 'my-device');
      expect(req['body'], 'line2\nline3\n');
    });

    test('resets byteOffset to 0 on successful upload', () async {
      final today = _todayStr();
      final file = File('${tempDir.path}/$today.log');
      file.writeAsStringSync('line1\nline2\n');

      final logOutput = ServerLogOutput(
        getDeviceId: () async => '',
        getBaseUrl: () => '',
      );
      logOutput.setByteOffset(6);

      final service = LogUploadService(
        logOutput: logOutput,
        client: _FakeHttpClient(statusCode: 200),
        getDeviceId: () async => 'dev',
        getBaseUrl: () => 'http://server',
        getLogsDir: () async => tempDir.path,
      );

      await service.uploadGap();

      expect(logOutput.byteOffset, 0);
    });

    test('does not reset byteOffset on upload failure', () async {
      final today = _todayStr();
      final file = File('${tempDir.path}/$today.log');
      file.writeAsStringSync('line1\nline2\n');

      final logOutput = ServerLogOutput(
        getDeviceId: () async => '',
        getBaseUrl: () => '',
      );
      logOutput.setByteOffset(6);

      final service = LogUploadService(
        logOutput: logOutput,
        client: _FakeHttpClient(statusCode: 500),
        getDeviceId: () async => 'dev',
        getBaseUrl: () => 'http://server',
        getLogsDir: () async => tempDir.path,
      );

      await service.uploadGap();

      expect(logOutput.byteOffset, 6); // unchanged
    });

    test('is a no-op when log file does not exist', () async {
      final logOutput = ServerLogOutput(
        getDeviceId: () async => '',
        getBaseUrl: () => '',
      );
      final fakeClient = _FakeHttpClient();

      final service = LogUploadService(
        logOutput: logOutput,
        client: fakeClient,
        getDeviceId: () async => 'dev',
        getBaseUrl: () => 'http://server',
        getLogsDir: () async => tempDir.path, // empty dir — no log file
      );

      await service.uploadGap();

      expect(fakeClient.captured, isEmpty);
    });

    test('is a no-op when file has no new bytes past byteOffset', () async {
      final today = _todayStr();
      final file = File('${tempDir.path}/$today.log');
      file.writeAsStringSync('line1\n');

      final logOutput = ServerLogOutput(
        getDeviceId: () async => '',
        getBaseUrl: () => '',
      );
      logOutput.setByteOffset(6); // whole file already sent

      final fakeClient = _FakeHttpClient();
      final service = LogUploadService(
        logOutput: logOutput,
        client: fakeClient,
        getDeviceId: () async => 'dev',
        getBaseUrl: () => 'http://server',
        getLogsDir: () async => tempDir.path,
      );

      await service.uploadGap();

      expect(fakeClient.captured, isEmpty);
    });
  });
}
