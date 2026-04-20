import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });
}
