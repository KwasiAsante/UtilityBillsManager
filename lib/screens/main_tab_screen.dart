import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'base_state.dart';
import 'bills/bill_list_screen.dart';
import 'rentors/rentor_list_screen.dart';
import 'payments/payment_list_screen.dart';
import 'emails/email_list_screen.dart';
import 'summary/summary_screen.dart';
import 'settings/settings_screen.dart';
import 'auth/login_screen.dart';

import '../config/app_config.dart';
import '../services/auth/auth_service.dart';
import '../services/google/google_account_service_native.dart';
import '../utils/app_breakpoints.dart';
import '../widgets/update_banner.dart';

/// The root shell of the app.
///
/// On compact screens (< 600 dp) renders a [NavigationBar] at the bottom with
/// five tabs: Bills (0), Rentors (1), Summary (2), Payments (3), and Emails (4).
/// On wide screens (≥ 600 dp) renders an extended [NavigationRail] on the left
/// with the same five tabs plus a Settings entry pinned at the bottom.
///
/// Uses an [IndexedStack] so each tab's widget tree is preserved across
/// navigation. On web, also initialises [GoogleAccountService] for Gmail
/// access.
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends BaseState<MainTabScreen> {
  // NavigationRail gives leading/trailing unconstrained width, so these are
  // passed explicitly to the rail and reused to size leading/trailing to
  // match instead of using an unbounded SizedBox(width: double.infinity).
  static const double _railMinWidth = 80.0;
  static const double _railExtendedWidth = 256.0;

  int _selectedIndex = 2;
  final _authService = AuthService();
  bool _loginScreenVisible = false;
  bool _railExtended = true;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_onAuthChanged);
    // Handle the case where a 401/403 arrived before this widget mounted
    // (notifyListeners fired with no listeners registered).
    if (_authService.pendingUnauthorized) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthChanged());
    }
    if (kIsWeb && AppConfig.mode == AppMode.server) {
      _initGoogleSignInForWeb();
    }
  }

  @override
  void dispose() {
    _authService.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (_authService.pendingUnauthorized && !_loginScreenVisible) {
      if (mounted) {
        _loginScreenVisible = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const LoginScreen(),
            fullscreenDialog: true,
          ),
        ).whenComplete(() {
          _loginScreenVisible = false;
          _authService.clearUnauthorized();
        });
      }
    }
    if (mounted) setState(() {});
  }

  /// Initialises Google Sign-In once on the web platform so that the
  /// [GoogleAccountService] is ready before any screen tries to sync.
  Future<void> _initGoogleSignInForWeb() async {
    if (!kIsWeb) return;

    if (!GoogleAccountService().isInitialized) {
      await GoogleAccountService().initialize();
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      BillListScreen(isVisible: _selectedIndex == 0),
      RentorListScreen(isVisible: _selectedIndex == 1),
      SummaryScreen(isVisible: _selectedIndex == 2),
      PaymentListScreen(isVisible: _selectedIndex == 3),
      EmailListScreen(isVisible: _selectedIndex == 4),
    ];

    final wide = AppBreakpoints.isWide(context);

    if (wide) {
      return UpdateBanner(
        child: Scaffold(
          body: Row(
            children: [
              NavigationRail(
                extended: _railExtended,
                minWidth: _railMinWidth,
                minExtendedWidth: _railExtendedWidth,
                scrollable: true,
                trailingAtBottom: true,
                selectedIndex: _selectedIndex,
                onDestinationSelected: _onItemTapped,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.receipt_outlined),
                    selectedIcon: Icon(Icons.receipt),
                    label: Text('Bills'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people),
                    label: Text('Rentors'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.summarize_outlined),
                    selectedIcon: Icon(Icons.summarize),
                    label: Text('Summary'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.payment_outlined),
                    selectedIcon: Icon(Icons.payment),
                    label: Text('Payments'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.email_outlined),
                    selectedIcon: Icon(Icons.email),
                    label: Text('Emails'),
                  ),
                ],
                leading: SizedBox(
                  width: _railExtended ? _railExtendedWidth : _railMinWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment:
                          _railExtended
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: _railExtended ? 20 : 0,
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap:
                                () => setState(
                                  () => _railExtended = !_railExtended,
                                ),
                            child: Tooltip(
                              message:
                                  _railExtended
                                      ? 'Collapse menu'
                                      : 'Expand menu',
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Image.asset(
                                      'assets/icon/utility_bills_manager_icon.png',
                                      width: 32,
                                      height: 32,
                                    ),
                                    if (_railExtended) ...[
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'Utility Bills Manager',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: _railExtended ? 20 : 0,
                          ),
                          child:
                              _railExtended && _authService.isLoggedIn
                                  ? Row(
                                    children: [
                                      buildAvatarButton(),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          _authService.email ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              Theme.of(
                                                context,
                                              ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ],
                                  )
                                  : buildAvatarButton(),
                        ),
                      ],
                    ),
                  ),
                ),
                trailing: SizedBox(
                  width: _railExtended ? _railExtendedWidth : _railMinWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap:
                              () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              ),
                          child: SizedBox(
                            width:
                                _railExtended
                                    ? _railExtendedWidth
                                    : _railMinWidth,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: _railExtended ? 20 : 0,
                                vertical: 12,
                              ),
                              child:
                                  _railExtended
                                      ? const Row(
                                        children: [
                                          Icon(Icons.settings_outlined),
                                          SizedBox(width: 24),
                                          Text('Settings'),
                                        ],
                                      )
                                      : const Center(
                                        child: Tooltip(
                                          message: 'Settings',
                                          child: Icon(Icons.settings_outlined),
                                        ),
                                      ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: IndexedStack(index: _selectedIndex, children: screens),
              ),
            ],
          ),
        ),
      );
    }

    return UpdateBanner(
      child: Scaffold(
        body: IndexedStack(index: _selectedIndex, children: screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: _onItemTapped,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.receipt_outlined),
              selectedIcon: Icon(Icons.receipt),
              label: 'Bills',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Rentors',
            ),
            NavigationDestination(
              icon: Icon(Icons.summarize_outlined),
              selectedIcon: Icon(Icons.summarize),
              label: 'Summary',
            ),
            NavigationDestination(
              icon: Icon(Icons.payment_outlined),
              selectedIcon: Icon(Icons.payment),
              label: 'Payments',
            ),
            NavigationDestination(
              icon: Icon(Icons.email_outlined),
              selectedIcon: Icon(Icons.email),
              label: 'Emails',
            ),
          ],
        ),
      ),
    );
  }
}
