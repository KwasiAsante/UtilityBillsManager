import 'package:flutter/widgets.dart';
import '../../services/auth/auth_service.dart';

/// Adds auth-aware reload behaviour to any [State].
///
/// When the tab is selected ([updateAuthListener] called with `visible: true`)
/// the mixin registers a listener on [AuthService]. If the user becomes
/// authenticated while the screen is on-screen, [onAuthReload] is called so
/// the screen can re-run its own data-fetch.  The listener is removed when the
/// tab is deselected or the widget is disposed.
///
/// Usage:
/// 1. Add `with AuthReloadMixin<MyWidget>` to the State class.
/// 2. Implement [onAuthReload] with the screen's load function.
/// 3. Call `updateAuthListener(visible: widget.isVisible)` in [initState].
/// 4. Call `updateAuthListener(visible: widget.isVisible)` in [didUpdateWidget]
///    when `widget.isVisible != oldWidget.isVisible`.
mixin AuthReloadMixin<T extends StatefulWidget> on State<T> {
  final _authService = AuthService();

  /// Implement to trigger the screen's data reload after login.
  void onAuthReload();

  void _onAuthServiceChanged() {
    if (_authService.isLoggedIn && mounted) onAuthReload();
  }

  void updateAuthListener({required bool visible}) {
    if (visible) {
      _authService.addListener(_onAuthServiceChanged);
    } else {
      _authService.removeListener(_onAuthServiceChanged);
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthServiceChanged);
    super.dispose();
  }
}
