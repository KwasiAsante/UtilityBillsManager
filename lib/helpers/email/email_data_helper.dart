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

  // #region CRUD Operations
  // #region Email Data
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

  // Retrieve unprocessed Email Data
  Future<Result<EmailData?>> readEmail(int id) async {
    final dbHelper = this.dbHelper;
    try {
      EmailData? emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readEmail(id);
      } else {
        emailData = await ApiService.emails().getEmail(id);
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve unprocessed Email Data
  Future<Result<List<EmailData>>> readEmails() async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readEmails();
      } else {
        emailData = await ApiService.emails().getEmails();
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve unprocessed Email Data
  Future<Result<List<EmailData>>> readUnprocessedEmails() async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readUnprocessedEmails();
      } else {
        emailData = await ApiService.emails().getUnprocessedEmails();
      }
      return Result.success(data: emailData);
    } on Exception catch (e) {
      return Result.exception(exception: e);
    }
  }

  // Retrieve unprocessed Email Data
  Future<Result<List<EmailData>>> readProcessedEmails() async {
    final dbHelper = this.dbHelper;
    try {
      List<EmailData> emailData;
      if (dbHelper != null) {
        emailData = await dbHelper.readProcessedEmails();
      } else {
        emailData = await ApiService.emails().getProcessedEmails();
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
      }
      else {
        return Result.error(errorMessage: returnValue);
      }
    }
  }
  // #endregion

  // #region Email

  Future<Map<MimeMessage, EmailData>> fetchEmails({int maxEmails = 100}) async {
    Map<MimeMessage, EmailData> finalMessages = {};
    final messages = await emailService.fetchRecentEmails(maxEmails: maxEmails);
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
        Result<EmailData?> result = await readEmail(emailData.getEmailId());
        if (result.isError || result.data == null) {
          Result<EmailData> retVal = await createEmailData(emailData);
          if (retVal.isError) {
            if (kDebugMode) {
              print(retVal.errorMessage);
            }
          }
          finalMessages[message] = emailData;
        }
      }
    }
    return finalMessages;
  }

  Future<void> fetchBillEmails({int maxEmails = 100}) async {
    final messages = await fetchEmails(maxEmails: maxEmails);
    if (messages.isNotEmpty) {
      for (MimeMessage message in messages.keys) {
        Bill? bill = await BillsParser.parseEmailToBill(message);
        if (bill != null) {
          if (kDebugMode) {
            print(
              'Bill Parsed: {\n\tID: ${bill.id}\n\tCompany: ${bill.company}\n\tAmount: ${bill.amount}\n\tBill Type: ${bill.type}\n\tDue Date: ${bill.dueDate}\n\tPayment Status: ${bill.status.name}\n\tNotes: ${bill.notes}\n}',
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
                emailSubject: emailData.emailSubject,
                emailBody: emailData.emailBody,
                emailId: emailData.emailId,
                billId: createResult.data!.billId,
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
      }
    }
  }

  // #endregion
  // #endregion
}
