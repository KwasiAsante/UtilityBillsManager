# Log Console – Flutter Client Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Push Flutter device logs to the self-hosted Grafana+Loki log console in real-time, with an end-of-day gap-fill upload for any lines missed during real-time streaming.

**Architecture:** Add a `ServerLogOutput` to `AppLogger`'s `MultiOutput` that buffers log lines and flushes them to `POST /logs/device` every 3 seconds or when 20 lines accumulate. A `LogUploadService` fires at midnight, reads from the in-memory byte offset to EOF in today's log file, and POSTs the gap to `POST /logs/device/upload`. On success the offset is reset to 0 for the new day.

**Tech Stack:** `http` (already in pubspec), `path_provider` (already in pubspec), `logger` (already in pubspec), Dart `dart:io` for file reading.

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `lib/services/logs/server_log_output.dart` | Create | `ServerLogOutput` — buffers log lines, flushes to server, tracks byte offset |
| `lib/services/logs/log_upload_service.dart` | Create | `LogUploadService` — midnight timer, EOD gap-fill upload |
| `lib/utils/app_logger.dart` | Modify | Add `serverLogOutput` field; add it to `MultiOutput` |
| `lib/main.dart` | Modify | Instantiate and start `LogUploadService` |
| `test/services/logs/server_log_output_test.dart` | Create | Unit tests for `ServerLogOutput` |
| `test/services/logs/log_upload_service_test.dart` | Create | Unit tests for `LogUploadService` |

---

### Task 1: Create feature branch

**Files:** (git operations only)

- [ ] **Step 1: Create and switch to the feature branch**

```bash
cd /Users/kasante/Projects/flutter/utility_bills_manager
git checkout -b feat/log-console
```

- [ ] **Step 2: Verify the branch**

```bash
git branch --show-current
```

Expected output: `feat/log-console`

---

### Task 2: `ServerLogOutput` — real-time log push with byte-offset tracking

**Files:**
- Create: `lib/services/logs/server_log_output.dart`
- Create: `test/services/logs/server_log_output_test.dart`

#### Background

`ServerLogOutput extends LogOutput` is added to `AppLogger`'s `MultiOutput` alongside the existing `ConsoleOutput` and `_FileLogOutput`. When `output(event)` is called, it formats the event identically to `_FileLogOutput` (same `[ISO8601] [LEVEL] body\n` format), buffers the formatted string, and flushes to the server when the buffer reaches 20 lines OR every 3 seconds.

On each **successful** flush (HTTP 200 response), `_byteOffset` advances by the sum of UTF-8 byte lengths of the flushed lines. This offset mirrors the position in the physical log file up to which content has been confirmed delivered to the server. The EOD uploader reads from this offset to EOF to fill any gaps.

On network failure the lines are dropped silently — the EOD upload covers them.

`_byteOffset` is injectable via `setByteOffset(int)` (marked `@visibleForTesting`) so `LogUploadService` tests can set a starting position without routing through the real server.

The constructor accepts an optional `http.Client` and two optional function parameters (`getDeviceId` and `getBaseUrl`) so tests can bypass `AppConfig` entirely.

- [ ] **Step 1: Create the test file with the `FakeHttpClient` helper**

Create `test/services/logs/server_log_output_test.dart`:

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
      Stream.fromIterable(<List<int>>[]),
      statusCode,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

OutputEvent _infoEvent(String message) =>
    OutputEvent(Level.info, [message]);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ServerLogOutput', () {
    test('does not flush when buffer has fewer than 20 lines', () async {
      final fake = _FakeHttpClient();
      final output = ServerLogOutput(
        client: fake,
        getDeviceId: () async => 'dev-1',
        getBaseUrl: () => 'http://localhost',
      );

      for (var i = 0; i < 19; i++) {
        output.output(_infoEvent('line $i'));
      }

      // Give async work a chance to run (there should be none)
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(fake.captured, isEmpty,
          reason: 'should not flush with fewer than 20 lines');
    });

    test('flushes when buffer reaches 20 lines and advances byteOffset', () async {
      final fake = _FakeHttpClient(statusCode: 200);
      final output = ServerLogOutput(
        client: fake,
        getDeviceId: () async => 'dev-1',
        getBaseUrl: () => 'http://localhost',
      );

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
      final output = ServerLogOutput(
        client: fake,
        getDeviceId: () async => 'dev-1',
        getBaseUrl: () => 'http://localhost',
      );

      for (var i = 0; i < 20; i++) {
        output.output(_infoEvent('line $i'));
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(output.byteOffset, 0);
    });

    test('is silent on network error', () async {
      final failingClient = _FailingHttpClient();
      final output = ServerLogOutput(
        client: failingClient,
        getDeviceId: () async => 'dev-1',
        getBaseUrl: () => 'http://localhost',
      );

      for (var i = 0; i < 20; i++) {
        output.output(_infoEvent('line $i'));
      }

      // Should complete without throwing
      await expectLater(
        Future<void>.delayed(const Duration(milliseconds: 50)),
        completes,
      );
    });
  });
}

class _FailingHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(Exception('network unavailable'));
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd /Users/kasante/Projects/flutter/utility_bills_manager
flutter test test/services/logs/server_log_output_test.dart
```

Expected: compile error — `ServerLogOutput` does not exist yet.

- [ ] **Step 3: Create the implementation**

Create `lib/services/logs/server_log_output.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

import '../../config/app_config.dart';

/// Streams log events to the remote Loki endpoint via `POST /logs/device`.
///
/// - Buffers lines internally; flushes every [_flushInterval] or when
///   [_bufferMaxLines] lines accumulate.
/// - On successful flush, [byteOffset] advances by the UTF-8 byte count of
///   the sent lines — this mirrors the write position in the on-device log
///   file so [LogUploadService] can read the remainder at end-of-day.
/// - On any failure (network error, non-200) the lines are dropped silently;
///   the end-of-day upload covers the gap.
class ServerLogOutput extends LogOutput {
  ServerLogOutput({
    http.Client? client,
    Future<String> Function()? getDeviceId,
    String Function()? getBaseUrl,
  })  : _client = client ?? http.Client(),
        _getDeviceId = getDeviceId ?? AppConfig.deviceId,
        _getBaseUrl = getBaseUrl ?? (() => AppConfig.apiBaseUrl);

  final http.Client _client;
  final Future<String> Function() _getDeviceId;
  final String Function() _getBaseUrl;

  final List<String> _buffer = [];
  int _byteOffset = 0;
  Timer? _timer;
  bool _flushing = false;

  static const _flushInterval = Duration(seconds: 3);
  static const _bufferMaxLines = 20;

  /// Bytes of today's log file successfully confirmed delivered to the server.
  int get byteOffset => _byteOffset;

  /// Resets the offset to 0 (called by [LogUploadService] at end-of-day after
  /// the gap-fill upload succeeds, so the new day starts from byte 0).
  void resetByteOffset() => _byteOffset = 0;

  /// Sets the offset to a specific value.
  ///
  /// Exposed for testing only — do not call in production code.
  @visibleForTesting
  void setByteOffset(int offset) => _byteOffset = offset;

  @override
  void output(OutputEvent event) {
    if (kIsWeb) return;
    final entry = _format(event);
    _buffer.add(entry);
    _timer ??= Timer.periodic(_flushInterval, (_) => _flush());
    if (_buffer.length >= _bufferMaxLines) _flush();
  }

  Future<void> _flush() async {
    if (_flushing || _buffer.isEmpty) return;
    _flushing = true;

    final lines = List<String>.from(_buffer);
    _buffer.clear();

    try {
      final deviceId = await _getDeviceId();
      final baseUrl = _getBaseUrl();
      final uri = Uri.parse('$baseUrl/logs/device');

      final payload = jsonEncode(lines);
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-device-id': deviceId,
            },
            body: payload,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final byteCount = lines.fold<int>(
          0,
          (sum, line) => sum + utf8.encode(line).length,
        );
        _byteOffset += byteCount;
      }
    } catch (_) {
      // Network unavailable — drop silently; EOD upload covers the gap.
    } finally {
      _flushing = false;
    }
  }

  static String _format(OutputEvent event) {
    final ts = DateTime.now().toIso8601String();
    final lvl = event.level.name.toUpperCase().padRight(5);
    final body = event.lines.map(_stripAnsi).join('\n        ');
    return '[$ts] [$lvl] $body\n';
  }

  static final _ansiRe = RegExp(r'\x1B\[[0-9;]*[a-zA-Z]');
  static String _stripAnsi(String s) => s.replaceAll(_ansiRe, '');

  @override
  void destroy() {
    _timer?.cancel();
    _timer = null;
    _flush(); // fire-and-forget; best-effort on shutdown
    super.destroy();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

```bash
flutter test test/services/logs/server_log_output_test.dart
```

Expected:
```
All tests passed!
```

- [ ] **Step 5: Commit**

```bash
git add lib/services/logs/server_log_output.dart test/services/logs/server_log_output_test.dart
git commit -m "feat: add ServerLogOutput for real-time device log streaming"
```

---

### Task 3: `LogUploadService` — end-of-day gap-fill upload

**Files:**
- Create: `lib/services/logs/log_upload_service.dart`
- Create: `test/services/logs/log_upload_service_test.dart`

#### Background

`LogUploadService` schedules a one-shot `Timer` for the next midnight. When it fires, it reads today's log file (`<documents>/logs/yyyy-MM-dd.log`) from `logOutput.byteOffset` to EOF, POSTs the raw text chunk to `POST /logs/device/upload`, and on a 200 response calls `logOutput.resetByteOffset()`. It then schedules the next midnight timer, repeating the cycle each day.

The test bypasses `path_provider` and `AppConfig` by injecting a temp-directory getter, a fake `deviceId` getter, a fake `baseUrl` getter, and a `_FakeHttpClient`.

`uploadGap()` is public so it can be called directly in tests without touching the timer machinery.

- [ ] **Step 1: Create the test file**

Create `test/services/logs/log_upload_service_test.dart`:

```dart
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
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/services/logs/log_upload_service_test.dart
```

Expected: compile error — `LogUploadService` does not exist yet.

- [ ] **Step 3: Create the implementation**

Create `lib/services/logs/log_upload_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import 'server_log_output.dart';

/// Fires at midnight each day and uploads any log lines from [logOutput.byteOffset]
/// to EOF in today's log file, filling gaps left by failed real-time pushes.
///
/// After a successful upload, resets [logOutput.byteOffset] to 0 so the new
/// day starts fresh.
class LogUploadService {
  LogUploadService({
    required ServerLogOutput logOutput,
    http.Client? client,
    Future<String> Function()? getDeviceId,
    String Function()? getBaseUrl,
    Future<String> Function()? getLogsDir,
  })  : _logOutput = logOutput,
        _client = client ?? http.Client(),
        _getDeviceId = getDeviceId ?? AppConfig.deviceId,
        _getBaseUrl = getBaseUrl ?? (() => AppConfig.apiBaseUrl),
        _getLogsDir = getLogsDir ?? _defaultLogsDir;

  final ServerLogOutput _logOutput;
  final http.Client _client;
  final Future<String> Function() _getDeviceId;
  final String Function() _getBaseUrl;
  final Future<String> Function() _getLogsDir;

  Timer? _timer;

  /// Starts the midnight upload cycle.
  ///
  /// Call once during app startup (after [AppConfig.init]).
  void start() => _scheduleNextMidnight();

  /// Cancels the scheduled timer. Call on app shutdown if needed.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Reads today's log file from [logOutput.byteOffset] to EOF and POSTs
  /// the chunk to `POST /logs/device/upload`.
  ///
  /// On HTTP 200, resets [logOutput.byteOffset] to 0 for the new day.
  /// Failures are silent — no retry in v1.
  Future<void> uploadGap() async {
    final logsDir = await _getLogsDir();
    final today = _todayStr();
    final file = File('$logsDir/$today.log');

    if (!file.existsSync()) return;

    final fileLength = file.lengthSync();
    final offset = _logOutput.byteOffset;
    if (fileLength <= offset) return;

    final raf = await file.open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(fileLength - offset);
      final chunk = utf8.decode(bytes, allowMalformed: true);

      final deviceId = await _getDeviceId();
      final baseUrl = _getBaseUrl();
      final uri = Uri.parse('$baseUrl/logs/device/upload');

      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'text/plain',
              'x-device-id': deviceId,
            },
            body: chunk,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        _logOutput.resetByteOffset();
      }
    } catch (_) {
      // Silent — EOD upload failures are not retried in v1.
    } finally {
      await raf.close();
    }
  }

  void _scheduleNextMidnight() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final until = tomorrow.difference(now);
    _timer = Timer(until, _onMidnight);
  }

  Future<void> _onMidnight() async {
    await uploadGap();
    _logOutput.resetByteOffset(); // start fresh for the new day
    _scheduleNextMidnight();
  }

  static String _todayStr() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  static Future<String> _defaultLogsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/logs';
  }
}
```

- [ ] **Step 4: Run tests and confirm all 5 pass**

```bash
flutter test test/services/logs/log_upload_service_test.dart
```

Expected:
```
All tests passed!
```

- [ ] **Step 5: Commit**

```bash
git add lib/services/logs/log_upload_service.dart test/services/logs/log_upload_service_test.dart
git commit -m "feat: add LogUploadService for end-of-day gap-fill upload"
```

---

### Task 4: Wire `ServerLogOutput` into `AppLogger` and start `LogUploadService` in `main.dart`

**Files:**
- Modify: `lib/utils/app_logger.dart`
- Modify: `lib/main.dart`

#### Background

`AppLogger` is a singleton initialized at class-load time. To expose the `ServerLogOutput` instance (so `main.dart` can hand it to `LogUploadService`), add it as a `final` field before `_logger`. Switch `_logger` to `late final` so it can reference the already-initialized `serverLogOutput` field.

In `main.dart`, after `AppConfig.init()`, instantiate and `start()` a `LogUploadService`.

- [ ] **Step 1: Modify `lib/utils/app_logger.dart`**

Add the import and `serverLogOutput` field, change `_logger` to `late final`:

```dart
// Add at the top of the imports:
import 'package:utility_bills_manager/services/logs/server_log_output.dart';
```

Replace the `AppLogger._internal()` constructor and `_logger` field:

```dart
// BEFORE:
AppLogger._internal();

final Logger _logger = Logger(
  filter: _AllowAllFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: MultiOutput([
    ConsoleOutput(),
    _FileLogOutput(maxFileSizeBytes: _fileMaxBytes),
  ]),
);

// AFTER:
AppLogger._internal();

/// The server log output instance — exposed so [LogUploadService] can be
/// handed the same instance that is writing to the logger.
final ServerLogOutput serverLogOutput = ServerLogOutput();

late final Logger _logger = Logger(
  filter: _AllowAllFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 5,
    lineLength: 80,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  output: MultiOutput([
    ConsoleOutput(),
    _FileLogOutput(maxFileSizeBytes: _fileMaxBytes),
    serverLogOutput,
  ]),
);
```

- [ ] **Step 2: Verify the app still compiles**

```bash
flutter analyze lib/utils/app_logger.dart
```

Expected: no errors.

- [ ] **Step 3: Modify `lib/main.dart` to start `LogUploadService`**

Add the import at the top of `main.dart`:

```dart
import 'services/logs/log_upload_service.dart';
```

In `main()`, after `await AppConfig.init();` add:

```dart
// Start end-of-day log upload service (skipped on web — no file system)
if (!kIsWeb) {
  LogUploadService(logOutput: AppLogger().serverLogOutput).start();
}
```

The full relevant block in `main()` after the change:

```dart
await AppConfig.init();

// Start end-of-day log upload service (skipped on web — no file system)
if (!kIsWeb) {
  LogUploadService(logOutput: AppLogger().serverLogOutput).start();
}

AppState().localDB = AppConfig.mode == AppMode.server;
```

- [ ] **Step 4: Run all tests to confirm nothing is broken**

```bash
flutter test
```

Expected: all pre-existing tests continue to pass, plus the 9 new tests from Tasks 2 and 3.

- [ ] **Step 5: Commit**

```bash
git add lib/utils/app_logger.dart lib/main.dart
git commit -m "feat: wire ServerLogOutput into AppLogger and start LogUploadService on startup"
```

---

### Task 5: Push branch and open PR

**Files:** (git/GitHub operations only)

- [ ] **Step 1: Push the branch to remote**

```bash
git push -u origin feat/log-console
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create \
  --title "feat: stream Flutter device logs to Loki log console" \
  --body "$(cat <<'EOF'
## Summary

- Adds `ServerLogOutput` to `AppLogger`'s `MultiOutput` — buffers log lines and flushes every 3 s or when 20 lines accumulate to `POST /logs/device`
- Tracks in-memory byte offset so `LogUploadService` knows where to start the end-of-day gap-fill
- Adds `LogUploadService` — fires at midnight, reads un-sent bytes from today's log file, POSTs them to `POST /logs/device/upload`, then resets the offset for the new day
- Wires both into startup: `LogUploadService` is started in `main()` after `AppConfig.init()`

## Test Plan

- [ ] Run `flutter test` — all tests pass
- [ ] Build and run on a real device, verify logs appear in Grafana under `job="device"` with the correct `device_id` label
- [ ] Let the app run overnight and confirm the midnight upload fills any gaps
EOF
)"
```

- [ ] **Step 3: Note the PR URL and verify it opened**

```bash
gh pr view --web
```

---

## Self-Review

### Spec coverage

| Spec requirement | Covered by |
|---|---|
| `_ServerLogOutput` added to `AppLogger` `MultiOutput` | Task 4 |
| Buffers lines, flushes every 3 s or 20 lines | Task 2 |
| Flushes to `POST /logs/device` with `x-device-id` | Task 2 |
| In-memory byte offset advanced on success | Task 2 |
| Failures are silent (network offline) | Task 2 test: "is silent on network error" |
| End-of-day upload at midnight | Task 3 (`_scheduleNextMidnight`) |
| Reads log file from byte offset to EOF | Task 3 test: "POSTs content from byteOffset to EOF" |
| POSTs to `POST /logs/device/upload` | Task 3 |
| Resets byte offset for new day | Task 3 + `_onMidnight` calls `resetByteOffset` |
| Server base URL from `AppConfig.apiBaseUrl` | Both services default to `AppConfig.apiBaseUrl` |
| Device ID from existing `x-device-id` / `AppConfig.deviceId` | Both services default to `AppConfig.deviceId` |
| New branch + PR | Tasks 1 and 5 |

### Known limitation (v1)

App restart resets the in-memory `_byteOffset` to 0. The next EOD upload will re-send lines that were already pushed before the restart, potentially creating duplicates in Loki. This is acceptable in v1 per the design spec.
