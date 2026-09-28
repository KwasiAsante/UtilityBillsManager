import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/summary_item.dart';

/// A single row in a Summary sheet/page: either a month's Total/Paid/Unpaid,
/// or (when [isYearTotal]) the rolled-up total for all months of one year.
class _SummaryRow {
  final String label;
  final double total;
  final double paid;
  final double unpaid;
  final bool isYearTotal;

  const _SummaryRow(this.label, this.total, this.paid, this.unpaid,
      {this.isYearTotal = false});
}

/// Utility class for exporting bill data to CSV or PDF files.
///
/// On desktop (Windows, macOS, Linux), exports use a native Save As dialog
/// via [file_selector].  On mobile and web, files are shared via the system
/// share sheet.
///
/// All methods are static; no instance state is needed.
class ExportUtils {
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _monthFmt = DateFormat('MMMM yyyy');

  static const _thresholdNote =
      'Note: Electric/Gas/Water bills with ≤30% unpaid (or within \$1.00 of that threshold), '
      'and Internet bills with ≤50% unpaid (or within \$1.00 of that threshold), '
      'are considered paid. Amounts in this export reflect actual values.';

  /// True when running natively on a desktop OS (not web, not mobile).
  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  /// Returns the actual amount paid toward [bill] based on its [PaymentStatus].
  static double _paidAmount(Bill bill) {
    if (bill.status == PaymentStatus.paid) {
      return bill.amountPaid ?? bill.amount;
    } else if (bill.status == PaymentStatus.partial) {
      return bill.amountPaid ?? 0.0;
    }
    return 0.0;
  }

  /// Groups [bills] by "MMMM yyyy" month label and sorts the resulting map
  /// with the most recent month first.
  static Map<String, List<Bill>> _groupByMonth(List<Bill> bills) {
    final Map<String, List<Bill>> grouped = {};
    for (var bill in bills) {
      final month = _monthFmt.format(bill.dueDate);
      grouped.putIfAbsent(month, () => []).add(bill);
    }
    final sorted = grouped.entries.toList()
      ..sort((a, b) {
        final dateA = _monthFmt.parse(a.key);
        final dateB = _monthFmt.parse(b.key);
        return dateB.compareTo(dateA);
      });
    return Map.fromEntries(sorted);
  }

  /// Restricts [grouped] to just the months in [selectedMonths], preserving
  /// [grouped]'s order. Returns [grouped] unchanged when [selectedMonths] is
  /// null (export everything, the pre-selection default behavior).
  static Map<String, List<Bill>> _filterMonths(
    Map<String, List<Bill>> grouped,
    List<String>? selectedMonths,
  ) {
    if (selectedMonths == null) return grouped;
    final allowed = selectedMonths.toSet();
    return Map.fromEntries(
      grouped.entries.where((e) => allowed.contains(e.key)),
    );
  }

  /// Builds Summary rows: one row per month in [grouped], with a "YYYY
  /// Total" row inserted after the last month of each year. Relies on
  /// [grouped]'s entries already being sorted most-recent-first, so every
  /// year's months are contiguous.
  static List<_SummaryRow> _buildSummaryRows(Map<String, List<Bill>> grouped) {
    final rows = <_SummaryRow>[];
    int? currentYear;
    var yearTotal = 0.0, yearPaid = 0.0, yearUnpaid = 0.0;

    void flushYear() {
      if (currentYear == null) return;
      rows.add(_SummaryRow(
          '$currentYear Total', yearTotal, yearPaid, yearUnpaid,
          isYearTotal: true));
    }

    for (final entry in grouped.entries) {
      final year = _monthFmt.parse(entry.key).year;
      if (currentYear != null && year != currentYear) {
        flushYear();
        yearTotal = 0;
        yearPaid = 0;
        yearUnpaid = 0;
      }
      currentYear = year;

      final total = entry.value.fold(0.0, (s, b) => s + b.amount);
      final paid = entry.value.fold(0.0, (s, b) => s + _paidAmount(b));
      rows.add(_SummaryRow(entry.key, total, paid, total - paid));

      yearTotal += total;
      yearPaid += paid;
      yearUnpaid += total - paid;
    }
    flushYear();

    return rows;
  }

  /// Returns rentor name → total amount paid for payments covering any bill in [bills].
  /// Each payment is counted once via [seen].
  static Map<String, double> _rentorPayments(
    List<Bill> bills,
    Map<String, List<Payment>> billPaymentIndex,
  ) {
    final result = <String, double>{};
    final seen = <String>{};
    for (final bill in bills) {
      for (final payment in (billPaymentIndex[bill.billId] ?? [])) {
        if (payment.rentor != null && !seen.contains(payment.paymentId)) {
          seen.add(payment.paymentId!);
          result[payment.rentor!.name] =
              (result[payment.rentor!.name] ?? 0) + payment.amountPaid;
        }
      }
    }
    return result;
  }

  /// Builds billId → payments index from a payment list.
  static Map<String, List<Payment>> _buildIndex(List<Payment> payments) {
    final index = <String, List<Payment>>{};
    for (final payment in payments) {
      for (final billId in (payment.billIds ?? [])) {
        index.putIfAbsent(billId, () => []).add(payment);
      }
    }
    return index;
  }

  /// Wraps [value] in double-quotes if it contains commas, quotes, or newlines
  /// (RFC 4180 CSV escaping).
  static String _csv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

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

  // ── CSV Export ───────────────────────────────────────────────────────────────

  /// Exports [bills], restricted to [selectedMonths] when given (defaults to
  /// every month present).
  ///
  /// When [combineAsWorkbook] is true, generates a single .xlsx workbook
  /// with a "Summary" sheet plus one sheet per month. Otherwise, generates
  /// one .csv file per month.
  ///
  /// On desktop, calls [desktopSaveFn] to get a save path and writes with
  /// dart:io.  On mobile/web, calls [shareFn] once with every file attached
  /// via the system share sheet — a second `navigator.share()` call per
  /// click is not viable on web (see [shareFn]'s doc comment).
  ///
  /// [desktopSaveFn] receives the suggested filename and returns the chosen
  /// path, or null if the user cancelled.  Defaults to [_defaultCsvSave] /
  /// [_defaultXlsxSave]. [isDesktopOverride] and [shareFn] exist for testing.
  static Future<void> exportBillsToCSV(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments, {
    List<String>? selectedMonths,
    bool combineAsWorkbook = false,
    Future<String?> Function(String suggestedName)? desktopSaveFn,
    Future<void> Function(List<XFile> files, List<String> names, String subject)?
        shareFn,
    bool? isDesktopOverride,
  }) async {
    final grouped = _filterMonths(_groupByMonth(bills), selectedMonths);
    final index = _buildIndex(payments);
    final isDesktop = isDesktopOverride ?? _isDesktop;
    final share = shareFn ?? _defaultShare;

    if (combineAsWorkbook) {
      final bytes = _buildWorkbook(grouped, index);
      if (isDesktop) {
        final saveFn = desktopSaveFn ?? _defaultXlsxSave;
        final path = await saveFn('bills_export.xlsx');
        if (path == null) return;
        await File(path).writeAsBytes(bytes);
        return;
      }
      const name = 'bills_export.xlsx';
      await share(
        [
          XFile.fromData(
            bytes,
            name: name,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          )
        ],
        [name],
        'Bills Export',
      );
      return;
    }

    if (isDesktop) {
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

    // Mobile / web: attach every selected month's CSV to a single share
    // call. navigator.share() consumes the page's user-activation the
    // instant it is invoked, before any UI appears (see step 7 of
    // https://w3c.github.io/web-share/#share-method) — so a second call in
    // the same click handler is guaranteed a NotAllowedError with no way to
    // recover it. One call with every file attached is the only pattern
    // that can show a real share dialog for more than one file.
    //
    // [names] is passed to [share] as fileNameOverrides — XFile.fromData's
    // `name` parameter is silently ignored by cross_file on every native
    // platform (Android/iOS/desktop), and without an explicit override,
    // share_plus falls back to a machine-generated name that can collide
    // across files in the same call. On Android specifically, share_plus's
    // native staging step then copies every file into one shared cache
    // folder keyed only by that (colliding) filename, so every same-named
    // file after the first silently overwrites the one before it — leaving
    // every shared file but the last with the wrong content once the
    // receiving app actually reads the bytes.
    final files = <XFile>[];
    final names = <String>[];
    for (final entry in grouped.entries) {
      final month = entry.key;
      final monthBills = entry.value;
      final csv = _buildCsvContent(month, monthBills, index);
      final safeName = month.replaceAll(' ', '_');
      final name = 'bills_$safeName.csv';
      files.add(XFile.fromData(utf8.encode(csv), name: name, mimeType: 'text/csv'));
      names.add(name);
    }
    if (files.isNotEmpty) {
      await share(files, names, 'Bills Export by Month');
    }
  }

  /// Default share function — shares all [files] via one system share-sheet
  /// call, passing [names] as `fileNameOverrides` so every file gets its
  /// real, unique name regardless of platform (see the call-site comment
  /// above for why this matters on Android).
  static Future<void> _defaultShare(
      List<XFile> files, List<String> names, String subject) {
    return SharePlus.instance.share(
      ShareParams(files: files, fileNameOverrides: names, subject: subject),
    );
  }

  /// Default desktop save function — opens the native Save As dialog for CSV.
  static Future<String?> _defaultCsvSave(String suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    return location?.path;
  }

  /// Default desktop save function — opens the native Save As dialog for XLSX.
  static Future<String?> _defaultXlsxSave(String suggestedName) async {
    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    return location?.path;
  }

  // Colors mirror the PDF export's palette (Material blueGrey800/grey50/
  // grey200/green700/red700) so both outputs read as one visual system.
  static const _xlsxHeaderBg = '37474F';
  static const _xlsxHeaderText = 'FFFFFF';
  static const _xlsxBandGrey = 'FAFAFA';
  static const _xlsxYearTotalBg = 'EEEEEE';
  static const _xlsxGreenText = '388E3C';
  static const _xlsxRedText = 'D32F2F';
  static const _xlsxNoteGrey = '757575';
  static const _xlsxAmountFmt = '#,##0.00';

  /// Builds a single workbook: a "Summary" sheet (Month/Total/Paid/Unpaid per
  /// month, with a "YYYY Total" row after each year's months) followed by
  /// one sheet per month with the same content as [_buildCsvContent], in
  /// the same order as [grouped]. Header rows, cell borders, alternating
  /// row banding, and colored Paid/Unpaid amounts match the PDF export.
  static Uint8List _buildWorkbook(
    Map<String, List<Bill>> grouped,
    Map<String, List<Payment>> index,
  ) {
    final builder = XlsxWorkbookBuilder();
    final headerStyle = builder.style(
      bold: true,
      color: _xlsxHeaderText,
      fillRgb: _xlsxHeaderBg,
      horizontal: 'center',
      border: true,
    );
    int cellStyle({
      String? fill,
      String? color,
      bool numeric = false,
      bool bold = false,
    }) {
      return builder.style(
        bold: bold,
        color: color ?? '000000',
        fillRgb: fill,
        border: true,
        horizontal: numeric ? 'right' : 'left',
        numFmt: numeric ? _xlsxAmountFmt : null,
      );
    }

    final summary = builder.addSheet('Summary');
    const summaryHeaders = ['Month', 'Total', 'Paid', 'Unpaid'];
    for (var c = 0; c < summaryHeaders.length; c++) {
      summary.setCell(0, c, summaryHeaders[c], style: headerStyle);
    }
    var summaryRow = 1;
    var monthIndex = 0;
    for (final row in _buildSummaryRows(grouped)) {
      final fill = row.isYearTotal
          ? _xlsxYearTotalBg
          : (monthIndex.isOdd ? _xlsxBandGrey : null);
      summary.setCell(summaryRow, 0, row.label,
          style: cellStyle(fill: fill, bold: row.isYearTotal));
      summary.setCell(summaryRow, 1, row.total,
          style:
              cellStyle(fill: fill, bold: row.isYearTotal, numeric: true));
      summary.setCell(summaryRow, 2, row.paid,
          style: cellStyle(
              fill: fill,
              bold: row.isYearTotal,
              numeric: true,
              color: _xlsxGreenText));
      summary.setCell(summaryRow, 3, row.unpaid,
          style: cellStyle(
              fill: fill,
              bold: row.isYearTotal,
              numeric: true,
              color: row.unpaid > 0.005 ? _xlsxRedText : null));
      summaryRow++;
      if (!row.isYearTotal) monthIndex++;
    }
    summary.colWidth(0, 22);
    for (var c = 1; c <= 3; c++) {
      summary.colWidth(c, 14);
    }

    for (final entry in grouped.entries) {
      final monthBills = entry.value;
      final sheet = builder.addSheet(entry.key);
      final contributions = _rentorPayments(monthBills, index);

      const billHeaders = [
        'Bill Type',
        'Company',
        'Due Date',
        'Amount',
        'Paid',
        'Unpaid',
        'Status',
      ];
      for (var c = 0; c < billHeaders.length; c++) {
        sheet.setCell(0, c, billHeaders[c], style: headerStyle);
      }

      var r = 1;
      for (final (i, bill) in monthBills.indexed) {
        final billPaid = _paidAmount(bill);
        final billUnpaid = bill.amount - billPaid;
        final fill = i.isOdd ? _xlsxBandGrey : null;
        sheet.setCell(r, 0, bill.type.name, style: cellStyle(fill: fill));
        sheet.setCell(r, 1, bill.company, style: cellStyle(fill: fill));
        sheet.setCell(r, 2, _dateFmt.format(bill.dueDate),
            style: cellStyle(fill: fill));
        sheet.setCell(r, 3, bill.amount,
            style: cellStyle(fill: fill, numeric: true));
        sheet.setCell(r, 4, billPaid,
            style: cellStyle(
                fill: fill, numeric: true, color: _xlsxGreenText));
        sheet.setCell(r, 5, billUnpaid,
            style: cellStyle(
                fill: fill,
                numeric: true,
                color: billUnpaid > 0.005 ? _xlsxRedText : null));
        sheet.setCell(r, 6, bill.status.name, style: cellStyle(fill: fill));
        r++;
      }

      if (contributions.isNotEmpty) {
        r++;
        sheet.setCell(r, 0, 'Rentor Contributions',
            style: builder.style(bold: true));
        r++;
        sheet.setCell(r, 0, 'Rentor', style: headerStyle);
        sheet.setCell(r, 1, 'Amount Paid', style: headerStyle);
        r++;
        for (final (i, e) in contributions.entries.indexed) {
          final fill = i.isOdd ? _xlsxBandGrey : null;
          sheet.setCell(r, 0, e.key, style: cellStyle(fill: fill));
          sheet.setCell(r, 1, e.value,
              style: cellStyle(
                  fill: fill, numeric: true, color: _xlsxGreenText));
          r++;
        }
      }

      r++;
      sheet.setCell(r, 0, _thresholdNote,
          style: builder.style(size: 9, color: _xlsxNoteGrey));

      sheet.colWidth(0, 14);
      sheet.colWidth(1, 24);
      for (var c = 2; c <= 6; c++) {
        sheet.colWidth(c, 12);
      }
    }

    return builder.build();
  }

  // ── PDF Export ───────────────────────────────────────────────────────────────

  /// Generates a single multi-page PDF: a summary page listing
  /// Total/Paid/Unpaid per month, followed by one page per month, restricted
  /// to [selectedMonths] when given (defaults to every month present).
  ///
  /// On desktop, calls [desktopSaveFn] to get a save path and writes with
  /// dart:io.  On mobile/web, shares via [SharePlus].
  static Future<void> exportBillsToPDF(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments, {
    List<String>? selectedMonths,
    Future<String?> Function(String suggestedName)? desktopSaveFn,
  }) async {
    final grouped = _filterMonths(_groupByMonth(bills), selectedMonths);
    final index = _buildIndex(payments);
    final doc = pw.Document();

    if (grouped.isNotEmpty) {
      doc.addPage(_buildSummaryPage(grouped));
    }

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
                // Heading
                pw.Text(month,
                    style: pw.TextStyle(
                        fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),

                // Month totals
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

                // Bills table
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

                // Rentor contributions table
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

                // Footer
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

  /// Builds the summary page listing Total/Paid/Unpaid for every month in
  /// [grouped], in the same (most-recent-first) order as the per-month pages
  /// that follow it, with a bolded "YYYY Total" row after each year's months.
  static pw.Page _buildSummaryPage(Map<String, List<Bill>> grouped) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Summary',
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(1.5),
                3: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration:
                      const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  children: [
                    _pdfCell('Month', header: true),
                    _pdfCell('Total', header: true),
                    _pdfCell('Paid', header: true),
                    _pdfCell('Unpaid', header: true),
                  ],
                ),
                ..._buildSummaryRows(grouped).map((row) {
                  return pw.TableRow(
                    decoration: row.isYearTotal
                        ? const pw.BoxDecoration(color: PdfColors.grey200)
                        : null,
                    children: [
                      _pdfCell(row.label, bold: row.isYearTotal),
                      _pdfCell('\$${row.total.toStringAsFixed(2)}',
                          bold: row.isYearTotal),
                      _pdfCell('\$${row.paid.toStringAsFixed(2)}',
                          bold: row.isYearTotal, color: PdfColors.green700),
                      _pdfCell('\$${row.unpaid.toStringAsFixed(2)}',
                          bold: row.isYearTotal,
                          color: row.unpaid > 0.005 ? PdfColors.red700 : null),
                    ],
                  );
                }),
              ],
            ),
          ],
        );
      },
    );
  }

  // ── PDF widget helpers ───────────────────────────────────────────────────────

  /// Builds a single table cell widget for the PDF output.  Header cells are
  /// bold white; body cells use the optional [color] override.
  static pw.Widget _pdfCell(String text,
      {bool header = false, bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight:
              (header || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.white : color,
        ),
      ),
    );
  }

  /// Builds a two-line stat widget (label + formatted dollar amount) for the
  /// month-summary row at the top of each PDF page.
  static pw.Widget _pdfStat(String label, double amount, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label,
            style:
                const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(
          '\$${amount.toStringAsFixed(2)}',
          style: pw.TextStyle(
              fontSize: 13, fontWeight: pw.FontWeight.bold, color: color),
        ),
      ],
    );
  }

  // ── Legacy stubs ─────────────────────────────────────────────────────────────

  static Future<void> exportToCSV(
    BuildContext context,
    List<SummaryItem> data,
    String filename,
  ) async {}

  static Future<void> exportToPDF(
    BuildContext context,
    List<SummaryItem> data,
    String filename,
  ) async {}
}
