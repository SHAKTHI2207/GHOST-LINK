import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/chat_contact.dart';
import '../models/user.dart';
import 'double_ratchet_service.dart';
import 'identity_service.dart';

class SecureStateSnapshot {
  final GhostIdentity identity;
  final LocalIdentityMaterial localIdentity;
  final List<ChatContact> contacts;
  final Map<String, RatchetSessionState> ratchetSessions;
  final String relayUrl;
  final bool stealthMode;
  final bool showReadReceipts;
  final int selfDestructSeconds;

  const SecureStateSnapshot({
    required this.identity,
    required this.localIdentity,
    required this.contacts,
    required this.ratchetSessions,
    required this.relayUrl,
    required this.stealthMode,
    required this.showReadReceipts,
    required this.selfDestructSeconds,
  });
}

class SecureStateStore {
  static const String _stateKey = 'ghostlink_secure_state_v1';

  final FlutterSecureStorage _storage;

  SecureStateStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
                resetOnError: true,
                sharedPreferencesName: 'ghostlink_secure_prefs',
                preferencesKeyPrefix: 'ghostlink_',
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  Future<void> save(SecureStateSnapshot snapshot) async {
    final serialized = jsonEncode({
      'identity': _encodeIdentity(snapshot.identity),
      'localIdentity': _encodeLocalIdentity(snapshot.localIdentity),
      'contacts': snapshot.contacts.map(_encodeContact).toList(),
      'ratchetSessions': snapshot.ratchetSessions.map(
        (contactId, state) => MapEntry(contactId, state.toJson()),
      ),
      'settings': {
        'relayUrl': snapshot.relayUrl,
        'stealthMode': snapshot.stealthMode,
        'showReadReceipts': snapshot.showReadReceipts,
        'selfDestructSeconds': snapshot.selfDestructSeconds,
      },
    });

    await _storage.write(key: _stateKey, value: serialized);
  }

  Future<SecureStateSnapshot?> load() async {
    final raw = await _storage.read(key: _stateKey);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    final identity = _decodeIdentity(Map<String, dynamic>.from(decoded['identity'] as Map));
    final localIdentity = _decodeLocalIdentity(
      Map<String, dynamic>.from(decoded['localIdentity'] as Map),
    );

    final rawContacts = (decoded['contacts'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => _decodeContact(Map<String, dynamic>.from(item)))
        .toList();

    final rawSessions = Map<String, dynamic>.from(decoded['ratchetSessions'] as Map? ?? {});
    final ratchetSessions = <String, RatchetSessionState>{};
    for (final entry in rawSessions.entries) {
      ratchetSessions[entry.key] = RatchetSessionState.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    final settings = Map<String, dynamic>.from(decoded['settings'] as Map? ?? {});

    return SecureStateSnapshot(
      identity: identity,
      localIdentity: localIdentity,
      contacts: rawContacts,
      ratchetSessions: ratchetSessions,
      relayUrl: settings['relayUrl'] as String? ?? 'ws://127.0.0.1:8080',
      stealthMode: settings['stealthMode'] as bool? ?? false,
      showReadReceipts: settings['showReadReceipts'] as bool? ?? false,
      selfDestructSeconds: (settings['selfDestructSeconds'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> clear() {
    return _storage.delete(key: _stateKey);
  }

  Map<String, dynamic> _encodeIdentity(GhostIdentity identity) {
    return {
      'id': identity.id,
      'publicIdentityKey': identity.publicIdentityKey,
      'signingPublicKey': identity.signingPublicKey,
      'fingerprint': identity.fingerprint,
      'verificationUri': identity.verificationUri,
      'availableOneTimePreKeys': identity.availableOneTimePreKeys,
    };
  }

  GhostIdentity _decodeIdentity(Map<String, dynamic> json) {
    return GhostIdentity(
      id: json['id'] as String,
      publicIdentityKey: json['publicIdentityKey'] as String,
      signingPublicKey: json['signingPublicKey'] as String,
      fingerprint: json['fingerprint'] as String,
      verificationUri: json['verificationUri'] as String,
      availableOneTimePreKeys: (json['availableOneTimePreKeys'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> _encodeLocalIdentity(LocalIdentityMaterial identity) {
    return {
      'id': identity.id,
      'identityKeyPair': _encodeKeyPair(identity.identityKeyPair),
      'signingKeyPair': _encodeKeyPair(identity.signingKeyPair),
      'signedPreKey': {
        'id': identity.signedPreKey.id,
        'signature': identity.signedPreKey.signature,
        'keyPair': _encodeKeyPair(identity.signedPreKey.keyPair),
      },
      'oneTimePreKeys': identity.oneTimePreKeys
          .map(
            (item) => {
              'id': item.id,
              'consumedAt': item.consumedAt?.toIso8601String(),
              'keyPair': _encodeKeyPair(item.keyPair),
            },
          )
          .toList(),
    };
  }

  LocalIdentityMaterial _decodeLocalIdentity(Map<String, dynamic> json) {
    final signedPreKey = Map<String, dynamic>.from(json['signedPreKey'] as Map);
    final rawOneTimeKeys = (json['oneTimePreKeys'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    return LocalIdentityMaterial(
      id: json['id'] as String,
      identityKeyPair: _decodeKeyPair(
        Map<String, dynamic>.from(json['identityKeyPair'] as Map),
      ),
      signingKeyPair: _decodeKeyPair(
        Map<String, dynamic>.from(json['signingKeyPair'] as Map),
      ),
      signedPreKey: SignedPreKeyMaterial(
        id: signedPreKey['id'] as String,
        keyPair: _decodeKeyPair(
          Map<String, dynamic>.from(signedPreKey['keyPair'] as Map),
        ),
        signature: signedPreKey['signature'] as String,
      ),
      oneTimePreKeys: rawOneTimeKeys
          .map(
            (item) => OneTimePreKeyMaterial(
              id: item['id'] as String,
              keyPair: _decodeKeyPair(
                Map<String, dynamic>.from(item['keyPair'] as Map),
              ),
              consumedAt: _parseDate(item['consumedAt'] as String?),
            ),
          )
          .toList(),
    );
  }

  Map<String, dynamic> _encodeContact(ChatContact contact) {
    return {
      'id': contact.id,
      'displayName': contact.displayName,
      'identityKey': contact.identityKey,
      'signingKey': contact.signingKey,
      'fingerprint': contact.fingerprint,
      'status': contact.status.name,
      'riskReason': contact.riskReason,
      'lastMessagePreview': contact.lastMessagePreview,
      'lastMessageAt': contact.lastMessageAt?.toIso8601String(),
    };
  }

  ChatContact _decodeContact(Map<String, dynamic> json) {
    final statusToken = json['status'] as String? ?? ContactTrustStatus.unverified.name;
    final status = ContactTrustStatus.values.firstWhere(
      (candidate) => candidate.name == statusToken,
      orElse: () => ContactTrustStatus.unverified,
    );

    return ChatContact(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? (json['id'] as String),
      identityKey: json['identityKey'] as String? ?? '',
      signingKey: json['signingKey'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      status: status,
      riskReason: json['riskReason'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: _parseDate(json['lastMessageAt'] as String?),
    );
  }

  Map<String, dynamic> _encodeKeyPair(SimpleKeyPairData keyPair) {
    return {
      'type': keyPair.type.name,
      'privateKey': _encode(keyPair.privateKeyBytes),
      'publicKey': _encode(keyPair.publicKey.bytes),
    };
  }

  SimpleKeyPairData _decodeKeyPair(Map<String, dynamic> json) {
    final typeToken = json['type'] as String? ?? KeyPairType.x25519.name;
    final type = _decodeKeyType(typeToken);

    final publicKey = SimplePublicKey(
      _decode(json['publicKey'] as String),
      type: type,
    );

    return SimpleKeyPairData(
      _decode(json['privateKey'] as String),
      type: type,
      publicKey: publicKey,
    );
  }

  KeyPairType _decodeKeyType(String value) {
    switch (value) {
      case 'ed25519':
        return KeyPairType.ed25519;
      case 'x25519':
      default:
        return KeyPairType.x25519;
    }
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
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
