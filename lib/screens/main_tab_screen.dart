import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/email/google_account_service.dart';
import 'bills/bill_list_screen.dart';
import 'rentors/rentor_list_screen.dart';
import 'payments/payment_list_screen.dart';
import 'emails/email_list_screen.dart';
import 'summary/summary_screen.dart';

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
    if (kIsWeb) {
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

    return Scaffold(
      appBar: AppBar(title: const Text('Utility Bills Manager')),
      body: IndexedStack(index: _selectedIndex, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.grey.shade300, width: 1.0),
          ),
        ),
        child: Row(
          children: [
            _buildNavItem(0, Icons.receipt, 'Bills'),
            _buildNavItem(1, Icons.people, 'Rentors'),
            _buildNavItem(2, Icons.summarize, 'Summary', isMain: true),
            _buildNavItem(3, Icons.payment, 'Payments'),
            _buildNavItem(4, Icons.email, 'Emails'),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData icon,
    String label, {
    bool isMain = false,
  }) {
    final isSelected = _selectedIndex == index;
    final theme = Theme.of(context);

    return Expanded(
      child: Material(
        color:
            isMain
                ? theme.colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isSelected ? theme.colorScheme.primary : Colors.grey,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? theme.colorScheme.primary : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
