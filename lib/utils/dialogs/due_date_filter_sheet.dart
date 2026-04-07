import 'package:flutter/material.dart';
import 'package:utility_bills_manager/utils/constants.dart';

/// Holds the values selected in [DueDateFilterSheet].
class DueDateFilterResult {
  final int? selectedYear;
  final int? selectedMonth;
  final DateTime? dateRangeStart;
  final DateTime? dateRangeEnd;

  const DueDateFilterResult({
    this.selectedYear,
    this.selectedMonth,
    this.dateRangeStart,
    this.dateRangeEnd,
  });

  bool get isEmpty =>
      selectedYear == null &&
      selectedMonth == null &&
      dateRangeStart == null &&
      dateRangeEnd == null;
}

/// A reusable bottom-sheet filter for due-date filtering.
///
/// Usage:
/// ```dart
/// final result = await DueDateFilterSheet.show(
///   context,
///   availableYears: [2024, 2025, 2026],
///   current: DueDateFilterResult(selectedYear: 2025),
/// );
/// if (result != null) { /* apply result */ }
/// ```
class DueDateFilterSheet {
  DueDateFilterSheet._();

  static String formatDate(DateTime date) =>
      '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Returns the earliest allowed date given the selected [year] and/or [month].
  static DateTime _constrainedFirst(int? year, int? month) {
    if (year != null && month != null) return DateTime(year, month, 1);
    if (year != null) return DateTime(year, 1, 1);
    if (month != null) return DateTime(2000, month, 1);
    return DateTime(2000);
  }

  /// Returns the latest allowed date given the selected [year] and/or [month].
  static DateTime _constrainedLast(int? year, int? month) {
    if (year != null && month != null) return DateTime(year, month + 1, 0);
    if (year != null) return DateTime(year, 12, 31);
    if (month != null) return DateTime(2100, month + 1, 0);
    return DateTime(2100);
  }

  /// Opens the filter bottom sheet and returns the user's selection,
  /// or `null` if the sheet was dismissed without applying.
  static Future<DueDateFilterResult?> show(
    BuildContext context, {
    required List<int> availableYears,
    DueDateFilterResult current = const DueDateFilterResult(),
  }) {
    return showModalBottomSheet<DueDateFilterResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _DueDateFilterSheetContent(
        availableYears: availableYears,
        current: current,
        monthNames: AppConstants.monthNames,
        formatDate: formatDate,
        constrainedFirst: _constrainedFirst,
        constrainedLast: _constrainedLast,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private stateful content widget
// ─────────────────────────────────────────────────────────────────────────────

class _DueDateFilterSheetContent extends StatefulWidget {
  const _DueDateFilterSheetContent({
    required this.availableYears,
    required this.current,
    required this.monthNames,
    required this.formatDate,
    required this.constrainedFirst,
    required this.constrainedLast,
  });

  final List<int> availableYears;
  final DueDateFilterResult current;
  final List<String> monthNames;
  final String Function(DateTime) formatDate;
  final DateTime Function(int?, int?) constrainedFirst;
  final DateTime Function(int?, int?) constrainedLast;

  @override
  State<_DueDateFilterSheetContent> createState() =>
      _DueDateFilterSheetContentState();
}

class _DueDateFilterSheetContentState
    extends State<_DueDateFilterSheetContent> {
  late int? _tempYear;
  late int? _tempMonth;
  late DateTime? _tempStart;
  late DateTime? _tempEnd;

  @override
  void initState() {
    super.initState();
    _tempYear = widget.current.selectedYear;
    _tempMonth = widget.current.selectedMonth;
    _tempStart = widget.current.dateRangeStart;
    _tempEnd = widget.current.dateRangeEnd;
  }

  /// Clears [_tempStart] / [_tempEnd] if they fall outside the date range
  /// implied by the currently selected year and/or month.
  void _clampRangeToBounds() {
    final first = widget.constrainedFirst(_tempYear, _tempMonth);
    final last = widget.constrainedLast(_tempYear, _tempMonth);
    if (_tempStart != null &&
        (_tempStart!.isBefore(first) || _tempStart!.isAfter(last))) {
      _tempStart = null;
    }
    if (_tempEnd != null &&
        (_tempEnd!.isBefore(first) || _tempEnd!.isAfter(last))) {
      _tempEnd = null;
    }
  }

  Future<void> _pickStartDate() async {
    final first = widget.constrainedFirst(_tempYear, _tempMonth);
    final last = widget.constrainedLast(_tempYear, _tempMonth);
    final initial = (_tempStart != null &&
            !_tempStart!.isBefore(first) &&
            !_tempStart!.isAfter(last))
        ? _tempStart!
        : first;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Select start date',
    );
    if (picked != null) {
      setState(() {
        _tempStart = picked;
        if (_tempEnd != null && _tempEnd!.isBefore(picked)) _tempEnd = null;
      });
    }
  }

  Future<void> _pickEndDate() async {
    final first = widget.constrainedFirst(_tempYear, _tempMonth);
    final last = widget.constrainedLast(_tempYear, _tempMonth);
    final rangeStart = (_tempStart != null &&
            !_tempStart!.isBefore(first) &&
            !_tempStart!.isAfter(last))
        ? _tempStart!
        : first;
    final initial = (_tempEnd != null &&
            !_tempEnd!.isBefore(rangeStart) &&
            !_tempEnd!.isAfter(last))
        ? _tempEnd!
        : rangeStart;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: rangeStart,
      lastDate: last,
      helpText: 'Select end date',
    );
    if (picked != null) setState(() => _tempEnd = picked);
  }

  @override
  Widget build(BuildContext context) {
    final safeYear = (_tempYear != null && widget.availableYears.contains(_tempYear))
        ? _tempYear
        : null;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Due Date Filters',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // ── Year / Month ──────────────────────────────────────────────────
          _sectionHeader(context, Icons.calendar_today, 'Year & Month'),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: safeYear,
            decoration: const InputDecoration(labelText: 'Year'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All years')),
              ...widget.availableYears.map(
                (y) => DropdownMenuItem<int?>(value: y, child: Text(y.toString())),
              ),
            ],
            onChanged: (value) => setState(() {
              _tempYear = value;
              _clampRangeToBounds();
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _tempMonth,
            decoration: const InputDecoration(labelText: 'Month'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('All months')),
              ...List.generate(
                12,
                (i) => DropdownMenuItem<int?>(
                  value: i + 1,
                  child: Text(widget.monthNames[i]),
                ),
              ),
            ],
            onChanged: (value) => setState(() {
              _tempMonth = value;
              _clampRangeToBounds();
            }),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),

          // ── Date Range ────────────────────────────────────────────────────
          _sectionHeader(context, Icons.date_range, 'Date Range'),
          if (_tempYear != null || _tempMonth != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 13,
                    color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Picker is limited to: '
                    '${_tempYear != null && _tempMonth != null ? '${widget.monthNames[_tempMonth! - 1]} $_tempYear' : _tempYear != null ? 'year $_tempYear' : widget.monthNames[_tempMonth! - 1]}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _tempStart != null
                        ? widget.formatDate(_tempStart!)
                        : 'From date',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickStartDate,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(
                    _tempEnd != null
                        ? widget.formatDate(_tempEnd!)
                        : 'To date',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _pickEndDate,
                ),
              ),
            ],
          ),
          if (_tempStart != null || _tempEnd != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.clear, size: 16),
                label: const Text('Clear range'),
                onPressed: () => setState(() {
                  _tempStart = null;
                  _tempEnd = null;
                }),
              ),
            ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _tempYear = null;
                  _tempMonth = null;
                  _tempStart = null;
                  _tempEnd = null;
                }),
                child: const Text('Clear All'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(
                  DueDateFilterResult(
                    selectedYear: _tempYear,
                    selectedMonth: _tempMonth,
                    dateRangeStart: _tempStart,
                    dateRangeEnd: _tempEnd,
                  ),
                ),
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _sectionHeader(
      BuildContext context, IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}



