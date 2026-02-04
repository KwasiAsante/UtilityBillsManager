import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  static Future<File> savePdfTemp(Uint8List pdfBytes, String filename) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    return await file.writeAsBytes(pdfBytes, flush: true);
  }

  static Future<void> deleteTempFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}
