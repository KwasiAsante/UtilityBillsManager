import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';
import 'package:utility_bills_manager/helpers/rentors/rentors_helper.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';

/// Serves a canned response for `GET /rentor/<id>` and records every request.
class _FakeRentorServer extends http.BaseClient {
  final Rentor? stored;
  final int getStatus;
  final List<http.Request> requests = [];

  _FakeRentorServer({this.stored, this.getStatus = 200});

  List<http.Request> get puts =>
      requests.where((r) => r.method == 'PUT').toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    requests.add(req);
    if (req.method == 'GET') {
      final body = getStatus == 200 && stored != null ? jsonEncode(stored) : '';
      return http.StreamedResponse(Stream.value(utf8.encode(body)), getStatus);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('')), 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // AppLogger reads the device id from SharedPreferences when it logs.
    SharedPreferences.setMockInitialValues({});
    // No APP_MODE configured -> client mode, so RentorsHelper talks to the
    // (fake) API instead of SQLite.
    dotenv.testLoad();
  });

  tearDown(ApiService.resetHttpClient);

  group('updateRentorPaymentInfo', () {
    const rentorId = 'rentor-1';

    Rentor rentorWith({DateTime? startDate, DateTime? lastPaymentDate}) =>
        Rentor(
          rentorId: rentorId,
          name: 'Sam',
          defaultPercentage: 30,
          billPercentages: const {},
          startDate: startDate,
          lastPaymentDate: lastPaymentDate,
        );

    Payment paymentOn(DateTime date) =>
        Payment(rentorId: rentorId, amountPaid: 10, paymentDate: date);

    test(
      'writes the freshly read rentor, not the stale passed-in copy',
      () async {
        // The cached copy predates a start-date correction made on the rentor.
        final stale = rentorWith(startDate: null);
        final fresh = rentorWith(startDate: DateTime(2026, 3, 5));
        final server = _FakeRentorServer(stored: fresh);
        ApiService.overrideHttpClient(server);

        await RentorsHelper().updateRentorPaymentInfo(
          paymentOn(DateTime(2026, 11, 10)),
          rentor: stale,
        );

        expect(server.puts, hasLength(1));
        final sent =
            jsonDecode(server.puts.single.body) as Map<String, dynamic>;
        expect(sent['rentorId'], rentorId);
        expect(sent['startDate'], '2026-03-05');
        expect(sent['lastPaymentDate'], '2026-11-10');
        // The stale object is only used for its id.
        expect(stale.lastPaymentDate, isNull);
      },
    );

    test('reads by rentorId when no rentor is passed', () async {
      final server = _FakeRentorServer(
        stored: rentorWith(startDate: DateTime(2026, 3, 5)),
      );
      ApiService.overrideHttpClient(server);

      await RentorsHelper().updateRentorPaymentInfo(
        paymentOn(DateTime(2026, 11, 10)),
        rentorId: rentorId,
      );

      final sent = jsonDecode(server.puts.single.body) as Map<String, dynamic>;
      expect(sent['startDate'], '2026-03-05');
      expect(sent['lastPaymentDate'], '2026-11-10');
    });

    test('keeps a newer existing lastPaymentDate', () async {
      final server = _FakeRentorServer(
        stored: rentorWith(lastPaymentDate: DateTime(2026, 12, 1)),
      );
      ApiService.overrideHttpClient(server);

      await RentorsHelper().updateRentorPaymentInfo(
        paymentOn(DateTime(2026, 11, 10)),
        rentor: rentorWith(),
      );

      final sent = jsonDecode(server.puts.single.body) as Map<String, dynamic>;
      expect(sent['lastPaymentDate'], '2026-12-01');
    });

    test('does not write when the read fails', () async {
      final server = _FakeRentorServer(getStatus: 500);
      ApiService.overrideHttpClient(server);

      await RentorsHelper().updateRentorPaymentInfo(
        paymentOn(DateTime(2026, 11, 10)),
        rentor: rentorWith(),
      );

      expect(server.puts, isEmpty);
    });

    test('does not write when the rentor is not found', () async {
      final server = _FakeRentorServer(getStatus: 404);
      ApiService.overrideHttpClient(server);

      await RentorsHelper().updateRentorPaymentInfo(
        paymentOn(DateTime(2026, 11, 10)),
        rentorId: rentorId,
      );

      expect(server.puts, isEmpty);
    });

    test('does nothing without a rentor or rentorId', () async {
      final server = _FakeRentorServer();
      ApiService.overrideHttpClient(server);

      await RentorsHelper().updateRentorPaymentInfo(
        paymentOn(DateTime(2026, 11, 10)),
      );

      expect(server.requests, isEmpty);
    });
  });
}
