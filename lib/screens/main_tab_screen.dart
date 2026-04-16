import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bills/bill_list_screen.dart';
import 'rentors/rentor_list_screen.dart';
import 'payments/payment_list_screen.dart';
import 'emails/email_list_screen.dart';
import 'summary/summary_screen.dart';
import 'settings/settings_screen.dart';

import '../config/app_config.dart';
import '../services/google/google_account_service_native.dart';
import '../utils/app_breakpoints.dart';

/// The root shell of the app containing a bottom navigation bar with five tabs:
/// Bills (0), Rentors (1), Summary (2), Payments (3), and Emails (4).
///
/// Uses an [IndexedStack] so each tab's widget tree is preserved across
/// navigation.  On web, also initialises [GoogleAccountService] for Gmail
/// access.
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _selectedIndex = 2;

  @override
  void initState() {
    super.initState();
    if (kIsWeb && AppConfig.mode == AppMode.server) {
      _initGoogleSignInForWeb();
    }
  }

  @override
  void dispose() {
    super.dispose();
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
      const RentorListScreen(),
      SummaryScreen(isVisible: _selectedIndex == 2,),
      PaymentListScreen(isVisible: _selectedIndex == 3),
      EmailListScreen(isVisible: _selectedIndex == 4),
    ];

    final wide = AppBreakpoints.isWide(context);

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: true,
              selectedIndex: _selectedIndex,
              onDestinationSelected: _onItemTapped,
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.receipt_outlined), selectedIcon: Icon(Icons.receipt), label: Text('Bills')),
                NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Rentors')),
                NavigationRailDestination(icon: Icon(Icons.summarize_outlined), selectedIcon: Icon(Icons.summarize), label: Text('Summary')),
                NavigationRailDestination(icon: Icon(Icons.payment_outlined), selectedIcon: Icon(Icons.payment), label: Text('Payments')),
                NavigationRailDestination(icon: Icon(Icons.email_outlined), selectedIcon: Icon(Icons.email), label: Text('Emails')),
              ],
              trailing: Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const SettingsScreen()),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: Row(
                              children: [
                                Icon(Icons.settings_outlined),
                                SizedBox(width: 24),
                                Text('Settings'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
      );
    }

    return Scaffold(
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
    );
  }
}
