import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class GoogleAccountService {
  static final GoogleAccountService _instance =
      GoogleAccountService._internal();

  factory GoogleAccountService() {
    return _instance;
  }

  GoogleAccountService._internal();

  GoogleSignIn get googleSignIn => GoogleSignIn.instance;
  GoogleSignInAccount? signedInAccount;

  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  Map<String, String>? _authorizationHeaders;
  Map<String, String>? get authorizationHeaders => _authorizationHeaders;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  bool _isAuthenticated = false;
  bool get isAuthenticated => _isAuthenticated;

  bool _isSignedIn = false;
  bool get isSignedIn => _isSignedIn;
  void setSignedIn(bool value) {
    _isSignedIn = value;
  }

  bool _isAuthorized = false;
  bool get isAuthorized => _isAuthorized;

  final Map<String, Function()> _onSignedInListeners = {};

  /// Subscribe to sign-in events
  void onSignedIn(String className, Function() callback) {
    _onSignedInListeners[className] = callback;
  }

  /// Unsubscribe from sign-in events
  void offSignedIn(String className) {
    _onSignedInListeners.remove(className);
  }

  bool isSubscribedToSignIn(String className) {
    return _onSignedInListeners.containsKey(className);
  }

  /// Notify all listeners of a sign-in event
  Future<void> _notifySignedIn() async {
    for (var listener in _onSignedInListeners.values) {
      await listener();
    }
  }

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
                    if (kDebugMode) {
                      print('Google sign in successful');
                    }
                    _isAuthenticated = true;
                    signedInAccount = event.user;
                    _isSignedIn = true;
                    await authorize();
                    await _notifySignedIn();
                  }
                })
                .onError((error, stackTrace) {
                  if (kDebugMode) {
                    print('Error initializing Google sign in: $error');
                  }
                  _isAuthenticated = false;
                  _isSignedIn = false;
                  _isInitialized = false;
                });
          });
    }
  }

  Future<GoogleSignInAccount?> signIn() async {
    if (!_isInitialized) {
      await initialize();
    }

    _isSignedIn = signedInAccount != null;

    if (!_isSignedIn) {
      if (kIsWeb) {
        if (kDebugMode) {
          print('On the web, sign in must be triggered from the UI.');
        }
        return null;
      }

      signedInAccount = await googleSignIn.attemptLightweightAuthentication();
      _isSignedIn = signedInAccount != null;
    }

    return signedInAccount;
  }

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
}
