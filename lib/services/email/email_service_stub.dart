import 'package:enough_mail/enough_mail.dart';

/// Stub implementation of [EmailService].
///
/// Fallback when neither [dart.library.html] nor [dart.library.io] is
/// available. Should never be reached at runtime, but satisfies the analyser
/// on unknown platforms.
class EmailService {
  final String email;
  final String password;
  final String imapServer;
  final int imapPort;
  final bool isImapSecure;

  EmailService({
    required this.email,
    required this.password,
    required this.imapServer,
    this.imapPort = 993,
    this.isImapSecure = true,
  });

  Future<List<MimeMessage>> fetchRecentEmails(
      EmailType type, {
        int? maxEmails,
        DateTime? earliestEmailDate,
        DateTime? latestEmailDate,
      }) async =>
      [];
}

enum EmailType { bill, payment, unknown }

extension EmailTypeExtension on EmailType {
  String get name {
    switch (this) {
      case EmailType.bill:
        return 'bills';
      case EmailType.payment:
        return 'bills-tenant-bills';
      default:
        return 'unknown';
    }
  }

  static EmailType fromString(String type) => EmailType.unknown;
}