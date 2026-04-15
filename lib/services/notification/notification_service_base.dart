import 'dart:async';

import 'package:uuid/uuid.dart';

import 'app_notification_store.dart';
import 'sse_service.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/sse_event.dart';
import '../../data/repositories/bills_repository.dart';
import '../../data/repositories/payments_repository.dart';
import '../../utils/app_logger.dart';

/// Shared state and helpers used by both platform implementations.
abstract class NotificationServiceBase {
  final uuid = const Uuid();

  StreamSubscription<SseEvent>? sseEventsSubscription;
  bool initialized = false;

  // ---------------------------------------------------------------------------
  // Public lifecycle
  // ---------------------------------------------------------------------------

  Future<void> initialize();

  void dispose() {
    sseEventsSubscription?.cancel();
    SseService.instance.disconnect();
    initialized = false;
  }

  // ---------------------------------------------------------------------------
  // SSE
  // ---------------------------------------------------------------------------

  Future<void> connectSse(String apiBaseUrl, String deviceId) async {
    await SseService.instance.connect(apiBaseUrl, deviceId);
    sseEventsSubscription = SseService.instance.events.listen(handleSseEvent);
  }

  void handleSseEvent(SseEvent event) {
    final title = switch (event.type) {
      SseEventType.newBill => 'New Bill',
      SseEventType.newPayment => 'New Payment',
    };

    AppLogger().d('[SSE] ${event.type}: $title');
    showNotification(title: title, body: event.message);
    addToStore(type: event.type, title: title, body: event.message);
    reloadRepository(event.type);
  }

  // ---------------------------------------------------------------------------
  // Notification display — overridden per platform
  // ---------------------------------------------------------------------------

  Future<void> showNotification({required String title, required String body});

  // ---------------------------------------------------------------------------
  // Store & repository helpers
  // ---------------------------------------------------------------------------

  void addToStore({
    required SseEventType type,
    required String title,
    required String body,
  }) {
    AppNotificationStore().add(
      AppNotification(
        id: uuid.v4(),
        type: type,
        title: title,
        body: body,
        timestamp: DateTime.now(),
      ),
    );
  }

  void reloadRepository(SseEventType type) {
    switch (type) {
      case SseEventType.newBill:
        BillsRepository().reload();
      case SseEventType.newPayment:
        PaymentsRepository().reload();
    }
  }
}
