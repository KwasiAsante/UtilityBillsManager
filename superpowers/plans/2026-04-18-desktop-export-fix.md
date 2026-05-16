# Desktop CSV/PDF Export Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix CSV and PDF export on Windows, macOS, and Linux by replacing `share_plus` with a native Save As dialog (`file_selector`) on desktop platforms, leaving mobile/web unchanged.

**Architecture:** Add a platform check in `ExportUtils`. On desktop, call `getSaveLocation()` to get a user-chosen path and write the file with `dart:io`. On mobile/web, keep the existing `SharePlus.instance.share()` flow. To keep the save-path logic testable, pass it as an optional callback parameter.

**Tech Stack:** `file_selector` (Flutter team), `dart:io` File, existing `share_plus` (unchanged for mobile/web)

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `pubspec.yaml` | Modify | Add `file_selector` dependency |
| `lib/utils/export_utils.dart` | Modify | Add desktop save path logic |
| `test/utils/export_utils_test.dart` | Create | Unit tests for desktop export |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b fix/windows-desktop-export
```

- [ ] **Step 2: Verify you are on the new branch**

```bash
git branch --show-current
```
Expected output: `fix/windows-desktop-export`

---

### Task 2: Add `file_selector` dependency

- [ ] **Step 1: Add the dependency to `pubspec.yaml`**

Open `pubspec.yaml`. After the `share_plus` line (currently line 52), add:

```yaml
  file_selector: ^0.9.0
```

Result should look like:
```yaml
  share_plus: ^13.0.0
  file_selector: ^0.9.0
```

- [ ] **Step 2: Fetch the package**

```bash
flutter pub get
```

Expected: resolves without errors, `pubspec.lock` updated.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore: add file_selector dependency for desktop Save As dialog"
```

---

### Task 3: Write failing tests

- [ ] **Step 1: Create the test file**

Create `test/utils/export_utils_test.dart` with the following content:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/utils/export_utils.dart';

void main() {
  group('ExportUtils desktop CSV', () {
    test('writes CSV file to the path returned by saveFn', () async {
      final dir = Directory.systemTemp.createTempSync('export_test');
      final savedPaths = <String>[];

      int callCount = 0;
      Future<String?> fakeSave(String suggestedName) async {
        final path = '${dir.path}/$suggestedName';
        savedPaths.add(path);
        callCount++;
        return path;
      }

      final bill = Bill(
        billId: 'b1',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        amountPaid: 100.0,
      );

      await ExportUtils.exportBillsToCSV(
        [bill],
        [],
        [],
        desktopSaveFn: fakeSave,
      );

      expect(callCount, equals(1));
      expect(savedPaths.length, equals(1));
      final file = File(savedPaths.first);
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, contains('April 2026'));
      expect(content, contains('Acme Power'));

      dir.deleteSync(recursive: true);
    });

    test('does not write file when saveFn returns null (user cancelled)', () async {
      final dir = Directory.systemTemp.createTempSync('export_test_cancel');
      bool writeAttempted = false;

      Future<String?> cancelSave(String suggestedName) async => null;

      final bill = Bill(
        billId: 'b2',
        type: BillType.water,
        company: 'City Water',
        amount: 50.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.unpaid,
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [bill],
        [],
        [],
        desktopSaveFn: cancelSave,
      );

      // No files should be written to temp dir
      expect(dir.listSync().isEmpty, isTrue);
      dir.deleteSync(recursive: true);
    });
  });

  group('ExportUtils desktop PDF', () {
    test('writes PDF file to the path returned by saveFn', () async {
      final dir = Directory.systemTemp.createTempSync('export_pdf_test');
      String? savedPath;

      Future<String?> fakeSave(String suggestedName) async {
        savedPath = '${dir.path}/$suggestedName';
        return savedPath;
      }

      final bill = Bill(
        billId: 'b3',
        type: BillType.internet,
        company: 'FastNet',
        amount: 75.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        amountPaid: 75.0,
      );

      await ExportUtils.exportBillsToPDF(
        [bill],
        [],
        [],
        desktopSaveFn: fakeSave,
      );

      expect(savedPath, isNotNull);
      final file = File(savedPath!);
      expect(file.existsSync(), isTrue);
      // PDF magic bytes: %PDF
      final bytes = file.readAsBytesSync();
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));

      dir.deleteSync(recursive: true);
    });

    test('does not write PDF when saveFn returns null', () async {
      final dir = Directory.systemTemp.createTempSync('export_pdf_cancel');

      Future<String?> cancelSave(String suggestedName) async => null;

      final bill = Bill(
        billId: 'b4',
        type: BillType.gas,
        company: 'GasCo',
        amount: 30.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.unpaid,
        amountPaid: null,
      );

      await ExportUtils.exportBillsToPDF(
        [bill],
        [],
        [],
        desktopSaveFn: cancelSave,
      );

      expect(dir.listSync().isEmpty, isTrue);
      dir.deleteSync(recursive: true);
    });
  });
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
flutter test test/utils/export_utils_test.dart
```

Expected: FAIL — `exportBillsToCSV` and `exportBillsToPDF` don't have a `desktopSaveFn` parameter yet.

---

### Task 4: Implement desktop save logic in `ExportUtils`

- [ ] **Step 1: Update the imports in `lib/utils/export_utils.dart`**

Replace the existing import block at the top of the file with:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/summary_item.dart';
```

- [ ] **Step 2: Add the `_isDesktop` getter to the `ExportUtils` class**

Add this private getter directly below the `_thresholdNote` constant (after line 28 in the original file):

```dart
  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
```

- [ ] **Step 3: Replace `exportBillsToCSV` with the updated signature and body**

Replace the entire `exportBillsToCSV` method (lines 100–165 in the original) with:

```dart
  /// Generates one CSV file per calendar month.
  ///
  /// On desktop, calls [desktopSaveFn] to get a save path and writes with
  /// dart:io.  On mobile/web, shares via [SharePlus].
  ///
  /// [desktopSaveFn] receives the suggested filename and returns the chosen
  /// path, or null if the user cancelled.  Defaults to [getSaveLocation].
  static Future<void> exportBillsToCSV(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments, {
    Future<String?> Function(String suggestedName)? desktopSaveFn,
  }) async {
    final grouped = _groupByMonth(bills);
    final index = _buildIndex(payments);

    if (_isDesktop) {
      final saveFn = desktopSaveFn ?? _defaultCsvSave;
      for (final entry in grouped.entries) {
        final month = entry.key;
        final monthBills = entry.value;
        final csv = _buildCsvContent(month, monthBills, index);
        final safeName = month.replaceAll(' ', '_');
        final path = await saveFn('bills_$safeName.csv');
        if (path == null) continue;
        await File(path).writeAsBytes(utf8.encode(csv));
      }
      return;
    }

    // Mobile / web: share via system share sheet
    final List<XFile> files = [];
    for (final entry in grouped.entries) {
      final month = entry.key;
      final monthBills = entry.value;
      final csv = _buildCsvContent(month, monthBills, index);
      final safeName = month.replaceAll(' ', '_');
      files.add(XFile.fromData(
        utf8.encode(csv),
        name: 'bills_$safeName.csv',
        mimeType: 'text/csv',
      ));
    }
    if (files.isNotEmpty) {
      await SharePlus.instance.share(
        ShareParams(files: files, subject: 'Bills Export by Month'),
      );
    }
  }
```

- [ ] **Step 4: Extract `_buildCsvContent` helper**

Add this private static method after `exportBillsToCSV` (before `exportBillsToPDF`):

```dart
  /// Builds the CSV string for a single month.
  static String _buildCsvContent(
    String month,
    List<Bill> monthBills,
    Map<String, List<Payment>> index,
  ) {
    final total = monthBills.fold(0.0, (s, b) => s + b.amount);
    final paid = monthBills.fold(0.0, (s, b) => s + _paidAmount(b));
    final unpaid = total - paid;
    final contributions = _rentorPayments(monthBills, index);

    final buffer = StringBuffer();

    buffer.writeln('Month,Total,Paid,Unpaid');
    buffer.writeln(
        '${_csv(month)},${total.toStringAsFixed(2)},${paid.toStringAsFixed(2)},${unpaid.toStringAsFixed(2)}');
    buffer.writeln();

    buffer.writeln('Bill Type,Company,Due Date,Amount,Paid,Unpaid,Status');
    for (final bill in monthBills) {
      final billPaid = _paidAmount(bill);
      final billUnpaid = bill.amount - billPaid;
      buffer.writeln([
        _csv(bill.type.name),
        _csv(bill.company),
        _dateFmt.format(bill.dueDate),
        bill.amount.toStringAsFixed(2),
        billPaid.toStringAsFixed(2),
        billUnpaid.toStringAsFixed(2),
        _csv(bill.status.name),
      ].join(','));
    }

    if (contributions.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Rentor Contributions');
      buffer.writeln('Rentor,Amount Paid');
      for (final e in contributions.entries) {
        buffer.writeln('${_csv(e.key)},${e.value.toStringAsFixed(2)}');
      }
    }

    buffer.writeln();
    buffer.writeln(_csv(_thresholdNote));

    return buffer.toString();
  }

  /// Default desktop save function — opens the native Save As dialog.
  static Future<String?> _defaultCsvSave(String suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    return location?.path;
  }
```

- [ ] **Step 5: Replace `exportBillsToPDF` with the updated signature and body**

Replace the entire `exportBillsToPDF` method with:

```dart
  /// Generates a multi-page PDF (one page per calendar month).
  ///
  /// On desktop, calls [desktopSaveFn] to get a save path and writes with
  /// dart:io.  On mobile/web, shares via [SharePlus].
  static Future<void> exportBillsToPDF(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments, {
    Future<String?> Function(String suggestedName)? desktopSaveFn,
  }) async {
    final grouped = _groupByMonth(bills);
    final index = _buildIndex(payments);
    final doc = pw.Document();

    for (final entry in grouped.entries) {
      final month = entry.key;
      final monthBills = entry.value;
      final total = monthBills.fold(0.0, (s, b) => s + b.amount);
      final paid = monthBills.fold(0.0, (s, b) => s + _paidAmount(b));
      final unpaid = total - paid;
      final contributions = _rentorPayments(monthBills, index);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(month,
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding:
                      const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      _pdfStat('Total', total, PdfColors.black),
                      _pdfStat('Paid', paid, PdfColors.green700),
                      _pdfStat('Unpaid', unpaid,
                          unpaid > 0.005 ? PdfColors.red700 : PdfColors.grey600),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Table(
                  border:
                      pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(2),
                    1: const pw.FlexColumnWidth(2.5),
                    2: const pw.FlexColumnWidth(1.8),
                    3: const pw.FlexColumnWidth(1.5),
                    4: const pw.FlexColumnWidth(1.5),
                    5: const pw.FlexColumnWidth(1.5),
                    6: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    pw.TableRow(
                      decoration:
                          const pw.BoxDecoration(color: PdfColors.blueGrey800),
                      children: [
                        _pdfCell('Bill Type', header: true),
                        _pdfCell('Company', header: true),
                        _pdfCell('Due Date', header: true),
                        _pdfCell('Amount', header: true),
                        _pdfCell('Paid', header: true),
                        _pdfCell('Unpaid', header: true),
                        _pdfCell('Status', header: true),
                      ],
                    ),
                    ...monthBills.asMap().entries.map((e) {
                      final bill = e.value;
                      final billPaid = _paidAmount(bill);
                      final billUnpaid = bill.amount - billPaid;
                      final isEven = e.key.isEven;
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: isEven ? PdfColors.white : PdfColors.grey50,
                        ),
                        children: [
                          _pdfCell(bill.type.name),
                          _pdfCell(bill.company),
                          _pdfCell(_dateFmt.format(bill.dueDate)),
                          _pdfCell('\$${bill.amount.toStringAsFixed(2)}'),
                          _pdfCell('\$${billPaid.toStringAsFixed(2)}',
                              color: PdfColors.green700),
                          _pdfCell('\$${billUnpaid.toStringAsFixed(2)}',
                              color:
                                  billUnpaid > 0.005 ? PdfColors.red700 : null),
                          _pdfCell(bill.status.name),
                        ],
                      );
                    }),
                  ],
                ),
                if (contributions.isNotEmpty) ...[
                  pw.SizedBox(height: 16),
                  pw.Text('Rentor Contributions',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 6),
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey400, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                            color: PdfColors.blueGrey800),
                        children: [
                          _pdfCell('Rentor', header: true),
                          _pdfCell('Amount Paid', header: true),
                        ],
                      ),
                      ...contributions.entries.map((e) => pw.TableRow(
                            children: [
                              _pdfCell(e.key),
                              _pdfCell('\$${e.value.toStringAsFixed(2)}',
                                  color: PdfColors.green700),
                            ],
                          )),
                    ],
                  ),
                ],
                pw.Spacer(),
                pw.Divider(color: PdfColors.grey400),
                pw.Text(
                  '* $_thresholdNote',
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Generated ${_dateFmt.format(DateTime.now())}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }

    final pdfBytes = await doc.save();

    if (_isDesktop) {
      final saveFn = desktopSaveFn ?? _defaultPdfSave;
      final path = await saveFn('bills_export.pdf');
      if (path == null) return;
      await File(path).writeAsBytes(pdfBytes);
      return;
    }

    await SharePlus.instance.share(ShareParams(
      files: [
        XFile.fromData(pdfBytes,
            name: 'bills_export.pdf', mimeType: 'application/pdf')
      ],
      subject: 'Bills Export',
    ));
  }

  /// Default desktop save function — opens the native Save As dialog for PDF.
  static Future<String?> _defaultPdfSave(String suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'PDF', extensions: ['pdf']),
      ],
    );
    return location?.path;
  }
```

---

### Task 5: Run the tests and confirm they pass, then commit

- [ ] **Step 1: Run the export tests**

```bash
flutter test test/utils/export_utils_test.dart
```

Expected: All 4 tests PASS.

- [ ] **Step 2: Run the full test suite to confirm no regressions**

```bash
flutter test
```

Expected: All tests pass.

- [ ] **Step 3: Commit implementation and tests together**

```bash
git add lib/utils/export_utils.dart test/utils/export_utils_test.dart
git commit -m "feat: use Save As dialog for CSV/PDF export on desktop platforms

Adds unit tests covering save and cancel paths for both CSV and PDF."
```

---

### Task 6: Open the PR

- [ ] **Step 1: Push the branch**

```bash
git push -u origin fix/windows-desktop-export
```

- [ ] **Step 2: Open the PR**

```bash
gh pr create \
  --title "fix: use Save As dialog for CSV/PDF export on desktop" \
  --body "$(cat <<'EOF'
## Summary
- Replaces `share_plus` file sharing with a native Save As dialog (`file_selector`) on Windows, macOS, and Linux
- Mobile and web export behaviour is unchanged
- Extracts `_buildCsvContent` helper to reduce duplication between desktop and share-sheet paths
- Adds 4 unit tests covering save and cancel for both CSV and PDF

## Test plan
- [ ] Run `flutter test test/utils/export_utils_test.dart` — all 4 tests pass
- [ ] Run the app on Windows, click Export CSV → Save As dialog opens, file saved correctly
- [ ] Run the app on Windows, click Export PDF → Save As dialog opens, file saved correctly
- [ ] Cancel the Save As dialog — no error shown, no file written
- [ ] Run the app on Android/iOS — share sheet still works as before

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```