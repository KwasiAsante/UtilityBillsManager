import 'package:flutter/material.dart';

class SyncOptions {
  final DateTime? earliestDate;
  final int maxEmails;

  const SyncOptions({this.earliestDate, this.maxEmails = 50});
}

class SyncOptionsDialog {
  SyncOptionsDialog._();

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
                      maxEmails: fetchLast50 ? 50 : 100,
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

