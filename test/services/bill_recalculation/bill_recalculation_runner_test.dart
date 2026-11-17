import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/bill_recalculation/bill_recalculation_runner.dart';
import 'package:utility_bills_manager/utils/bills/bill_recalculation.dart';

void main() {
  group('BillRecalculationRunner', () {
    final changedCrown = BillRecalculation(
      bill: Bill(
        billId: 'crown',
        company: 'Co',
        type: BillType.gas,
        amount: 44.43,
        dueDate: DateTime(2025, 1, 1),
        status: PaymentStatus.partial,
        notes: null,
        amountPaid: 16,
      ),
      amountPaid: 32,
      status: PaymentStatus.paid,
    );

    final changedEnbridge = BillRecalculation(
      bill: Bill(
        billId: 'enbridge',
        company: 'Co',
        type: BillType.gas,
        amount: 193.00,
        dueDate: DateTime(2025, 1, 27),
        status: PaymentStatus.partial,
        notes: null,
        amountPaid: 81,
      ),
      amountPaid: 64,
      status: PaymentStatus.partial,
    );

    final unchangedBell = BillRecalculation(
      bill: Bill(
        billId: 'bell',
        company: 'Co',
        type: BillType.internet,
        amount: 188.71,
        dueDate: DateTime(2025, 1, 23),
        status: PaymentStatus.paid,
        notes: null,
        amountPaid: 94,
      ),
      amountPaid: 94,
      status: PaymentStatus.paid,
    );

    test('writes only changed bills', () async {
      final written = <Bill>[];
      final runner = BillRecalculationRunner(updateBill: (b) async {
        written.add(b);
        return Result.success(data: b);
      });
      final summary = await runner.apply([changedCrown, unchangedBell]);
      expect(written.map((b) => b.billId), ['crown']);
      expect(written.single.amountPaid, 32);
      expect(summary.updated, 1);
      expect(summary.failed, 0);
    });

    test('keeps going after a failed save', () async {
      final runner = BillRecalculationRunner(updateBill: (b) async =>
          b.billId == 'crown'
              ? Result.error(errorMessage: 'boom')
              : Result.success(data: b));
      final summary = await runner.apply([changedCrown, changedEnbridge]);
      expect(summary.updated, 1);
      expect(summary.failed, 1);
      expect(summary.errors, ['boom']);
    });

    test('nothing to do', () async {
      final summary = await BillRecalculationRunner(
              updateBill: (b) async => fail('should not write'))
          .apply([unchangedBell]);
      expect([summary.updated, summary.failed], [0, 0]);
    });
  });
}
