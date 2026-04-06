import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class CipherEnvelope {
  final String cipher;
  final String nonce;
  final String mac;

  const CipherEnvelope({
    required this.cipher,
    required this.nonce,
    required this.mac,
  });

  Map<String, dynamic> toJson() {
    return {
      'cipher': cipher,
      'nonce': nonce,
      'mac': mac,
    };
  }

  static CipherEnvelope fromJson(Map<String, dynamic> json) {
    return CipherEnvelope(
      cipher: json['cipher'] as String,
      nonce: json['nonce'] as String,
      mac: json['mac'] as String,
    );
  }
}

class CryptoService {
  final AesGcm _algorithm = AesGcm.with256bits();
  final Sha256 _sha256 = Sha256();

  Future<SecretKey> generateKey() {
    return _algorithm.newSecretKey();
  }

  Future<CipherEnvelope> encryptMessage(String message, SecretKey key) async {
    final nonce = _algorithm.newNonce();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(message),
      secretKey: key,
      nonce: nonce,
    );

    return CipherEnvelope(
      cipher: base64UrlEncode(secretBox.cipherText),
      nonce: base64UrlEncode(secretBox.nonce),
      mac: base64UrlEncode(secretBox.mac.bytes),
    );
  }

  Future<String> decryptMessage(Map<String, dynamic> payload, SecretKey key) async {
    final envelope = CipherEnvelope.fromJson(payload);
    final secretBox = SecretBox(
      base64UrlDecode(_restorePadding(envelope.cipher)),
      nonce: base64UrlDecode(_restorePadding(envelope.nonce)),
      mac: Mac(base64UrlDecode(_restorePadding(envelope.mac))),
    );

    final clearBytes = await _algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(clearBytes);
  }

  Future<String> sha256Fingerprint(String value) async {
    final digest = await _sha256.hash(utf8.encode(value));
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _restorePadding(String value) {
    final mod = value.length % 4;
    if (mod == 0) {
      return value;
    }
    return '$value${'=' * (4 - mod)}';
  }
}
