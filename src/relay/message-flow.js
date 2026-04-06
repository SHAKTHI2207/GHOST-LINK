import { decryptMessage, encryptMessage } from '../core/message-crypto.js';
import {
  deriveX3dhInitiatorSecret,
  deriveX3dhMessageKey,
  deriveX3dhResponderSecret,
  generateEphemeralKeyPair
} from '../core/x3dh.js';

export function createEncryptedX3dhPacket(senderIdentity, receiverBundle, plaintext) {
  const ephemeralKeyPair = generateEphemeralKeyPair();

  const masterSecret = deriveX3dhInitiatorSecret({
    senderIdentityPrivateKeyPem: senderIdentity.identityKey.privateKeyPem,
    senderEphemeralPrivateKeyPem: ephemeralKeyPair.privateKeyPem,
    receiverIdentityPublicKeyPem: receiverBundle.identityKey,
    receiverSignedPreKeyPublicKeyPem: receiverBundle.signedPreKey.publicKeyPem,
    receiverOneTimePreKeyPublicKeyPem: receiverBundle.oneTimePreKey
      ? receiverBundle.oneTimePreKey.publicKeyPem
      : null
  });

  const messageKey = deriveX3dhMessageKey(masterSecret);
  const encryptedPayload = encryptMessage(plaintext, messageKey);

  return {
    version: 1,
    kind: 'x3dh_init',
    from: senderIdentity.id,
    sentAt: new Date().toISOString(),
    x3dh: {
      senderIdentityKey: senderIdentity.identityKey.publicKeyPem,
      senderEphemeralKey: ephemeralKeyPair.publicKeyPem,
      receiverSignedPreKeyId: receiverBundle.signedPreKey.id,
      receiverOneTimePreKeyId: receiverBundle.oneTimePreKey ? receiverBundle.oneTimePreKey.id : null
    },
    body: encryptedPayload
  };
}

function resolveReceiverOneTimePreKey(identity, oneTimePreKeyId) {
  if (!oneTimePreKeyId) {
    return null;
  }

  const oneTimePreKey = identity.oneTimePreKeys.find((key) => key.id === oneTimePreKeyId);
  return oneTimePreKey || null;
}

export function decryptX3dhPacket(receiverIdentity, senderContact, packet) {
  if (!packet || packet.kind !== 'x3dh_init' || !packet.x3dh || !packet.body) {
    throw new Error('Invalid x3dh packet.');
  }

  if (
    senderContact &&
    senderContact.identityKeyPem &&
    senderContact.identityKeyPem !== packet.x3dh.senderIdentityKey
  ) {
    throw new Error('Sender identity key mismatch. Verification failed.');
  }

  if (receiverIdentity.signedPreKey.id !== packet.x3dh.receiverSignedPreKeyId) {
    throw new Error('Signed prekey id mismatch. Rotate synchronization required.');
  }

  const oneTimePreKey = resolveReceiverOneTimePreKey(
    receiverIdentity,
    packet.x3dh.receiverOneTimePreKeyId
  );

  if (packet.x3dh.receiverOneTimePreKeyId && !oneTimePreKey) {
    throw new Error('One-time prekey not available.');
  }

  const masterSecret = deriveX3dhResponderSecret({
    receiverIdentityPrivateKeyPem: receiverIdentity.identityKey.privateKeyPem,
    receiverSignedPreKeyPrivateKeyPem: receiverIdentity.signedPreKey.privateKeyPem,
    receiverOneTimePreKeyPrivateKeyPem: oneTimePreKey ? oneTimePreKey.privateKeyPem : null,
    senderIdentityPublicKeyPem: packet.x3dh.senderIdentityKey,
    senderEphemeralPublicKeyPem: packet.x3dh.senderEphemeralKey
  });

  const messageKey = deriveX3dhMessageKey(masterSecret);
  const plaintext = decryptMessage(packet.body, messageKey);

  return {
    plaintext,
    senderId: packet.from,
    sentAt: packet.sentAt,
    oneTimePreKeyId: packet.x3dh.receiverOneTimePreKeyId || null
  };
}
