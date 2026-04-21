import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models/bill.dart';
import '../../utils/app_logger.dart';
import '../../data/models/email_data.dart';
import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../data/models/server_config.dart';

/// Central HTTP client facade for the local shelf server (client mode).
///
/// Defaults to `http://127.0.0.1:8080`.  Call [configure] to override (e.g.
/// when connecting to a remote host).  Use the static factory methods
/// ([bills], [rentors], [payments], [emails]) to obtain the type-specific
/// service singletons — they all share the same [baseUrl].

/// An [http.BaseClient] that logs every outgoing request and its response.
///
/// Logs the HTTP method and URL before the request is sent, then logs the
/// status code and elapsed time when the response arrives (or the error if the
/// request throws).
class LoggingHttpClient extends http.BaseClient {
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();
    AppLogger().d('→ ${request.method} ${request.url}');
    try {
      final response = await _inner.send(request);
      stopwatch.stop();
      final bodyBytes = await response.stream.toBytes();
      final body = utf8.decode(bodyBytes, allowMalformed: true);
      AppLogger().d(
        '← ${response.statusCode} ${request.url} (${stopwatch.elapsedMilliseconds}ms)\n$body',
      );
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (e) {
      stopwatch.stop();
      AppLogger().e(
        '✗ ${request.method} ${request.url} failed after ${stopwatch.elapsedMilliseconds}ms: $e',
      );
      rethrow;
    }
  }
}

class ApiService {
  static String baseUrl = 'http://127.0.0.1:8080';
  static final http.Client _client = LoggingHttpClient();

  /// Overrides the base URL for all API service singletons.
  static void configure({required String baseUrl}) {
    ApiService.baseUrl = baseUrl;
  }

  /// Returns the [BillsApiService] singleton configured with the current [baseUrl].
  static BillsApiService bills() {
    final billApiService = BillsApiService._instance;
    billApiService.baseUrl = baseUrl;
    return billApiService;
  }

  /// Returns the [RentorsApiService] singleton configured with the current [baseUrl].
  static RentorsApiService rentors() {
    final rentorApiService = RentorsApiService._instance;
    rentorApiService.baseUrl = baseUrl;
    return rentorApiService;
  }

  /// Returns the [PaymentsApiService] singleton configured with the current [baseUrl].
  static PaymentsApiService payments() {
    final paymentApiService = PaymentsApiService._instance;
    paymentApiService.baseUrl = baseUrl;
    return paymentApiService;
  }

  /// Returns the [EmailDataApiService] singleton configured with the current [baseUrl].
  static EmailDataApiService emails() {
    final emailDataApiService = EmailDataApiService._instance;
    emailDataApiService.baseUrl = baseUrl;
    return emailDataApiService;
  }

  /// Returns the [ConfigApiService] singleton configured with the current [baseUrl].
  static ConfigApiService config() {
    final configApiService = ConfigApiService._instance;
    configApiService.baseUrl = baseUrl;
    return configApiService;
  }

  /// Returns the [NotificationApiService] singleton configured with the current [baseUrl].
  static NotificationApiService notifications() {
    final notificationApiService = NotificationApiService._instance;
    notificationApiService.baseUrl = baseUrl;
    return notificationApiService;
  }
}

/// HTTP client for bill endpoints (`/bill`, `/bill/list`).
///
/// All methods return `"OK"` on success or an error string on failure so that
/// callers can map the result into a [Result] without parsing the body.
class BillsApiService {
  static final BillsApiService _instance = BillsApiService._internal();

  factory BillsApiService() {
    return _instance;
  }

  BillsApiService._internal();

  String baseUrl = '';

  //region CRUD Operations

  //region Create
  /// POST `/bill` — creates a new bill.  Returns `"OK"` or an error string.
  Future<String> createBill(Bill bill) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/bill'),
        body: jsonEncode(bill),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to create bill ${bill.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error creating bill: $e');
      return e.toString();
    }
  }
  //endregion

  //region Read
  /// GET `/bill/<id>` — returns the bill with [id], or `null` if not found.
  Future<Bill?> getBill(String id) async {
    try {
      final response = await ApiService._client.get(Uri.parse('$baseUrl/bill/$id'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Bill.fromJson(json);
      } else {
        AppLogger().e('Failed to load bill $id: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error fetching bill $id: $e');
      return null;
    }
  }

  /// GET `/bill/list` — returns all bills.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.  When [limit] is provided the server wraps the response
  /// in `{ "data": [...], "total": N, "limit": N, "offset": N }` — this method
  /// transparently unwraps that envelope and returns just the list.
  Future<List<Bill>> getAllBills({
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/bill/list')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Bill.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load bills: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching bills: $e');
      return [];
    }
  }

  /// GET `/bill/list/<status>` — returns bills filtered by [status].
  ///
  /// Pass [ids] to restrict results to specific `billId` values.  Pass [limit]
  /// and [offset] for pagination; [sortBy] and [sortOrder] to control ordering.
  Future<List<Bill>> getBillsByStatus(
    String status, {
    List<String>? ids,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (ids != null) 'bill_ids': ids.join(','),
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/bill/list/$status')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Bill.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load bills: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching bills: $e');
      return [];
    }
  }

  /// GET `/bill/list/sync` — triggers an on-demand bill email sync and returns
  /// all bills after completion.
  ///
  /// Pass [maxEmails] (default 50) and [earliestEmailDate] to control the IMAP
  /// fetch scope.  Returns `null` when the server responds with HTTP 409
  /// (sync already in progress).
  Future<List<Bill>?> getSyncedBills({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
      final uri = Uri.parse('$baseUrl/bill/list/sync')
          .replace(queryParameters: queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Bill.fromJson(e))
            .toList();
      } else if (response.statusCode == 409) {
        AppLogger().w('Bill sync is already running');
        return null;
      } else {
        AppLogger().e('Failed to sync bills: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error syncing bills: $e');
      return [];
    }
  }
  //endregion

  //region Update
  /// PUT `/bill` — updates an existing bill.  Returns `"OK"` or an error string.
  Future<String> updateBill(Bill bill) async {
    try {
      final response = await ApiService._client.put(
        Uri.parse('$baseUrl/bill'),
        body: jsonEncode(bill),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to update bill ${bill.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error update bill: $e');
      return e.toString();
    }
  }
  //endregion

  //region Delete
  /// DELETE `/bill/<id>` — deletes the bill with [id].
  Future<String> deleteBill(String id) async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/bill/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete bill $id: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error delete bill $id: $e');
      return e.toString();
    }
  }

  /// DELETE `/bill/list` — deletes all bills.
  Future<String> deleteAllBills() async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/bill/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete all bills: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error delete bills: $e');
      return e.toString();
    }
  }
  //endregion

  //endregion
}

/// HTTP client for rentor endpoints (`/rentor`, `/rentor/list`).
class RentorsApiService {
  static final RentorsApiService _instance = RentorsApiService._internal();

  factory RentorsApiService() {
    return _instance;
  }

  RentorsApiService._internal();

  String baseUrl = '';

  //region CRUD Operations

  //region Create
  /// POST `/rentor` — creates a new rentor.  Returns `"OK"` or an error string.
  Future<String> createRentor(Rentor rentor) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/rentor'),
        body: jsonEncode(rentor),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to create rentor ${rentor.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error creating rentor: $e');
      return e.toString();
    }
  }
  //endregion

  //region Read
  /// GET `/rentor/<id>` — returns the rentor with [id], or `null` if not found.
  Future<Rentor?> getRentor(String id) async {
    try {
      final response = await ApiService._client.get(Uri.parse('$baseUrl/rentor/$id'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Rentor.fromJson(json);
      } else {
        AppLogger().e('Failed to load rentor $id: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error fetching rentor: $e');
      return null;
    }
  }

  /// GET `/rentor/list` — returns all rentors.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.
  Future<List<Rentor>> getAllRentors({
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/rentor/list')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Rentor.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load rentors: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching rentors: $e');
      return [];
    }
  }
  //endregion

  //region Update
  /// PUT `/rentor` — updates an existing rentor.  Returns `"OK"` or an error string.
  Future<String> updateRentor(Rentor rentor) async {
    try {
      final response = await ApiService._client.put(
        Uri.parse('$baseUrl/rentor'),
        body: jsonEncode(rentor),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to update rentor ${rentor.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error updating rentors: $e');
      return e.toString();
    }
  }
  //endregion

  //region Delete
  /// DELETE `/rentor/<id>` — deletes the rentor with [id].
  Future<String> deleteRentor(String id) async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/rentor/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete rentor $id: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error delete rentor $id: $e');
      return e.toString();
    }
  }

  /// DELETE `/rentor/list` — deletes all rentors.
  Future<String> deleteAllRentors() async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/rentor/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete all rentors: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting rentors: $e');
      return e.toString();
    }
  }
  //endregion

  //endregion
}

/// HTTP client for payment endpoints (`/payment`, `/payment/list`).
class PaymentsApiService {
  static final PaymentsApiService _instance = PaymentsApiService._internal();

  factory PaymentsApiService() {
    return _instance;
  }

  PaymentsApiService._internal();

  String baseUrl = '';

  //region CRUD Operations

  //region Create
  /// POST `/payment` — creates a new payment (with bill IDs and rentor ID).
  /// Returns `"OK"` or an error string.
  Future<String> createPayment(Payment payment) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/payment'),
        body: jsonEncode(payment.toJson(include: {'bill': true, 'rentor': true})),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to create payment: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error fetching payments: $e');
      return e.toString();
    }
  }
  //endregion

  //region Read
  /// GET `/payment/<id>` — returns the payment with [id].
  /// Pass [include] flags (`bill`, `rentor`) to request eager joins.
  Future<Payment?> getPayment(String id, {Map<String, bool>? include}) async {
    try {
      final includeParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
      };
      final uri = Uri.parse(
        '$baseUrl/payment/$id',
      ).replace(queryParameters: includeParams.isEmpty ? null : includeParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Payment.fromJson(json);
      } else {
        AppLogger().e('Failed to load payment $id: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error fetching payment $id: $e');
      return null;
    }
  }

  /// GET `/payment/list` — returns all payments, optionally filtered to [ids]
  /// and with related records eager-loaded via [include] flags.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.
  Future<List<Payment>> getAllPayments({
    Map<String, bool>? include,
    List<String>? ids,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (ids != null) 'payment_ids': ids.join(','),
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/payment/list')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Payment.fromJson(e, billRows: e['billList'] != null && e['billList'] is List ? List<Map<String, dynamic>>.from(e['billList']) : null))
            .toList();
      } else {
        AppLogger().e('Failed to load payments: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching payments: $e');
      return [];
    }
  }

  /// GET `/payment/list/sync` — triggers an on-demand payment email sync and
  /// returns all payments after completion.
  ///
  /// Accepts the same [include] and [ids] filters as [getAllPayments], plus
  /// [maxEmails] and [earliestEmailDate] for the IMAP fetch scope.
  /// Returns `null` when the server responds with HTTP 409 (sync already in
  /// progress).
  Future<List<Payment>?> getSyncedPayments({
    Map<String, bool>? include,
    List<String>? ids,
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (ids != null) 'payment_ids': ids.join(','),
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
      final uri = Uri.parse('$baseUrl/payment/list/sync')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Payment.fromJson(e, billRows: e['billList'] != null && e['billList'] is List ? List<Map<String, dynamic>>.from(e['billList']) : null))
            .toList();
      } else if (response.statusCode == 409) {
        AppLogger().w('Payment sync is already running');
        return null;
      } else {
        AppLogger().e('Failed to sync payments: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error syncing payments: $e');
      return [];
    }
  }
  //endregion

  //region Update
  /// PUT `/payment` — updates an existing payment.  Returns `"OK"` or an error string.
  Future<String> updatePayment(Payment payment) async {
    try {
      final response = await ApiService._client.put(
        Uri.parse('$baseUrl/payment'),
        body: jsonEncode(payment.toJson(include: {'bill': true, 'rentor': true})),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to update payment ${payment.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error updating payment: $e');
      return e.toString();
    }
  }
  //endregion

  //region Delete
  /// DELETE `/payment/<id>` — deletes the payment with [id].
  Future<String> deletePayment(String id) async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/payment/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete payment $id: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting payment: $e');
      return e.toString();
    }
  }

  /// DELETE `/payment/list` — deletes all payments.
  Future<String> deleteAllPayments() async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/payment/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete all payments: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting payments: $e');
      return e.toString();
    }
  }
  //endregion

  //endregion
}

/// HTTP client for email data endpoints (`/email`, `/email/list`, etc.).
class EmailDataApiService {
  static final EmailDataApiService _instance = EmailDataApiService._internal();

  factory EmailDataApiService() {
    return _instance;
  }

  EmailDataApiService._internal();

  String baseUrl = '';

  //region CRUD Operations

  //region Create
  /// POST `/email` — creates a new email record.  Returns `"OK"` or an error string.
  Future<String> createEmailData(EmailData emailData) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/email'),
        body: jsonEncode(emailData),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to create emailData ${emailData.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error creating emailData: $e');
      return e.toString();
    }
  }
  //endregion

  //region Read
  /// GET `/email/<id>` — returns the email record with [id].
  /// Set [queryByEmailId] to `true` to match on the numeric `emailId` field
  /// rather than the UUID `emailDataId`.
  Future<EmailData?> getEmail(String id, {Map<String, bool>? include, bool queryByEmailId = false}) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',

        'query_by_email_id': '$queryByEmailId',
      };
      final uri = Uri.parse('$baseUrl/email/$id').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return EmailData.fromJson(json);
      } else {
        AppLogger().e('Failed to load emailData $id: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error fetching emailDatas: $e');
      return null;
    }
  }

  /// GET `/email/list` — returns all email records.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.
  Future<List<EmailData>> getEmails({
    Map<String, bool>? include,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/email/list').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load emailDatas: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching emailDatas: $e');
      return [];
    }
  }

  /// GET `/email/list/unprocessed` — returns only unprocessed email records.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.
  Future<List<EmailData>> getUnprocessedEmails({
    Map<String, bool>? include,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/email/list/unprocessed').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load unprocessed emailDatas: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching emailDatas: $e');
      return [];
    }
  }

  /// GET `/email/list/processed` — returns only processed email records.
  ///
  /// Pass [limit] and [offset] for pagination; [sortBy] and [sortOrder] to
  /// control ordering.
  Future<List<EmailData>> getProcessedEmails({
    Map<String, bool>? include,
    int? limit,
    int? offset,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
        if (limit != null) 'limit': '$limit',
        if (offset != null) 'offset': '$offset',
        if (sortBy != null) 'sort_by': sortBy,
        if (sortOrder != null) 'sort_order': sortOrder,
      };
      final uri = Uri.parse('$baseUrl/email/list/processed').replace(
        queryParameters: queryParams.isEmpty ? null : queryParams,
      );
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final List<dynamic> jsonList =
            decoded is Map ? decoded['data'] as List : decoded as List;
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        AppLogger().e('Failed to load processed emailDatas: ${response.statusCode} - $response');
        return [];
      }
    } catch (e) {
      AppLogger().e('Error fetching emailDatas: $e');
      return [];
    }
  }

  /// GET `/email/list/sync` — triggers both bill and payment email syncs and
  /// returns the newly fetched raw [EmailData] records grouped by type.
  ///
  /// Returns `{'bills': [...], 'payments': [...]}` on success.
  /// Returns `null` when the server responds with HTTP 409 (sync already in
  /// progress).
  Future<Map<String, dynamic>?> getSyncedEmail({
    int? maxEmails,
    DateTime? earliestEmailDate,
    DateTime? latestEmailDate,
  }) async {
    try {
      final queryParams = <String, String>{
        if (maxEmails != null)
          'maxEmails': '$maxEmails',
        if (earliestEmailDate != null)
          'earliestEmailDate': earliestEmailDate.toIso8601String(),
        if (latestEmailDate != null)
          'latestEmailDate': latestEmailDate.toIso8601String(),
      };
      final uri = Uri.parse('$baseUrl/email/list/sync')
          .replace(queryParameters: queryParams);
      final response = await ApiService._client.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return {
          'bills': (json['bills'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map((e) => Bill.fromJson(e))
              .toList(),
          'payments': (json['payments'] as List<dynamic>? ?? [])
              .whereType<Map<String, dynamic>>()
              .map((e) => Payment.fromJson(e))
              .toList(),
        };
      } else if (response.statusCode == 409) {
        AppLogger().w('Email sync is already running');
        return null;
      } else {
        AppLogger().e('Failed to sync email data: ${response.statusCode} - $response');
        return {};
      }
    } catch (e) {
      AppLogger().e('Error syncing email data: $e');
      return {};
    }
  }
  //endregion

  //region Update
  /// PUT `/email` — updates an existing email record.  Returns `"OK"` or an error string.
  Future<String> updateEmailData(EmailData emailData) async {
    try {
      final response = await ApiService._client.put(
        Uri.parse('$baseUrl/email'),
        body: jsonEncode(emailData),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to update emailData ${emailData.id}: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error updating emailData: $e');
      return e.toString();
    }
  }
  //endregion

  //region Delete
  /// DELETE `/email/<id>` — deletes the email record with [id].
  Future<String> deleteEmailData(String id) async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/email/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete emailData: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting emailData: $e');
      return e.toString();
    }
  }

  /// DELETE `/email/list` — deletes all email records.
  Future<String> deleteAllEmailData() async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/email/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete all emailData: ${response.statusCode} - ${response.toString()}');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting emailData: $e');
      return e.toString();
    }
  }
  //endregion

  //endregion
}

/// HTTP client for the server configuration endpoint (`/config`).
class ConfigApiService {
  static final ConfigApiService _instance = ConfigApiService._internal();

  factory ConfigApiService() {
    return _instance;
  }

  ConfigApiService._internal();

  String baseUrl = '';

  /// GET `/config` — returns the active [ServerConfig], or `null` on error.
  Future<ServerConfig?> getConfig() async {
    try {
      final response = await ApiService._client.get(Uri.parse('$baseUrl/config'));
      if (response.statusCode == 200) {
        return ServerConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        AppLogger().e('Failed to get config: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error getting config: $e');
      return null;
    }
  }

  /// POST `/config` — creates a new configuration.  Returns the created
  /// [ServerConfig] on success, or `null` on error.
  Future<ServerConfig?> createConfig(ServerConfig config) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/config'),
        body: jsonEncode(config.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return ServerConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        AppLogger().e('Failed to create config: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error creating config: $e');
      return null;
    }
  }

  /// PUT `/config` — updates the stored configuration.  Returns the updated
  /// [ServerConfig] on success, or `null` on error.
  Future<ServerConfig?> updateConfig(ServerConfig config) async {
    try {
      final response = await ApiService._client.put(
        Uri.parse('$baseUrl/config'),
        body: jsonEncode(config.toJson()),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return ServerConfig.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      } else {
        AppLogger().e('Failed to update config: ${response.statusCode} - $response');
        return null;
      }
    } catch (e) {
      AppLogger().e('Error updating config: $e');
      return null;
    }
  }

  /// DELETE `/config` — deletes the stored configuration.
  /// Returns `"OK"` on success or an error string on failure.
  Future<String> deleteConfig() async {
    try {
      final response = await ApiService._client.delete(Uri.parse('$baseUrl/config'));
      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e('Failed to delete config: ${response.statusCode} - $response');
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error deleting config: $e');
      return e.toString();
    }
  }
}

/// HTTP client for notification endpoints (`/device/token`).
///
/// The SSE stream at `GET /connect` must be consumed directly via a streaming
/// HTTP client (e.g. `dart:io HttpClient`); this service only wraps the
/// FCM token-registration side-channel.
class NotificationApiService {
  static final NotificationApiService _instance =
      NotificationApiService._internal();

  factory NotificationApiService() {
    return _instance;
  }

  NotificationApiService._internal();

  String baseUrl = '';

  /// POST `/device/token` — registers [fcmToken] for [deviceId] so the server
  /// can deliver FCM push notifications to this device.
  ///
  /// Requires the `x-device-id` request header; the server returns 400 if it
  /// is absent or if [fcmToken] is empty.  Returns `"OK"` on success.
  Future<String> registerDeviceToken(String deviceId, String fcmToken) async {
    try {
      final response = await ApiService._client.post(
        Uri.parse('$baseUrl/device/token'),
        body: jsonEncode({'fcmToken': fcmToken}),
        headers: {
          'Content-Type': 'application/json',
          'x-device-id': deviceId,
        },
      );
      if (response.statusCode == 200) {
        return "OK";
      } else {
        AppLogger().e(
          'Failed to register device token: ${response.statusCode} - $response',
        );
        return response.toString();
      }
    } catch (e) {
      AppLogger().e('Error registering device token: $e');
      return e.toString();
    }
  }
}
