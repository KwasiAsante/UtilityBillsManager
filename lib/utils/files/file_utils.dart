import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';

/// Static helpers for converting in-memory file data to cross-platform
/// [XFile] objects that can be shared or opened by the OS.
class FileUtils {
  /// Wraps raw [pdfBytes] in an [XFile] with the given [filename] and the
  /// `application/pdf` MIME type, so it can be shared via [Share.shareXFiles].
  static XFile pdfToXFile(Uint8List pdfBytes, String filename) {
    return XFile.fromData(pdfBytes, name: filename, mimeType: 'application/pdf');
  }
}
