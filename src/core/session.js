import { createPrivateKey, createPublicKey, diffieHellman, hkdfSync } from 'node:crypto';

const HKDF_SALT = Buffer.from('ghostlink-hkdf-v1', 'utf8');

export function deriveSharedSecret(localPrivateKeyPem, remotePublicKeyPem) {
  const localPrivateKey = createPrivateKey(localPrivateKeyPem);
  const remotePublicKey = createPublicKey(remotePublicKeyPem);
  return diffieHellman({ privateKey: localPrivateKey, publicKey: remotePublicKey });
}

export function deriveMessageKey(sharedSecret, senderId, counter) {
  const info = Buffer.from('ghostlink/message/' + senderId + '/' + String(counter), 'utf8');
  return Buffer.from(hkdfSync('sha256', sharedSecret, HKDF_SALT, info, 32));
}
