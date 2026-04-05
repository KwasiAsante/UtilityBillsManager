import 'package:flutter/foundation.dart';
import '../models/email_data.dart';
import '../models/result.dart';
import '../../helpers/email/email_data_helper.dart';

class EmailDataRepository extends ChangeNotifier {
  static final EmailDataRepository _instance = EmailDataRepository._internal();
  factory EmailDataRepository() => _instance;
  EmailDataRepository._internal();

  final EmailDataHelper _helper = EmailDataHelper();

  List<EmailData> emails = [];
  String? lastError;

  Future<void> reload() async {
    final result = await _helper.readEmails();
    if (result.isSuccess) {
      emails = result.data!;
      lastError = null;
    } else {
      lastError = result.errorMessage;
    }
    notifyListeners();
  }

  Future<Result<EmailData>> create(EmailData emailData) async {
    final result = await _helper.createEmailData(emailData);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<EmailData>> update(EmailData emailData) async {
    final result = await _helper.updateEmailData(emailData);
    if (result.isSuccess) await reload();
    return result;
  }

  Future<Result<void>> deleteAll() async {
    final result = await _helper.deleteAllEmails();
    if (result.isSuccess) await reload();
    return result;
  }
}
