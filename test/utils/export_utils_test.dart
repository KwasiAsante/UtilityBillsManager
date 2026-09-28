import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
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
        notes: 'April bill',
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

      Future<String?> cancelSave(String suggestedName) async => null;

      final bill = Bill(
        billId: 'b2',
        type: BillType.water,
        company: 'City Water',
        amount: 50.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.unpaid,
        notes: 'Water bill',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [bill],
        [],
        [],
        desktopSaveFn: cancelSave,
      );

      expect(dir.listSync().isEmpty, isTrue);
      dir.deleteSync(recursive: true);
    });

    test('only writes files for months in selectedMonths', () async {
      final dir = Directory.systemTemp.createTempSync('export_test_selected');
      final savedNames = <String>[];

      Future<String?> fakeSave(String suggestedName) async {
        savedNames.add(suggestedName);
        return '${dir.path}/$suggestedName';
      }

      final aprilBill = Bill(
        billId: 'b5',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: 'April bill',
        amountPaid: 100.0,
      );
      final mayBill = Bill(
        billId: 'b6',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 5, 1),
        status: PaymentStatus.paid,
        notes: 'May bill',
        amountPaid: 100.0,
      );

      await ExportUtils.exportBillsToCSV(
        [aprilBill, mayBill],
        [],
        [],
        selectedMonths: ['April 2026'],
        desktopSaveFn: fakeSave,
      );

      expect(savedNames, equals(['bills_April_2026.csv']));
      dir.deleteSync(recursive: true);
    });

    test('combineAsWorkbook writes a single xlsx with a Summary sheet '
        'and one sheet per selected month', () async {
      final dir = Directory.systemTemp.createTempSync('export_test_workbook');
      final savedNames = <String>[];
      String? savedPath;

      Future<String?> fakeSave(String suggestedName) async {
        savedNames.add(suggestedName);
        savedPath = '${dir.path}/$suggestedName';
        return savedPath;
      }

      final aprilBill = Bill(
        billId: 'b9',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: 'April bill',
        amountPaid: 100.0,
      );
      final mayBill = Bill(
        billId: 'b10',
        type: BillType.water,
        company: 'City Water',
        amount: 40.0,
        dueDate: DateTime(2026, 5, 1),
        status: PaymentStatus.unpaid,
        notes: 'May bill',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [aprilBill, mayBill],
        [],
        [],
        selectedMonths: ['April 2026', 'May 2026'],
        combineAsWorkbook: true,
        desktopSaveFn: fakeSave,
      );

      expect(savedNames, equals(['bills_export.xlsx']));
      final bytes = File(savedPath!).readAsBytesSync();

      expect(XlsxGridReader.listSheets(bytes),
          containsAll(['Summary', 'April 2026', 'May 2026']));

      final sheets = XlsxGridReader.readAll(bytes);
      String sheetText(String name) => sheets
          .firstWhere((s) => s.name == name)
          .rows
          .expand((row) => row)
          .join('|');

      expect(sheetText('Summary'), contains('April 2026'));
      expect(sheetText('Summary'), contains('May 2026'));
      expect(sheetText('April 2026'), contains('Acme Power'));
      expect(sheetText('May 2026'), contains('City Water'));

      dir.deleteSync(recursive: true);
    });

    test('Summary sheet groups months under a "YYYY Total" row per year',
        () async {
      final dir =
          Directory.systemTemp.createTempSync('export_test_year_summary');
      String? savedPath;
      Future<String?> fakeSave(String name) async {
        savedPath = '${dir.path}/$name';
        return savedPath;
      }

      final janBill = Bill(
        billId: 'b13',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 1, 1),
        status: PaymentStatus.paid,
        notes: '',
        amountPaid: 100.0,
      );
      final decBill = Bill(
        billId: 'b14',
        type: BillType.water,
        company: 'City Water',
        amount: 50.0,
        dueDate: DateTime(2025, 12, 1),
        status: PaymentStatus.unpaid,
        notes: '',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [janBill, decBill],
        [],
        [],
        selectedMonths: ['January 2026', 'December 2025'],
        combineAsWorkbook: true,
        desktopSaveFn: fakeSave,
      );

      final bytes = File(savedPath!).readAsBytesSync();
      final summaryRows = XlsxGridReader.readAll(bytes)
          .firstWhere((s) => s.name == 'Summary')
          .rows;
      final labels = summaryRows.map((r) => r.isNotEmpty ? r.first : '').toList();

      final janIndex = labels.indexOf('January 2026');
      final total2026Index = labels.indexOf('2026 Total');
      final decIndex = labels.indexOf('December 2025');
      final total2025Index = labels.indexOf('2025 Total');

      expect(janIndex, greaterThanOrEqualTo(0));
      expect(total2026Index, greaterThan(janIndex));
      expect(decIndex, greaterThan(total2026Index));
      expect(total2025Index, greaterThan(decIndex));

      final total2026Row = summaryRows[total2026Index];
      expect(double.parse(total2026Row[1]), closeTo(100.0, 0.001));
      expect(double.parse(total2026Row[2]), closeTo(100.0, 0.001));
      expect(double.parse(total2026Row[3]), closeTo(0.0, 0.001));

      final total2025Row = summaryRows[total2025Index];
      expect(double.parse(total2025Row[1]), closeTo(50.0, 0.001));
      expect(double.parse(total2025Row[2]), closeTo(0.0, 0.001));
      expect(double.parse(total2025Row[3]), closeTo(50.0, 0.001));

      dir.deleteSync(recursive: true);
    });

    test('workbook cells carry real styling (header fill, borders, '
        'colored amounts) rather than plain unstyled values', () async {
      final dir = Directory.systemTemp.createTempSync('export_test_styles');
      String? savedPath;
      Future<String?> fakeSave(String name) async {
        savedPath = '${dir.path}/$name';
        return savedPath;
      }

      final bill = Bill(
        billId: 'b17',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: '',
        amountPaid: 100.0,
      );

      await ExportUtils.exportBillsToCSV(
        [bill],
        [],
        [],
        combineAsWorkbook: true,
        desktopSaveFn: fakeSave,
      );

      final bytes = File(savedPath!).readAsBytesSync();
      final package = OpcPackage.openBytes(bytes);
      final stylesXml = package.getPart('/xl/styles.xml')!.readText();

      // Header background, green "Paid" text, and at least one real border
      // definition should all appear as actual style entries, not just be
      // silently accepted and dropped.
      expect(stylesXml, contains('37474F')); // header fill
      expect(stylesXml, contains('388E3C')); // paid (green) text
      expect(stylesXml, contains('<border'));

      dir.deleteSync(recursive: true);
    });
  });

  group('ExportUtils mobile/web CSV', () {
    test('shares every selected month as one batched call, not one call per '
        'month (navigator.share() only works once per user gesture)',
        () async {
      final shareCalls = <List<XFile>>[];
      Future<void> fakeShare(
          List<XFile> files, List<String> names, String subject) async {
        shareCalls.add(files);
      }

      final aprilBill = Bill(
        billId: 'b11',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: 'April bill',
        amountPaid: 100.0,
      );
      final mayBill = Bill(
        billId: 'b12',
        type: BillType.water,
        company: 'City Water',
        amount: 40.0,
        dueDate: DateTime(2026, 5, 1),
        status: PaymentStatus.unpaid,
        notes: 'May bill',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [aprilBill, mayBill],
        [],
        [],
        selectedMonths: ['April 2026', 'May 2026'],
        isDesktopOverride: false,
        shareFn: fakeShare,
      );

      expect(shareCalls.length, equals(1));
      final files = shareCalls.single;
      expect(files.length, equals(2));
      final contents = await Future.wait(files.map((f) => f.readAsString()));
      // _groupByMonth sorts most-recent-first.
      expect(contents[0], contains('City Water'));
      expect(contents[1], contains('Acme Power'));
    });

    test('passes real, unique per-month names via fileNameOverrides '
        '(XFile.fromData.name is dropped by cross_file on native platforms, '
        'and share_plus\'s Android staging step collapses same-named files '
        'into one, silently corrupting every file but the last)', () async {
      final shareCalls = <List<String>>[];
      Future<void> fakeShare(
          List<XFile> files, List<String> names, String subject) async {
        shareCalls.add(names);
      }

      final aprilBill = Bill(
        billId: 'b18',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: '',
        amountPaid: 100.0,
      );
      final mayBill = Bill(
        billId: 'b19',
        type: BillType.water,
        company: 'City Water',
        amount: 40.0,
        dueDate: DateTime(2026, 5, 1),
        status: PaymentStatus.unpaid,
        notes: '',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToCSV(
        [aprilBill, mayBill],
        [],
        [],
        selectedMonths: ['April 2026', 'May 2026'],
        isDesktopOverride: false,
        shareFn: fakeShare,
      );

      final names = shareCalls.single;
      expect(names.toSet().length, equals(names.length)); // all unique
      expect(names, equals(['bills_May_2026.csv', 'bills_April_2026.csv']));
    });

    test('workbook share also passes a real fileNameOverrides name, not '
        'relying on XFile.fromData.name (dropped on native platforms)',
        () async {
      List<String>? capturedNames;
      Future<void> fakeShare(
          List<XFile> files, List<String> names, String subject) async {
        capturedNames = names;
      }

      final bill = Bill(
        billId: 'b20',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: '',
        amountPaid: 100.0,
      );

      await ExportUtils.exportBillsToCSV(
        [bill],
        [],
        [],
        combineAsWorkbook: true,
        isDesktopOverride: false,
        shareFn: fakeShare,
      );

      expect(capturedNames, equals(['bills_export.xlsx']));
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
        notes: 'Internet bill',
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
        notes: 'Gas bill',
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

    test('produces one summary page plus one page per selected month', () async {
      final dir = Directory.systemTemp.createTempSync('export_pdf_selected');
      String? savedPath;

      Future<String?> fakeSave(String suggestedName) async {
        savedPath = '${dir.path}/$suggestedName';
        return savedPath;
      }

      final aprilBill = Bill(
        billId: 'b7',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 4, 1),
        status: PaymentStatus.paid,
        notes: 'April bill',
        amountPaid: 100.0,
      );
      final mayBill = Bill(
        billId: 'b8',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 5, 1),
        status: PaymentStatus.paid,
        notes: 'May bill',
        amountPaid: 100.0,
      );

      await ExportUtils.exportBillsToPDF(
        [aprilBill, mayBill],
        [],
        [],
        selectedMonths: ['April 2026'],
        desktopSaveFn: fakeSave,
      );

      final bytes = File(savedPath!).readAsBytesSync();
      final pageCount = RegExp(r'/Type\s*/Page(?!s)')
          .allMatches(String.fromCharCodes(bytes))
          .length;
      // 1 summary page + 1 page for the selected month (May excluded).
      expect(pageCount, equals(2));
      dir.deleteSync(recursive: true);
    });

    test('summary page renders successfully for months spanning two years',
        () async {
      final dir =
          Directory.systemTemp.createTempSync('export_pdf_two_years');
      String? savedPath;

      Future<String?> fakeSave(String suggestedName) async {
        savedPath = '${dir.path}/$suggestedName';
        return savedPath;
      }

      final janBill = Bill(
        billId: 'b15',
        type: BillType.electric,
        company: 'Acme Power',
        amount: 100.0,
        dueDate: DateTime(2026, 1, 1),
        status: PaymentStatus.paid,
        notes: '',
        amountPaid: 100.0,
      );
      final decBill = Bill(
        billId: 'b16',
        type: BillType.water,
        company: 'City Water',
        amount: 50.0,
        dueDate: DateTime(2025, 12, 1),
        status: PaymentStatus.unpaid,
        notes: '',
        amountPaid: null,
      );

      await ExportUtils.exportBillsToPDF(
        [janBill, decBill],
        [],
        [],
        selectedMonths: ['January 2026', 'December 2025'],
        desktopSaveFn: fakeSave,
      );

      final bytes = File(savedPath!).readAsBytesSync();
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
      final pageCount = RegExp(r'/Type\s*/Page(?!s)')
          .allMatches(String.fromCharCodes(bytes))
          .length;
      // 1 summary page + 1 page per month, regardless of year span.
      expect(pageCount, equals(3));
      dir.deleteSync(recursive: true);
    });
  });
}
