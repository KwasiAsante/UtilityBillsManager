import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:utility_bills_manager/data/models/bill.dart';
import 'package:utility_bills_manager/data/models/payment.dart';
import 'package:utility_bills_manager/utils/email/email_parser.dart';

/// Utility class that converts a raw [MimeMessage] into a [Bill].
///
/// The parser performs three steps:
/// 1. **Filter** — reject known irrelevant senders / subjects (e.g. bank
///    statements, credit-card payment confirmations) to avoid false positives.
/// 2. **Extract** — pull a dollar amount and due date from the email body
///    (or PDF attachment text).
/// 3. **Infer** — guess the [BillType] from keywords in the combined
///    sender + subject + body text.
///
/// All methods are static; no instance state is needed.
class BillsParser {
  /// Parses [message] into a [Bill], or returns `null` if the message is
  /// irrelevant or no dollar amount could be extracted.
  static Future<Bill?> parseEmailToBill(MimeMessage message) async {
    final subject = message.decodeSubject() ?? '';
    final sender = message.from?.firstOrNull?.email ?? '';

    if (subject.contains('Your RBC Royal Bank eStatement is ready') ||
        subject.contains('eStatement Alert for your Simplii Credit Card') ||
        subject.contains('Enbridge - Your Payment is Due') ||
        subject.contains('Your Freedom Mobile bill is ready') ||
        subject.contains('Your Bell bill is ready') ||
        subject.contains('Payment received on your credit account') ||
        subject.contains('Your credit account: Payment due in') ||
        sender.contains('info@neofinancial.com')) {
      return null;
    }

    if (sender.contains('neofinancial')) {
      if (kDebugMode) {
        print('breakpoint');
      }
    }

    final hasAttachment = EmailParser.hasAttachment(message);
    final body =
        hasAttachment
            ? await EmailParser.extractEmailAttachment(message)
            : EmailParser.extractEmailBody(message);

    // Try to extract amount from the body or subject
    final amount = extractSmartAmount(body);

    // Attempt to extract a date
    final dueDate =
        extractDueDate(body)?.toIso8601String().split('T').first ??
        DateTime.now().toIso8601String().split('T').first;

    // Guess the bill type
    final billType = _inferBillType(sender, subject, body);

    if (amount != null) {
      return Bill(
        company: sender,
        type: billType,
        amount: amount,
        dueDate: DateTime.parse(dueDate),
        status: amount <= 0 ? PaymentStatus.paid : PaymentStatus.unpaid,
        notes: subject,
      );
    }

    return null; // Couldn't extract a valid bill
  }

  /// Infers a [BillType] by checking the combined [sender] + [subject] + [body]
  /// text for keywords associated with each utility category.
  static BillType _inferBillType(String sender, String subject, String body) {
    final text = '$sender $subject $body'.toLowerCase();

    if (text.contains('hydro') ||
        text.contains('electric') ||
        sender.contains('noreply@alectrautilities.com')) {
      return BillType.electric;
    }
    if (text.contains('gas') ||
        sender.contains('NoReplyCCC@ngutech.com') ||
        sender.contains('enbridge.e-bill@enbridgegas.com')) {
      return BillType.gas;
    }
    if (text.contains('water') ||
        (sender.contains('donotreply@kubra.peelregion.ca') &&
            subject.contains(
              'Region of Peel water e-bill account - your bill is ready',
            ))) {
      return BillType.water;
    }
    if (text.contains('internet') ||
        text.contains('wifi') ||
        sender.contains('ebill@bell.ca')) {
      return BillType.internet;
    }
    if (text.contains('phone') || sender.contains('noreply@freedommobile.ca')) {
      return BillType.phone;
    }
    if (text.contains('rent')) return BillType.rent;
    if (text.contains('creditcard') ||
        text.contains('credit card') ||
        text.contains('your credit statement is available')) {
      return BillType.creditcard;
    }
    if (text.contains('personallineofcredit') ||
        text.contains('personal line of credit')) {
      return BillType.personallineofcredit;
    }

    return BillType.other;
  }

  /// Simple dollar-amount extractor.  Prefers explicit `$`-prefixed amounts;
  /// falls back to bare numeric strings if none are found.
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

  /// Context-aware dollar-amount extractor.
  ///
  /// Strategy:
  /// 1. Split the normalised text into lines and look for a line that contains
  ///    one of the [prioritizedKeywords] (e.g. "total due", "amount due").
  ///    If found, try to parse a number from the same line, or from the
  ///    following 1–2 lines via [getAmountFromNextIndex].
  /// 2. Fall back to the last `$`-prefixed amount in the entire text if no
  ///    keyword match produced a result.
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

  /// Looks for a [pattern] match in the 1–2 lines immediately after [index] in
  /// [lines].  Returns the parsed double, or `null` if nothing matches.
  static double? getAmountFromNextIndex(
    RegExp pattern,
    int index,
    List<String> lines,
  ) {
    int updatedIndex = index + 1;
    if (updatedIndex >= lines.length) return null;
    var line = lines[updatedIndex];
    var match = pattern.firstMatch(line);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', ''));
    } else {
      updatedIndex++;
      if (updatedIndex >= lines.length) return null;
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

  /// Extracts a due date from [text] using keyword-anchored line scanning.
  ///
  /// Strategy mirrors [extractSmartAmount]:
  /// 1. Scan lines for a keyword (e.g. "due date", "payment due") and parse a
  ///    date from that line or the following 1–2 lines.
  /// 2. Fall back to the last recognisable date anywhere in the text.
  static DateTime? extractDueDate(String text) {
    final prioritizedKeywords = [
      'payment due date',
      'due date',
      'invoice due',
      'payment due',
      'due by',
      'your balance will be withdrawn on',
      'withdrawn on',
      'payment date'
    ];

    final lines = text.toLowerCase().split('\n');
    lines.removeWhere((str) => str == "" || str.isEmpty);
    final datePatterns = [
      RegExp(r'(\d{4}-\d{2}-\d{2})'), // Match date format YYYY-MM-DD
      RegExp(r'(\d{4}\s+\d{2}\s+\d{2})'), // Match date format YYYY MM DD
      RegExp(
        r'([a-zA-Z]+ \d{1,2}(?:st|nd|rd|th)?,? \d{4})',
        caseSensitive: false,
      ), // April 24th, 2025
      RegExp(r'(\d{1,2} [a-zA-Z]+ \d{4})'), // 24 April 2025
      RegExp(
        r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}\s+\d{4}\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2},\s+\d{4}\b',
        caseSensitive: false,
      ),
    ];

    // 1. Look for matching lines that contain keywords + dates
    for (final line in lines) {
      if (line.isEmpty) {
        continue;
      }

      if (prioritizedKeywords.any((keyword) => line.contains(keyword))) {
        for (final datePattern in datePatterns) {
          final match = datePattern.firstMatch(line);
          if (match != null) {
            String s = match.group(1)!;
            DateTime? d = DateTime.tryParse(s);
            d ??= parseFancyDate(s);
            return d;
          } else {
            final date = getDateFromNextIndex(
              datePattern,
              lines.indexOf(line),
              lines,
            );
            if (date != null) {
              return date;
            }
          }
        }
      }
    }

    // 2. Fallback: try to find any date in the text
    for (final datePattern in datePatterns) {
      final matches = datePattern.allMatches(text);
      if (matches.isNotEmpty) {
        final lastMatch = matches.last;
        return DateTime.tryParse(lastMatch.group(1)!);
      }
    }

    return null;
  }

  /// Looks for a [pattern] date match in the 1–2 lines immediately after
  /// [index] in [lines].  Returns the parsed [DateTime], or `null` if nothing
  /// matches.
  static DateTime? getDateFromNextIndex(
    RegExp pattern,
    int index,
    List<String> lines,
  ) {
    int updatedIndex = index + 1;
    if (updatedIndex >= lines.length) return null;
    var line = lines[updatedIndex];
    line = line.replaceAll(RegExp(r','), "");
    var match = pattern.firstMatch(line);
    if (match != null) {
      String s = match.group(0)!;
      DateTime? d = DateTime.tryParse(s);
      d ??= parseFancyDate(s);
      return d;
    } else {
      updatedIndex++;
      if (updatedIndex >= lines.length) return null;
      line = lines[updatedIndex];
      match = pattern.firstMatch(line);
      if (match != null) {
        String s = match.group(0)!;
        DateTime? d = DateTime.tryParse(s);
        d ??= parseFancyDate(s);
        return d;
      } else if (DateTime.tryParse(line) != null) {
        return DateTime.tryParse(line);
      } else if (parseFancyDate(line) != null) {
        return parseFancyDate(line);
      } else {
        return null;
      }
    }
  }

  /// Parses human-friendly date strings such as "April 24th, 2025" or
  /// "Apr 24 2025" that [DateTime.tryParse] cannot handle natively.
  ///
  /// Strips ordinal suffixes (st, nd, rd, th) and tries a series of
  /// [DateFormat] patterns until one succeeds.
  static DateTime? parseFancyDate(String text) {
    // Remove ordinal suffixes (st, nd, rd, th)
    final cleaned = text.replaceAllMapped(
      RegExp(r'(\d+)(st|nd|rd|th)', caseSensitive: false),
      (match) => match.group(1)!,
    );

    // Capitalize first letter of the month (if not already)
    final normalized = cleaned.replaceFirstMapped(
      RegExp(r'^[a-zA-Z]'),
      (match) => match.group(0)!.toUpperCase(),
    );

    // Define supported date formats
    final formats = [
      DateFormat("MMMM d, yyyy"), // April 24, 2025
      DateFormat("MMM d, yyyy"), // Apr 24, 2025
      DateFormat("MMM d yyyy"), // Apr 24 2025
      DateFormat("yyyy MM dd"), // 2026 03 23
    ];

    // Try parsing with each format
    for (var format in formats) {
      try {
        return format.parseStrict(normalized);
      } catch (_) {
        // Ignore and try the next format
      }
    }

    return null;
  }
}
