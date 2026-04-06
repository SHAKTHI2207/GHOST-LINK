import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'identity_service.dart';

class X3dhHeader {
  final String senderIdentityKey;
  final String senderEphemeralKey;
  final String receiverSignedPreKeyId;
  final String? receiverOneTimePreKeyId;

  const X3dhHeader({
    required this.senderIdentityKey,
    required this.senderEphemeralKey,
    required this.receiverSignedPreKeyId,
    required this.receiverOneTimePreKeyId,
  });

  Map<String, dynamic> toJson() {
    return {
      'senderIdentityKey': senderIdentityKey,
      'senderEphemeralKey': senderEphemeralKey,
      'receiverSignedPreKeyId': receiverSignedPreKeyId,
      'receiverOneTimePreKeyId': receiverOneTimePreKeyId,
    };
  }

  factory X3dhHeader.fromJson(Map<String, dynamic> json) {
    return X3dhHeader(
      senderIdentityKey: json['senderIdentityKey'] as String,
      senderEphemeralKey: json['senderEphemeralKey'] as String,
      receiverSignedPreKeyId: json['receiverSignedPreKeyId'] as String,
      receiverOneTimePreKeyId: json['receiverOneTimePreKeyId'] as String?,
    );
  }
}

class X3dhMessagePacket {
  final int version;
  final String kind;
  final String from;
  final String sentAt;
  final X3dhHeader x3dh;
  final String? senderRatchetKey;
  final Map<String, dynamic> body;

  const X3dhMessagePacket({
    required this.version,
    required this.kind,
    required this.from,
    required this.sentAt,
    required this.x3dh,
    required this.senderRatchetKey,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'kind': kind,
      'from': from,
      'sentAt': sentAt,
      'x3dh': x3dh.toJson(),
      'senderRatchetKey': senderRatchetKey,
      'body': body,
    };
  }

  factory X3dhMessagePacket.fromJson(Map<String, dynamic> json) {
    return X3dhMessagePacket(
      version: (json['version'] as int?) ?? 1,
      kind: json['kind'] as String,
      from: json['from'] as String,
      sentAt: json['sentAt'] as String,
      x3dh: X3dhHeader.fromJson(Map<String, dynamic>.from(json['x3dh'] as Map)),
      senderRatchetKey: json['senderRatchetKey'] as String?,
      body: Map<String, dynamic>.from(json['body'] as Map),
    );
  }
}

class X3dhService {
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256());

  Future<SimpleKeyPairData> generateEphemeralKeyPair() async {
    final extracted = await (await _x25519.newKeyPair()).extract();
    if (extracted is! SimpleKeyPairData) {
      throw const StateError('Failed to extract ephemeral key pair.');
    }
    return extracted;
  }

  Future<bool> verifyPrekeyBundleSignature(PreKeyBundle bundle) async {
    final signature = Signature(
      _decode(bundle.signedPreKey.signature),
      publicKey: SimplePublicKey(
        _decode(bundle.identitySigningKey),
        type: KeyPairType.ed25519,
      ),
    );

    final message = utf8.encode(
      'ghostlink/spk/v1/${bundle.signedPreKey.id}/${bundle.signedPreKey.publicKeyPem}',
    );

    return _ed25519.verify(message, signature: signature);
  }

  Future<List<int>> deriveInitiatorMasterSecret({
    required LocalIdentityMaterial sender,
    required SimpleKeyPairData senderEphemeralKeyPair,
    required PreKeyBundle receiverBundle,
  }) async {
    final dh1 = await _dh(sender.identityKeyPair, receiverBundle.signedPreKey.publicKeyPem);
    final dh2 = await _dh(senderEphemeralKeyPair, receiverBundle.identityKey);
    final dh3 = await _dh(senderEphemeralKeyPair, receiverBundle.signedPreKey.publicKeyPem);

    final parts = <List<int>>[dh1, dh2, dh3];

    final opk = receiverBundle.selectedOneTimePreKey;
    if (opk != null) {
      final dh4 = await _dh(senderEphemeralKeyPair, opk.publicKeyPem);
      parts.add(dh4);
    }

    return _concat(parts);
  }

  Future<List<int>> deriveResponderMasterSecret({
    required LocalIdentityMaterial receiver,
    required X3dhHeader header,
  }) async {
    if (receiver.signedPreKey.id != header.receiverSignedPreKeyId) {
      throw const StateError('Signed prekey ID mismatch.');
    }

    final dh1 = await _dh(receiver.signedPreKey.keyPair, header.senderIdentityKey);
    final dh2 = await _dh(receiver.identityKeyPair, header.senderEphemeralKey);
    final dh3 = await _dh(receiver.signedPreKey.keyPair, header.senderEphemeralKey);

    final parts = <List<int>>[dh1, dh2, dh3];

    if (header.receiverOneTimePreKeyId != null) {
      final opk = receiver.resolveOneTimePreKey(header.receiverOneTimePreKeyId!);
      if (opk == null || opk.consumedAt != null) {
        throw const StateError('Receiver one-time prekey unavailable.');
      }

      final dh4 = await _dh(opk.keyPair, header.senderEphemeralKey);
      parts.add(dh4);
      receiver.consumeOneTimePreKey(opk.id);
    }

    return _concat(parts);
  }

  Future<SecretKey> deriveMessageKey(List<int> masterSecret) {
    return _hkdf.deriveKey(
      secretKey: SecretKey(masterSecret),
      nonce: utf8.encode('ghostlink-x3dh-message-v1'),
      info: utf8.encode('ghostlink/x3dh/message-key'),
      outputLength: 32,
    );
  }

  X3dhMessagePacket buildPacket({
    required String senderId,
    required String senderIdentityKey,
    required String senderEphemeralKey,
    required PreKeyBundle receiverBundle,
    required String senderRatchetKey,
    required Map<String, dynamic> body,
  }) {
    return X3dhMessagePacket(
      version: 1,
      kind: 'x3dh_init',
      from: senderId,
      sentAt: DateTime.now().toUtc().toIso8601String(),
      x3dh: X3dhHeader(
        senderIdentityKey: senderIdentityKey,
        senderEphemeralKey: senderEphemeralKey,
        receiverSignedPreKeyId: receiverBundle.signedPreKey.id,
        receiverOneTimePreKeyId: receiverBundle.selectedOneTimePreKey?.id,
      ),
      senderRatchetKey: senderRatchetKey,
      body: body,
    );
  }

  Future<List<int>> _dh(SimpleKeyPairData privateKeyPair, String remotePublicKeyEncoded) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: privateKeyPair,
      remotePublicKey: SimplePublicKey(
        _decode(remotePublicKeyEncoded),
        type: KeyPairType.x25519,
      ),
    );

    return shared.extractBytes();
  }

  List<int> _concat(List<List<int>> parts) {
    final output = <int>[];
    for (final part in parts) {
      output.addAll(part);
    }
    return output;
  }

  List<int> _decode(String value) {
    final mod = value.length % 4;
    final padded = mod == 0 ? value : '$value${'=' * (4 - mod)}';
    return base64Url.decode(padded);
  }
}
