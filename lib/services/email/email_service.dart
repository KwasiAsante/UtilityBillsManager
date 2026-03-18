import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'package:utility_bills_manager/services/email/google_account_service.dart';

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
    if (kIsWeb) {
      return _fetchRecentEmailsFromGmailWeb(maxEmails: maxEmails);
    }

    final client = ImapClient(isLogEnabled: false);
    var didLogin = false;

    try {
      await client.connectToServer(
        imapServer,
        imapPort,
        isSecure: isImapSecure,
      );
      await client.login(email, password);
      didLogin = true;

      final mailboxes = await client.listMailboxes();
      if (mailboxes.isEmpty) {
        return [];
      }
      final billsMailbox = mailboxes.cast<Mailbox>().firstWhere(
        (box) => box.name.toLowerCase() == 'bills',
        orElse: () => mailboxes.first,
      );

      await client.selectMailbox(billsMailbox);

      final fetchResult = await client.fetchRecentMessages(
        messageCount: maxEmails,
        criteria: 'BODY[]',
      );

      return fetchResult.messages;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emails via IMAP: $e');
      }
      return [];
    } finally {
      if (didLogin) {
        try {
          await client.logout();
        } catch (_) {
          // Ignore logout errors during cleanup.
        }
      }
    }
  }

  Future<List<MimeMessage>> _fetchRecentEmailsFromGmailWeb({
    int maxEmails = 100,
  }) async {
    try {
      if (!GoogleAccountService().isInitialized ||
          !GoogleAccountService().isAuthenticated ||
          !GoogleAccountService().isSignedIn) {
        if (kDebugMode) {
          if (!GoogleAccountService().isInitialized) {
            print('Google account is not initialized');
          }
          if (!GoogleAccountService().isAuthenticated) {
            print('Google account is not authenticated');
          }
          if (!GoogleAccountService().isSignedIn) {
            print('Google account is not signed in');
          }
        }
        return [];
      } else if (!GoogleAccountService().isAuthenticated &&
          !GoogleAccountService().isSignedIn) {
        await GoogleAccountService().signIn();
        if (!GoogleAccountService().isSignedIn) {
          return [];
        }
      }

      if (!GoogleAccountService().isAuthorized) {
        await GoogleAccountService().authorize();
        if (!GoogleAccountService().isAuthorized) {
          return [];
        }
      }

      final headers = GoogleAccountService().authorizationHeaders;
      if (headers == null) {
        return [];
      }

      final client = _AuthClient(headers);
      final gmailApi = gmail.GmailApi(client);

      // Adjust Gmail search query as needed for your "bills" mailbox.
      final listResponse = await gmailApi.users.messages.list(
        'me',
        maxResults: maxEmails,
        q: 'label:bills',
      );

      final messageRefs = listResponse.messages ?? const <gmail.Message>[];
      final mimeMessages = <MimeMessage>[];

      for (final ref in messageRefs) {
        if (ref.id == null) continue;
        final msg = await gmailApi.users.messages.get(
          'me',
          ref.id!,
          format: 'raw',
        );

        final raw = msg.raw;
        if (raw == null) continue;

        final bytes = base64Url.decode(raw);
        final text = utf8.decode(bytes);
        final mime = MimeMessage.parseFromText(text);
        mimeMessages.add(mime);
      }

      return mimeMessages;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching emails via Gmail API (web): $e');
      }
      return [];
    }
  }
}

class _AuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
