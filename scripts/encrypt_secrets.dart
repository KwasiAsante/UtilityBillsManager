// ignore_for_file: avoid_print
/// Encrypts string values in `assets/config/local_secrets.json` using
/// AES-256-GCM and writes the result back to the same file.
///
/// Non-string fields (int, bool) are left as-is.
/// Already-encrypted values (prefixed with `enc:`) are skipped.
///
/// Usage (run from the project root):
///   dart run scripts/encrypt_secrets.dart --key=<32-char-key>
///
/// The same key must be passed at Flutter build/run time:
///   flutter run  --dart-define=SECRETS_KEY=<32-char-key>
///   flutter build apk --dart-define=SECRETS_KEY=<32-char-key>
///   flutter build web --dart-define=SECRETS_KEY=<32-char-key>
///   flutter build windows --dart-define=BUILD_TARGET=windows --dart-define=SECRETS_KEY=<32-char-key>
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final keyArg = args
      .where((a) => a.startsWith('--key='))
      .map((a) => a.substring(6))
      .firstOrNull;

  if (keyArg == null || keyArg.isEmpty) {
    stderr.writeln(
        'Usage: dart run scripts/encrypt_secrets.dart --key=<32-char-key>');
    exit(1);
  }

  if (keyArg.length != 32) {
    stderr.writeln(
        'Error: key must be exactly 32 characters (got ${keyArg.length}).');
    exit(1);
  }

  final secretsFile = File('assets/config/local_secrets.json');
  if (!secretsFile.existsSync()) {
    stderr.writeln('Error: assets/config/local_secrets.json not found.');
    stderr.writeln('Run this script from the project root.');
    exit(1);
  }

  final raw = secretsFile.readAsStringSync();
  final json = jsonDecode(raw) as Map<String, dynamic>;

  final algorithm = AesGcm.with256bits();
  final secretKey = await algorithm.newSecretKeyFromBytes(keyArg.codeUnits);

  var encrypted = 0;
  final result = <String, dynamic>{};

  for (final entry in json.entries) {
    if (entry.value is! String ||
        (entry.value as String).isEmpty ||
        (entry.value as String).startsWith('enc:')) {
      result[entry.key] = entry.value;
      continue;
    }

    final plainBytes = (entry.value as String).codeUnits;
    final secretBox = await algorithm.encrypt(plainBytes, secretKey: secretKey);

    // Store as enc:<base64-nonce>.<base64-(ciphertext+mac)>
    final nonceB64 = base64Encode(secretBox.nonce);
    final payloadB64 =
        base64Encode([...secretBox.cipherText, ...secretBox.mac.bytes]);
    result[entry.key] = 'enc:$nonceB64.$payloadB64';
    encrypted++;
  }

  const encoder = JsonEncoder.withIndent('  ');
  secretsFile.writeAsStringSync(encoder.convert(result));

  print('Encrypted $encrypted value(s) in assets/config/local_secrets.json.');
  print(
      'Add --dart-define=SECRETS_KEY=$keyArg to your build and run commands.');
}
