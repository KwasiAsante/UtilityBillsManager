import 'dart:ui';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../config/app_config.dart';
import '../../data/models/email_data.dart';
import '../../data/repositories/email_data_repository.dart';
import '../../helpers/email/email_data_helper.dart';
import '../../screens/base/google_sign_in_screen_state.dart';
import '../../utils/dialogs/sync_options_dialog.dart';
import 'edit_email_data_screen.dart';

class EmailListScreen extends StatefulWidget {
  const EmailListScreen({super.key, required this.isVisible});

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
      earliestEmailDate: AppConfig.emailEarliestDate,
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

  Future<List<EmailData>>? _emails;
  List<EmailData> _allEmails = [];
  bool _loading = true;
  bool _isListScrollable = false;
  String _selectedFilter = 'All';
  String _selectedSort = 'Default';
  String _searchQuery = '';

  //region Lifecycle
  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      initGoogleSignInForWeb();
    } else {
      _loadEmails(
        syncEmails: true,
        earliestEmailDate: AppConfig.emailEarliestDate,
      );
    }
    if (widget.isVisible) {
      subscribeToSignedInEvents();
    }
    _scrollController.addListener(_checkScrollability);
    _emailDataRepository.addListener(_onEmailsUpdated);
  }

  @override
  void didUpdateWidget(covariant EmailListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isVisible && widget.isVisible) {
      subscribeToSignedInEvents();
    } else if (oldWidget.isVisible && !widget.isVisible) {
      unsubscribeFromSignedInEvents();
    }
  }

  @override
  void dispose() {
    unsubscribeFromSignedInEvents();
    _emailDataRepository.removeListener(_onEmailsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
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
  }
  //endregion

  //region Emails
  Future<void> _syncEmails() async {
    if (kIsWeb && !googleAccountService.isAuthorized) {
      googleAccountService.showAuthorizationRequiredMessage(context);
      return;
    }

    final options = await SyncOptionsDialog.show(context);
    if (options == null) return;

    await _loadEmails(
      syncEmails: true,
      earliestEmailDate: options.earliestDate,
      maxEmails: options.maxEmails,
    );
  }

  Future<void> _loadEmails({
    bool syncEmails = false,
    DateTime? earliestEmailDate,
    int maxEmails = 50,
  }) async {
    setState(() => _loading = true);

    if (syncEmails && (!kIsWeb || googleAccountService.isAuthorized)) {
      await _emailDataHelper.fetchBillEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
      await _emailDataHelper.fetchPaymentEmails(
        earliestEmailDate: earliestEmailDate,
        maxEmails: maxEmails,
      );
    }

    if (!mounted) return;
    await _emailDataRepository.reload();
  }

  Future<void> _deleteAllEmails() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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
    var displayed = _allEmails.where((email) {
      final matchesFilter = _selectedFilter == 'All' ||
          (_selectedFilter == 'Processed' && email.processed) ||
          (_selectedFilter == 'Unprocessed' && !email.processed);
      final matchesSearch = _searchQuery.isEmpty ||
          email.emailSubject.toLowerCase().contains(_searchQuery.toLowerCase());
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
              decoration: InputDecoration(
                hintText: 'Search by subject...',
                prefixIcon: const Icon(Icons.search),
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
          if (kIsWeb)
            googleAccountService.buildWebGoogleAction(authorizeGoogleAccount),
          if (_searchQuery.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                });
                _updateDisplayedEmails();
              },
            ),
          DropdownButton<String>(
            value: _selectedFilter,
            items: ['All', 'Processed', 'Unprocessed'].map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedFilter = newValue;
                });
                _updateDisplayedEmails();
              }
            },
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _selectedSort,
            items: [
              'Default',
              'Subject (A-Z)',
              'Subject (Z-A)',
              'Processed First',
              'Unprocessed First',
            ].map((String value) {
              return DropdownMenuItem<String>(
                value: value,
                child: Text(value),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedSort = newValue;
                });
                _updateDisplayedEmails();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Sync emails',
            onPressed: _syncEmails,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Delete all email records',
            onPressed: _deleteAllEmails,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          if (googleAccountService.buildWebWarningBanner() != null)
            googleAccountService.buildWebWarningBanner()!,
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<List<EmailData>>(
                    future: _emails,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        if (!kIsWeb ||
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
                          behavior: ScrollConfiguration.of(context).copyWith(
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
    );
  }

  Widget _buildEmailCard(EmailData email) {
    final bodyPreview = email.emailBody.length > 100
        ? '${email.emailBody.substring(0, 100)}...'
        : email.emailBody;

    return Card(
      margin: const EdgeInsets.all(8.0),
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
                  backgroundColor: email.processed
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
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Email'),
                  content: const Text(
                    'Are you sure you want to delete this email record?',
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
                await _emailDataRepository.delete(email.emailDataId!);
              }
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Text('Edit'),
            ),
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
