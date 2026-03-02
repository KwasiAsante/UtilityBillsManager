import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/data/models/rentor.dart';

class ApiService {
  static String baseUrl = 'http://127.0.0.1:8080';

  static void configure({required String baseUrl}) {
    ApiService.baseUrl = baseUrl;
  }

  static BillsApiService bills() {
    final billApiService = BillsApiService._instance;
    billApiService.baseUrl = baseUrl;
    return billApiService;
  }

  static RentorsApiService rentors() {
    final rentorApiService = RentorsApiService._instance;
    rentorApiService.baseUrl = baseUrl;
    return rentorApiService;
  }

  static PaymentsApiService payments() {
    final paymentApiService = PaymentsApiService._instance;
    paymentApiService.baseUrl = baseUrl;
    return paymentApiService;
  }

  static EmailDataApiService emails() {
    final emailDataApiService = EmailDataApiService._instance;
    emailDataApiService.baseUrl = baseUrl;
    return emailDataApiService;
  }
}

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
          print('Failed to create bill: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
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
          print('Failed to load bills: ${response.statusCode} - $response');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
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

  Future<List<Bill>> getBillsByStatus(String status) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/bill/list/$status'));

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
          print('Failed to load bills: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteBill(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/bill/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to load bills: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching bills: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}

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
          print('Failed to create rentor: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rentors: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
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
          print('Failed to load rentors: ${response.statusCode} - $response');
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rentors: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteRentor(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/rentor/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to load rentors: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching rentors: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}

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
  Future<List<Payment>> getAllPayments() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/payment/list'));

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
  // #endregion

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
          print('Failed to load payments: ${response.statusCode} - $response');
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

  // #region Delete
  Future<String> deletePayment(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/payment/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to load payments: ${response.statusCode} - ${response.toString()}',
          );
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

  // #endregion
}

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
            'Failed to create emailData: ${response.statusCode} - $response',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Read
  Future<EmailData?> getEmail(int id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/email/$id'));

      if (response.statusCode == 200) {
        final Map<String, dynamic> json = jsonDecode(response.body);
        return EmailData.fromJson(json);
      } else {
        if (kDebugMode) {
          print(
            'Failed to load emailData: ${response.statusCode} - $response',
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

  Future<List<EmailData>> getEmails() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/email/list'));

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

  Future<List<EmailData>> getUnprocessedEmails() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/email/list/unprocessed'),
      );

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

  Future<List<EmailData>> getProcessedEmails() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/email/list/processed'),
      );

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
            'Failed to load emailDatas: ${response.statusCode} - $response',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #region Delete
  Future<String> deleteEmailData(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/email/$id'));

      if (response.statusCode == 200) {
        return "OK";
      } else {
        if (kDebugMode) {
          print(
            'Failed to load emailDatas: ${response.statusCode} - ${response.toString()}',
          );
        }
        return response.toString();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emailDatas: $e');
      }
      return e.toString();
    }
  }
  // #endregion

  // #endregion
}
