// This file is the single public entry point for the SSE service.
// Dart's conditional export selects the correct implementation at compile time:
//   • dart.library.js_interop  →  web    (Flutter Web, uses browser EventSource)
//   • otherwise                →  native (Android / iOS / macOS / Windows / Linux,
//                                         uses SseChannel over dart:io)
//
// Consumers use the [SseService] typedef and the singleton [SseService.instance]:
//
//   import 'sse_service.dart';
//   await SseService.instance.connect(baseUrl, deviceId);
//   SseService.instance.events.listen(_handleEvent);

export 'sse_service_native.dart'
    if (dart.library.js_interop) 'sse_service_web.dart';
