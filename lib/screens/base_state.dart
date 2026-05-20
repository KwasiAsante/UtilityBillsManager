import 'package:flutter/material.dart';

import 'auth/login_screen.dart';
import '../services/auth/auth_service.dart';

class BaseState<T extends StatefulWidget> extends State<T> {
  final _authService = AuthService();

  @protected
  Widget buildAvatarButton() {
    if (!_authService.isLoggedIn) {
      return TextButton.icon(
        onPressed: _openLogin,
        icon: const Icon(Icons.login, size: 18),
        label: const Text('Sign in'),
      );
    }
    final initial = (_authService.email ?? '?')[0].toUpperCase();
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(50, 0),
      onSelected: (value) async {
        if (value == 'logout') await _authService.logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            _authService.email ?? '',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text('Sign out', style: TextStyle(color: Colors.red)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primary,
          child: Text(
            initial,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void _openLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
        fullscreenDialog: true,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
