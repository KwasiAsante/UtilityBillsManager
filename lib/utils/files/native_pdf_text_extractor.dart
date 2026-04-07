import 'package:flutter/services.dart';
import 'dart:io';

/// Extracts plain text from a PDF file via a native platform channel.
///
/// **Platform support:** Android / iOS only. On other platforms (web, desktop)
/// use [EmailParser.extractTextFromPdf] which relies on the `pdfrx` package
/// instead of a native MethodChannel.
///
/// The native side must implement the `pdf_text` channel and handle the
/// `extractPdfText` method, accepting `{'filePath': String}`.
class NativePdfTextExtractor {
  static const _channel = MethodChannel('pdf_text');

  /// Invokes the native `extractPdfText` method with [pdfFile]'s path and
  /// returns the extracted plain text, or an empty string if the invocation
  /// returns `null`.
  static Future<String> extractTextFromPdf(File pdfFile) async {
    final result = await _channel.invokeMethod<String>(
      'extractPdfText',
      {'filePath': pdfFile.path},
    );
    return result ?? '';
  }
}