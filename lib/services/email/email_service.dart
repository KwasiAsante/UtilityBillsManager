
import 'package:flutter/foundation.dart';
import 'package:enough_mail/enough_mail.dart';

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

  Future<List<MimeMessage>> fetchRecentEmails({int maxEmails = 100}) async {
    final client = ImapClient(isLogEnabled: false);

    try {
      await client.connectToServer(imapServer, imapPort, isSecure: isImapSecure);
      await client.login(email, password);

      final mailboxes = await client.listMailboxes();
      final inbox = mailboxes.firstWhere((box) => box.name.toLowerCase() == 'bills');

      await client.selectMailbox(inbox);

      final fetchResult = await client.fetchRecentMessages(
        messageCount: maxEmails,
        criteria: 'BODY[]'
      );

      return fetchResult.messages;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emails: $e');
      }
      return [];
    } finally {
      await client.logout();
    }
  }
}
