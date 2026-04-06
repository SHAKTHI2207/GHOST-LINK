import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/fingerprint.dart';
import '../../models/chat_contact.dart';
import '../../models/message.dart';
import '../../models/user.dart';
import '../../services/crypto_service.dart';
import '../../services/double_ratchet_service.dart';
import '../../services/identity_service.dart';
import '../../services/secure_state_store.dart';
import '../../services/verification_service.dart';
import '../../services/websocket_service.dart';
import '../../services/x3dh_service.dart';

class GhostLinkController extends ChangeNotifier {
  final CryptoService _crypto = CryptoService();
  late final VerificationService _verification = VerificationService(_crypto);
  late final IdentityService _identityService = IdentityService(_verification);
  late final DoubleRatchetService _doubleRatchet = DoubleRatchetService(_crypto);
  final SecureStateStore _secureStateStore = SecureStateStore();
  final WebSocketService _webSocket = WebSocketService();
  final X3dhService _x3dh = X3dhService();

  final Random _random = Random.secure();

  GhostIdentity? identity;
  LocalIdentityMaterial? _localIdentity;

  final List<ChatContact> _contacts = [];
  final Map<String, List<ChatMessage>> _messagesByContact = {};
  final Map<String, RatchetSessionState> _ratchetSessions = {};

  StreamSubscription<Map<String, dynamic>>? _deliverySub;

  String relayUrl = 'ws://127.0.0.1:8080';
  bool relayConnected = false;
  bool stealthMode = false;
  bool showReadReceipts = false;
  Duration selfDestructTimer = Duration.zero;

  bool busy = false;
  bool restoring = true;
  String? errorMessage;

  GhostLinkController() {
    unawaited(_restoreSecureState());
  }

  List<ChatContact> get contacts {
    final sorted = List<ChatContact>.from(_contacts);
    sorted.sort((a, b) {
      final aTime = a.lastMessageAt;
      final bTime = b.lastMessageAt;
      if (aTime == null && bTime == null) {
        return a.displayName.compareTo(b.displayName);
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      return bTime.compareTo(aTime);
    });
    return sorted;
  }

  List<ChatMessage> messagesFor(String contactId) {
    return List.unmodifiable(_messagesByContact[contactId] ?? const []);
  }

  Future<void> createIdentity() async {
    busy = true;
    errorMessage = null;
    notifyListeners();

    try {
      _contacts.clear();
      _messagesByContact.clear();
      _ratchetSessions.clear();

      final generated = await _identityService.generateIdentity(
        userId: _nextUserId(),
        oneTimePreKeyCount: 20,
      );
      identity = generated.identity;
      _localIdentity = generated.material;
      await _persistSecureState();
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> connectRelay({String? urlOverride}) async {
    if (identity == null || _localIdentity == null) {
      throw const StateError('Create identity first.');
    }

    busy = true;
    errorMessage = null;
    notifyListeners();

    try {
      if (urlOverride != null && urlOverride.trim().isNotEmpty) {
        relayUrl = urlOverride.trim();
      }

      await _webSocket.connect(url: relayUrl, userId: identity!.id);

      final bundle = _identityService.buildRelayPreKeyBundle(_localIdentity!);
      await _webSocket.publishPrekeys(bundle.toJson());

      await _deliverySub?.cancel();
      _deliverySub = _webSocket.deliveries.listen((event) {
        _handleDelivery(event);
      });

      relayConnected = true;
      unawaited(_persistSecureState());
    } catch (error) {
      relayConnected = false;
      errorMessage = error.toString();
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> disconnectRelay() async {
    await _deliverySub?.cancel();
    _deliverySub = null;
    await _webSocket.disconnect();
    relayConnected = false;
    unawaited(_persistSecureState());
    notifyListeners();
  }

  Future<void> verifyContactPayload(String rawPayload) async {
    errorMessage = null;

    final payload = _verification.fromUriOrToken(rawPayload);

    final existingIndex = _contacts.indexWhere((item) => item.id == payload.id);

    if (existingIndex == -1) {
      _contacts.add(
        ChatContact(
          id: payload.id,
          displayName: payload.id,
          identityKey: payload.identityKey,
          signingKey: payload.identitySigningKey,
          fingerprint: payload.fingerprint,
          status: ContactTrustStatus.verified,
        ),
      );
      unawaited(_persistSecureState());
      notifyListeners();
      return;
    }

    final existing = _contacts[existingIndex];
    final keyMismatch =
        existing.identityKey != payload.identityKey || existing.signingKey != payload.identitySigningKey;

    _contacts[existingIndex] = existing.copyWith(
      identityKey: payload.identityKey,
      signingKey: payload.identitySigningKey,
      fingerprint: payload.fingerprint,
      status: keyMismatch ? ContactTrustStatus.risk : ContactTrustStatus.verified,
      riskReason: keyMismatch ? 'Fingerprint changed during verification.' : null,
    );

    unawaited(_persistSecureState());
    notifyListeners();
  }

  Future<void> sendMessage({
    required String contactId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final me = identity;
    final local = _localIdentity;
    if (me == null || local == null) {
      throw const StateError('Identity not initialized.');
    }

    if (!relayConnected) {
      await connectRelay();
    }

    if (stealthMode) {
      final jitterMs = 300 + _random.nextInt(900);
      await Future<void>.delayed(Duration(milliseconds: jitterMs));
    }

    await _ensureContactExists(contactId);

    final existingSession = _ratchetSessions[contactId];
    if (existingSession == null) {
      final bundleJson = await _webSocket.fetchPrekeyBundle(contactId);
      final bundle = PreKeyBundle.fromJson(bundleJson);

      final validSignature = await _x3dh.verifyPrekeyBundleSignature(bundle);
      if (!validSignature) {
        throw const StateError('Contact signed prekey signature verification failed.');
      }

      final ephemeral = await _x3dh.generateEphemeralKeyPair();
      final masterSecret = await _x3dh.deriveInitiatorMasterSecret(
        sender: local,
        senderEphemeralKeyPair: ephemeral,
        receiverBundle: bundle,
      );

      final messageKey = await _x3dh.deriveMessageKey(masterSecret);
      final encrypted = await _crypto.encryptMessage(trimmed, messageKey);

      final ratchetSession = await _doubleRatchet.initializeFromX3dh(
        contactId: contactId,
        masterSecret: masterSecret,
        isInitiator: true,
      );
      _ratchetSessions[contactId] = ratchetSession;

      final packet = _x3dh.buildPacket(
        senderId: me.id,
        senderIdentityKey: _identityService.encodePublicKey(local.identityKeyPair.publicKey),
        senderEphemeralKey: _identityService.encodePublicKey(ephemeral.publicKey),
        receiverBundle: bundle,
        senderRatchetKey: _doubleRatchet.encodePublicDhKey(ratchetSession.localDhKeyPair.publicKey),
        body: encrypted.toJson(),
      );

      await _webSocket.sendPacket(to: contactId, packet: packet.toJson());
    } else {
      final packet = await _doubleRatchet.encryptMessage(
        session: existingSession,
        senderId: me.id,
        plaintext: trimmed,
      );

      await _webSocket.sendPacket(to: contactId, packet: packet.toJson());
    }

    _appendMessage(
      ChatMessage(
        id: _nextMessageId(),
        contactId: contactId,
        text: trimmed,
        isMe: true,
        createdAt: DateTime.now().toUtc(),
        expiresAt: selfDestructTimer == Duration.zero
            ? null
            : DateTime.now().toUtc().add(selfDestructTimer),
      ),
    );

    unawaited(_persistSecureState());
  }

  void setStealthMode(bool enabled) {
    stealthMode = enabled;
    unawaited(_persistSecureState());
    notifyListeners();
  }

  void setSelfDestructTimer(Duration duration) {
    selfDestructTimer = duration;
    unawaited(_persistSecureState());
    notifyListeners();
  }

  void setReadReceipts(bool enabled) {
    showReadReceipts = enabled;
    unawaited(_persistSecureState());
    notifyListeners();
  }

  void deleteMessage(String contactId, String messageId) {
    final messages = _messagesByContact[contactId];
    if (messages == null) {
      return;
    }

    messages.removeWhere((item) => item.id == messageId);
    unawaited(_persistSecureState());
    notifyListeners();
  }

  void clearChat(String contactId) {
    _messagesByContact.remove(contactId);

    final index = _contacts.indexWhere((item) => item.id == contactId);
    if (index != -1) {
      _contacts[index] = _contacts[index].copyWith(
        lastMessagePreview: 'No messages yet',
        lastMessageAt: null,
      );
    }

    unawaited(_persistSecureState());
    notifyListeners();
  }

  Future<void> _handleDelivery(Map<String, dynamic> envelope) async {
    final local = _localIdentity;
    if (local == null) {
      return;
    }

    try {
      final from = envelope['from'] as String?;
      final packetRaw = envelope['packet'];

      if (from == null || packetRaw is! Map) {
        return;
      }

      final packetJson = Map<String, dynamic>.from(packetRaw);
      final kind = packetJson['kind'] as String?;
      if (kind == null) {
        return;
      }

      if (kind == 'x3dh_init') {
        final packet = X3dhMessagePacket.fromJson(packetJson);
        final masterSecret = await _x3dh.deriveResponderMasterSecret(
          receiver: local,
          header: packet.x3dh,
        );
        final messageKey = await _x3dh.deriveMessageKey(masterSecret);
        final plaintext = await _crypto.decryptMessage(packet.body, messageKey);

        final senderRatchetKey = packet.senderRatchetKey;
        if (senderRatchetKey == null || senderRatchetKey.isEmpty) {
          throw const StateError('Missing sender ratchet key in X3DH packet.');
        }

        final ratchetSession = await _doubleRatchet.initializeFromX3dh(
          contactId: from,
          masterSecret: masterSecret,
          isInitiator: false,
          remoteDhPublicKey: senderRatchetKey,
        );
        _ratchetSessions[from] = ratchetSession;

        await _upsertContactFromIncoming(from, packet.x3dh.senderIdentityKey);

        _appendMessage(
          ChatMessage(
            id: _nextMessageId(),
            contactId: from,
            text: plaintext,
            isMe: false,
            createdAt: DateTime.tryParse(packet.sentAt)?.toUtc() ?? DateTime.now().toUtc(),
            status: 'delivered',
          ),
        );

        unawaited(_persistSecureState());
        return;
      }

      if (kind == 'dr_msg') {
        final packet = RatchetMessagePacket.fromJson(packetJson);
        final ratchetSession = _ratchetSessions[from];
        if (ratchetSession == null) {
          throw const StateError('No ratchet session available for incoming message.');
        }

        final plaintext = await _doubleRatchet.decryptMessage(
          session: ratchetSession,
          packet: packet,
        );

        await _ensureContactExists(from);

        _appendMessage(
          ChatMessage(
            id: _nextMessageId(),
            contactId: from,
            text: plaintext,
            isMe: false,
            createdAt: DateTime.tryParse(packet.sentAt)?.toUtc() ?? DateTime.now().toUtc(),
            status: 'delivered',
          ),
        );

        unawaited(_persistSecureState());
      }
    } catch (error) {
      errorMessage = error.toString();
      notifyListeners();
    }
  }

  Future<void> _ensureContactExists(String contactId) async {
    final index = _contacts.indexWhere((item) => item.id == contactId);
    if (index != -1) {
      return;
    }

    _contacts.add(
      ChatContact(
        id: contactId,
        displayName: contactId,
        identityKey: '',
        signingKey: '',
        fingerprint: '',
        status: ContactTrustStatus.unverified,
      ),
    );
  }

  Future<void> _upsertContactFromIncoming(String contactId, String senderIdentityKey) async {
    final index = _contacts.indexWhere((item) => item.id == contactId);
    final fingerprint = formatFingerprint(await _crypto.sha256Fingerprint(senderIdentityKey));

    if (index == -1) {
      _contacts.add(
        ChatContact(
          id: contactId,
          displayName: contactId,
          identityKey: senderIdentityKey,
          signingKey: '',
          fingerprint: fingerprint,
          status: ContactTrustStatus.unverified,
        ),
      );
      notifyListeners();
      return;
    }

    final existing = _contacts[index];
    if (existing.identityKey.isEmpty) {
      _contacts[index] = existing.copyWith(
        identityKey: senderIdentityKey,
        fingerprint: fingerprint,
      );
      notifyListeners();
      return;
    }

    if (existing.identityKey == senderIdentityKey) {
      return;
    }

    _contacts[index] = existing.copyWith(
      status: ContactTrustStatus.risk,
      riskReason: 'Incoming sender key does not match verified key.',
    );
    notifyListeners();
  }

  void _appendMessage(ChatMessage message) {
    final list = _messagesByContact.putIfAbsent(message.contactId, () => <ChatMessage>[]);
    list.add(message);

    final contactIndex = _contacts.indexWhere((item) => item.id == message.contactId);
    if (contactIndex != -1) {
      _contacts[contactIndex] = _contacts[contactIndex].copyWith(
        lastMessagePreview: message.text,
        lastMessageAt: message.createdAt,
      );
    }

    notifyListeners();
  }

  Future<void> _restoreSecureState() async {
    try {
      final snapshot = await _secureStateStore.load();
      if (snapshot == null) {
        return;
      }

      identity = snapshot.identity;
      _localIdentity = snapshot.localIdentity;

      _contacts
        ..clear()
        ..addAll(snapshot.contacts);

      _ratchetSessions
        ..clear()
        ..addAll(snapshot.ratchetSessions);

      relayUrl = snapshot.relayUrl;
      stealthMode = snapshot.stealthMode;
      showReadReceipts = snapshot.showReadReceipts;
      selfDestructTimer = Duration(seconds: snapshot.selfDestructSeconds);
    } catch (error) {
      errorMessage = 'Secure storage restore failed: $error';
    } finally {
      restoring = false;
      notifyListeners();
    }
  }

  Future<void> _persistSecureState() async {
    final currentIdentity = identity;
    final localIdentity = _localIdentity;

    if (currentIdentity == null || localIdentity == null) {
      return;
    }

    final snapshot = SecureStateSnapshot(
      identity: currentIdentity,
      localIdentity: localIdentity,
      contacts: List<ChatContact>.from(_contacts),
      ratchetSessions: Map<String, RatchetSessionState>.from(_ratchetSessions),
      relayUrl: relayUrl,
      stealthMode: stealthMode,
      showReadReceipts: showReadReceipts,
      selfDestructSeconds: selfDestructTimer.inSeconds,
    );

    try {
      await _secureStateStore.save(snapshot);
    } catch (error) {
      errorMessage = 'Secure storage save failed: $error';
      notifyListeners();
    }
  }

  String _nextUserId() {
    final token = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return 'user-$token$suffix';
  }

  String _nextMessageId() {
    final ms = DateTime.now().microsecondsSinceEpoch;
    final random = _random.nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'm-$ms-$random';
  }

  @override
  void dispose() {
    unawaited(_deliverySub?.cancel());
    unawaited(_persistSecureState());
    _webSocket.dispose();
    super.dispose();
  }
}
