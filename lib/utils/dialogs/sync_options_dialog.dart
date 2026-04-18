import 'package:flutter/material.dart';

/// Holds the user's selections from [SyncOptionsDialog]: how far back to fetch
/// emails and the maximum number of emails to retrieve.
class SyncOptions {
  final DateTime? earliestDate;
  final int? maxEmails;

  const SyncOptions({this.earliestDate, this.maxEmails});
}

/// Static-only utility that shows a dialog for configuring email sync options.
///
/// The user can either pick an earliest date (date-picker) or tick "Fetch last
/// 50 emails" to ignore the date filter entirely.
class SyncOptionsDialog {
  SyncOptionsDialog._();

  /// Shows the sync-options [AlertDialog] and returns the user's [SyncOptions],
  /// or `null` if the dialog was cancelled.
  static Future<SyncOptions?> show(BuildContext context) {
    DateTime? selectedDate;
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
                    'Choose how far back to fetch emails, or fetch the last 50 emails regardless of date.',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  if (!fetchLast50)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        selectedDate == null
                            ? 'Select earliest email date'
                            : 'From: ${selectedDate!.toLocal().toString().split(' ')[0]}',
                      ),
                      trailing: selectedDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear date',
                              onPressed: () =>
                                  setDialogState(() => selectedDate = null),
                            )
                          : null,
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: selectedDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setDialogState(() => selectedDate = date);
                        }
                      },
                    ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fetch last 50 emails instead'),
                    value: fetchLast50,
                    onChanged: (value) {
                      setDialogState(() {
                        fetchLast50 = value ?? false;
                        if (fetchLast50) selectedDate = null;
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

