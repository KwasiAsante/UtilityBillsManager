/// Platform-aware export for [EmailService].
///
/// - Web    → [email_service_web.dart]    (Gmail REST API via GoogleAccountService)
/// - Native → [email_service_native.dart] (IMAP via enough_mail)
library;

export 'email_service_stub.dart'
    if (dart.library.js_interop) 'email_service_web.dart'
    if (dart.library.io) 'email_service_native.dart';
