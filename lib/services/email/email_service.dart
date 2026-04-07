import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
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

  Future<List<MimeMessage>> fetchRecentEmails(EmailType type, {int maxEmails = 50, DateTime? earliestEmailDate}) async {
    if (kIsWeb) {
      return _fetchRecentEmailsFromGmailWeb(type, maxEmails: maxEmails, earliestEmailDate: earliestEmailDate);
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
        (box) => box.name.toLowerCase() == type.name,
        orElse: () => mailboxes.first,
      );

      await client.selectMailbox(billsMailbox);

      FetchImapResult? fetchResult;

      if (earliestEmailDate != null) {
        try {
          // Search for messages within date range using IMAP SEARCH
          final now = DateTime.now();

          final searchResult = await client.searchMessagesWithQuery(
            SearchQueryBuilder.from(
              '',
              SearchQueryType.allTextHeaders,
              since: earliestEmailDate,
              before: now.add(const Duration(days: 1)), // BEFORE is exclusive in IMAP
            ),
          );

          final matchingSequence = searchResult.matchingSequence;
          if (matchingSequence != null && matchingSequence.isNotEmpty && !matchingSequence.isNil) {
            // Get message IDs and limit to maxEmails (newest ones)
            final allIds = matchingSequence.toList();
            final startIdx = allIds.length > maxEmails ? allIds.length - maxEmails : 0;
            final limitedIds = allIds.sublist(startIdx);

            // Fetch the limited set of messages
            fetchResult = await client.fetchMessages(
              MessageSequence.fromIds(limitedIds),
              'BODY[]',
            );
          }
        } catch (e) {
          if (kDebugMode) {
            print('SEARCH failed, falling back to fetchRecentMessages: $e');
          }
        }
      }
      else {
        fetchResult = await client.fetchRecentMessages(
          messageCount: maxEmails,
          criteria: 'BODY[]',
        );
      }

      return fetchResult?.messages ?? [];
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

  Future<List<MimeMessage>> _fetchRecentEmailsFromGmailWeb(EmailType type, {int maxEmails = 50, DateTime? earliestEmailDate}) async {
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

      // Adjust Gmail search query as needed for your mailbox.
      String query = 'label:${type.name}';
      if (earliestEmailDate != null) {
        var dateFormat = DateFormat('yyyy/MM/dd');
        // Gmail: after:<older-date> before:<newer-date>
        query += ' after:${dateFormat.format(earliestEmailDate)} before:${dateFormat.format(DateTime.now())}';
      }
      final listResponse = await gmailApi.users.messages.list(
        'me',
        maxResults: maxEmails,
        q: query,
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

      client.close();

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

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

enum EmailType {
  bill,
  payment,
  unknown,
}

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

  static EmailType fromString(String type) {
    switch (type.toLowerCase()) {
      case 'bill':
      case 'bills':
        return EmailType.bill;
      case 'payment':
      case 'payments':
      case 'bill payment':
      case 'bill payments':
      case 'bill_payment':
      case 'bill_payments':
      case 'bill-payment':
      case 'bill-payments':
      case 'bills-bill-payment':
      case 'bill-bill-payments':
        return EmailType.payment;
      default:
        return EmailType.unknown;
    }
  }
}
