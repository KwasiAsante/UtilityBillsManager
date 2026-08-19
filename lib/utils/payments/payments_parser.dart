import 'package:enough_mail/enough_mail.dart';
import 'package:intl/intl.dart';

import '../email/email_parser.dart';
import '../../data/models/rentor.dart';
import '../../data/models/payment.dart';


/// Utility class that converts a raw [MimeMessage] into a [Payment].
///
/// Works symmetrically to [BillsParser]: it extracts a dollar amount and
/// payment date from the email body (or PDF attachment), and optionally
/// matches the sender / subject / body against known [Rentor] names to
/// associate the payment with a tenant.
///
/// All methods are static; no instance state is needed.
class PaymentsParser {
  /// Parses [message] into a [Payment], or returns `null` if no dollar amount
  /// could be extracted.
  ///
  /// Pass [rentors] to enable automatic rentor matching via [extractRentor].
  static Future<Payment?> parseEmailToPayment(MimeMessage message, {List<Rentor>? rentors}) async {
    final subject = message.decodeSubject() ?? '';
    final sender = message.from?.firstOrNull?.email ?? '';

    final hasAttachment = EmailParser.hasAttachment(message);
    final body =
    hasAttachment
        ? await EmailParser.extractEmailAttachment(message)
        : EmailParser.extractEmailBody(message);

    // Try to extract amount from the body or subject
    final amount = extractSmartAmount(body);

    // Attempt to extract a date
    final paymentDate = message.decodeDate() != null ? DateFormat('yyyy-MM-dd').format(message.decodeDate()!) : null;

    final rentor = extractRentor(rentors, sender: sender, subject: subject, body: body);

    if (amount != null) {
      return Payment(
        amountPaid: amount,
        paymentDate: paymentDate != null ? DateTime.parse(paymentDate) : DateTime.now(),
        rentor: rentor,
        rentorId: rentor?.rentorId
      );
    }

    return null; // Couldn't extract a valid payment
  }

  /// Simple dollar-amount extractor (mirrors [BillsParser.extractAmount]).
  static double? extractAmount(String text) {
    // Look for explicit dollar amounts first, e.g. $123.45
    final dollarPattern = RegExp(r'\$\s?(\d+[.,]?\d{0,2})');
    final fallbackPattern = RegExp(
      r'\b(\d{2,5}[.,]?\d{0,2})\b',
    ); // fallback for amounts without $

    final dollarMatch = dollarPattern.firstMatch(text);
    if (dollarMatch != null) {
      return _parseSignedAmount(text, dollarMatch);
    }

    final fallbackMatch = fallbackPattern.firstMatch(text);
    if (fallbackMatch != null) {
      return _parseSignedAmount(text, fallbackMatch);
    }

    return null;
  }

  /// Parses the digits captured by [match] (found within [source]) and
  /// negates the result if a `-` immediately precedes the match — the
  /// amount regexes above only capture digits, so a leading sign (before an
  /// optional `$`) is never part of the capture group itself.
  static double? _parseSignedAmount(String source, Match match) {
    final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
    if (value == null) return null;
    final isNegative = match.start > 0 && source[match.start - 1] == '-';
    return isNegative ? -value : value;
  }

  /// Context-aware amount extractor (mirrors [BillsParser.extractSmartAmount]).
  static double? extractSmartAmount(String text) {
    final prioritizedKeywords = [
      'total due',
      'amount due',
      'current charges',
      'total balance',
      'balance due',
      'payment due',
      'a minimum payment of',
      'account balance',
      'total amount',
    ];

    final normalizedText =
    text.replaceAll(RegExp(r'[\u00A0\u2007\u202F]'), ' ').toLowerCase();
    final lines = normalizedText.split('\n');
    lines.removeWhere((str) => str == "" || str.isEmpty);
    final keywordAmountPattern = RegExp(r'(?:\$\s?)?(\d{1,5}(?:[.,]\d{2})?)\b');
    final dollarPattern = RegExp(r'\$\s?(\d{1,5}(?:[.,]\d{2})?)');

    // 1. Look for matching lines that contain keywords + dollar amounts
    for (final line in lines) {
      if (prioritizedKeywords.any((keyword) => line.contains(keyword))) {
        final match = keywordAmountPattern.firstMatch(line);
        if (match != null) {
          return _parseSignedAmount(line, match);
        } else {
          final amount = getAmountFromNextIndex(
            keywordAmountPattern,
            lines.indexOf(line),
            lines,
          );
          if (amount != null) {
            return amount;
          }
        }
      }
    }

    // 2. Fallback: use the **last** unique dollar amount from the text
    final matches = dollarPattern.allMatches(text);
    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      return _parseSignedAmount(text, lastMatch);
    }

    return null;
  }

  /// Looks for a [pattern] match in the 1–2 lines immediately after [index].
  static double? getAmountFromNextIndex(RegExp pattern, int index, List<String> lines) {
    int updatedIndex = index + 1;
    var line = lines[updatedIndex];
    var match = pattern.firstMatch(line);
    if (match != null) {
      return _parseSignedAmount(line, match);
    } else {
      updatedIndex++;
      line = lines[updatedIndex];
      match = pattern.firstMatch(line);
      if (match != null) {
        return _parseSignedAmount(line, match);
      } else if (double.tryParse(line) != null) {
        return double.tryParse(line);
      } else {
        return null;
      }
    }
  }

  /// Finds the first [Rentor] in [rentors] whose name appears (case-insensitive)
  /// in the email [sender], [subject], or [body].  Returns `null` if no match
  /// is found or [rentors] is empty.
  static Rentor? extractRentor(List<Rentor>? rentors, {String? sender, String? subject, String? body}) {
    if (rentors == null || rentors.isEmpty) {
      return null;
    }
    final senderL = sender?.toLowerCase() ?? '';
    final subjectL = subject?.toLowerCase() ?? '';
    final bodyL = body?.toLowerCase() ?? '';

    Rentor matchingRentor = rentors.firstWhere((rentor) =>
    senderL.contains(rentor.name.toLowerCase()) ||
        subjectL.contains(rentor.name.toLowerCase()) ||
        bodyL.contains(rentor.name.toLowerCase()),
    orElse: () => Rentor(name: 'Unknown Rentor', defaultPercentage: 0.0, billPercentages: {}));

    return matchingRentor.id != null ? matchingRentor : null;
  }
}
