import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:utility_bills_manager/helpers/database/database_helper.dart';

// Define the main function to start the server
Future<void> startServer() async {
  final router = Router();

  final DatabaseHelper dbHelper = DatabaseHelper();
  // Define routes for your API endpoints

  // #region Bills

  // #region GET

  // GET request to retrieve bill
  router.get('/bill/<id>', (Request request, String id) async {
    try {
      final bill = await dbHelper.readBill(id);
      if (bill != null) {
        return Response.ok(
          jsonEncode(bill),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(
          body: "Bill with id: $id is null",
          headers: {'Content-Type': 'application/json'},
        );
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });

  // GET request to retrieve all bills
  router.get('/bill/list', (Request request) async {
    try {
      final bills = await dbHelper.readAllBills();
      final billList = bills.map((e) => e).toList();
      return Response.ok(
        jsonEncode(billList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });

  // GET request to retrieve bills by status
  router.get('/bill/list/<status>', (Request request, String status) async {
    try {
      final bills = await dbHelper.readBillsByStatus(status);
      final billList = bills.map((e) => e).toList();
      return Response.ok(
        jsonEncode(billList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region POST

  // POST request to add a new bill
  router.post('/bill', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final bill = jsonDecode(body);

      int createdBillId = await dbHelper.createBill(bill);
      if (createdBillId >= 0) {
        return Response.ok(
          jsonEncode(bill),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to create bill");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region PUT

  // PUT request to update an existing bill
  router.put('/bill', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final bill = jsonDecode(body);

      int numberOfChanges = await dbHelper.updateBill(bill);
      if (numberOfChanges >= 0) {
        return Response.ok(
          jsonEncode(bill),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to update bill");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region DELETE

  // DELETE request to delete an existing bill
  router.delete('/bill/<id>', (Request request, int id) async {
    try {
      int deletedBills = await dbHelper.deleteBill(id);
      if (deletedBills > 0) {
        return Response.ok('Bill deleted');
      } else {
        return Response.badRequest(body: "Failed to delete bill");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion
  // #endregion

  // #region Rentors

  // #region GET

  // GET request to retrieve all rentors
  router.get('/rentor/list', (Request request) async {
    try {
      final rentors = await dbHelper.readAllRentors();
      final rentorList = rentors.map((e) => e).toList();
      return Response.ok(
        jsonEncode(rentorList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region POST

  // POST request to add a new rentor
  router.post('/rentor', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final rentor = jsonDecode(body);

      int createdRentorId = await dbHelper.createRentor(rentor);
      if (createdRentorId >= 0) {
        return Response.ok(
          jsonEncode(rentor),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to create rentor");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region PUT

  // PUT request to update an existing rentor
  router.put('/rentor', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final rentor = jsonDecode(body);

      int numberOfChanges = await dbHelper.updateRentor(rentor);
      if (numberOfChanges >= 0) {
        return Response.ok(
          jsonEncode(rentor),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to update rentor");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region DELETE

  // DELETE request to delete an existing rentor
  router.delete('/rentor/<id>', (Request request, int id) async {
    try {
      int deletedRentors = await dbHelper.deleteRentor(id);
      if (deletedRentors > 0) {
        return Response.ok('Rentor deleted');
      } else {
        return Response.badRequest(body: "Failed to delete rentor");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion
  // #endregion

  // #region Payments

  // #region GET

  // GET request to retrieve all payments
  router.get('/payment/list', (Request request) async {
    try {
      final payments = await dbHelper.readAllPayments();
      final paymentList = payments.map((e) => e).toList();
      return Response.ok(
        jsonEncode(paymentList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region POST

  // POST request to add a new payment
  router.post('/payment', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final payment = jsonDecode(body);

      int createdPaymentId = await dbHelper.createPayment(payment);
      if (createdPaymentId >= 0) {
        return Response.ok(
          jsonEncode(payment),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to create payment");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region PUT

  // PUT request to update an existing payment
  router.put('/payment', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final payment = jsonDecode(body);

      int numberOfChanges = await dbHelper.updatePayment(payment);
      if (numberOfChanges >= 0) {
        return Response.ok(
          jsonEncode(payment),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to update payment");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region DELETE

  // DELETE request to delete an existing payment
  router.delete('/payment/<id>', (Request request, int id) async {
    try {
      int deletedPayments = await dbHelper.deletePayment(id);
      if (deletedPayments > 0) {
        return Response.ok('Payment deleted');
      } else {
        return Response.badRequest(body: "Failed to delete payment");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion
  // #endregion

  // #region EmailData

  // #region GET

  // GET request to retrieve bill
  router.get('/email/<id>', (Request request, int id) async {
    try {
      final bill = await dbHelper.readEmail(id);
      if (bill != null) {
        return Response.ok(
          jsonEncode(bill),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(
          body: "EmailData with id: $id is null",
          headers: {'Content-Type': 'application/json'},
        );
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });

  // GET request to retrieve all emailData
  router.get('/email/list', (Request request) async {
    try {
      final emailData = await dbHelper.readUnprocessedEmails();
      final emailDataList = emailData.map((e) => e).toList();
      return Response.ok(
        jsonEncode(emailDataList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });

  // GET request to retrieve all emailData
  router.get('/email/list/unprocessed', (Request request) async {
    try {
      final emailData = await dbHelper.readUnprocessedEmails();
      final emailDataList = emailData.map((e) => e).toList();
      return Response.ok(
        jsonEncode(emailDataList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });

  // GET request to retrieve all emailData
  router.get('/email/list/processed', (Request request) async {
    try {
      final emailData = await dbHelper.readUnprocessedEmails();
      final emailDataList = emailData.map((e) => e).toList();
      return Response.ok(
        jsonEncode(emailDataList),
        headers: {'Content-Type': 'application/json'},
      );
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region POST

  // POST request to add a new emailData
  router.post('/email', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final emailData = jsonDecode(body);

      int createdEmailDataId = await dbHelper.createEmailData(emailData);
      if (createdEmailDataId >= 0) {
        return Response.ok(
          jsonEncode(emailData),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to create emailData");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region PUT

  // PUT request to update an existing emailData
  router.put('/email', (Request request) async {
    try {
      final body = await request.readAsString();
      if (kDebugMode) {
        print('Received POST data: $body');
      }
      final emailData = jsonDecode(body);

      int numberOfChanges = await dbHelper.updateEmailData(emailData);
      if (numberOfChanges >= 0) {
        return Response.ok(
          jsonEncode(emailData),
          headers: {'Content-Type': 'application/json'},
        );
      } else {
        return Response.badRequest(body: "Failed to update emailData");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion

  // #region DELETE

  // DELETE request to delete an existing emailData
  router.delete('/email/<id>', (Request request, int id) async {
    try {
      int deletedEmailData = await dbHelper.deleteEmailData(id);
      if (deletedEmailData > 0) {
        return Response.ok('EmailData deleted');
      } else {
        return Response.badRequest(body: "Failed to delete emailData");
      }
    } on Exception catch (e) {
      return Response.badRequest(body: e.toString());
    }
  });
  // #endregion
  // #endregion

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router.call);

  final ip = InternetAddress.anyIPv4; // accessible from local network
  final server = await io.serve(handler, ip, 8080);
  if (kDebugMode) {
    print('Server listening on http://${server.address.host}:${server.port}');
  }
}
