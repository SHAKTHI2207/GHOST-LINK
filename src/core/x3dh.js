import { createPrivateKey, createPublicKey, diffieHellman, hkdfSync } from 'node:crypto';
import { generateX25519KeyPair, verifySignedPreKey } from './prekeys.js';

const X3DH_SALT = Buffer.from('ghostlink-x3dh-v1', 'utf8');
const X3DH_MASTER_INFO = Buffer.from('ghostlink/x3dh/master', 'utf8');
const X3DH_MESSAGE_KEY_SALT = Buffer.from('ghostlink-x3dh-message-v1', 'utf8');
const X3DH_MESSAGE_KEY_INFO = Buffer.from('ghostlink/x3dh/message-key', 'utf8');

function computeDiffieHellman(privateKeyPem, publicKeyPem) {
  const localPrivateKey = createPrivateKey(privateKeyPem);
  const remotePublicKey = createPublicKey(publicKeyPem);
  return diffieHellman({ privateKey: localPrivateKey, publicKey: remotePublicKey });
}

function deriveMasterSecret(parts) {
  const inputKeyMaterial = Buffer.concat(parts.map((part) => Buffer.from(part)));
  return Buffer.from(hkdfSync('sha256', inputKeyMaterial, X3DH_SALT, X3DH_MASTER_INFO, 32));
}

export function verifyPrekeyBundleSignature(bundle) {
  if (
    !bundle ||
    typeof bundle.identitySigningKey !== 'string' ||
    !bundle.signedPreKey ||
    typeof bundle.signedPreKey.id !== 'string' ||
    typeof bundle.signedPreKey.publicKeyPem !== 'string' ||
    typeof bundle.signedPreKey.signature !== 'string'
  ) {
    return false;
  }

  return verifySignedPreKey(
    bundle.signedPreKey.id,
    bundle.signedPreKey.publicKeyPem,
    bundle.signedPreKey.signature,
    bundle.identitySigningKey
  );
}

export function generateEphemeralKeyPair() {
  return generateX25519KeyPair();
}

export function deriveX3dhInitiatorSecret(params) {
  const dh1 = computeDiffieHellman(
    params.senderIdentityPrivateKeyPem,
    params.receiverSignedPreKeyPublicKeyPem
  );
  const dh2 = computeDiffieHellman(
    params.senderEphemeralPrivateKeyPem,
    params.receiverIdentityPublicKeyPem
  );
  const dh3 = computeDiffieHellman(
    params.senderEphemeralPrivateKeyPem,
    params.receiverSignedPreKeyPublicKeyPem
  );

  const parts = [dh1, dh2, dh3];

  if (params.receiverOneTimePreKeyPublicKeyPem) {
    const dh4 = computeDiffieHellman(
      params.senderEphemeralPrivateKeyPem,
      params.receiverOneTimePreKeyPublicKeyPem
    );
    parts.push(dh4);
  }

  return deriveMasterSecret(parts);
}

export function deriveX3dhResponderSecret(params) {
  const dh1 = computeDiffieHellman(
    params.receiverSignedPreKeyPrivateKeyPem,
    params.senderIdentityPublicKeyPem
  );
  const dh2 = computeDiffieHellman(
    params.receiverIdentityPrivateKeyPem,
    params.senderEphemeralPublicKeyPem
  );
  const dh3 = computeDiffieHellman(
    params.receiverSignedPreKeyPrivateKeyPem,
    params.senderEphemeralPublicKeyPem
  );

  const parts = [dh1, dh2, dh3];

  if (params.receiverOneTimePreKeyPrivateKeyPem) {
    const dh4 = computeDiffieHellman(
      params.receiverOneTimePreKeyPrivateKeyPem,
      params.senderEphemeralPublicKeyPem
    );
    parts.push(dh4);
  }

  return deriveMasterSecret(parts);
}

export function deriveX3dhMessageKey(masterSecret) {
  return Buffer.from(
    hkdfSync('sha256', masterSecret, X3DH_MESSAGE_KEY_SALT, X3DH_MESSAGE_KEY_INFO, 32)
  );
}
