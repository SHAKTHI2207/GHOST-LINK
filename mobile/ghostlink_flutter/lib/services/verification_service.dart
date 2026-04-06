import 'dart:convert';

import '../core/utils/fingerprint.dart';
import 'crypto_service.dart';

class VerificationPayload {
  final int version;
  final String id;
  final String identityKey;
  final String identitySigningKey;
  final String fingerprint;

  const VerificationPayload({
    required this.version,
    required this.id,
    required this.identityKey,
    required this.identitySigningKey,
    required this.fingerprint,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'id': id,
      'identityKey': identityKey,
      'identitySigningKey': identitySigningKey,
      'fingerprint': fingerprint,
    };
  }

  factory VerificationPayload.fromJson(Map<String, dynamic> json) {
    return VerificationPayload(
      version: (json['version'] as int?) ?? 1,
      id: json['id'] as String,
      identityKey: json['identityKey'] as String,
      identitySigningKey: json['identitySigningKey'] as String,
      fingerprint: json['fingerprint'] as String,
    );
  }
}

class VerificationService {
  final CryptoService _crypto;

  VerificationService(this._crypto);

  Future<VerificationPayload> buildPayload({
    required String id,
    required String identityKey,
    required String identitySigningKey,
  }) async {
    final rawFingerprint = await _crypto.sha256Fingerprint(identityKey);
    return VerificationPayload(
      version: 1,
      id: id,
      identityKey: identityKey,
      identitySigningKey: identitySigningKey,
      fingerprint: formatFingerprint(rawFingerprint),
    );
  }

  String toUri(VerificationPayload payload) {
    final token = base64UrlEncode(utf8.encode(jsonEncode(payload.toJson()))).replaceAll('=', '');
    return 'ghostlink://verify/$token';
  }

  VerificationPayload fromUriOrToken(String rawInput) {
    var token = rawInput.trim();
    if (token.startsWith('ghostlink://verify/')) {
      token = token.substring('ghostlink://verify/'.length);
    }

    final decoded = utf8.decode(base64Url.decode(_restorePadding(token)));
    final parsed = jsonDecode(decoded) as Map<String, dynamic>;

    if (!parsed.containsKey('id') ||
        !parsed.containsKey('identityKey') ||
        !parsed.containsKey('identitySigningKey')) {
      throw const FormatException('Invalid verification payload.');
    }

    final payload = VerificationPayload.fromJson(parsed);
    return VerificationPayload(
      version: payload.version,
      id: payload.id,
      identityKey: payload.identityKey,
      identitySigningKey: payload.identitySigningKey,
      fingerprint: payload.fingerprint.isEmpty
          ? formatFingerprint(_fallbackFingerprint(payload.identityKey))
          : payload.fingerprint,
    );
  }

  String _restorePadding(String value) {
    final mod = value.length % 4;
    if (mod == 0) {
      return value;
    }
    return '$value${'=' * (4 - mod)}';
  }

  String _fallbackFingerprint(String identityKey) {
    final bytes = utf8.encode(identityKey);
    final hash = bytes.fold<int>(0, (acc, item) => (acc * 31 + item) & 0xFFFFFFFF);
    return hash.toRadixString(16).padLeft(8, '0').toUpperCase();
  }
}
