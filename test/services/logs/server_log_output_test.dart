import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/services/logs/server_log_output.dart';
import 'package:logger/logger.dart';

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
      Stream.fromIterable(<List<int>>[utf8.encode('ok')]),
      statusCode,
    );
  }
}

class _FailingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(Exception('network unavailable'));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OutputEvent _infoEvent(String message) =>
    OutputEvent(LogEvent(Level.info, message), [message]);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ServerLogOutput', () {
    tearDown(() => ApiService.resetHttpClient());

    test('does not flush when buffer has fewer than 20 lines', () async {
      final fake = _FakeHttpClient();
      ApiService.overrideHttpClient(fake);

      final output = ServerLogOutput(getDeviceId: () async => 'dev-1');
      addTearDown(output.destroy);

      for (var i = 0; i < 19; i++) {
        output.output(_infoEvent('line $i'));
      }

      // Give async work a chance to run (there should be none)
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.captured, isEmpty,
          reason: 'should not flush with fewer than 20 lines');
    });

    test('flushes when buffer reaches 20 lines and advances byteOffset',
        () async {
      final fake = _FakeHttpClient(statusCode: 200);
      ApiService.overrideHttpClient(fake);

      final output = ServerLogOutput(getDeviceId: () async => 'dev-1');
      addTearDown(output.destroy);

      for (var i = 0; i < 20; i++) {
        output.output(_infoEvent('line $i'));
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.captured, hasLength(1));
      expect(fake.captured.first['path'], '/logs/device');
      expect(fake.captured.first['headers']['x-device-id'], 'dev-1');
      expect(fake.captured.first['method'], 'POST');

      // Verify the body is a JSON array of strings
      final body = jsonDecode(fake.captured.first['body'] as String);
      expect(body, isA<List>());
      expect((body as List).length, 20);

      // byteOffset should have advanced
      expect(output.byteOffset, greaterThan(0));
    });

    test('does not advance byteOffset on non-200 response', () async {
      final fake = _FakeHttpClient(statusCode: 500);
      ApiService.overrideHttpClient(fake);

      final output = ServerLogOutput(getDeviceId: () async => 'dev-1');
      addTearDown(output.destroy);

      for (var i = 0; i < 20; i++) {
        output.output(_infoEvent('line $i'));
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(output.byteOffset, 0);
    });

    test('is silent on network error', () async {
      ApiService.overrideHttpClient(_FailingHttpClient());

      final output = ServerLogOutput(getDeviceId: () async => 'dev-1');
      addTearDown(output.destroy);

      for (var i = 0; i < 20; i++) {
        output.output(_infoEvent('line $i'));
      }

      // Should complete without throwing
      await expectLater(
        Future<void>.delayed(const Duration(milliseconds: 50)),
        completes,
      );
    });

    test('destroy flushes partial buffer', () async {
      final fake = _FakeHttpClient(statusCode: 200);
      ApiService.overrideHttpClient(fake);

      final output = ServerLogOutput(getDeviceId: () async => 'dev-1');

      // Add fewer than 20 lines (would not auto-flush)
      for (var i = 0; i < 5; i++) {
        output.output(_infoEvent('line $i'));
      }

      // destroy() should fire-and-forget flush
      await output.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.captured, hasLength(1));
      expect((jsonDecode(fake.captured.first['body'] as String) as List).length, 5);
    });
  });
}
