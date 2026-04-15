/// Platform-aware export for [GoogleAccountService].
///
/// - Web  → [google_account_service_web.dart]   (uses google_sign_in_web + GIS button)
/// - Native → [google_account_service_native.dart] (uses google_sign_in standard flow)
library;

export 'google_account_service_stub.dart'
    if (dart.library.js_interop) 'google_account_service_web.dart'
    if (dart.library.io) 'google_account_service_native.dart';
