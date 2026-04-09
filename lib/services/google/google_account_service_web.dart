import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';
import 'package:google_sign_in_web/web_only.dart' as web;
import '../../utils/app_logger.dart';

/// Web-only implementation of [GoogleAccountService].
///
/// Manages the full Google OAuth 2.0 lifecycle for the web platform:
/// - Sign-in is triggered via the Google Identity Services (GIS) button rendered
///   by [buildWebGoogleAction]; [signIn] is a no-op on web.
/// - [authorize] requests the `gmail.readonly` OAuth scope and caches the
///   resulting [authorizationHeaders] (used by the Gmail API client).
/// - [signOut] / [disconnect] clear all cached credentials.
///
/// Screens that need sign-in state subscribe via [onSignedIn] and unsubscribe
/// via [offSignedIn].
class GoogleAccountService {
  static final GoogleAccountService _instance =
      GoogleAccountService._internal();

  factory GoogleAccountService() => _instance;

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

  void setSignedIn(bool value) => _isSignedIn = value;

  bool _isAuthorized = false;

  bool get isAuthorized => _isAuthorized;

  /// Listeners keyed by the subscribing class name so each class registers at
  /// most once.
  final Map<String, Function()> _onSignedInListeners = {};

  void onSignedIn(String className, Function() callback) =>
      _onSignedInListeners[className] = callback;

  void offSignedIn(String className) => _onSignedInListeners.remove(className);

  bool isSubscribedToSignIn(String className) =>
      _onSignedInListeners.containsKey(className);

  Future<void> _notifySignedIn() async {
    for (final listener in _onSignedInListeners.values) {
      await listener();
    }
  }

  /// Initialises the Google Sign-In SDK and listens to authentication events.
  Future<void> initialize() async {
    if (_isInitialized) return;

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

  /// No-op on web — sign-in must be triggered from the GIS button in the UI.
  Future<GoogleSignInAccount?> signIn() async {
    if (!_isInitialized) await initialize();
    AppLogger().d('On the web, sign in must be triggered from the UI.');
    return null;
  }

  /// Requests [scopes] from the signed-in account and caches
  /// [authorizationHeaders].
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
    _authorizationHeaders = <String, String>{
      'Authorization': 'Bearer ${authorization.accessToken}',
      'X-Goog-AuthUser': '0',
    };
  }

  Future<void> signOut() async {
    await googleSignIn.signOut();
    signedInAccount = null;
    _isSignedIn = false;
    _isAuthorized = false;
  }

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
  /// - Not signed in → the native GIS sign-in button.
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

    // Not signed in — render the GIS button (web-only import used here).
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
  /// Gmail, or `null` if already fully authorized.
  Widget? buildWebWarningBanner() {
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

  void showAuthorizationRequiredMessage(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Authorize Gmail access before syncing bills.'),
      ),
    );
  }
}
