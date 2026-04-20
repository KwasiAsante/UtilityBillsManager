import 'package:flutter/material.dart';

/// Holds the user's selections from [SyncOptionsDialog]: a date range to
/// filter emails and the maximum number of emails to retrieve.
class SyncOptions {
  final DateTime? earliestDate;
  final DateTime? latestDate;
  final int? maxEmails;

  const SyncOptions({this.earliestDate, this.latestDate, this.maxEmails});
}

/// Static-only utility that shows a dialog for configuring email sync options.
///
/// The user can pick a date range (earliest → latest) or tick "Fetch last
/// 50 emails" to ignore the date filter entirely.
class SyncOptionsDialog {
  SyncOptionsDialog._();

  /// Shows the sync-options [AlertDialog] and returns the user's [SyncOptions],
  /// or `null` if the dialog was cancelled.
  static Future<SyncOptions?> show(BuildContext context) {
    DateTime? selectedDate;
    DateTime? latestDate;
    bool fetchLast50 = false;

    return showDialog<SyncOptions>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Sync Emails'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose a date range to fetch emails, or fetch the last 50 emails regardless of date.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (!fetchLast50)
                    Row(
                      children: [
                        Expanded(
                          child: _DateChip(
                            label: 'From',
                            date: selectedDate,
                            placeholder: 'Any date',
                            onTap: () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (date != null) {
                                setDialogState(() {
                                  selectedDate = date;
                                  // Guard: if the user re-picks a From date that is after the existing To date,
                                  // clear To to avoid returning an inverted range.
                                  if (latestDate != null &&
                                      date.isAfter(latestDate!)) {
                                    latestDate = null;
                                  }
                                });
                              }
                            },
                            onClear: () => setDialogState(() {
                              selectedDate = null;
                              latestDate = null;
                            }),
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '→',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        Expanded(
                          child: IgnorePointer(
                            ignoring: selectedDate == null,
                            child: Opacity(
                              opacity: selectedDate == null ? 0.4 : 1.0,
                              child: _DateChip(
                                label: 'To',
                                date: latestDate,
                                placeholder: 'No end date',
                                onTap: () async {
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: latestDate ?? selectedDate!,
                                    firstDate: selectedDate!,
                                    lastDate: DateTime.now(),
                                  );
                                  if (date != null) {
                                    setDialogState(() => latestDate = date);
                                  }
                                },
                                onClear: () => setDialogState(
                                  () => latestDate = null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fetch last 50 emails instead'),
                    value: fetchLast50,
                    onChanged: (value) {
                      setDialogState(() {
                        fetchLast50 = value ?? false;
                        if (fetchLast50) {
                          selectedDate = null;
                          latestDate = null;
                        }
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(
                    context,
                    SyncOptions(
                      earliestDate: fetchLast50 ? null : selectedDate,
                      latestDate: fetchLast50 ? null : latestDate,
                      maxEmails: fetchLast50 ? 50 : null,
                    ),
                  ),
                  child: const Text('Sync'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// A compact tappable chip for displaying and selecting a date.
class _DateChip extends StatelessWidget {
  final String label;
  final DateTime? date;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _DateChip({
    required this.label,
    required this.date,
    required this.placeholder,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    date != null
                        ? '${date!.year}-${date!.month.toString().padLeft(2, '0')}-${date!.day.toString().padLeft(2, '0')}'
                        : placeholder,
                    style: TextStyle(
                      fontSize: 12,
                      color: date != null
                          ? Theme.of(context).colorScheme.primary
                          : null,
                      fontWeight: date != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                      fontStyle: date != null
                          ? FontStyle.normal
                          : FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            if (date != null)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.clear, size: 14),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                iconSize: 14,
              ),
          ],
        ),
      ),
    );
  }
}
