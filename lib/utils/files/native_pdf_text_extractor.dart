import 'package:flutter/services.dart';
import 'dart:io';

class NativePdfTextExtractor {
  static const _channel = MethodChannel('pdf_text');

  static Future<String> extractTextFromPdf(File pdfFile) async {
    final result = await _channel.invokeMethod<String>(
      'extractPdfText',
      {'filePath': pdfFile.path},
    );
    return result ?? '';
  }
}