import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:utility_bills_manager/data/models/email_data.dart';
import 'package:utility_bills_manager/utils/files/file_utils.dart';
import 'package:utility_bills_manager/utils/files/native_pdf_text_extractor.dart';

class EmailParser {
  static String extractEmailBody(MimeMessage message) {
    final plainBody = message.decodeTextPlainPart();
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      return plainBody;
    }

    final htmlBody = message.decodeTextHtmlPart();
    if (htmlBody != null && htmlBody.trim().isNotEmpty) {
      // Strip HTML tags and decode entities
      final document = html_parser.parse(htmlBody);
      return document.body?.text ?? '';
    }

    return '';
  }

  static bool isBodyPlainText(MimeMessage message) {
    final plainBody = message.decodeTextPlainPart();
    if (plainBody != null && plainBody.trim().isNotEmpty) {
      return true;
    }

    return false;
  }

  static bool isBodyHTML(MimeMessage message) {
    final htmlBody = message.decodeTextHtmlPart();
    if (htmlBody != null && htmlBody.trim().isNotEmpty) {
      // Strip HTML tags and decode entities
      final document = html_parser.parse(htmlBody);
      return document.body != null && document.body!.text.isNotEmpty;
    }

    return false;
  }

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

  static Future<String> extractEmailAttachment(MimeMessage message) async {
    for (final part in message.parts!) {
      if (part.mediaType.isApplication) {
        final filename = part.decodeFileName();
        final data = part.decodeContentBinary();
        if (filename != null && data != null) {
          return await extractTextFromPdf(filename, data);
        }
      }
    }

    return '';
  }

  static Future<String> extractTextFromPdf(
    String filename,
    Uint8List pdfBytes,
  ) async {
    final doc = await FileUtils.savePdfTemp(pdfBytes, filename);
    final text = await NativePdfTextExtractor.extractTextFromPdf(doc);
    return text;
  }

  static Future<EmailData?> parseEmailToEmailData(MimeMessage message) async {
    final subject = message.decodeSubject() ?? '';
    if (subject.contains('Your RBC Royal Bank eStatement is ready') ||
        subject.contains('eStatement Alert for your Simplii Credit Card') ||
        subject.contains('Enbridge - Your Payment is Due')) {
      return null;
    }

    final hasAttachment = EmailParser.hasAttachment(message);
    final body =
        hasAttachment
            ? await EmailParser.extractEmailAttachment(message)
            : EmailParser.extractEmailBody(message);

    if (subject.isNotEmpty && body.isNotEmpty) {
      // Generate a stable billId based on email properties that don't change
      final date = message.decodeDate()?.millisecondsSinceEpoch ?? 0;
      final from = message.from?.first.email ?? '';
      
      // Combine these stable properties to create a unique hash
      final uniqueString = '$date$from$subject';
      final emailId = uniqueString.hashCode.abs();

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
