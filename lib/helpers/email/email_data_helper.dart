import 'package:enough_mail/enough_mail.dart';

import '../bills/bills_helper.dart';
import '../database/database_helper.dart';
import '../payments/payments_helper.dart';
import '../rentors/rentors_helper.dart';
import '../../config/app_config.dart';
import '../../data/models/app_state.dart';
import '../../data/models/bill.dart';
import '../../data/models/email_data.dart';
import '../../data/models/payment.dart';
import '../../data/models/result.dart';
import '../../data/models/rentor.dart';
import '../../services/api/api_service.dart';
import '../../utils/app_logger.dart';
import '../../services/email/email_service.dart';
import '../../utils/bills/bills_parser.dart';
import '../../utils/email/email_parser.dart';
import '../../utils/payments/payments_parser.dart';

/// Singleton service that handles email data persistence **and** the full
/// email-import pipeline (fetch → parse → persist bill/payment).
///
/// CRUD operations are routed to [DatabaseHelper] (local-DB mode) or
/// [ApiService] (server mode) exactly like the other helpers.
///
/// The import pipeline ([fetchBillEmails] / [fetchPaymentEmails]) fetches raw
/// [MimeMessage]s from the IMAP account configured in [AppConfig], converts
/// them to [EmailData] records, and then attempts to parse a [Bill] or
/// [Payment] out of each message body.  Existing records are detected by
/// `emailId` and skipped to avoid duplicates.
class EmailDataHelper {
  static final EmailDataHelper _instance = EmailDataHelper._internal();

  factory EmailDataHelper() {
    return _instance;
  }

  EmailDataHelper._internal();

  /// Returns the [DatabaseHelper] singleton when in local-DB mode, or `null`
  /// when API mode is active.
  DatabaseHelper? get dbHelper => AppState().localDB ? DatabaseHelper() : null;

  /// IMAP client configured from [AppConfig] credentials and server settings.
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
  /// Persists [emailData] to the data source.
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

  /// Retrieves a single email record by [id], with optional join of bill/payment.
  Future<Result<EmailData?>> readEmail(String id, {Map<String, bool>? include, bool queryByEmailId = false}) async {
    final dbHelper = this.dbHelper;
    try {
      EmailData? emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readEmail(id, include: include, queryByEmailId: queryByEmailId);
      } else {
        emailData = await ApiService.emails().getEmail(id, include: include, queryByEmailId: queryByEmailId);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  /// Returns all email records, with optional join of bill/payment.
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

  /// Returns only email records that have not yet been processed (`processed = false`).
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

  /// Returns only email records that have been processed (`processed = true`).
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

  /// Updates [emailData] in the data source.
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

  /// Deletes the email record identified by [emailDataId].
  Future<Result<void>> deleteEmailData(String emailDataId) async {
    final dbHelper = this.dbHelper;
    if (dbHelper != null) {
      await dbHelper.deleteEmailData(emailDataId);
      return Result.success();
    } else {
      final returnValue = await ApiService.emails().deleteEmailData(emailDataId);
      if (returnValue == "OK") {
        return Result.success();
      }
      return Result.error(errorMessage: returnValue);
    }
  }

  /// Deletes all email records from the data source.
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
  /// Fetches recent emails of [type] from the IMAP server, converts each
  /// [MimeMessage] to an [EmailData] record via [EmailParser], and persists any
  /// new records (skipping ones already stored by `emailId`).
  ///
  /// Returns a map of [MimeMessage] → [EmailData] for all messages that were
  /// successfully parsed, whether freshly inserted or already existing in the DB.
  Future<Map<MimeMessage, EmailData>> fetchEmails(EmailType type, {int maxEmails = 50, DateTime? earliestEmailDate}) async {
    Map<MimeMessage, EmailData> finalMessages = {};
    final messages = await emailService.fetchRecentEmails(type, maxEmails: maxEmails, earliestEmailDate: earliestEmailDate);
    for (MimeMessage message in messages) {
      AppLogger().d(
        'Email Parsed: {\n\tFrom: ${message.from}\n\tSubject: ${message.decodeSubject()}\n\tDate: ${message.decodeDate()}\n\tText: ${EmailParser.extractEmailBody(message)}\n}',
      );

      EmailData? emailData = await EmailParser.parseEmailToEmailData(message);
      if (emailData != null) {
        Map<String, bool> include = type == EmailType.bill ? {'bill': true} : {'payment': true};
        Result<EmailData?> result = await readEmail(emailData.getEmailId(), include: include, queryByEmailId: true);
        if (result.isError || result.data == null) {
          Result<EmailData> retVal = await createEmailData(emailData);
          if (retVal.isError) {
            AppLogger().e(retVal.errorMessage);
          }
          finalMessages[message] = emailData;
        } else {
          finalMessages[message] = result.data!;
        }
      }
    }
    return finalMessages;
  }

  /// Fetches bill emails, parses each one into a [Bill] via [BillsParser], and
  /// persists both the bill and an updated [EmailData] record (marked
  /// `processed = true`).  If a bill is already stored (by `billId`), the
  /// email record is simply linked to the existing bill.
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
            AppLogger().d(
              'Bill Parsed: {\n\tID: ${bill.billId}\n\tCompany: ${bill.company}\n\tAmount: ${bill.amount}\n\tBill Type: ${bill.type}\n\tDue Date: ${bill.dueDate}\n\tPayment Status: ${bill.status.name}\n\tNotes: ${bill.notes}\n}',
            );

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
            AppLogger().w('Failed to convert Bill: ${message.decodeSubject()}');
            AppLogger().d('---------------------------------------------------------------------\n\n\n\n\n');
          }
        } else {
          AppLogger().d(
            'Bill Found: {\n\tID: ${bill.id}\n\tCompany: ${bill.company}\n\tAmount: ${bill.amount}\n\tBill Type: ${bill.type}\n\tDue Date: ${bill.dueDate}\n\tPayment Status: ${bill.status.name}\n\tNotes: ${bill.notes}\n}',
          );
          AppLogger().d('---------------------------------------------------------------------\n\n\n\n\n');

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

  /// Fetches payment emails, parses each one into a [Payment] via
  /// [PaymentsParser] (using the full rentor list to match names), and persists
  /// both the payment and the updated [EmailData].  If a payment is already
  /// stored (by `paymentId`), the email is simply linked to the existing record.
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
            AppLogger().d(
              'Payment Parsed: {\n\tID: ${payment.paymentId}\n\tPayment Date: ${payment.paymentDate}\n\tAmount Paid: ${payment.amountPaid}\n\tPaid Rentor: ${payment.rentorName}\n\tBill Paid: \n\t\t${payment.billNames(newLine: true)}\n}',
            );
            AppLogger().d('---------------------------------------------------------------------\n\n\n\n\n');

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
            AppLogger().w('Failed to convert Payment: ${message.decodeSubject()}');
            AppLogger().d('---------------------------------------------------------------------\n\n\n\n\n');
          }
        } else {
          AppLogger().d(
            'Payment Found: {\n\tID: ${payment.paymentId}\n\tPayment Date: ${payment.paymentDate}\n\tAmount Paid: ${payment.amountPaid}\n\tPaid Rentor: ${payment.rentorName}\n\tBill Paid: \n\t\t${payment.billNames(newLine: true)}\n}',
          );
          AppLogger().d('---------------------------------------------------------------------\n\n\n\n\n');

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
