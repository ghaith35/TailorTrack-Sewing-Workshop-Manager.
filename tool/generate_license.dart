// tool/generate_license.dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:pointycastle/export.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart generate_license.dart <DEVICE_CODE>');
    exit(1);
  }

  // 1️⃣ Read the device code from the command line
  final deviceCode = args.first.trim();

  // 2️⃣ Load your RSA PRIVATE key
  final pem = File('tool/private.pem').readAsStringSync();
  final privateKey = CryptoUtils.rsaPrivateKeyFromPem(pem) as RSAPrivateKey;

  // 3️⃣ Sign the device code
  final signer = Signer('SHA-256/RSA')
    ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  final signature = signer.generateSignature(
    Uint8List.fromList(utf8.encode(deviceCode)),
  ) as RSASignature;

  // 4️⃣ Output a Base64‐encoded license string
  final license = base64.encode(signature.bytes);
  stdout.writeln(license);
}
