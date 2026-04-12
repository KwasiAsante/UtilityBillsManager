/// App-wide constants shared across screens and utilities.
///
/// - [monthNames] — ordered list of month display names.
/// - [invalidEmailSubjects] / [invalidEmailSenders] — denylist entries used by
///   [BillsParser] and [EmailParser] to skip non-bill / non-payment emails
///   (e.g. bank statements, payment-received confirmations) before attempting
///   to parse amounts or dates.
abstract final class AppConstants {
  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// Email subjects that are known to be irrelevant (statements, receipts, etc.)
  /// and should be skipped during the import pipeline.
  static const List<String> invalidEmailSubjects = [
    'Your RBC Royal Bank eStatement is ready',
    'eStatement Alert for your Simplii Credit Card',
    'Enbridge - Your Payment is Due',
    'Your Freedom Mobile bill is ready',
    'Payment received on your credit account',
    'Your credit account: Payment due in'
  ];

  /// Sender email addresses whose messages should always be skipped.
  static const List<String> invalidEmailSenders = [
    'info@neofinancial.com',
  ];
}

