import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'edit_email_data_screen.dart';
import '../../config/app_config.dart';
import '../../config/server_configuration.dart';
import '../../data/models/email_data.dart';
import '../../data/repositories/email_data_repository.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../screens/base/google_sign_in_screen_state.dart';
import '../../utils/app_breakpoints.dart';
import '../../utils/dialogs/sync_options_dialog.dart';
import '../../widgets/notification_bell_icon.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';

/// Screen that displays the list of imported email records.
///
/// Supports filtering by processed/unprocessed state, sorting, and search.
/// On web it syncs emails via Gmail; on mobile / desktop it uses IMAP.
/// Tapping an email navigates to [EditEmailDataScreen].
class EmailListScreen extends StatefulWidget {
  const EmailListScreen({super.key, required this.isVisible});

  /// Controls visibility — passed from the [IndexedStack] in [MainTabScreen].
  final bool isVisible;

  @override
  State<EmailListScreen> createState() => _EmailListScreenState();
}

class _EmailListScreenState extends GoogleSignInScreenState<EmailListScreen> {
  //region GoogleSignInScreenState contract
  @override
  String get googleListenerKey => 'EmailListScreen';

  @override
  Future<void> onGoogleSignedIn({bool canSync = true}) async {
    await _loadEmails(
      syncEmails: canSync,
      earliestEmailDate: ServerConfiguration.emailEarliestDate,
    );
  }

  @override
  void onWebGoogleNotInitialized() {
    setState(() => _loading = false);
  }
  //endregion

  final EmailDataRepository _emailDataRepository = EmailDataRepository();
  final EmailDataHelper _emailDataHelper = EmailDataHelper();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  Future<List<EmailData>>? _emails;
  List<EmailData> _allEmails = [];
  bool _loading = false;
  bool _deferLoading = false; // used to defer loading until after Google sign-in if needed or when screen becomes visible
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedSort = 'Default';
  String _searchQuery = '';

  //region Lifecycle
  @override
  void initState() {
    super.initState();
    if (isGoogleSignInEnabled) {
      if (widget.isVisible) {
        subscribeToSignedInEvents();
      }

      initGoogleSignInForWeb();
    } else {
      if (widget.isVisible) {
        _loadEmails(
          syncEmails: !kIsWeb && AppConfig.mode == AppMode.server,
          earliestEmailDate: ServerConfiguration.emailEarliestDate,
        );
      }
      else {
        _deferLoading = true;
      }
    }

    _scrollController.addListener(_checkScrollability);
    _emailDataRepository.addListener(_onEmailsUpdated);
  }

  @override
  void didUpdateWidget(covariant EmailListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool isVisibleNow = !oldWidget.isVisible && widget.isVisible;

    if (isGoogleSignInEnabled) {
      if (isVisibleNow) {
        subscribeToSignedInEvents();
      } else if (!isVisibleNow) {
        unsubscribeFromSignedInEvents();
      }
    }

    if (isVisibleNow && _deferLoading) {
      _loadEmails(
        syncEmails: !kIsWeb && AppConfig.mode == AppMode.server,
        earliestEmailDate: ServerConfiguration.emailEarliestDate,
      );
    }
  }

  @override
  void dispose() {
    unsubscribeFromSignedInEvents();
    _emailDataRepository.removeListener(_onEmailsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onEmailsUpdated() {
    if (!mounted) return;
    if (_emailDataRepository.lastError != null) {
      setState(() {
        _emails = Future.error(_emailDataRepository.lastError!);
        _loading = false;
      });
    } else {
      _allEmails = _emailDataRepository.emails;
      _updateDisplayedEmails();
    }

    _deferLoading = false;
  }
  //endregion

  //region Emails
  Future<void> _syncEmails() async {
    if (isGoogleSignInEnabled && !googleAccountService.isAuthorized) {
      googleAccountService.showAuthorizationRequiredMessage(context);
      return;
    }

    final options = await SyncOptionsDialog.show(context);
    if (options == null) return;

    await _loadEmails(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      latestEmailDate: options.latestDate,
      maxEmails: options.maxEmails,
    );
  }

  Future<void> _loadEmails({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
    int? maxEmails,
  }) async {
    setState(() => _loading = true);

    if (syncEmails) {
      if (shouldAbortWebSync('emails')) {
        setState(() => _loading = false);
        return;
      }

      await _emailDataHelper.syncEmails(
        earliestEmailDate: earliestEmailDate,
        latestEmailDate: latestEmailDate,
        maxEmails: maxEmails,
      );
    }

    if (!mounted) return;
    await _emailDataRepository.reload();
  }

  Future<void> _deleteEmail(EmailData emailData) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Email'),
            content: Text(
              'Are you sure you want to delete email ${emailData.emailSubject} record?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _emailDataRepository.delete(emailData.emailDataId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email record deleted.')),
        );
      }
    }
  }

  Future<void> _deleteAllEmails() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete All Emails'),
            content: const Text(
              'Are you sure you want to delete all email records? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _emailDataRepository.deleteAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All email records deleted.')),
        );
      }
    }
  }

  void _updateDisplayedEmails() {
    var displayed =
        _allEmails.where((email) {
          final matchesFilter =
              _selectedFilter == 'All' ||
              (_selectedFilter == 'Processed' && email.processed) ||
              (_selectedFilter == 'Unprocessed' && !email.processed);
          final matchesSearch =
              _searchQuery.isEmpty ||
              email.emailSubject.toLowerCase().contains(
                _searchQuery.toLowerCase(),
              );
          return matchesFilter && matchesSearch;
        }).toList();

    switch (_selectedSort) {
      case 'Subject (A-Z)':
        displayed.sort((a, b) => a.emailSubject.compareTo(b.emailSubject));
        break;
      case 'Subject (Z-A)':
        displayed.sort((a, b) => b.emailSubject.compareTo(a.emailSubject));
        break;
      case 'Processed First':
        displayed.sort((a, b) => (b.processed ? 1 : 0) - (a.processed ? 1 : 0));
        break;
      case 'Unprocessed First':
        displayed.sort((a, b) => (a.processed ? 1 : 0) - (b.processed ? 1 : 0));
        break;
    }

    setState(() {
      _emails = Future.value(displayed);
      _loading = false;
    });
  }
  //endregion

  //region Scroll
  void _checkScrollability() {
    if (_scrollController.hasClients) {
      final isScrollable = _scrollController.position.maxScrollExtent > 0;
      if (isScrollable != _isListScrollable) {
        setState(() {
          _isListScrollable = isScrollable;
        });
      }
    }
  }
  //endregion

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emails'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by subject...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _updateDisplayedEmails();
                          },
                        )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
                _updateDisplayedEmails();
              },
            ),
          ),
        ),
        actions: [
          const NotificationBellIcon(),
          if (isGoogleSignInEnabled)
            googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
          PopupMenuButton<String>(
            icon: Icon(
              _selectedFilter == 'All'
                  ? Icons.filter_list
                  : Icons.filter_list_alt,
            ),
            tooltip: 'Filter: $_selectedFilter',
            onSelected: (value) {
              setState(() => _selectedFilter = value);
              _updateDisplayedEmails();
            },
            itemBuilder:
                (context) =>
                    ['All', 'Processed', 'Unprocessed']
                        .map(
                          (value) => CheckedPopupMenuItem<String>(
                            value: value,
                            checked: _selectedFilter == value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort: $_selectedSort',
            onSelected: (value) {
              setState(() => _selectedSort = value);
              _updateDisplayedEmails();
            },
            itemBuilder:
                (context) =>
                    [
                          'Default',
                          'Subject (A-Z)',
                          'Subject (Z-A)',
                          'Processed First',
                          'Unprocessed First',
                        ]
                        .map(
                          (value) => CheckedPopupMenuItem<String>(
                            value: value,
                            checked: _selectedSort == value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
          ),
          if (AppBreakpoints.isWide(context))
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sync emails',
              onPressed: _loading ? null : _syncEmails,
            ),
          if (AppBreakpoints.isWide(context))
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete all email records',
              color: Colors.red,
              onPressed: _deleteAllEmails,
            ),
          if (!AppBreakpoints.isWide(context))
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'More actions',
              itemBuilder:
                  (context) => [
                    const PopupMenuItem(
                      value: 'refresh',
                      child: ListTile(
                        leading: Icon(Icons.sync),
                        title: Text('Sync emails'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Settings'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete_all',
                      child: ListTile(
                        leading: Icon(Icons.delete_sweep, color: Colors.red),
                        title: Text(
                          'Delete all email records',
                          style: TextStyle(color: Colors.red),
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
              onSelected: (String value) {
                if (value == 'refresh') {
                  _syncEmails();
                } else if (value == 'settings') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                } else if (value == 'delete_all') {
                  _deleteAllEmails();
                }
              },
            ),
        ],
      ),
      body: ResponsiveConstraint(
        child: Column(
          children: [
            if (isGoogleSignInEnabled &&
                googleAccountService.buildWebWarningBanner() != null)
              googleAccountService.buildWebWarningBanner()!,
            Expanded(
              child:
                  _loading
                      ? const Center(child: CircularProgressIndicator())
                      : FutureBuilder<List<EmailData>>(
                        future: _emails,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          } else if (snapshot.hasError) {
                            return Center(
                              child: Text('Error: ${snapshot.error}'),
                            );
                          } else if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            if (!isGoogleSignInEnabled ||
                                (googleAccountService.isSignedIn &&
                                    googleAccountService.isAuthorized)) {
                              return const Center(
                                child: Text(
                                  'No emails found. Pull down or click the Refresh button to sync emails.',
                                ),
                              );
                            } else {
                              return const Center(
                                child: Text(
                                  'Please sign in to your Google account to view emails.',
                                ),
                              );
                            }
                          }

                          final emails = snapshot.data!;
                          return RefreshIndicator(
                            onRefresh: () async {
                              await Future.delayed(const Duration(seconds: 2));
                              await _syncEmails();
                            },
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(
                                dragDevices: {
                                  PointerDeviceKind.touch,
                                  PointerDeviceKind.mouse,
                                },
                              ),
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.only(bottom: 80),
                                itemCount: emails.length,
                                itemBuilder: (context, index) {
                                  return _buildEmailCard(emails[index]);
                                },
                              ),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailCard(EmailData email) {
    final bodyPreview =
        email.emailBody.length > 100
            ? '${email.emailBody.substring(0, 100)}...'
            : email.emailBody;

    return Card(
      child: ListTile(
        title: Text(
          email.emailSubject,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bodyPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                Chip(
                  label: Text(
                    email.processed ? 'Processed' : 'Unprocessed',
                    style: const TextStyle(fontSize: 11),
                  ),
                  backgroundColor:
                      email.processed
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                if (email.bill != null)
                  Chip(
                    label: Text(
                      'Bill: ${email.bill!.companyName}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: Colors.blue.shade100,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                if (email.payment != null)
                  Chip(
                    label: Text(
                      'Payment: \$${email.payment!.amountPaid.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    backgroundColor: Colors.purple.shade100,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditEmailDataScreen(emailData: email),
                ),
              );
            } else if (value == 'delete') {
              await _deleteEmail(email);
            }
          },
          itemBuilder:
              (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditEmailDataScreen(emailData: email),
            ),
          );
        },
      ),
    );
  }
}
