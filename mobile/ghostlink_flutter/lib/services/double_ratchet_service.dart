import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto_service.dart';

class RatchetHeader {
  final String dhPublicKey;
  final int messageNumber;
  final int previousChainLength;

  const RatchetHeader({
    required this.dhPublicKey,
    required this.messageNumber,
    required this.previousChainLength,
  });

  Map<String, dynamic> toJson() {
    return {
      'dhPublicKey': dhPublicKey,
      'messageNumber': messageNumber,
      'previousChainLength': previousChainLength,
    };
  }

  factory RatchetHeader.fromJson(Map<String, dynamic> json) {
    return RatchetHeader(
      dhPublicKey: json['dhPublicKey'] as String,
      messageNumber: (json['messageNumber'] as num?)?.toInt() ?? 0,
      previousChainLength: (json['previousChainLength'] as num?)?.toInt() ?? 0,
    );
  }
}

class RatchetMessagePacket {
  final int version;
  final String kind;
  final String from;
  final String sentAt;
  final RatchetHeader ratchet;
  final Map<String, dynamic> body;

  const RatchetMessagePacket({
    required this.version,
    required this.kind,
    required this.from,
    required this.sentAt,
    required this.ratchet,
    required this.body,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'kind': kind,
      'from': from,
      'sentAt': sentAt,
      'ratchet': ratchet.toJson(),
      'body': body,
    };
  }

  factory RatchetMessagePacket.fromJson(Map<String, dynamic> json) {
    return RatchetMessagePacket(
      version: (json['version'] as num?)?.toInt() ?? 1,
      kind: json['kind'] as String,
      from: json['from'] as String,
      sentAt: json['sentAt'] as String,
      ratchet: RatchetHeader.fromJson(Map<String, dynamic>.from(json['ratchet'] as Map)),
      body: Map<String, dynamic>.from(json['body'] as Map),
    );
  }
}

class RatchetSessionState {
  final String contactId;
  List<int> rootKey;
  List<int> sendingChainKey;
  List<int> receivingChainKey;
  SimpleKeyPairData localDhKeyPair;
  String? remoteDhPublicKey;
  int sendCount;
  int receiveCount;
  int previousChainLength;
  bool pendingSendRatchet;

  RatchetSessionState({
    required this.contactId,
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.localDhKeyPair,
    required this.remoteDhPublicKey,
    required this.sendCount,
    required this.receiveCount,
    required this.previousChainLength,
    required this.pendingSendRatchet,
  });

  Map<String, dynamic> toJson() {
    return {
      'contactId': contactId,
      'rootKey': _encode(rootKey),
      'sendingChainKey': _encode(sendingChainKey),
      'receivingChainKey': _encode(receivingChainKey),
      'localDh': {
        'privateKey': _encode(localDhKeyPair.privateKeyBytes),
        'publicKey': _encode(localDhKeyPair.publicKey.bytes),
      },
      'remoteDhPublicKey': remoteDhPublicKey,
      'sendCount': sendCount,
      'receiveCount': receiveCount,
      'previousChainLength': previousChainLength,
      'pendingSendRatchet': pendingSendRatchet,
    };
  }

  factory RatchetSessionState.fromJson(Map<String, dynamic> json) {
    final localDh = Map<String, dynamic>.from(json['localDh'] as Map);
    final localPublicKey = SimplePublicKey(
      _decode(localDh['publicKey'] as String),
      type: KeyPairType.x25519,
    );

    return RatchetSessionState(
      contactId: json['contactId'] as String,
      rootKey: _decode(json['rootKey'] as String),
      sendingChainKey: _decode(json['sendingChainKey'] as String),
      receivingChainKey: _decode(json['receivingChainKey'] as String),
      localDhKeyPair: SimpleKeyPairData(
        _decode(localDh['privateKey'] as String),
        type: KeyPairType.x25519,
        publicKey: localPublicKey,
      ),
      remoteDhPublicKey: json['remoteDhPublicKey'] as String?,
      sendCount: (json['sendCount'] as num?)?.toInt() ?? 0,
      receiveCount: (json['receiveCount'] as num?)?.toInt() ?? 0,
      previousChainLength: (json['previousChainLength'] as num?)?.toInt() ?? 0,
      pendingSendRatchet: (json['pendingSendRatchet'] as bool?) ?? false,
    );
  }

  static String _encode(List<int> value) {
    return base64UrlEncode(value).replaceAll('=', '');
  }

  static List<int> _decode(String value) {
    final mod = value.length % 4;
    final padded = mod == 0 ? value : '$value${'=' * (4 - mod)}';
    return base64Url.decode(padded);
  }
}

class DoubleRatchetService {
  final CryptoService _crypto;
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256());
  final Hmac _hmac = Hmac.sha256();

  DoubleRatchetService(this._crypto);

  Future<SimpleKeyPairData> generateDhKeyPair() async {
    final extracted = await (await _x25519.newKeyPair()).extract();
    if (extracted is! SimpleKeyPairData) {
      throw const StateError('Unable to generate ratchet key pair.');
    }
    return extracted;
  }

  String encodePublicDhKey(SimplePublicKey key) {
    return _encode(key.bytes);
  }

  Future<RatchetSessionState> initializeFromX3dh({
    required String contactId,
    required List<int> masterSecret,
    required bool isInitiator,
    String? remoteDhPublicKey,
    SimpleKeyPairData? localDhKeyPair,
  }) async {
    final seed = await _hkdf.deriveKey(
      secretKey: SecretKey(masterSecret),
      nonce: utf8.encode('ghostlink-double-ratchet-init-salt'),
      info: utf8.encode('ghostlink/double-ratchet/init'),
      outputLength: 96,
    );

    final seedBytes = await seed.extractBytes();
    final root = seedBytes.sublist(0, 32);
    final firstChain = seedBytes.sublist(32, 64);
    final secondChain = seedBytes.sublist(64, 96);

    return RatchetSessionState(
      contactId: contactId,
      rootKey: root,
      sendingChainKey: isInitiator ? firstChain : secondChain,
      receivingChainKey: isInitiator ? secondChain : firstChain,
      localDhKeyPair: localDhKeyPair ?? await generateDhKeyPair(),
      remoteDhPublicKey: remoteDhPublicKey,
      sendCount: 0,
      receiveCount: 0,
      previousChainLength: 0,
      pendingSendRatchet: !isInitiator && remoteDhPublicKey != null,
    );
  }

  Future<RatchetMessagePacket> encryptMessage({
    required RatchetSessionState session,
    required String senderId,
    required String plaintext,
  }) async {
    if (session.pendingSendRatchet) {
      await _performSendRatchet(session);
    }

    final messageKey = await _deriveMessageKey(session.sendingChainKey);
    session.sendingChainKey = await _deriveNextChainKey(session.sendingChainKey);

    final encrypted = await _crypto.encryptMessage(plaintext, SecretKey(messageKey));

    final packet = RatchetMessagePacket(
      version: 1,
      kind: 'dr_msg',
      from: senderId,
      sentAt: DateTime.now().toUtc().toIso8601String(),
      ratchet: RatchetHeader(
        dhPublicKey: encodePublicDhKey(session.localDhKeyPair.publicKey),
        messageNumber: session.sendCount,
        previousChainLength: session.previousChainLength,
      ),
      body: encrypted.toJson(),
    );

    session.sendCount += 1;
    return packet;
  }

  Future<String> decryptMessage({
    required RatchetSessionState session,
    required RatchetMessagePacket packet,
  }) async {
    if (packet.ratchet.dhPublicKey != session.remoteDhPublicKey) {
      await _performReceiveRatchet(session, packet.ratchet.dhPublicKey);
    }

    while (session.receiveCount < packet.ratchet.messageNumber) {
      session.receivingChainKey = await _deriveNextChainKey(session.receivingChainKey);
      session.receiveCount += 1;
    }

    final messageKey = await _deriveMessageKey(session.receivingChainKey);
    session.receivingChainKey = await _deriveNextChainKey(session.receivingChainKey);
    session.receiveCount += 1;

    return _crypto.decryptMessage(packet.body, SecretKey(messageKey));
  }

  Future<void> _performSendRatchet(RatchetSessionState session) async {
    final remoteDhPublicKey = session.remoteDhPublicKey;
    if (remoteDhPublicKey == null) {
      return;
    }

    session.previousChainLength = session.sendCount;
    session.sendCount = 0;

    final nextLocalDhKeyPair = await generateDhKeyPair();
    session.localDhKeyPair = nextLocalDhKeyPair;

    final dhOutput = await _dh(
      localDhKeyPair: nextLocalDhKeyPair,
      remoteDhPublicKey: remoteDhPublicKey,
    );

    final rootOutput = await _kdfRoot(
      currentRootKey: session.rootKey,
      dhOutput: dhOutput,
    );

    session.rootKey = rootOutput.rootKey;
    session.sendingChainKey = rootOutput.chainKey;
    session.pendingSendRatchet = false;
  }

  Future<void> _performReceiveRatchet(
    RatchetSessionState session,
    String newRemoteDhPublicKey,
  ) async {
    session.previousChainLength = session.sendCount;
    session.sendCount = 0;
    session.receiveCount = 0;
    session.remoteDhPublicKey = newRemoteDhPublicKey;

    final receivingDhOutput = await _dh(
      localDhKeyPair: session.localDhKeyPair,
      remoteDhPublicKey: newRemoteDhPublicKey,
    );

    final receivingRootOutput = await _kdfRoot(
      currentRootKey: session.rootKey,
      dhOutput: receivingDhOutput,
    );

    session.rootKey = receivingRootOutput.rootKey;
    session.receivingChainKey = receivingRootOutput.chainKey;

    final nextLocalDhKeyPair = await generateDhKeyPair();
    session.localDhKeyPair = nextLocalDhKeyPair;

    final sendingDhOutput = await _dh(
      localDhKeyPair: nextLocalDhKeyPair,
      remoteDhPublicKey: newRemoteDhPublicKey,
    );

    final sendingRootOutput = await _kdfRoot(
      currentRootKey: session.rootKey,
      dhOutput: sendingDhOutput,
    );

    session.rootKey = sendingRootOutput.rootKey;
    session.sendingChainKey = sendingRootOutput.chainKey;
    session.pendingSendRatchet = false;
  }

  Future<List<int>> _dh({
    required SimpleKeyPairData localDhKeyPair,
    required String remoteDhPublicKey,
  }) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localDhKeyPair,
      remotePublicKey: SimplePublicKey(
        _decode(remoteDhPublicKey),
        type: KeyPairType.x25519,
      ),
    );

    return sharedSecret.extractBytes();
  }

  Future<_RootOutput> _kdfRoot({
    required List<int> currentRootKey,
    required List<int> dhOutput,
  }) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(dhOutput),
      nonce: currentRootKey,
      info: utf8.encode('ghostlink/double-ratchet/root'),
      outputLength: 64,
    );

    final bytes = await derived.extractBytes();
    return _RootOutput(
      rootKey: bytes.sublist(0, 32),
      chainKey: bytes.sublist(32, 64),
    );
  }

  Future<List<int>> _deriveMessageKey(List<int> chainKey) async {
    final mac = await _hmac.calculateMac(
      const [0x01],
      secretKey: SecretKey(chainKey),
    );
    return mac.bytes;
  }

  Future<List<int>> _deriveNextChainKey(List<int> chainKey) async {
    final mac = await _hmac.calculateMac(
      const [0x02],
      secretKey: SecretKey(chainKey),
    );
    return mac.bytes;
  }

  String _encode(List<int> value) {
    return base64UrlEncode(value).replaceAll('=', '');
  }

  List<int> _decode(String value) {
    final mod = value.length % 4;
    final padded = mod == 0 ? value : '$value${'=' * (4 - mod)}';
    return base64Url.decode(padded);
  }
}

class _RootOutput {
  final List<int> rootKey;
  final List<int> chainKey;

  const _RootOutput({
    required this.rootKey,
    required this.chainKey,
  });
}
