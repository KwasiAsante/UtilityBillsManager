import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import '../../utils/app_logger.dart';

/// Singleton wrapper around the `google_sign_in` plugin for **web-only** Gmail
/// access.
///
/// Manages the full Google OAuth 2.0 lifecycle:
/// - [initialize] — sets up the `GoogleSignIn` instance and listens to
///   authentication events.
/// - [signIn] — initiates the sign-in flow (no-op on web; must be triggered
///   from a button).
/// - [authorize] — requests the `gmail.readonly` OAuth scope and caches the
///   resulting [authorizationHeaders] (used by [_AuthClient]).
/// - [signOut] / [disconnect] — clears credentials.
///
/// Screens that require a signed-in state subscribe via [onSignedIn] and
/// unsubscribe via [offSignedIn].
class GoogleAccountService {
  static final GoogleAccountService _instance =
      GoogleAccountService._internal();

  factory GoogleAccountService() {
    return _instance;
  }

  GoogleAccountService._internal();

  GoogleSignIn get googleSignIn => GoogleSignIn.instance;

  /// The currently signed-in Google account, or `null` if not signed in.
  GoogleSignInAccount? signedInAccount;

  /// OAuth 2.0 scopes requested — read-only Gmail access.
  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  Map<String, String>? _authorizationHeaders;

  /// Bearer-token headers to inject into Gmail API requests, or `null` if not
  /// yet authorised.
  Map<String, String>? get authorizationHeaders => _authorizationHeaders;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  bool _isSignedIn = false;
  bool get isSignedIn => _isSignedIn;

  /// Manually overrides the signed-in state (used by the sign-in screen
  /// after a successful authentication event).
  void setSignedIn(bool value) {
    _isSignedIn = value;
  }

  bool _isAuthorized = false;
  bool get isAuthorized => _isAuthorized;

  /// Listeners keyed by the subscribing class name so each class registers at
  /// most once.
  final Map<String, Function()> _onSignedInListeners = {};

  /// Subscribe to sign-in events
  void onSignedIn(String className, Function() callback) {
    _onSignedInListeners[className] = callback;
  }

  /// Unsubscribe from sign-in events
  void offSignedIn(String className) {
    _onSignedInListeners.remove(className);
  }

  /// Returns `true` if [className] is currently subscribed to sign-in events.
  bool isSubscribedToSignIn(String className) {
    return _onSignedInListeners.containsKey(className);
  }

  /// Notify all listeners of a sign-in event
  Future<void> _notifySignedIn() async {
    for (var listener in _onSignedInListeners.values) {
      await listener();
    }
  }

  /// Initialises the Google Sign-In SDK once and starts listening to
  /// [GoogleSignInAuthenticationEventSignIn] events so that [authorize] and the
  /// registered [onSignedIn] callbacks are called automatically on sign-in.
  Future<void> initialize() async {
    if (!_isInitialized) {
      await googleSignIn
          .initialize(
            clientId:
                '910862354798-fm2ttlkjnv5nscsqrsqm0ieou2lva2ub.apps.googleusercontent.com',
          )
          .then((_) {
            _isInitialized = true;
            googleSignIn.authenticationEvents
                .listen((event) async {
                  if (event is GoogleSignInAuthenticationEventSignIn) {
                    AppLogger().d('Google sign in successful');
                    _isAuthenticated = true;
                    signedInAccount = event.user;
                    _isSignedIn = true;
                    await authorize();
                    await _notifySignedIn();
                  }
                })
                .onError((error, stackTrace) {
                  AppLogger().e('Error initializing Google sign in: $error');
                  _isAuthenticated = false;
                  _isSignedIn = false;
                  _isInitialized = false;
                });
          });
    }
  }

  /// Attempts a lightweight (cached) sign-in on mobile / desktop.
  ///
  /// On web the sign-in flow must be initiated from the UI (the Google Identity
  /// Services button), so this method is a no-op there.
  Future<GoogleSignInAccount?> signIn() async {
    if (!_isInitialized) {
      await initialize();
    }

    _isSignedIn = signedInAccount != null;

    if (!_isSignedIn) {
      if (kIsWeb) {
        AppLogger().d('On the web, sign in must be triggered from the UI.');
        return null;
      }

      signedInAccount = await googleSignIn.attemptLightweightAuthentication();
      _isSignedIn = signedInAccount != null;
    }

    return signedInAccount;
  }

  /// Requests the [scopes] from the signed-in account and caches the resulting
  /// [authorizationHeaders].  Sets [isAuthorized] to `false` if the user is
  /// not signed in or declines the request.
  Future<void> authorize() async {
    if (!_isSignedIn) {
      _isAuthorized = false;
      return;
    }
    final GoogleSignInClientAuthorization? authorization = await signedInAccount
        ?.authorizationClient
        .authorizeScopes(scopes);

    if (authorization == null) {
      _isAuthorized = false;
      return;
    }
    _isAuthorized = true;
    // authorizationHeaders(scopes) calls authorizationForScopes first without
    // prompting; right after authorizeScopes the token may not be readable back
    // yet, so it returns null. Build the same map the plugin uses from the
    // authorization we already have (Bearer + X-Goog-AuthUser for Google APIs).
    _authorizationHeaders = <String, String>{
      'Authorization': 'Bearer ${authorization.accessToken}',
      'X-Goog-AuthUser': '0',
    };
  }

  /// Signs out the current user without revoking app access.
  Future<void> signOut() async {
    await googleSignIn.signOut();
    signedInAccount = null;
    _isSignedIn = false;
    _isAuthorized = false;
  }

  /// Revokes app access and clears all cached state.
  Future<void> disconnect() async {
    await googleSignIn.disconnect();
    signedInAccount = null;
    _isSignedIn = false;
    _isAuthenticated = false;
    _isAuthorized = false;
    _isInitialized = false;
  }

  /// Builds the appropriate Google sign-in / authorize widget for the app bar.
  ///
  /// - Fully authorized → a read-only indicator icon.
  /// - Signed in but not authorized → an "Authorize Gmail" button.
  /// - Not signed in → the native Google Identity Services sign-in button.
  Widget buildWebGoogleAction(Function() onPressed) {
    if (isSignedIn) {
      if (isAuthorized) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0),
          child: Tooltip(
            message: 'Gmail access authorized',
            child: Icon(Icons.mark_email_read),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: const Icon(Icons.lock_open),
            label: const Text('Authorize Gmail'),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: SizedBox(
        height: 36,
        child: web.renderButton(
          configuration: GSIButtonConfiguration(
            theme: GSIButtonTheme.filledBlack,
            text: GSIButtonText.continueWith,
          ),
        ),
      ),
    );
  }

  /// Returns a [MaterialBanner] reminding the user to sign in or authorize
  /// Gmail on the web, or `null` if already fully authorized (or not on web).
  Widget? buildWebWarningBanner() {
    if (!kIsWeb) return null;

    if (isSignedIn && isAuthorized) return null;

    final String message;
    final IconData icon;

    if (!isSignedIn || !isAuthenticated) {
      message =
      'You are not signed in to your Google account. Sign in via the button in the top-right corner to sync bills from Gmail.';
      icon = Icons.account_circle_outlined;
    } else {
      message =
      'Gmail access has not been authorized. Tap "Authorize Gmail" in the top-right corner to allow the app to read your bill emails.';
      icon = Icons.lock_outlined;
    }

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Icon(icon, color: Colors.orange.shade800),
      backgroundColor: Colors.orange.shade50,
      dividerColor: Colors.transparent,
      content: Text(
        message,
        style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
      ),
      actions: const [SizedBox.shrink()],
    );
  }

  /// Shows a [SnackBar] prompting the user to authorize Gmail access before
  /// attempting a sync.
  void showAuthorizationRequiredMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authorize Gmail access before syncing bills.'),
      ),
    );
  }
}
