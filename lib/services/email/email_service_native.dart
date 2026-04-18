import 'package:enough_mail/enough_mail.dart';

import '../../utils/app_logger.dart';

/// Native implementation of [EmailService] for Android, iOS, macOS, Windows,
/// and Linux.
///
/// Connects directly to the IMAP server specified by [imapServer] / [imapPort]
/// using the `enough_mail` library. No Google sign-in dependency.
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

  /// Fetches up to [maxEmails] messages from the IMAP mailbox folder
  /// corresponding to [type].
  ///
  /// When [earliestEmailDate] is provided, an IMAP `SEARCH SINCE … BEFORE …`
  /// query is used to limit results before fetching.
  Future<List<MimeMessage>> fetchRecentEmails(
    EmailType type, {
    int? maxEmails,
    DateTime? earliestEmailDate,
  }) async {
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
              before: now.add(
                const Duration(days: 1),
              ), // BEFORE is exclusive in IMAP
            ),
          );

          final matchingSequence = searchResult.matchingSequence;
          if (matchingSequence != null &&
              matchingSequence.isNotEmpty &&
              !matchingSequence.isNil) {
            // Get message IDs and limit to maxEmails (newest ones)
            final allIds = matchingSequence.toList();
            final startIdx = maxEmails != null && allIds.length > maxEmails
                ? allIds.length - maxEmails
                : 0;
            final limitedIds = allIds.sublist(startIdx);

            // Fetch the limited set of messages
            fetchResult = await client.fetchMessages(
              MessageSequence.fromIds(limitedIds),
              'BODY[]',
            );
          }
        } catch (e) {
          AppLogger().w(
            'SEARCH failed, falling back to fetchRecentMessages: $e',
          );
        }
      } else {
        fetchResult = await client.fetchRecentMessages(
          messageCount: maxEmails ?? 50,
          criteria: 'BODY[]',
        );
      }

      return fetchResult?.messages ?? [];
    } catch (e) {
      AppLogger().e('Error fetching emails via IMAP: $e');
      return [];
    } finally {
      if (didLogin) {
        try {
          await client.logout();
        } catch (e) {
          AppLogger().e('Error logging out of IMAP server: $e');
        }
      }
    }
  }
}

/// Distinguishes the two kinds of emails the app imports.
enum EmailType { bill, payment, unknown }

/// Provides [name] (IMAP mailbox name) and [fromString] factory for
/// [EmailType].
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
