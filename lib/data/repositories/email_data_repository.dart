import 'package:flutter/foundation.dart';
import '../models/email_data.dart';
import '../models/result.dart';
import '../../helpers/email/email_data_helper.dart';

/// Singleton [ChangeNotifier] repository that manages the in-memory list of
/// [EmailData] records and delegates persistence to [EmailDataHelper].
///
/// Screens subscribe via `context.watch<EmailDataRepository>()`. Any mutating
/// operation automatically calls [reload] so the list stays current before
/// [notifyListeners] fires.
class EmailDataRepository extends ChangeNotifier {
  static final EmailDataRepository _instance = EmailDataRepository._internal();
  factory EmailDataRepository() => _instance;
  EmailDataRepository._internal();

  final EmailDataHelper _helper = EmailDataHelper();

  /// The current list of email records held in memory.
  List<EmailData> emails = [];

  /// The error message from the most recent failed operation, or `null` if the
  /// last operation succeeded.
  String? lastError;

  /// Fetches all email records from the database and refreshes [emails].
  ///
  /// Always calls [notifyListeners] regardless of outcome.
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

  /// Persists a new [emailData] record to the database and reloads on success.
  Future<Result<EmailData>> create(EmailData emailData) async {
    final result = await _helper.createEmailData(emailData);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Updates an existing [emailData] record and reloads the list on success.
  Future<Result<EmailData>> update(EmailData emailData) async {
    final result = await _helper.updateEmailData(emailData);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes the email record identified by [emailDataId] and reloads on success.
  Future<Result<void>> delete(String emailDataId) async {
    final result = await _helper.deleteEmailData(emailDataId);
    if (result.isSuccess) await reload();
    return result;
  }

  /// Deletes all email records from the data source and clears the in-memory list.
  Future<Result<void>> deleteAll() async {
    final result = await _helper.deleteAllEmails();
    if (result.isSuccess) await reload();
    return result;
  }
}
