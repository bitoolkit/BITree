import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

// These algorithms and the public key are required by the school's SSO protocol.
String encryptSchoolValue(String value, Uint8List key) =>
    base64Encode(_aes(true, key, Uint8List.fromList(utf8.encode(value))));

String decryptSchoolValue(String value, Uint8List key) =>
    utf8.decode(_aes(false, key, base64Decode(value)));

Uint8List _aes(bool encrypt, Uint8List key, Uint8List value) {
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()))..init(
        encrypt,
        PaddedBlockCipherParameters<KeyParameter, Null>(
          KeyParameter(key),
          null,
        ),
      );
  return cipher.process(value);
}

Uint8List schoolRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

String schoolSha256(String value) =>
    _hex(SHA256Digest().process(Uint8List.fromList(utf8.encode(value))));

String _hex(Uint8List bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

Map<String, String> schoolCsrfHeaders() {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  final random = Random.secure();
  final key = List.generate(
    32,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  final encoded = base64Encode(ascii.encode(key));
  final middle = encoded.length ~/ 2;
  final mixed =
      '${encoded.substring(0, middle)}$encoded${encoded.substring(middle)}';
  return {
    'Csrf-Key': key,
    'Csrf-Value': _hex(
      MD5Digest().process(Uint8List.fromList(ascii.encode(mixed))),
    ),
  };
}

String encryptSchoolKey(Uint8List key) {
  const encoded =
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAjVr1zKwohU3xA0afprWLSQvIymaSH/V27MedFc+CecXSnORIFMAp4uEIb4taDq/2X4eMeTI66Mu/rB5GKSFDbExF2Gu4NaO/CNDpf1gHMScUrIFCh4CDqzBnx17kclvezLkIK0T8FVa4cRsINvzjbnA6jUSMaf6Fm1n9wTAtW6QYBjssGOEtCj+c38PTBdFMmJbXp3brt1tEBesz6lb3Fjp76FGvDZ08xtYG8fxYPuiMwKU04eS+mcX/BunwgpU3zwekHYB+PWRIvq0lBry9Wms25sJE5T/RAv5fEuMLbBkfcZK3+7ivSZthTmPpr2Ap/ji70ZZ6u2jvR5VJq+LJHQIDAQAB';
  final outer = ASN1Parser(base64Decode(encoded)).nextObject() as ASN1Sequence;
  final bits = outer.elements![1] as ASN1BitString;
  final sequence =
      ASN1Parser(Uint8List.fromList(bits.stringValues!)).nextObject()
          as ASN1Sequence;
  final modulus = (sequence.elements![0] as ASN1Integer).integer!;
  final exponent = (sequence.elements![1] as ASN1Integer).integer!;
  final random = FortunaRandom()..seed(KeyParameter(schoolRandomBytes(32)));
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(
      true,
      ParametersWithRandom(
        PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
        random,
      ),
    );
  return base64Encode(
    cipher.process(Uint8List.fromList(ascii.encode(base64Encode(key)))),
  );
}
