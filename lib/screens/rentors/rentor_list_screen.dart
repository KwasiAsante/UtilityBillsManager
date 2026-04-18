import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../rentors/add_edit_rentor_screen.dart';
import '../../data/models/rentor.dart';
import '../../data/repositories/rentors_repository.dart';
import '../../helpers/rentors/rentors_helper.dart';
import '../../utils/comparable_utils.dart';
import '../../utils/app_breakpoints.dart';
import '../../widgets/notification_bell_icon.dart';
import '../../widgets/responsive_constraint.dart';
import '../settings/settings_screen.dart';

/// Screen that displays the list of rentors (tenants).
///
/// Subscribes to [RentorsRepository] for reactive list updates.
/// Supports sorting by percentage, name, and last-payment date, as well as
/// full-text search.
class RentorListScreen extends StatefulWidget {
  const RentorListScreen({super.key, required this.isVisible});

  /// Controls visibility — passed from the [IndexedStack] in [MainTabScreen]
  /// to avoid unnecessary background work when the tab is not active.
  final bool isVisible;

  @override
  State<RentorListScreen> createState() => _RentorListScreenState();
}

class _RentorListScreenState extends State<RentorListScreen> {
  final RentorsHelper _rentorsHelper = RentorsHelper();
  final RentorsRepository _rentorsRepository = RentorsRepository();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  Future<List<Rentor>>? _rentors;
  List<Rentor> _allRentors = [];
  bool _loading = false;
  bool _deferLoading = false; // used to defer loading until screen becomes visible
  bool _isListScrollable = false;
  String _selectedSort = 'Percentage';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rentorsRepository.addListener(_onRentorsUpdated);
    _scrollController.addListener(_checkScrollability);
    if (widget.isVisible) {
      setState(() => _loading = true);
      _rentorsRepository.reload();
    }
    else {
      _deferLoading = true;
    }
  }

  @override
  void didUpdateWidget(covariant RentorListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    bool isVisibleNow = !oldWidget.isVisible && widget.isVisible;

    if (isVisibleNow && _deferLoading) {
      setState(() => _loading = true);
      _rentorsRepository.reload();
    }
  }

  @override
  void dispose() {
    _rentorsRepository.removeListener(_onRentorsUpdated);
    _scrollController.removeListener(_checkScrollability);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onRentorsUpdated() {
    if (!mounted) return;
    if (_rentorsRepository.lastError != null) {
      setState(() {
        _rentors = Future.error(_rentorsRepository.lastError!);
        _loading = false;
      });
    } else {
      _allRentors = _rentorsRepository.rentors;
      _updateDisplayedRentors();
    }

    _deferLoading = false;
  }

  void _updateDisplayedRentors() {
    var displayed =
        _allRentors
            .where(
              (rentor) =>
                  _searchQuery.isEmpty ||
                  rentor.name.toLowerCase().contains(
                    _searchQuery.toLowerCase(),
                  ),
            )
            .toList();

    switch (_selectedSort) {
      case 'Percentage':
        displayed.sort(
          (a, b) => a.defaultPercentage.compareTo(b.defaultPercentage),
        );
        break;
      case 'Last Payment Date (Asc)':
        displayed.sort(
          (a, b) => ComparableUtils.compareNullable(
            a.lastPaymentDate,
            b.lastPaymentDate,
          ),
        );
        break;
      case 'Last Payment Date (Desc)':
        displayed.sort(
          (a, b) => ComparableUtils.compareNullable(
            a.lastPaymentDate,
            b.lastPaymentDate,
            descending: true,
          ),
        );
        break;
    }

    setState(() {
      _rentors = Future.value(displayed);
      _loading = false;
    });
  }

  Future<void> _deleteAllRentors() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete All Rentors'),
            content: const Text(
              'Are you sure you want to delete all rentors? This action cannot be undone.',
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
      for (final rentor in _allRentors) {
        await _rentorsHelper.deleteRentor(rentor.rentorId);
      }

      await _rentorsRepository.reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('All rentors deleted.')));
      }
    }
  }

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
        title: const Text('Rentors'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _updateDisplayedRentors();
                          },
                        )
                        : null,
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
                _updateDisplayedRentors();
              },
            ),
          ),
        ),
        actions: [
          const NotificationBellIcon(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort: $_selectedSort',
            onSelected: (value) {
              setState(() => _selectedSort = value);
              _updateDisplayedRentors();
            },
            itemBuilder:
                (context) =>
                    [
                          'Percentage',
                          'Last Payment Date (Asc)',
                          'Last Payment Date (Desc)',
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More actions',
            itemBuilder:
                (context) => [
                  const PopupMenuItem<String>(
                    value: 'refresh',
                    child: ListTile(
                      leading: Icon(Icons.refresh),
                      title: Text('Refresh'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  if (!AppBreakpoints.isWide(context))
                    const PopupMenuItem<String>(
                      value: 'settings',
                      child: ListTile(
                        leading: Icon(Icons.settings_outlined),
                        title: Text('Settings'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem<String>(
                    value: 'delete_all',
                    child: ListTile(
                      leading: Icon(Icons.delete_sweep, color: Colors.red),
                      title: Text(
                        'Delete all rentors',
                        style: TextStyle(color: Colors.red),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
            onSelected: (String value) async {
              if (value == 'refresh') {
                await _rentorsRepository.reload();
              } else if (value == 'settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              } else if (value == 'delete_all') {
                _deleteAllRentors();
              }
            },
          ),
        ],
      ),
      body: ResponsiveConstraint(
        child:
            _loading
                ? const Center(child: CircularProgressIndicator())
                : FutureBuilder<List<Rentor>>(
                  future: _rentors,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                        child: Text(
                          'No rentors found. Pull down or click on the Refresh button to sync or click the + button to add a rentor.',
                        ),
                      );
                    }

                    final rentors = snapshot.data!;
                    return RefreshIndicator(
                      onRefresh: () async {
                        await _rentorsRepository.reload();
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
                          itemCount: rentors.length,
                          itemBuilder: (context, index) {
                            final rentor = rentors[index];
                            return Card(
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                isThreeLine:
                                    rentor.email != null ||
                                    rentor.phone != null,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (context) => AddEditRentorScreen(
                                            rentor: rentor,
                                          ),
                                    ),
                                  );
                                },
                                title: Text(
                                  rentor.name,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${rentor.defaultPercentage.toStringAsFixed(1)}%',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            rentor.lastPaymentDate != null
                                                ? 'Last paid: ${DateFormat('MMM d, yyyy').format(rentor.lastPaymentDate!)}'
                                                : 'No payments yet',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (rentor.email != null ||
                                          rentor.phone != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          [
                                            if (rentor.email != null)
                                              rentor.email!,
                                            if (rentor.phone != null)
                                              rentor.phone!,
                                          ].join('  ·  '),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'edit') {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (context) => AddEditRentorScreen(
                                                rentor: rentor,
                                              ),
                                        ),
                                      );
                                    } else if (value == 'delete') {
                                      await _rentorsRepository.delete(
                                        rentor.rentorId,
                                      );
                                    }
                                  },
                                  itemBuilder:
                                      (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          textStyle: TextStyle(
                                            color: Colors.red,
                                          ),
                                          child: Text('Delete'),
                                        ),
                                      ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'rentor_list_fab',
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEditRentorScreen(),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
