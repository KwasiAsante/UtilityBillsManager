import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:pdfrx/pdfrx.dart';
import 'package:utility_bills_manager/data/models/email_data.dart';

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
    if (kDebugMode) {
      print('Extracting email body');
    }
    final plainBody = message.decodeTextPlainPart();
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      if (kDebugMode) {
        print('Plain body: $plainBody');
      }
      return plainBody;
    }

    final htmlBody = message.decodeTextHtmlPart();
    if (htmlBody != null && htmlBody.trim().isNotEmpty) {
      if (kDebugMode) {
        print('HTML body: $htmlBody');
      }
      // Strip HTML tags and decode entities
      final document = html_parser.parse(htmlBody);
      return document.body?.text ?? '';
    }

    if (kDebugMode) {
      print('No body found');
    }
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
    if (kDebugMode) {
      print('Extracting email attachment');
    }
    for (final part in message.parts!) {
      if (part.mediaType.isApplication) {
        final filename = part.decodeFileName();
        final data = part.decodeContentBinary();
        if (kDebugMode) {
          print('Filename: $filename');
          print('Data: $data');
        }
        if (filename != null && data != null) {
          if (kDebugMode) {
            print('Extracting text from PDF');
          }
          return await extractTextFromPdf(filename, data);
        }
        if (kDebugMode) {
          print('No attachment found');
        }
      }
    }

    if (kDebugMode) {
      print('No attachment found');
    }
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
    if (kDebugMode) {
      print('Extracting text from PDF (${pdfBytes.length} bytes)');
    }
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
      if (kDebugMode) {
        print(
          'Extracted text from PDF (${doc.pages.length} pages, ${text.length} chars)',
        );
      }
      return text;
    } catch (e, st) {
      if (kDebugMode) {
        print('PDF text extraction failed: $e\n$st');
      }
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
    if (kDebugMode) {
      print('Subject: $subject');
    }
    if (subject.contains('Your RBC Royal Bank eStatement is ready') ||
        subject.contains('eStatement Alert for your Simplii Credit Card') ||
        subject.contains('Enbridge - Your Payment is Due')) {
      if (kDebugMode) {
        print('Subject is a known email, skipping');
      }
      return null;
    }

    final hasAttachment = EmailParser.hasAttachment(message);
    if (kDebugMode) {
      print('Has attachment: $hasAttachment');
    }
    final body =
        hasAttachment
            ? await EmailParser.extractEmailAttachment(message)
            : EmailParser.extractEmailBody(message);
    if (kDebugMode) {
      print('Body: $body');
    }
    if (subject.isNotEmpty && body.isNotEmpty) {
      // Generate a stable billId based on email properties that don't change
      final date = message.decodeDate()?.millisecondsSinceEpoch ?? 0;
      final from = message.from?.first.email ?? '';
      if (kDebugMode) {
        print('Date: $date');
        print('From: $from');
      }
      // Combine these stable properties to create a unique hash
      final uniqueString = '$date$from$subject';
      final emailId = uniqueString.hashCode.abs();
      if (kDebugMode) {
        print('Email ID: $emailId');
      }
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
