import '../../data/models/sse_event.dart';

void openWebSse({
  required String url,
  required String deviceId,
  required void Function(SseEvent) onEvent,
  required void Function() onConnected,
  required void Function() onClosed,
}) {
  throw UnsupportedError('openWebSse is only supported on web');
}

void closeWebSse() {
  throw UnsupportedError('closeWebSse is only supported on web');
}

