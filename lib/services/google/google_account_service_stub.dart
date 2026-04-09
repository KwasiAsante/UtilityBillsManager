import 'package:flutter/material.dart';

/// Stub implementation of [GoogleAccountService].
///
/// This file is the fallback export when neither [dart.library.html] (web) nor
/// [dart.library.io] (native) is available. In practice this should never be
/// reached, but it satisfies the Dart analyser and prevents compile errors on
/// unknown platforms.
class GoogleAccountService {
  static final GoogleAccountService _instance =
      GoogleAccountService._internal();

  factory GoogleAccountService() => _instance;

  GoogleAccountService._internal();

  static const List<String> scopes = <String>[
    'https://www.googleapis.com/auth/gmail.readonly',
  ];

  Map<String, String>? get authorizationHeaders => null;

  bool get isInitialized => false;

  bool get isAuthenticated => false;

  bool get isSignedIn => false;

  bool get isAuthorized => false;

  void setSignedIn(bool value) {}

  void onSignedIn(String className, Function() callback) {}

  void offSignedIn(String className) {}

  bool isSubscribedToSignIn(String className) => false;

  Future<void> initialize() async {}

  Future<dynamic> signIn() async => null;

  Future<void> authorize() async {}

  Future<void> signOut() async {}

  Future<void> disconnect() async {}

  Widget buildWebGoogleAction(Function() onPressed) => const SizedBox.shrink();

  Widget? buildWebWarningBanner() => null;

  void showAuthorizationRequiredMessage(BuildContext context) {}
}
