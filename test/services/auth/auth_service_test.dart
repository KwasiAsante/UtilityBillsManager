import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/services/auth/auth_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AuthService().loadFromPrefs(); // flushes token/email from empty prefs
    AuthService().clearUnauthorized();
  });

  group('AuthService.loadFromPrefs', () {
    test('is not logged in when prefs are empty', () async {
      await AuthService().loadFromPrefs();
      expect(AuthService().isLoggedIn, isFalse);
      expect(AuthService().token, isNull);
      expect(AuthService().email, isNull);
    });

    test('restores token and email from prefs', () async {
      SharedPreferences.setMockInitialValues({
        'AUTH_TOKEN': 'abc123',
        'AUTH_EMAIL': 'user@example.com',
      });
      await AuthService().loadFromPrefs();
      expect(AuthService().isLoggedIn, isTrue);
      expect(AuthService().token, 'abc123');
      expect(AuthService().email, 'user@example.com');
    });
  });

  group('AuthService.notifyUnauthorized', () {
    test('sets pendingUnauthorized to true and notifies', () {
      var notified = false;
      void listener() => notified = true;
      AuthService().addListener(listener);
      AuthService().notifyUnauthorized();
      expect(AuthService().pendingUnauthorized, isTrue);
      expect(notified, isTrue);
      AuthService().removeListener(listener);
    });

    test('clearUnauthorized resets the flag', () {
      AuthService().notifyUnauthorized();
      AuthService().clearUnauthorized();
      expect(AuthService().pendingUnauthorized, isFalse);
    });

    test('calling notifyUnauthorized twice does not double-notify', () {
      var count = 0;
      void listener() => count++;
      AuthService().addListener(listener);
      AuthService().notifyUnauthorized();
      AuthService().notifyUnauthorized();
      expect(count, 1);
      AuthService().removeListener(listener);
    });
  });
}
