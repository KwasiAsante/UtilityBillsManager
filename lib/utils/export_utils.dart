import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/summary_item.dart';

/// Utility class for exporting bill data to CSV or PDF files.
///
/// Both [exportBillsToCSV] and [exportBillsToPDF] group bills by calendar
/// month, compute totals / paid / unpaid breakdowns, include per-rentor
/// payment contributions, and share the resulting files via [SharePlus.instance.share()].
///
/// All methods are static; no instance state is needed.
class ExportUtils {
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _monthFmt = DateFormat('MMMM yyyy');

  static const _thresholdNote =
      'Note: Electric/Gas/Water bills with ≤30% unpaid (or within \$1.00 of that threshold), '
      'and Internet bills with ≤50% unpaid (or within \$1.00 of that threshold), '
      'are considered paid. Amounts in this export reflect actual values.';

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
      ..sort((a, b) => b.value.first.dueDate.compareTo(a.value.first.dueDate));
    return Map.fromEntries(sorted);
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

  // ── CSV Export ───────────────────────────────────────────────────────────────

  /// Generates one CSV file per calendar month and shares them via the system
  /// share sheet.  Each file contains a month-summary row, a per-bill table,
  /// and an optional rentor-contributions section.
  static Future<void> exportBillsToCSV(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments,
  ) async {
    final grouped = _groupByMonth(bills);
    final index = _buildIndex(payments);
    final List<XFile> files = [];

    for (final entry in grouped.entries) {
      final month = entry.key;
      final monthBills = entry.value;
      final total = monthBills.fold(0.0, (s, b) => s + b.amount);
      final paid = monthBills.fold(0.0, (s, b) => s + _paidAmount(b));
      final unpaid = total - paid;
      final contributions = _rentorPayments(monthBills, index);

      final buffer = StringBuffer();

      // Month summary
      buffer.writeln('Month,Total,Paid,Unpaid');
      buffer.writeln('${_csv(month)},${total.toStringAsFixed(2)},${paid.toStringAsFixed(2)},${unpaid.toStringAsFixed(2)}');
      buffer.writeln();

      // Bills table
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

      // Rentor contributions
      if (contributions.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('Rentor Contributions');
        buffer.writeln('Rentor,Amount Paid');
        for (final e in contributions.entries) {
          buffer.writeln('${_csv(e.key)},${e.value.toStringAsFixed(2)}');
        }
      }

      // Threshold note
      buffer.writeln();
      buffer.writeln(_csv(_thresholdNote));

      final safeName = month.replaceAll(' ', '_');
      files.add(XFile.fromData(
        utf8.encode(buffer.toString()),
        name: 'bills_$safeName.csv',
        mimeType: 'text/csv',
      ));
    }

    if (files.isNotEmpty) {
      await SharePlus.instance.share(ShareParams(files: files, subject: 'Bills Export by Month'));
    }
  }

  // ── PDF Export ───────────────────────────────────────────────────────────────

  /// Generates a multi-page PDF (one page per calendar month) and shares it via
  /// the system share sheet.  Each page includes a month-totals summary, a
  /// styled bill table, optional rentor-contributions table, and a footer note
  /// explaining the "paid" threshold logic.
  static Future<void> exportBillsToPDF(
    List<Bill> bills,
    List<Rentor> rentors,
    List<Payment> payments,
  ) async {
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
                // Heading
                pw.Text(month,
                    style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),

                // Month totals
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
                      decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
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
                              color: billUnpaid > 0.005 ? PdfColors.red700 : null),
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
                    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(2),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
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
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Generated ${_dateFmt.format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                ),
              ],
            );
          },
        ),
      );
    }

    await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(await doc.save(), name: 'bills_export.pdf', mimeType: 'application/pdf')],
        subject: 'Bills Export'),
    );
  }

  // ── PDF widget helpers ───────────────────────────────────────────────────────

  /// Builds a single table cell widget for the PDF output.  Header cells are
  /// bold white; body cells use the optional [color] override.
  static pw.Widget _pdfCell(String text, {bool header = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
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
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(
          '\$${amount.toStringAsFixed(2)}',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: color),
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
