# Rentor Bill Summary Messaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Send Bill Summary" button to the rentor edit screen that generates a formatted bill summary message, lets the user edit it, and shares it via the system share sheet.

**Architecture:** A pure `BillSummaryService` singleton handles all business logic (filtering eligible bills, calculating owed amounts, formatting the message). Two new screens — `BillSelectionScreen` and `MessagePreviewScreen` — handle the two-step wizard UI. `AddEditRentorScreen` is modified to load eligible bills and show the button when editing an existing rentor.

**Tech Stack:** Flutter, Dart, `share_plus ^13.0.0` (already integrated), `BillsRepository` (already integrated in `AddEditRentorScreen`)

---

## File Map

| File | Action |
|---|---|
| `lib/services/bill_summary/bill_summary_service.dart` | Create — all business logic |
| `lib/screens/bill_summary/bill_selection_screen.dart` | Create — Step 1 of wizard |
| `lib/screens/bill_summary/message_preview_screen.dart` | Create — Step 2 of wizard |
| `lib/screens/rentors/add_edit_rentor_screen.dart` | Modify — add button and loading logic |
| `test/services/bill_summary/bill_summary_service_test.dart` | Create — unit tests |

---

### Task 1: Create the feature branch

- [ ] **Step 1: Create and check out the branch**

```bash
git checkout -b feat/rentor-bill-summary-messaging
```

- [ ] **Step 2: Verify**

```bash
git branch --show-current
```
Expected: `feat/rentor-bill-summary-messaging`

---

### Task 2: `BillSummaryService` (TDD)

**Files:**
- Create: `test/services/bill_summary/bill_summary_service_test.dart`
- Create: `lib/services/bill_summary/bill_summary_service.dart`

**Background:** `Rentor.calculateOwedAmount(rentor, bill)` is a static method that computes `(bill.amount * percentage / 100).round().toDouble()`. `BillType.name` returns human-readable capitalized strings ("Electric", "Gas", "Water", "Internet", "Credit Card", etc.) via a Dart extension in `lib/data/models/bill.dart`. `PaymentStatus` has four values: `paid`, `unpaid`, `partial`, `unknown`.

**Water bill note:** Water bills arrive mid-month but are due early the following month. `getEligibleBills` includes water bills where `dueDate` is in the next calendar month (not just the current month) so landlords can notify rentors as soon as the water bill arrives.

- [ ] **Step 1: Write the test file**

Create `test/services/bill_summary/bill_summary_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/services/bill_summary/bill_summary_service.dart';

void main() {
  late BillSummaryService service;

  setUp(() {
    service = BillSummaryService();
  });

  Bill makeBill({
    required BillType type,
    required double amount,
    required DateTime dueDate,
    PaymentStatus status = PaymentStatus.unpaid,
  }) =>
      Bill(
        company: 'Test Co',
        type: type,
        amount: amount,
        dueDate: dueDate,
        status: status,
        notes: null,
      );

  Rentor makeRentor({
    String name = 'Alex Johnson',
    double defaultPercentage = 50.0,
    List<BillType> excluded = const [],
  }) =>
      Rentor(
        name: name,
        defaultPercentage: defaultPercentage,
        billPercentages: const {},
        excludedBillTypes: excluded,
      );

  group('getEligibleBills', () {
    test('excludes paid bills', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
        status: PaymentStatus.paid,
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('excludes bills outside current month (non-water)', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 3, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('excludes bills for excluded bill types', () {
      final rentor = makeRentor(excluded: [BillType.electric]);
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('includes unpaid bill due this month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, hasLength(1));
    });

    test('includes partial bill due this month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 4, 15),
        status: PaymentStatus.partial,
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, hasLength(1));
    });

    test('includes water bill due next month', () {
      final rentor = makeRentor();
      final waterBill = makeBill(
        type: BillType.water,
        amount: 80.0,
        dueDate: DateTime(2026, 5, 1), // due May, current month is April
      );
      final result = service.getEligibleBills(rentor, [waterBill],
          now: DateTime(2026, 4, 15));
      expect(result, hasLength(1));
    });

    test('excludes non-water bill due next month', () {
      final rentor = makeRentor();
      final bill = makeBill(
        type: BillType.electric,
        amount: 100.0,
        dueDate: DateTime(2026, 5, 15), // due May, current month is April
      );
      final result = service.getEligibleBills(rentor, [bill],
          now: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('handles December → January year boundary for water bill', () {
      final rentor = makeRentor();
      final waterBill = makeBill(
        type: BillType.water,
        amount: 80.0,
        dueDate: DateTime(2027, 1, 1), // due January 2027, current month is December 2026
      );
      final result = service.getEligibleBills(rentor, [waterBill],
          now: DateTime(2026, 12, 15));
      expect(result, hasLength(1));
    });
  });

  group('isSettledForMonth', () {
    test('returns true for empty list', () {
      expect(service.isSettledForMonth([]), isTrue);
    });

    test('returns false for non-empty list', () {
      final bill = makeBill(
          type: BillType.electric,
          amount: 100.0,
          dueDate: DateTime(2026, 4, 15));
      expect(service.isSettledForMonth([bill]), isFalse);
    });
  });

  group('generateMessage — greeting', () {
    test('Good morning when hour < 12', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg, startsWith('Good morning'));
    });

    test('Good afternoon when hour is 12–16', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 14));
      expect(msg, startsWith('Good afternoon'));
    });

    test('Good evening when hour >= 17', () {
      final rentor = makeRentor();
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 19));
      expect(msg, startsWith('Good evening'));
    });
  });

  group('generateMessage — format', () {
    test('uses first name only', () {
      final rentor = makeRentor(name: 'Alex Johnson');
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg, contains('Alex'));
      expect(msg, isNot(contains('Johnson')));
    });

    test('single regular bill', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final bill = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      // (90 * 50/100).round() = 45
      final msg = service.generateMessage(rentor, [bill],
          now: DateTime(2026, 4, 15, 8));
      expect(msg,
          equals('Good morning Alex, the electric bill is \$45.00 due April 15th.'));
    });

    test('two regular bills joined with "and", no comma', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 10));
      final gas = makeBill(
          type: BillType.gas, amount: 60.0, dueDate: DateTime(2026, 4, 20));
      // avg day = (10+20)/2 = 15 → April 15th
      // electric: 45.00, gas: 30.00
      final msg = service.generateMessage(rentor, [electric, gas],
          now: DateTime(2026, 4, 1, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00 and gas bill is \$30.00 due April 15th.'));
    });

    test('three regular bills: Oxford comma before last', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final gas = makeBill(
          type: BillType.gas, amount: 60.0, dueDate: DateTime(2026, 4, 15));
      final internet = makeBill(
          type: BillType.internet,
          amount: 50.0,
          dueDate: DateTime(2026, 4, 15));
      // electric: 45.00, gas: 30.00, internet: 25.00
      final msg = service.generateMessage(rentor, [electric, gas, internet],
          now: DateTime(2026, 4, 1, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00, gas bill is \$30.00, and internet bill is \$25.00 due April 15th.'));
    });

    test('water bill only', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final water = makeBill(
          type: BillType.water, amount: 80.0, dueDate: DateTime(2026, 5, 1));
      // (80 * 0.5).round() = 40
      final msg = service.generateMessage(rentor, [water],
          now: DateTime(2026, 4, 15, 8));
      expect(msg,
          equals('Good morning Alex, the water bill is \$40.00 due May 1st.'));
    });

    test('regular bills + water bill', () {
      final rentor = makeRentor(defaultPercentage: 50.0);
      final electric = makeBill(
          type: BillType.electric,
          amount: 90.0,
          dueDate: DateTime(2026, 4, 15));
      final water = makeBill(
          type: BillType.water, amount: 80.0, dueDate: DateTime(2026, 5, 1));
      final msg = service.generateMessage(rentor, [electric, water],
          now: DateTime(2026, 4, 15, 8));
      expect(
          msg,
          equals(
              'Good morning Alex, the electric bill is \$45.00 due April 15th. The water bill is \$40.00 due May 1st.'));
    });
  });

  group('generateMessage — ordinal date suffixes', () {
    Bill billDue(int day) => makeBill(
        type: BillType.electric,
        amount: 90.0,
        dueDate: DateTime(2026, 4, day));
    final rentor = makeRentor(defaultPercentage: 50.0);

    test('1st', () {
      expect(
          service.generateMessage(rentor, [billDue(1)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 1st'));
    });
    test('2nd', () {
      expect(
          service.generateMessage(rentor, [billDue(2)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 2nd'));
    });
    test('3rd', () {
      expect(
          service.generateMessage(rentor, [billDue(3)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 3rd'));
    });
    test('11th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(11)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 11th'));
    });
    test('12th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(12)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 12th'));
    });
    test('13th (special case)', () {
      expect(
          service.generateMessage(rentor, [billDue(13)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 13th'));
    });
    test('21st', () {
      expect(
          service.generateMessage(rentor, [billDue(21)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 21st'));
    });
    test('22nd', () {
      expect(
          service.generateMessage(rentor, [billDue(22)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 22nd'));
    });
    test('23rd', () {
      expect(
          service.generateMessage(rentor, [billDue(23)],
              now: DateTime(2026, 4, 1, 8)),
          contains('April 23rd'));
    });
  });
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
flutter test test/services/bill_summary/bill_summary_service_test.dart
```
Expected: FAIL — `bill_summary_service.dart` does not exist.

- [ ] **Step 3: Create `lib/services/bill_summary/bill_summary_service.dart`**

```dart
import '../../data/models/bill.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';

/// Singleton service for rentor bill summary messaging.
///
/// All methods are pure (no I/O) — callers supply the bills list and an
/// optional [DateTime] for the current time so the service is fully testable
/// without mocking.
class BillSummaryService {
  static final BillSummaryService _instance = BillSummaryService._internal();

  factory BillSummaryService() => _instance;

  BillSummaryService._internal();

  /// Returns the subset of [allBills] that are eligible for [rentor]'s
  /// summary this month (as determined by [now], defaulting to [DateTime.now]).
  ///
  /// A bill is eligible when ALL of the following are true:
  /// 1. [bill.status] is not [PaymentStatus.paid].
  /// 2. [bill.type] is not in [rentor.excludedBillTypes].
  /// 3. [bill.dueDate] falls in the current calendar month — OR, for
  ///    [BillType.water] only, in the following month (water bills arrive
  ///    mid-month but are due early next month).
  List<Bill> getEligibleBills(
    Rentor rentor,
    List<Bill> allBills, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final nextMonth = ref.month == 12 ? 1 : ref.month + 1;
    final nextYear = ref.month == 12 ? ref.year + 1 : ref.year;

    return allBills.where((bill) {
      if (bill.status == PaymentStatus.paid) return false;
      if (rentor.excludedBillTypes.contains(bill.type)) return false;

      final dueThisMonth =
          bill.dueDate.year == ref.year && bill.dueDate.month == ref.month;
      final dueNextMonthWater = bill.type == BillType.water &&
          bill.dueDate.year == nextYear &&
          bill.dueDate.month == nextMonth;

      return dueThisMonth || dueNextMonthWater;
    }).toList();
  }

  /// Returns `true` when [eligibleBills] is empty — the rentor owes nothing
  /// this month.
  bool isSettledForMonth(List<Bill> eligibleBills) => eligibleBills.isEmpty;

  /// Generates a bill summary message for [rentor] from [selectedBills].
  ///
  /// [now] defaults to [DateTime.now] and is used to determine the greeting
  /// and the average due-date month for regular bills. Pass it explicitly in
  /// tests to get deterministic output.
  ///
  /// Format:
  /// - Regular bills only:
  ///   "{greeting} {firstName}, the electric bill is $X and gas bill is $Y due April 15th."
  /// - With water:
  ///   "{greeting} {firstName}, the electric bill is $X due April 15th. The water bill is $Y due May 1st."
  /// - Water only:
  ///   "{greeting} {firstName}, the water bill is $Y due May 1st."
  String generateMessage(
    Rentor rentor,
    List<Bill> selectedBills, {
    DateTime? now,
  }) {
    final ref = now ?? DateTime.now();
    final greeting = _greeting(ref.hour);
    final firstName = rentor.name.split(' ').first;

    final waterBills =
        selectedBills.where((b) => b.type == BillType.water).toList();
    final regularBills =
        selectedBills.where((b) => b.type != BillType.water).toList();

    // Sum owed amount per bill type for regular bills.
    final Map<BillType, double> regularOwed = {};
    for (final bill in regularBills) {
      final owed = Rentor.calculateOwedAmount(rentor, bill);
      regularOwed.update(bill.type, (v) => v + owed, ifAbsent: () => owed);
    }

    String message = '$greeting $firstName';
    final hasRegular = regularOwed.isNotEmpty;

    if (hasRegular) {
      final avgDay =
          (regularBills.map((b) => b.dueDate.day).reduce((a, b) => a + b) /
                  regularBills.length)
              .round();
      final avgDate = DateTime(ref.year, ref.month, avgDay);
      final billList = _formatBillList(regularOwed.entries.toList());
      message += ', $billList due ${_formatDate(avgDate)}.';
    }

    if (waterBills.isNotEmpty) {
      final waterOwed = waterBills.fold(
          0.0, (sum, b) => sum + Rentor.calculateOwedAmount(rentor, b));
      final waterDate = waterBills.first.dueDate;
      final waterAmount = '\$${waterOwed.toStringAsFixed(2)}';
      final waterDue = _formatDate(waterDate);
      if (hasRegular) {
        message += ' The water bill is $waterAmount due $waterDue.';
      } else {
        message += ', the water bill is $waterAmount due $waterDue.';
      }
    }

    return message;
  }

  String _greeting(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Formats [date] as "Month Dayth" — e.g. "April 15th", "May 1st".
  String _formatDate(DateTime date) {
    final day = date.day;
    return '${_monthName(date.month)} $day${_ordinalSuffix(day)}';
  }

  String _ordinalSuffix(int day) {
    // 11–13 are exceptions: always "th"
    if (day >= 11 && day <= 13) return 'th';
    switch (day % 10) {
      case 1:
        return 'st';
      case 2:
        return 'nd';
      case 3:
        return 'rd';
      default:
        return 'th';
    }
  }

  String _monthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }

  /// Formats a list of (BillType → owed amount) entries as a human-readable
  /// bill list:
  /// - 1 item:  "the electric bill is $45.00"
  /// - 2 items: "the electric bill is $45.00 and gas bill is $30.00"
  /// - 3+items: "the electric bill is $45.00, gas bill is $30.00, and internet bill is $25.00"
  ///
  /// [BillType.name] returns capitalized names ("Electric", "Gas", etc.).
  /// They are lowercased here for message text.
  String _formatBillList(List<MapEntry<BillType, double>> entries) {
    if (entries.isEmpty) return '';

    String formatEntry(MapEntry<BillType, double> e, bool isFirst) {
      final typeName = e.key.name.toLowerCase();
      final amount = e.value.toStringAsFixed(2);
      return '${isFirst ? 'the ' : ''}$typeName bill is \$$amount';
    }

    if (entries.length == 1) return formatEntry(entries[0], true);
    if (entries.length == 2) {
      return '${formatEntry(entries[0], true)} and ${formatEntry(entries[1], false)}';
    }

    final parts = [formatEntry(entries[0], true)];
    for (int i = 1; i < entries.length - 1; i++) {
      parts.add(formatEntry(entries[i], false));
    }
    parts.add('and ${formatEntry(entries[entries.length - 1], false)}');
    return parts.join(', ');
  }
}
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
flutter test test/services/bill_summary/bill_summary_service_test.dart
```
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/bill_summary/bill_summary_service.dart \
        test/services/bill_summary/bill_summary_service_test.dart
git commit -m "feat: add BillSummaryService with eligible bill filtering and message generation"
```

---

### Task 3: `BillSelectionScreen`

**Files:**
- Create: `lib/screens/bill_summary/bill_selection_screen.dart`

**Background:** `BillType.name` (from the extension in `lib/data/models/bill.dart`) returns human-readable capitalized strings: "Electric", "Gas", "Water", "Internet", "Credit Card", etc. `Rentor.calculateOwedAmount(rentor, bill)` returns the rentor's share rounded to the nearest whole dollar. `DateFormat` is from `package:intl/intl.dart`.

- [ ] **Step 1: Create `lib/screens/bill_summary/bill_selection_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/bill.dart';
import '../../data/models/rentor.dart';
import '../../services/bill_summary/bill_summary_service.dart';
import 'message_preview_screen.dart';

/// Step 1 of the bill summary wizard.
///
/// Shows a checkbox list of [eligibleBills] for [rentor]. All bills are
/// pre-checked. Tapping "Generate Message" calls [BillSummaryService] and
/// pushes [MessagePreviewScreen].
class BillSelectionScreen extends StatefulWidget {
  final Rentor rentor;
  final List<Bill> eligibleBills;

  const BillSelectionScreen({
    super.key,
    required this.rentor,
    required this.eligibleBills,
  });

  @override
  State<BillSelectionScreen> createState() => _BillSelectionScreenState();
}

class _BillSelectionScreenState extends State<BillSelectionScreen> {
  late Set<String> _selectedIds;

  final _dateFormat = DateFormat('MMM d');

  @override
  void initState() {
    super.initState();
    // Pre-select all eligible bills.
    _selectedIds = widget.eligibleBills.map((b) => b.billId).toSet();
  }

  void _toggleBill(String billId, bool? selected) {
    setState(() {
      if (selected == true) {
        _selectedIds.add(billId);
      } else {
        _selectedIds.remove(billId);
      }
    });
  }

  void _generateMessage() {
    final selectedBills = widget.eligibleBills
        .where((b) => _selectedIds.contains(b.billId))
        .toList();
    final message = BillSummaryService()
        .generateMessage(widget.rentor, selectedBills);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessagePreviewScreen(initialMessage: message),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Bills')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: widget.eligibleBills.length,
              itemBuilder: (context, index) {
                final bill = widget.eligibleBills[index];
                final isSelected = _selectedIds.contains(bill.billId);
                final owedAmount =
                    Rentor.calculateOwedAmount(widget.rentor, bill);
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) => _toggleBill(bill.billId, value),
                  title: Text('${bill.type.name} — ${bill.companyName}'),
                  subtitle: Text(
                    'Due: ${_dateFormat.format(bill.dueDate)} · '
                    'Total: \$${bill.amount.toStringAsFixed(2)} · '
                    'Your share: \$${owedAmount.toStringAsFixed(2)}',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: FilledButton(
              onPressed: _selectedIds.isEmpty ? null : _generateMessage,
              child: const Text('Generate Message'),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/screens/bill_summary/bill_selection_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/bill_summary/bill_selection_screen.dart
git commit -m "feat: add BillSelectionScreen for bill summary wizard step 1"
```

---

### Task 4: `MessagePreviewScreen`

**Files:**
- Create: `lib/screens/bill_summary/message_preview_screen.dart`

**Background:** `SharePlus.instance.share(ShareParams(text: ...))` from `package:share_plus/share_plus.dart` opens the system share sheet. It returns a `ShareResult` with a `.status` field. `ShareResultStatus.unavailable` means sharing is not supported on this platform — in that case, fall back to `Clipboard.setData` from `package:flutter/services.dart`.

- [ ] **Step 1: Create `lib/screens/bill_summary/message_preview_screen.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Step 2 of the bill summary wizard.
///
/// Shows [initialMessage] in an editable [TextField]. Tapping "Share" opens
/// the system share sheet via [share_plus]. If sharing is unavailable on the
/// current platform, the message is copied to the clipboard instead.
class MessagePreviewScreen extends StatefulWidget {
  final String initialMessage;

  const MessagePreviewScreen({super.key, required this.initialMessage});

  @override
  State<MessagePreviewScreen> createState() => _MessagePreviewScreenState();
}

class _MessagePreviewScreenState extends State<MessagePreviewScreen> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialMessage);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final text = _controller.text;
    final result =
        await SharePlus.instance.share(ShareParams(text: text));
    if (result.status == ShareResultStatus.unavailable && mounted) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bill Summary Message')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Edit your message here…',
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Share'),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify**

```bash
flutter analyze lib/screens/bill_summary/message_preview_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/bill_summary/message_preview_screen.dart
git commit -m "feat: add MessagePreviewScreen for bill summary wizard step 2"
```

---

### Task 5: Modify `AddEditRentorScreen`

**Files:**
- Modify: `lib/screens/rentors/add_edit_rentor_screen.dart`

**Background:** `AddEditRentorScreen` receives an optional `Rentor? rentor`. `widget.rentor != null` means edit mode. The screen already holds `_billsRepository` (a `BillsRepository` instance) which has `bills` (a `List<Bill>`) and a `Future<void> reload()` method. The button should only appear in edit mode and only after eligible bills are loaded. It should look greyed-out when the rentor is settled but still show a snackbar on tap (achieved by wrapping a `null`-`onPressed` button with `GestureDetector`).

- [ ] **Step 1: Read the file**

Read `lib/screens/rentors/add_edit_rentor_screen.dart` in full before editing.

- [ ] **Step 2: Add imports**

Find:
```dart
import '../../data/repositories/bills_repository.dart';
```

Replace with:
```dart
import '../../data/repositories/bills_repository.dart';
import '../../services/bill_summary/bill_summary_service.dart';
import '../bill_summary/bill_selection_screen.dart';
```

- [ ] **Step 3: Add state variables**

Find:
```dart
  final _amountOwedController = TextEditingController();
```

Replace with:
```dart
  final _amountOwedController = TextEditingController();
  final BillSummaryService _billSummaryService = BillSummaryService();
  List<Bill>? _eligibleBills; // null while loading; empty list means settled
```

- [ ] **Step 4: Schedule loading in `initState`**

Find:
```dart
    } else {
      _selectedBillTypes = [];
      _excludedBillTypes = [];
    }
  }
```

Replace with:
```dart
    } else {
      _selectedBillTypes = [];
      _excludedBillTypes = [];
    }

    if (widget.rentor != null) {
      // Defer until after first frame so the widget tree is built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadEligibleBills());
    }
  }
```

- [ ] **Step 5: Add `_loadEligibleBills` and `_navigateToBillSelection` methods**

Find:
```dart
  Future<void> _saveRentor() async {
```

Insert the following block immediately before that line:

```dart
  Future<void> _loadEligibleBills() async {
    if (_billsRepository.bills.isEmpty) {
      await _billsRepository.reload();
    }
    if (mounted) {
      setState(() {
        _eligibleBills = _billSummaryService.getEligibleBills(
          widget.rentor!,
          _billsRepository.bills,
        );
      });
    }
  }

  void _navigateToBillSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BillSelectionScreen(
          rentor: widget.rentor!,
          eligibleBills: _eligibleBills!,
        ),
      ),
    );
  }

```

- [ ] **Step 6: Add the "Send Bill Summary" button in `build`**

Find:
```dart
                const SizedBox(height: 25),
                FilledButton(
                  onPressed: _saveRentor,
                  child: const Text('Save Rentor'),
                ),
```

Replace with:
```dart
                const SizedBox(height: 25),
                if (isEditing && _eligibleBills != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: GestureDetector(
                      // When settled (button disabled), GestureDetector still
                      // catches the tap and shows an informative snackbar.
                      onTap: _eligibleBills!.isEmpty
                          ? () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${widget.rentor!.name} is settled for this month'),
                                ),
                              )
                          : null,
                      child: ElevatedButton.icon(
                        onPressed: _eligibleBills!.isEmpty
                            ? null
                            : _navigateToBillSelection,
                        icon: const Icon(Icons.message),
                        label: const Text('Send Bill Summary'),
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _saveRentor,
                  child: const Text('Save Rentor'),
                ),
```

- [ ] **Step 7: Verify**

```bash
flutter analyze lib/screens/rentors/add_edit_rentor_screen.dart
```
Expected: no errors.

- [ ] **Step 8: Commit**

```bash
git add lib/screens/rentors/add_edit_rentor_screen.dart
git commit -m "feat: add Send Bill Summary button to AddEditRentorScreen"
```

---

### Task 6: Full test suite and PR

- [ ] **Step 1: Run the full test suite**

```bash
flutter test
```
Expected: All tests pass (no regressions).

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/rentor-bill-summary-messaging
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create \
  --title "feat: rentor bill summary messaging" \
  --body "$(cat <<'EOF'
## Summary
- Adds `BillSummaryService` — pure singleton with `getEligibleBills`, `isSettledForMonth`, and `generateMessage`
- `getEligibleBills` filters by current month due date (+ next month for water bills), excludes paid bills and each rentor's excluded bill types
- `generateMessage` uses device time for greeting, rentor first name, per-type owed amounts via `Rentor.calculateOwedAmount`, average due date for regular bills, separate sentence for water bills with its own due date
- Adds `BillSelectionScreen` (checkbox list, pre-selects all, "Generate Message" button)
- Adds `MessagePreviewScreen` (editable TextField, share via `share_plus`, clipboard fallback when sharing unavailable)
- Adds "Send Bill Summary" button to `AddEditRentorScreen` (edit mode only): greyed out with snackbar when settled, navigates to wizard when unpaid bills exist

## Test plan
- [ ] Run `flutter test` — all tests pass
- [ ] Open a rentor with unpaid bills for the current month → "Send Bill Summary" button appears and is enabled
- [ ] Tap button → BillSelectionScreen shows correct bills pre-checked
- [ ] Deselect all → "Generate Message" button is disabled
- [ ] Select bills, tap "Generate Message" → MessagePreviewScreen shows correct message
- [ ] Edit message, tap "Share" → system share sheet opens
- [ ] Open a rentor with no unpaid bills → button is greyed out; tap shows snackbar

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
