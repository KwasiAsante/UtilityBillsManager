import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_breakpoints.dart';

/// Chromium's Web Share API rejects any call sharing more than this many
/// files (see https://w3c.github.io/web-share/, Blink's kMaxSharedFileCount).
/// Past this, the browser falls back to downloading each file individually
/// instead of showing a share dialog — native mobile share sheets have no
/// such limit.
const kMaxWebShareFiles = 10;

/// Holds the values selected in [ExportMonthPickerDialog].
class ExportMonthPickerResult {
  final List<String> selectedMonths;
  final bool combineAsWorkbook;

  const ExportMonthPickerResult({
    required this.selectedMonths,
    required this.combineAsWorkbook,
  });
}

/// A reusable month-selection dialog/bottom-sheet for CSV/PDF export.
///
/// Lists [availableMonths] as checkboxes (all pre-checked), plus a
/// "Combine into single Excel workbook" toggle when [showCombineOption] is
/// true (CSV export only — PDF is always a single combined file). On web,
/// when the combine toggle is off and more than [kMaxWebShareFiles] months
/// are available, selection is capped at [kMaxWebShareFiles]: further
/// checkboxes are disabled, "Select All" only selects up to the cap, and
/// turning combine off while over the cap trims the selection down to it.
/// Native mobile share sheets have no such limit.
class ExportMonthPickerDialog {
  ExportMonthPickerDialog._();

  /// Opens the picker and returns the user's selection, or `null` if
  /// dismissed without exporting.
  static Future<ExportMonthPickerResult?> show(
    BuildContext context, {
    required List<String> availableMonths,
    bool showCombineOption = false,
    @visibleForTesting bool? isWebOverride,
  }) {
    if (AppBreakpoints.isWide(context)) {
      return showDialog<ExportMonthPickerResult>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
            child: SingleChildScrollView(
              child: _ExportMonthPickerContent(
                availableMonths: availableMonths,
                showCombineOption: showCombineOption,
                isWebOverride: isWebOverride,
                isDialog: true,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<ExportMonthPickerResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ExportMonthPickerContent(
        availableMonths: availableMonths,
        showCombineOption: showCombineOption,
        isWebOverride: isWebOverride,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private stateful content widget
// ─────────────────────────────────────────────────────────────────────────────

class _ExportMonthPickerContent extends StatefulWidget {
  const _ExportMonthPickerContent({
    required this.availableMonths,
    required this.showCombineOption,
    this.isWebOverride,
    this.isDialog = false,
  });

  final List<String> availableMonths;
  final bool showCombineOption;
  final bool? isWebOverride;
  final bool isDialog;

  @override
  State<_ExportMonthPickerContent> createState() =>
      _ExportMonthPickerContentState();
}

class _ExportMonthPickerContentState
    extends State<_ExportMonthPickerContent> {
  late Set<String> _selected;
  bool _combineAsWorkbook = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.availableMonths.toSet();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = widget.isWebOverride ?? kIsWeb;
    // Chromium rejects navigator.share() outright above kMaxWebShareFiles,
    // so past that, sharing without combining is capped rather than left to
    // fail into an unpredictable download fallback.
    final capApplies = widget.showCombineOption &&
        !_combineAsWorkbook &&
        isWeb &&
        widget.availableMonths.length > kMaxWebShareFiles;
    final effectiveMax =
        capApplies ? kMaxWebShareFiles : widget.availableMonths.length;
    final allSelected = _selected.length == effectiveMax;
    final atLimit = capApplies && _selected.length >= kMaxWebShareFiles;

    // On the bottom-sheet branch, clear both the keyboard (viewInsets) and
    // the system nav bar / gesture area (padding) — using viewInsets alone
    // leaves the Export/Cancel row hidden behind Android's nav bar.
    final bottomInset = widget.isDialog
        ? 16.0
        : MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom +
            16;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Export Months',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    _selected = <String>{};
                  } else if (capApplies) {
                    _selected =
                        widget.availableMonths.take(kMaxWebShareFiles).toSet();
                  } else {
                    _selected = widget.availableMonths.toSet();
                  }
                }),
                child: Text(allSelected ? 'Clear All' : 'Select All'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                children: widget.availableMonths.map((month) {
                  final isChecked = _selected.contains(month);
                  final disabled = atLimit && !isChecked;
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(month),
                    value: isChecked,
                    onChanged: disabled
                        ? null
                        : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(month);
                              } else {
                                _selected.remove(month);
                              }
                            }),
                  );
                }).toList(),
              ),
            ),
          ),
          if (widget.showCombineOption) ...[
            const Divider(),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Combine into single Excel workbook'),
              subtitle: const Text(
                'Off: each month is exported as its own CSV file',
              ),
              value: _combineAsWorkbook,
              onChanged: (checked) => setState(() {
                _combineAsWorkbook = checked ?? true;
                if (!_combineAsWorkbook &&
                    isWeb &&
                    _selected.length > kMaxWebShareFiles) {
                  _selected = widget.availableMonths
                      .where(_selected.contains)
                      .take(kMaxWebShareFiles)
                      .toSet();
                }
              }),
            ),
            if (atLimit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reached the $kMaxWebShareFiles-file browser sharing '
                        'limit. Turn on "Combine into workbook" to export '
                        'more months at once.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(
                          ExportMonthPickerResult(
                            selectedMonths: widget.availableMonths
                                .where(_selected.contains)
                                .toList(),
                            combineAsWorkbook: _combineAsWorkbook,
                          ),
                        ),
                child: const Text('Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
