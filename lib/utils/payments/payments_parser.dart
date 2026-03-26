import 'package:enough_mail/enough_mail.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/utils/email/email_parser.dart';

import '../../data/models/rentor.dart';

class PaymentsParser {
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
        paymentDate: paymentDate,
        rentor: rentor,
        rentorId: rentor?.rentorId
      );
    }

    return null; // Couldn't extract a valid payment
  }

  static double? extractAmount(String text) {
    // Look for explicit dollar amounts first, e.g. $123.45
    final dollarPattern = RegExp(r'\$\s?(\d+[.,]?\d{0,2})');
    final fallbackPattern = RegExp(
      r'\b(\d{2,5}[.,]?\d{0,2})\b',
    ); // fallback for amounts without $

    final dollarMatch = dollarPattern.firstMatch(text);
    if (dollarMatch != null) {
      return double.tryParse(dollarMatch.group(1)!.replaceAll(',', ''));
    }

    final fallbackMatch = fallbackPattern.firstMatch(text);
    if (fallbackMatch != null) {
      return double.tryParse(fallbackMatch.group(1)!.replaceAll(',', ''));
    }

    return null;
  }

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
          return double.tryParse(match.group(1)!.replaceAll(',', ''));
        } else {
          final amount = getAmountFromNextIndex(
            keywordAmountPattern,
            lines.indexOf(line),
            lines,
          );
          if (amount != null && amount >= 0.00) {
            return amount;
          }
        }
      }
    }

    // 2. Fallback: use the **last** unique dollar amount from the text
    final matches = dollarPattern.allMatches(text);
    if (matches.isNotEmpty) {
      final lastMatch = matches.last;
      return double.tryParse(lastMatch.group(1)!.replaceAll(',', ''));
    }

    return null;
  }

  static double? getAmountFromNextIndex(RegExp pattern, int index, List<String> lines) {
    int updatedIndex = index + 1;
    var line = lines[updatedIndex];
    var match = pattern.firstMatch(line);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', ''));
    } else {
      updatedIndex++;
      line = lines[updatedIndex];
      match = pattern.firstMatch(line);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', ''));
      } else if (double.tryParse(line) != null) {
        return double.tryParse(line);
      } else {
        return null;
      }
    }
  }

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
