import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

/// Central HTTP client facade for the local shelf server (client mode).
///
/// Defaults to `http://127.0.0.1:8080`.  Call [configure] to override (e.g.
/// when connecting to a remote host).  Use the static factory methods
/// ([bills], [rentors], [payments], [emails]) to obtain the type-specific
/// service singletons — they all share the same [baseUrl].
class ApiService {
  static String baseUrl = 'http://127.0.0.1:8080';

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

  // #region CRUD Operations

  // #region Create
  Future<String> createBill(Bill bill) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/bill'),
        body: jsonEncode(bill),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to create bill ${bill.id}: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating bill: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
  Future<Bill?> getBill(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/bill/$id'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Bill.fromJson(json);
      } else {
        if (kDebugMode) {
          print('Failed to load bill $id: ${response.statusCode} - $response');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bill $id: $e');
      }
      return null;
    }
  }

  Future<List<Bill>> getAllBills() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/bill/list'));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Bill.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print('Failed to load bills: ${response.statusCode} - $response');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
      }
      return [];
    }
  }

  Future<List<Bill>> getBillsByStatus(String status, {List<String>? ids}) async {
    try {
      final queryParams = <String, String>{
        if (ids != null)
          'bill_ids': ids.join(','),
      };
      final uri = Uri.parse('$baseUrl/bill/list/$status').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Bill.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print('Failed to load bills: ${response.statusCode} - $response');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
      }
      return [];
    }
  }
  // #endregion

  // #region Update
  Future<String> updateBill(Bill bill) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/bill'),
        body: jsonEncode(bill),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to update bill ${bill.id}: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error update bill: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteBill(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/bill/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete bill $id: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error delete bill $id: $e');
      }
      return e.toString();
    }
  }

  Future<String> deleteAllBills() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/bill/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete all bills: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error delete bills: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}

/// HTTP client for rentor endpoints (`/rentor`, `/rentor/list`).
class RentorsApiService {
  static final RentorsApiService _instance = RentorsApiService._internal();

  factory RentorsApiService() {
    return _instance;
  }

  RentorsApiService._internal();

  String baseUrl = '';

  // #region CRUD Operations

  // #region Create
  Future<String> createRentor(Rentor rentor) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/rentor'),
        body: jsonEncode(rentor),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to create rentor ${rentor.id}: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating rentor: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
  Future<Rentor?> getRentor(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/rentor/$id'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Rentor.fromJson(json);
      } else {
        if (kDebugMode) {
          print('Failed to load rentor $id: ${response.statusCode} - $response');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rentor: $e');
      }
      return null;
    }
  }

  Future<List<Rentor>> getAllRentors() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/rentor/list'));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Rentor.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print('Failed to load rentors: ${response.statusCode} - $response');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rentors: $e');
      }
      return [];
    }
  }
  // #endregion

  // #region Update
  Future<String> updateRentor(Rentor rentor) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/rentor'),
        body: jsonEncode(rentor),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to update rentor ${rentor.id}: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating rentors: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteRentor(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/rentor/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete rentor $id: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error delete rentor $id: $e');
      }
      return e.toString();
    }
  }

  Future<String> deleteAllRentors() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/rentor/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete all rentors: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting rentors: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}

/// HTTP client for payment endpoints (`/payment`, `/payment/list`).
class PaymentsApiService {
  static final PaymentsApiService _instance = PaymentsApiService._internal();

  factory PaymentsApiService() {
    return _instance;
  }

  PaymentsApiService._internal();

  String baseUrl = '';

  // #region CRUD Operations

  // #region Create
  Future<String> createPayment(Payment payment) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/payment'),
        body: jsonEncode(payment),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to create payment: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching payments: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
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
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return Payment.fromJson(json);
      } else {
        if (kDebugMode) {
          print('Failed to load payment $id: ${response.statusCode} - $response');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching payment $id: $e');
      }
      return null;
    }
  }

  Future<List<Payment>> getAllPayments({Map<String, bool>? include, List<String>? ids}) async {
    try {
      final queryParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',

        if (ids != null)
          'payment_ids': ids.join(','),
      };
      final uri = Uri.parse(
        '$baseUrl/payment/list',
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => Payment.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print('Failed to load payments: ${response.statusCode} - $response');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching payments: $e');
      }
      return [];
    }
  }
  // #endregiosadn

  // #region Update
  Future<String> updatePayment(Payment payment) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/payment'),
        body: jsonEncode(payment),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print('Failed to update payment ${payment.id}: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating payment: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deletePayment(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/payment/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete payment $id: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting payment: $e');
      }
      return e.toString();
    }
  }

  Future<String> deleteAllPayments() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/payment/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete all payments: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting payments: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}

/// HTTP client for email data endpoints (`/email`, `/email/list`, etc.).
class EmailDataApiService {
  static final EmailDataApiService _instance = EmailDataApiService._internal();

  factory EmailDataApiService() {
    return _instance;
  }

  EmailDataApiService._internal();

  String baseUrl = '';

  // #region CRUD Operations

  // #region Create
  Future<String> createEmailData(EmailData emailData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/email'),
        body: jsonEncode(emailData),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to create emailData ${emailData.id}: ${response.statusCode} - $response',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating emailData: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
  Future<EmailData?> getEmail(String id, {Map<String, bool>? include}) async {
    try {
      final includeParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
      };
      final uri = Uri.parse('$baseUrl/email/$id').replace(
        queryParameters: includeParams.isEmpty ? null : includeParams,
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return EmailData.fromJson(json);
      } else {
        if (kDebugMode) {
          print(
            'Failed to load emailData $id: ${response.statusCode} - $response',
          );
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return null;
    }
  }

  Future<List<EmailData>> getEmails({Map<String, bool>? include}) async {
    try {
      final includeParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
      };
      final uri = Uri.parse('$baseUrl/email/list').replace(
        queryParameters: includeParams.isEmpty ? null : includeParams,
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print(
            'Failed to load emailDatas: ${response.statusCode} - $response',
          );
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return [];
    }
  }

  Future<List<EmailData>> getUnprocessedEmails({Map<String, bool>? include}) async {
    try {
      final includeParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
      };
      final uri = Uri.parse('$baseUrl/email/list/unprocessed').replace(
        queryParameters: includeParams.isEmpty ? null : includeParams,
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print(
            'Failed to load unprocessed emailDatas: ${response.statusCode} - $response',
          );
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return [];
    }
  }

  Future<List<EmailData>> getProcessedEmails({Map<String, bool>? include}) async {
    try {
      final includeParams = <String, String>{
        if (include != null)
          for (final entry in include.entries)
            if (entry.value) entry.key: 'true',
      };
      final uri = Uri.parse('$baseUrl/email/list/processed').replace(
        queryParameters: includeParams.isEmpty ? null : includeParams,
      );
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList
            .whereType<Map<String, dynamic>>()
            .map((e) => EmailData.fromJson(e))
            .toList();
      } else {
        if (kDebugMode) {
          print(
            'Failed to load processed emailDatas: ${response.statusCode} - $response',
          );
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return [];
    }
  }
  // #endregion

  // #region Update
  Future<String> updateEmailData(EmailData emailData) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/email'),
        body: jsonEncode(emailData),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to update emailData ${emailData.id}: ${response.statusCode} - $response',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating emailData: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteEmailData(String id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/email/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete emailData: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting emailData: $e');
      }
      return e.toString();
    }
  }

  Future<String> deleteAllEmailData() async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/email/list'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to delete all emailData: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting emailData: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}
