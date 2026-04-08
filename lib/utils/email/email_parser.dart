import 'dart:typed_data' show Uint8List;

import 'package:enough_mail/enough_mail.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfrx/pdfrx.dart';

import '../app_logger.dart';
import '../constants.dart';
import '../../data/models/email_data.dart';

/// Utility class for extracting structured content from [MimeMessage] objects.
///
/// Covers three extraction paths:
/// - Plain-text / HTML body extraction ([extractEmailBody])
/// - PDF attachment text extraction ([extractEmailAttachment], [extractTextFromPdf])
/// - High-level email → [EmailData] conversion ([parseEmailToEmailData])
///
/// All methods are static; no instance state is needed.
class EmailParser {
  /// Returns the decoded body of [message] as plain text.
  ///
  /// Prefers the plain-text part; falls back to stripping the HTML part.
  /// Returns an empty string if neither part is present.
  static String extractEmailBody(MimeMessage message) {
    AppLogger().d('Extracting email body');
    final plainBody = message.decodeTextPlainPart();
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      AppLogger().d('Plain body: $plainBody');
      return plainBody;
    }

    final htmlBody = message.decodeTextHtmlPart();
    if (htmlBody != null && htmlBody.trim().isNotEmpty) {
      AppLogger().d('HTML body: $htmlBody');
      // Strip HTML tags and decode entities
      final document = html_parser.parse(htmlBody);
      return document.body?.text ?? '';
    }

    AppLogger().d('No body found');
    return '';
  }

  /// Returns `true` if [message] has a non-empty plain-text part.
  static bool isBodyPlainText(MimeMessage message) {
    final plainBody = message.decodeTextPlainPart();
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      return true;
    }

    return false;
  }

  /// Returns `true` if [message] has a non-empty HTML part.
  static bool isBodyHTML(MimeMessage message) {
    final htmlBody = message.decodeTextHtmlPart();
    if (htmlBody != null && htmlBody.trim().isNotEmpty) {
      // Strip HTML tags and decode entities
      final document = html_parser.parse(htmlBody);
      return document.body != null && document.body!.text.isNotEmpty;
    }

    return false;
  }

  /// Returns `true` if [message] contains an application attachment (e.g. PDF).
  static bool hasAttachment(MimeMessage message) {
    if (message.parts != null) {
      for (final part in message.parts!) {
        if (part.mediaType.isApplication) {
          final filename = part.decodeFileName();
          final data = part.decodeContentBinary();
          return filename != null && data != null;
        }
      }
    }

    return false;
  }

  /// Extracts the text content of the first application attachment in [message].
  ///
  /// Currently handles PDF files by delegating to [extractTextFromPdf].
  /// Returns an empty string if no suitable attachment is found.
  static Future<String> extractEmailAttachment(MimeMessage message) async {
    AppLogger().d('Extracting email attachment');
    for (final part in message.parts!) {
      if (part.mediaType.isApplication) {
        final filename = part.decodeFileName();
        final data = part.decodeContentBinary();
        AppLogger().d('Filename: $filename');
        AppLogger().d('Data: $data');
        if (filename != null && data != null) {
          AppLogger().d('Extracting text from PDF');
          return await extractTextFromPdf(filename, data);
        }
        AppLogger().d('No attachment found');
      }
    }

    AppLogger().d('No attachment found');
    return '';
  }

  /// Extracts plain text from PDF bytes on **web, mobile, and desktop**.
  ///
  /// Uses [pdfrx] with [PdfDocument.openData] so no temp file or platform
  /// channel is required. On web, ensure pdfrx WASM is set up for production
  /// (see pdfrx README).
  static Future<String> extractTextFromPdf(
    String filename,
    Uint8List pdfBytes,
  ) async {
    AppLogger().d('Extracting text from PDF (${pdfBytes.length} bytes)');
    await pdfrxFlutterInitialize();

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(
        pdfBytes,
        sourceName: filename,
      );
      final buffer = StringBuffer();
      for (final page in doc.pages) {
        final raw = await page.loadText();
        if (raw != null && raw.fullText.trim().isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.writeln();
          }
          buffer.write(raw.fullText);
        }
      }
      final text = buffer.toString();
      AppLogger().d('Extracted text from PDF (${doc.pages.length} pages, ${text.length} chars)');
      return text;
    } catch (e, st) {
      AppLogger().e('PDF text extraction failed', error: e, stackTrace: st);
      return '';
    } finally {
      await doc?.dispose();
    }
  }

  /// Converts a [MimeMessage] into an [EmailData] record, or returns `null` for
  /// known irrelevant email subjects.
  ///
  /// The stable numeric [EmailData.emailId] is derived from a hash of the
  /// message date, sender, and subject so that the same email is never
  /// imported twice.
  static Future<EmailData?> parseEmailToEmailData(MimeMessage message) async {
    final subject = message.decodeSubject() ?? '';
    final sender = message.from?.firstOrNull?.email ?? '';

    AppLogger().d('Subject: $subject');
    AppLogger().d('Sender: $sender');

    if (AppConstants.invalidEmailSubjects.any((sub) => subject.contains(sub)) ||
        AppConstants.invalidEmailSenders.any((send) => sender.contains(send))) {
      AppLogger().d('Email subject or sender is in the invalid list, skipping email');
      return null;
    }

    final hasAttachment = EmailParser.hasAttachment(message);
    AppLogger().d('Has attachment: $hasAttachment');
    final body =
        hasAttachment
            ? await EmailParser.extractEmailAttachment(message)
            : EmailParser.extractEmailBody(message);
    AppLogger().d('Body: $body');
    if (subject.isNotEmpty && body.isNotEmpty) {
      // Generate a stable billId based on email properties that don't change
      final date = message.decodeDate()?.millisecondsSinceEpoch ?? 0;
      final from = message.from?.first.email ?? '';
      AppLogger().d('Date: $date');
      AppLogger().d('From: $from');
      // Combine these stable properties to create a unique hash
      final uniqueString = '$date$from$subject';
      final emailId = uniqueString.hashCode.abs();
      AppLogger().d('Email ID: $emailId');
      return EmailData(
        emailSubject: subject,
        emailBody: body,
        emailId: emailId,
        processed: false,
      );
    }

    return null; // Couldn't extract a valid bill
  }
}
