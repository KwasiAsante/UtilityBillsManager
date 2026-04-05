import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import 'package:utility_bills_manager/config/app_config.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/helpers/bills/bills_helper.dart';
import 'package:utility_bills_manager/helpers/database/database_helper.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/data/models/result.dart';
import 'package:utility_bills_manager/services/api/api_service.dart';
import 'package:utility_bills_manager/data/models/app_state.dart';
import 'package:utility_bills_manager/services/email/email_service.dart';
import 'package:utility_bills_manager/utils/bills/bills_parser.dart';
import 'package:utility_bills_manager/utils/email/email_parser.dart';

import '../../data/models/payment.dart';
import '../../data/models/rentor.dart';
import '../../utils/payments/payments_parser.dart';
import '../payments/payments_helper.dart';
import '../rentors/rentors_helper.dart';

class EmailDataHelper {
  static final EmailDataHelper _instance = EmailDataHelper._internal();

  factory EmailDataHelper() {
    return _instance;
  }

  EmailDataHelper._internal();

  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  late final EmailService emailService = EmailService(
    email: AppConfig.emailAddress,
    password: AppConfig.emailPassword,
    imapServer: AppConfig.emailImapServer,
    imapPort: AppConfig.emailImapPort,
    isImapSecure: AppConfig.emailImapSecure,
  );

  final BillsHelper _billsHelper = BillsHelper();
  final PaymentsHelper _paymentsHelper = PaymentsHelper();
  final RentorsHelper _rentorsHelper = RentorsHelper();

  // region CRUD Operations
  // region Email Data
  // Create Email Data
  Future<Result<EmailData>> createEmailData(EmailData emailData) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.createEmailData(emailData);
      if (id >= 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when creating Bill ${emailData.id}",
        );
      }
    } else {
      final returnValue = await ApiService.emails().createEmailData(emailData);
      if (returnValue == "OK") {
        return Result.success();
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  // Retrieve Email Data
  Future<Result<EmailData?>> readEmail(String id, {Map<String, bool>? include}) async {
    final dbHelper = this.dbHelper;
    try {
      EmailData? emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readEmail(id, include: include);
      } else {
        emailData = await ApiService.emails().getEmail(id, include: include);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve Email Data list
  Future<Result<List<EmailData>>> readEmails({Map<String, bool>? include}) async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readEmails(include: include);
      } else {
        emailData = await ApiService.emails().getEmails(include: include);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve unprocessed Email Data
  Future<Result<List<EmailData>>> readUnprocessedEmails({Map<String, bool>? include}) async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readUnprocessedEmails(include: include);
      } else {
        emailData = await ApiService.emails().getUnprocessedEmails(include: include);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve processed Email Data
  Future<Result<List<EmailData>>> readProcessedEmails({Map<String, bool>? include}) async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readProcessedEmails(include: include);
      } else {
        emailData = await ApiService.emails().getProcessedEmails(include: include);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  Future<Result<EmailData>> updateEmailData(EmailData emailData) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      final id = await dbHelper.updateEmailData(emailData);
      if (id >= 0) {
        return Result.success();
      } else {
        return Result.error(
          errorMessage: "Error when updating Bill ${emailData.emailId}",
        );
      }
    } else {
      final returnValue = await ApiService.emails().updateEmailData(emailData);
      if (returnValue == "OK") {
        return Result.success();
      } else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }

  // Delete Email Data by emailDataId
  Future<Result<void>> deleteEmailData(String emailDataId) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      await dbHelper.deleteEmailDataByEmailDataId(emailDataId);
      return Result.success();
    } else {
      final returnValue = await ApiService.emails().deleteEmailData(emailDataId);
      if (returnValue == "OK") {
        return Result.success();
      }
      return Result.error(errorMessage: returnValue);
    }
  }

  // Delete all Email Data
  Future<Result<void>> deleteAllEmails() async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      await dbHelper.deleteAllEmailData();
      return Result.success();
    } else {
      final returnValue = await ApiService.emails().deleteAllEmailData();
      if (returnValue == "OK") {
        return Result.success();
      }
      return Result.error(errorMessage: returnValue);
    }
  }
  // endregion
  // endregion

  // region Email
  Future<Map<MimeMessage, EmailData>> fetchEmails(EmailType type, {int maxEmails = 50, DateTime? earliestEmailDate}) async {
    Map<MimeMessage, EmailData> finalMessages = {};
    final messages = await emailService.fetchRecentEmails(type, maxEmails: maxEmails, earliestEmailDate: earliestEmailDate);
    for (MimeMessage message in messages) {
      if (kDebugMode) {
        print('From: ${message.from}');
        print('Subject: ${message.decodeSubject()}');
        print('Date: ${message.decodeDate()}');
        print('Text: ${EmailParser.extractEmailBody(message)}');
        print(
          '---------------------------------------------------------------------\n\n\n\n\n',
        );
      }

      EmailData? emailData = await EmailParser.parseEmailToEmailData(message);
      if (emailData != null) {
        Map<String, bool> include = type == EmailType.bill ? {'bill': true} : {'payment': true};
        Result<EmailData?> result = await readEmail(emailData.getEmailId(), include: include);
        if (result.isError || result.data == null) {
          Result<EmailData> retVal = await createEmailData(emailData);
          if (retVal.isError) {
            if (kDebugMode) {
              print(retVal.errorMessage);
            }
          }
          finalMessages[message] = emailData;
        } else {
          finalMessages[message] = result.data!;
        }
      }
    }
    return finalMessages;
  }

  Future<void> fetchBillEmails({int maxEmails = 50, DateTime? earliestEmailDate}) async {
    final messages = await fetchEmails(EmailType.bill, maxEmails: maxEmails, earliestEmailDate: earliestEmailDate);
    if (messages.isNotEmpty) {
      for (MimeMessage message in messages.keys) {
        Bill? bill = messages[message]?.bill;
        if (bill == null) {
          var billId = messages[message]?.billId;
          Result<Bill?> billResult = await _billsHelper.readBill(billId ?? '');
          bill = billResult.isSuccess ? billResult.data : null;
        }

        if (bill == null) {
          bill = await BillsParser.parseEmailToBill(message);
          if (bill != null) {
            if (kDebugMode) {
              print(
                'Bill Parsed: {\n\tID: ${bill.billId}\n\tCompany: ${bill.company}\n\tAmount: ${bill.amount}\n\tBill Type: ${bill.type}\n\tDue Date: ${bill.dueDate}\n\tPayment Status: ${bill.status.name}\n\tNotes: ${bill.notes}\n}',
              );
              print(
                '---------------------------------------------------------------------\n\n\n\n\n',
              );
            }

            // Create the bill and get its ID
            Result<Bill> createResult = await _billsHelper.createBill(bill);
            if (createResult.isSuccess && createResult.data != null) {
              var emailData = messages[message];
              if (emailData != null) {
                // Create a new EmailData instance with updated values
                EmailData updatedEmailData = EmailData(
                  id: emailData.id,
                  emailDataId: emailData.emailDataId,
                  emailSubject: emailData.emailSubject,
                  emailBody: emailData.emailBody,
                  emailId: emailData.emailId,
                  billId: createResult.data!.billId,
                  bill: createResult.data,
                  paymentId: emailData.paymentId,
                  processed: true,
                );
                await updateEmailData(updatedEmailData);
              }
            }
          } else {
            if (kDebugMode) {
              print('Failed to convert Bill: ${message.decodeSubject()}');
              print(
                '---------------------------------------------------------------------\n\n\n\n\n',
              );
            }
          }
        } else {
          if (kDebugMode) {
            print(
              'Bill Found: {\n\tID: ${bill.id}\n\tCompany: ${bill.company}\n\tAmount: ${bill.amount}\n\tBill Type: ${bill.type}\n\tDue Date: ${bill.dueDate}\n\tPayment Status: ${bill.status.name}\n\tNotes: ${bill.notes}\n}',
            );
            print(
              '---------------------------------------------------------------------\n\n\n\n\n',
            );
          }

          var emailData = messages[message];
          if (emailData != null) {
            // Create a new EmailData instance with updated values
            EmailData updatedEmailData = EmailData(
              id: emailData.id,
              emailDataId: emailData.emailDataId,
              emailSubject: emailData.emailSubject,
              emailBody: emailData.emailBody,
              emailId: emailData.emailId,
              billId: bill.billId,
              bill: bill,
              paymentId: emailData.paymentId,
              processed: true,
            );
            await updateEmailData(updatedEmailData);
          }
        }
      }
    }
  }

  Future<void> fetchPaymentEmails({int maxEmails = 50, DateTime? earliestEmailDate}) async {
    final messages = await fetchEmails(EmailType.payment, maxEmails: maxEmails, earliestEmailDate: earliestEmailDate);
    if (messages.isNotEmpty) {
      List<Rentor> rentors = [];
      final rentorListResult = await _rentorsHelper.readAllRentors();
      if (rentorListResult.isSuccess && rentorListResult.data != null) {
        rentors = rentorListResult.data!;
      }

      for (MimeMessage message in messages.keys) {
        Payment? payment = messages[message]?.payment;
        if (payment == null) {
          var paymentId = messages[message]?.paymentId;
          Result<Payment?> paymentResult = await _paymentsHelper.readPayment(paymentId ?? '');
          payment = paymentResult.isSuccess ? paymentResult.data : null;
        }

        if (payment == null) {
          payment = await PaymentsParser.parseEmailToPayment(message, rentors: rentors);
          if (payment != null) {
            if (kDebugMode) {
              print(
                'Payment Parsed: {\n\tID: ${payment.paymentId}\n\tPayment Date: ${payment.paymentDate}\n\tAmount Paid: ${payment.amountPaid}\n\tPaid Rentor: ${payment.rentorName}\n\tBill Paid: \n\t\t${payment.billNames(newLine: true)}\n}',
              );
              print(
                '---------------------------------------------------------------------\n\n\n\n\n',
              );
            }

            // Create the payment and get its ID
            Result<Payment> createResult = await _paymentsHelper.createPayment(payment);
            if (createResult.isSuccess && createResult.data != null) {
              var emailData = messages[message];
              if (emailData != null) {
                // Create a new EmailData instance with updated values
                EmailData updatedEmailData = EmailData(
                  id: emailData.id,
                  emailDataId: emailData.emailDataId,
                  emailSubject: emailData.emailSubject,
                  emailBody: emailData.emailBody,
                  emailId: emailData.emailId,
                  billId: emailData.billId,
                  paymentId: createResult.data!.paymentId,
                  payment: createResult.data,
                  processed: true,
                );
                await updateEmailData(updatedEmailData);
              }
            }
          } else {
            if (kDebugMode) {
              print('Failed to convert Payment: ${message.decodeSubject()}');
              print(
                '---------------------------------------------------------------------\n\n\n\n\n',
              );
            }
          }
        } else {
          if (kDebugMode) {
            print(
              'Payment Found: {\n\tID: ${payment.paymentId}\n\tPayment Date: ${payment.paymentDate}\n\tAmount Paid: ${payment.amountPaid}\n\tPaid Rentor: ${payment.rentorName}\n\tBill Paid: \n\t\t${payment.billNames(newLine: true)}\n}',
            );
            print(
              '---------------------------------------------------------------------\n\n\n\n\n',
            );
          }

          var emailData = messages[message];
          if (emailData != null) {
            // Create a new EmailData instance with updated values
            EmailData updatedEmailData = EmailData(
              id: emailData.id,
              emailDataId: emailData.emailDataId,
              emailSubject: emailData.emailSubject,
              emailBody: emailData.emailBody,
              emailId: emailData.emailId,
              billId: emailData.billId,
              paymentId: payment.paymentId,
              payment: payment,
              processed: true,
            );
            await updateEmailData(updatedEmailData);
          }
        }
      }
    }
  }
  // endregion
}
