import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

class FileUtils {
  static XFile pdfToXFile(Uint8List pdfBytes, String filename) {
    return XFile.fromData(pdfBytes, name: filename, mimeType: 'application/pdf');
  }
}
