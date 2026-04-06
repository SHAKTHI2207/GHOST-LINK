import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../models/user.dart';
import 'verification_service.dart';

class SignedPreKeyPublic {
  final String id;
  final String publicKeyPem;
  final String signature;

  const SignedPreKeyPublic({
    required this.id,
    required this.publicKeyPem,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'publicKeyPem': publicKeyPem,
      'signature': signature,
    };
  }

  factory SignedPreKeyPublic.fromJson(Map<String, dynamic> json) {
    return SignedPreKeyPublic(
      id: json['id'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
      signature: json['signature'] as String,
    );
  }
}

class OneTimePreKeyPublic {
  final String id;
  final String publicKeyPem;

  const OneTimePreKeyPublic({
    required this.id,
    required this.publicKeyPem,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'publicKeyPem': publicKeyPem,
    };
  }

  factory OneTimePreKeyPublic.fromJson(Map<String, dynamic> json) {
    return OneTimePreKeyPublic(
      id: json['id'] as String,
      publicKeyPem: json['publicKeyPem'] as String,
    );
  }
}

class PreKeyBundle {
  final int version;
  final String userId;
  final String identityKey;
  final String identitySigningKey;
  final SignedPreKeyPublic signedPreKey;
  final List<OneTimePreKeyPublic> oneTimePreKeys;
  final OneTimePreKeyPublic? oneTimePreKey;

  const PreKeyBundle({
    required this.version,
    required this.userId,
    required this.identityKey,
    required this.identitySigningKey,
    required this.signedPreKey,
    required this.oneTimePreKeys,
    required this.oneTimePreKey,
  });

  OneTimePreKeyPublic? get selectedOneTimePreKey {
    if (oneTimePreKey != null) {
      return oneTimePreKey;
    }
    if (oneTimePreKeys.isEmpty) {
      return null;
    }
    return oneTimePreKeys.first;
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'userId': userId,
      'identityKey': identityKey,
      'identitySigningKey': identitySigningKey,
      'signedPreKey': signedPreKey.toJson(),
      'oneTimePreKeys': oneTimePreKeys.map((item) => item.toJson()).toList(),
      if (oneTimePreKey != null) 'oneTimePreKey': oneTimePreKey!.toJson(),
    };
  }

  factory PreKeyBundle.fromJson(Map<String, dynamic> json) {
    final rawSpk = Map<String, dynamic>.from(json['signedPreKey'] as Map);
    final rawOpkList = (json['oneTimePreKeys'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return PreKeyBundle(
      version: (json['version'] as int?) ?? 1,
      userId: json['userId'] as String,
      identityKey: json['identityKey'] as String,
      identitySigningKey: json['identitySigningKey'] as String,
      signedPreKey: SignedPreKeyPublic.fromJson(rawSpk),
      oneTimePreKeys: rawOpkList.map(OneTimePreKeyPublic.fromJson).toList(),
      oneTimePreKey: json['oneTimePreKey'] is Map
          ? OneTimePreKeyPublic.fromJson(
              Map<String, dynamic>.from(json['oneTimePreKey'] as Map),
            )
          : null,
    );
  }
}

class SignedPreKeyMaterial {
  final String id;
  final SimpleKeyPairData keyPair;
  final String signature;

  const SignedPreKeyMaterial({
    required this.id,
    required this.keyPair,
    required this.signature,
  });
}

class OneTimePreKeyMaterial {
  final String id;
  final SimpleKeyPairData keyPair;
  DateTime? consumedAt;

  OneTimePreKeyMaterial({
    required this.id,
    required this.keyPair,
    this.consumedAt,
  });
}

class LocalIdentityMaterial {
  final String id;
  final SimpleKeyPairData identityKeyPair;
  final SimpleKeyPairData signingKeyPair;
  SignedPreKeyMaterial signedPreKey;
  final List<OneTimePreKeyMaterial> oneTimePreKeys;

  LocalIdentityMaterial({
    required this.id,
    required this.identityKeyPair,
    required this.signingKeyPair,
    required this.signedPreKey,
    required this.oneTimePreKeys,
  });

  List<OneTimePreKeyMaterial> get availableOneTimePreKeys {
    return oneTimePreKeys.where((item) => item.consumedAt == null).toList(growable: false);
  }

  OneTimePreKeyMaterial? resolveOneTimePreKey(String id) {
    return oneTimePreKeys.where((item) => item.id == id).firstOrNull;
  }

  void consumeOneTimePreKey(String id) {
    final match = resolveOneTimePreKey(id);
    if (match != null && match.consumedAt == null) {
      match.consumedAt = DateTime.now().toUtc();
    }
  }
}

class GeneratedIdentity {
  final GhostIdentity identity;
  final LocalIdentityMaterial material;
  final PreKeyBundle preKeyBundle;

  const GeneratedIdentity({
    required this.identity,
    required this.material,
    required this.preKeyBundle,
  });
}

class IdentityService {
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();
  final VerificationService _verification;
  final Random _random = Random.secure();

  IdentityService(this._verification);

  Future<GeneratedIdentity> generateIdentity({
    required String userId,
    int oneTimePreKeyCount = 20,
  }) async {
    final identityKeyPair = await _newSimpleKeyPair(_x25519.newKeyPair());
    final signingKeyPair = await _newSimpleKeyPair(_ed25519.newKeyPair());
    final signedPreKeyPair = await _newSimpleKeyPair(_x25519.newKeyPair());
    final signedPreKeyId = _randomKeyId('spk');

    final signedPreKeyPublic = _encode(signedPreKeyPair.publicKey.bytes);
    final signature = await _ed25519.sign(
      _signedPreKeyMessage(signedPreKeyId, signedPreKeyPublic),
      keyPair: signingKeyPair,
    );

    final oneTimeKeys = <OneTimePreKeyMaterial>[];
    for (var i = 0; i < oneTimePreKeyCount; i++) {
      oneTimeKeys.add(
        OneTimePreKeyMaterial(
          id: _randomKeyId('opk'),
          keyPair: await _newSimpleKeyPair(_x25519.newKeyPair()),
        ),
      );
    }

    final material = LocalIdentityMaterial(
      id: userId,
      identityKeyPair: identityKeyPair,
      signingKeyPair: signingKeyPair,
      signedPreKey: SignedPreKeyMaterial(
        id: signedPreKeyId,
        keyPair: signedPreKeyPair,
        signature: _encode(signature.bytes),
      ),
      oneTimePreKeys: oneTimeKeys,
    );

    final identityKeyPublic = _encode(identityKeyPair.publicKey.bytes);
    final signingKeyPublic = _encode(signingKeyPair.publicKey.bytes);

    final verificationPayload = await _verification.buildPayload(
      id: userId,
      identityKey: identityKeyPublic,
      identitySigningKey: signingKeyPublic,
    );

    final bundle = buildRelayPreKeyBundle(material);

    return GeneratedIdentity(
      identity: GhostIdentity(
        id: userId,
        publicIdentityKey: identityKeyPublic,
        signingPublicKey: signingKeyPublic,
        fingerprint: verificationPayload.fingerprint,
        verificationUri: _verification.toUri(verificationPayload),
        availableOneTimePreKeys: oneTimeKeys.length,
      ),
      material: material,
      preKeyBundle: bundle,
    );
  }

  PreKeyBundle buildRelayPreKeyBundle(LocalIdentityMaterial identity) {
    return PreKeyBundle(
      version: 1,
      userId: identity.id,
      identityKey: _encode(identity.identityKeyPair.publicKey.bytes),
      identitySigningKey: _encode(identity.signingKeyPair.publicKey.bytes),
      signedPreKey: SignedPreKeyPublic(
        id: identity.signedPreKey.id,
        publicKeyPem: _encode(identity.signedPreKey.keyPair.publicKey.bytes),
        signature: identity.signedPreKey.signature,
      ),
      oneTimePreKeys: identity.availableOneTimePreKeys
          .map(
            (item) => OneTimePreKeyPublic(
              id: item.id,
              publicKeyPem: _encode(item.keyPair.publicKey.bytes),
            ),
          )
          .toList(growable: false),
      oneTimePreKey: null,
    );
  }

  String encodePublicKey(SimplePublicKey key) {
    return _encode(key.bytes);
  }

  SimplePublicKey decodeX25519PublicKey(String encoded) {
    return SimplePublicKey(_decode(encoded), type: KeyPairType.x25519);
  }

  List<int> decodeSignature(String encoded) {
    return _decode(encoded);
  }

  List<int> signedPreKeyMessage(String signedPreKeyId, String signedPreKeyPublicKey) {
    return _signedPreKeyMessage(signedPreKeyId, signedPreKeyPublicKey);
  }

  Future<SimpleKeyPairData> _newSimpleKeyPair(Future<KeyPair> futureKeyPair) async {
    final extracted = await (await futureKeyPair).extract();
    if (extracted is! SimpleKeyPairData) {
      throw const StateError('Key extraction failed for simple key pair.');
    }
    return extracted;
  }

  List<int> _signedPreKeyMessage(String signedPreKeyId, String signedPreKeyPublicKey) {
    return utf8.encode('ghostlink/spk/v1/$signedPreKeyId/$signedPreKeyPublicKey');
  }

  String _randomKeyId(String prefix) {
    final bytes = List<int>.generate(5, (_) => _random.nextInt(256));
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '$prefix-$token';
  }

  String _encode(List<int> data) {
    return base64UrlEncode(data).replaceAll('=', '');
  }

  List<int> _decode(String value) {
    final mod = value.length % 4;
    final padded = mod == 0 ? value : '$value${'=' * (4 - mod)}';
    return base64Url.decode(padded);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }
}
