import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../services/google/google_account_service_native.dart';

/// Abstract base [State] that encapsulates Google sign-in lifecycle logic.
///
/// Subclasses must provide:
/// - [googleListenerKey] – a unique key used to register/deregister the
///   sign-in listener with [GoogleAccountService].
/// - [onGoogleSignedIn] – called whenever sign-in / authorization succeeds.
///   [canSync] indicates whether network-dependent sync is safe to perform.
///
/// Optionally override [onWebGoogleNotInitialized] to react when the Google
/// SDK is not yet initialised on web (e.g. to hide a loading indicator early).
abstract class GoogleSignInScreenState<T extends StatefulWidget>
    extends State<T> {
  // ---------------------------------------------------------------------------
  // Dependencies
  // ---------------------------------------------------------------------------

  final GoogleAccountService googleAccountService = GoogleAccountService();

  /// `true` only when the app is running as a web server — the only context
  /// where Google sign-in is needed (Gmail sync is handled server-side otherwise).
  bool get isGoogleSignInEnabled => kIsWeb && AppConfig.mode == AppMode.server;

  // ---------------------------------------------------------------------------
  // Abstract contract
  // ---------------------------------------------------------------------------

  /// A unique key identifying this screen in the [GoogleAccountService]
  /// listener registry.
  String get googleListenerKey;

  /// Called after a successful sign-in event or after [initGoogleSignInForWeb]
  /// resolves. Subclasses should trigger their data-loading logic here.
  ///
  /// [canSync] is `true` when the user is authenticated **and** authorised, so
  /// email synchronisation is safe to perform.
  Future<void> onGoogleSignedIn({bool canSync = true});

  // ---------------------------------------------------------------------------
  // Optional hooks
  // ---------------------------------------------------------------------------

  /// Called inside [initGoogleSignInForWeb] when [GoogleAccountService] has
  /// not yet been initialised. Override to adjust loading state early.
  void onWebGoogleNotInitialized() {}

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  bool _isSignedInListenerAttached = false;

  // ---------------------------------------------------------------------------
  // Sign-in subscription helpers
  // ---------------------------------------------------------------------------

  /// Registers a sign-in listener so that [onGoogleSignedIn] is invoked
  /// whenever the user completes the Google sign-in flow.
  void subscribeToSignedInEvents() {
    if (_isSignedInListenerAttached &&
        googleAccountService.isSubscribedToSignIn(googleListenerKey)) {
      return;
    }

    googleAccountService.onSignedIn(
      googleListenerKey,
      () => onGoogleSignedIn(canSync: true),
    );
    _isSignedInListenerAttached = true;
  }

  /// Removes the sign-in listener registered by [subscribeToSignedInEvents].
  void unsubscribeFromSignedInEvents() {
    if (!_isSignedInListenerAttached ||
        !googleAccountService.isSubscribedToSignIn(googleListenerKey)) {
      return;
    }

    googleAccountService.offSignedIn(googleListenerKey);
    _isSignedInListenerAttached = false;
  }

  // ---------------------------------------------------------------------------
  // Web initialisation
  // ---------------------------------------------------------------------------

  /// Handles the web-specific Google sign-in initialisation flow.
  ///
  /// Should be called from the subclass [State.initState] when [kIsWeb] is
  /// `true` instead of performing a direct data load.
  Future<void> initGoogleSignInForWeb() async {
    if (!isGoogleSignInEnabled) return;

    if (!googleAccountService.isInitialized) {
      onWebGoogleNotInitialized();
    }

    final canSync =
        googleAccountService.isAuthenticated && googleAccountService.isSignedIn;
    await onGoogleSignedIn(canSync: canSync);
  }

  // ---------------------------------------------------------------------------
  // Authorization
  // ---------------------------------------------------------------------------

  /// Triggers the Gmail authorization flow and calls [onGoogleSignedIn] on
  /// success. Shows appropriate snack-bar messages in both cases.
  Future<void> authorizeGoogleAccount() async {
    await googleAccountService.authorize();

    if (!mounted) return;

    if (googleAccountService.isAuthorized) {
      await onGoogleSignedIn(canSync: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail access authorized.')),
      );
    } else {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gmail authorization was not granted.')),
      );
    }
  }
}

