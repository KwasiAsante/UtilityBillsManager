import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../google/google_account_service.dart';
import '../../utils/app_logger.dart';

/// Web implementation of [EmailService].
///
/// Fetches messages via the Gmail REST API using an authorised
/// [GoogleAccountService] session. Each message is retrieved in `raw` format
/// and parsed into a [MimeMessage] so the rest of the app can use the same
/// parsing logic regardless of platform.
class EmailService {
  // IMAP fields are accepted for API compatibility but unused on web.
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

  /// Fetches up to [maxEmails] messages for the given [type] via the Gmail API.
  ///
  /// When [earliestEmailDate] is provided the `after:` / `before:` Gmail search
  /// operators are used to limit the result set.
  Future<List<MimeMessage>> fetchRecentEmails(
      EmailType type, {
        int? maxEmails,
        DateTime? earliestEmailDate,
      }) async {
    try {
      if (!GoogleAccountService().isInitialized ||
          !GoogleAccountService().isAuthenticated ||
          !GoogleAccountService().isSignedIn) {
        if (!GoogleAccountService().isInitialized) {
          AppLogger().w('Google account is not initialized');
        }
        if (!GoogleAccountService().isAuthenticated) {
          AppLogger().w('Google account is not authenticated');
        }
        if (!GoogleAccountService().isSignedIn) {
          AppLogger().w('Google account is not signed in');
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
        query +=
        ' after:${dateFormat.format(earliestEmailDate)} before:${dateFormat.format(DateTime.now())}';
      }
      final listResponse = await gmailApi.users.messages.list(
        'me',
        maxResults: earliestEmailDate == null && maxEmails == null ? 50 : maxEmails,
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
      AppLogger().e('Error fetching emails via Gmail API (web): $e');
      return [];
    }
  }
}

/// Internal [http.BaseClient] that injects OAuth2 authorisation headers into
/// every outgoing request so Gmail API calls are authenticated.
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

/// Distinguishes the two kinds of emails the app imports.
enum EmailType { bill, payment, unknown }

/// Provides [name] (Gmail label) and [fromString] factory for [EmailType].
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