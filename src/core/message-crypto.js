import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

const NONCE_SIZE = 12;
const AUTH_TAG_SIZE = 16;

export function encryptMessage(plaintext, messageKey) {
  const nonce = randomBytes(NONCE_SIZE);
  const cipher = createCipheriv('chacha20-poly1305', messageKey, nonce, {
    authTagLength: AUTH_TAG_SIZE
  });

  const ciphertext = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const authTag = cipher.getAuthTag();

  return {
    nonce: nonce.toString('base64'),
    ciphertext: ciphertext.toString('base64'),
    authTag: authTag.toString('base64')
  };
}

export function decryptMessage(payload, messageKey) {
  const nonce = Buffer.from(payload.nonce, 'base64');
  const ciphertext = Buffer.from(payload.ciphertext, 'base64');
  const authTag = Buffer.from(payload.authTag, 'base64');

  const decipher = createDecipheriv('chacha20-poly1305', messageKey, nonce, {
    authTagLength: AUTH_TAG_SIZE
  });
  decipher.setAuthTag(authTag);

  const plaintext = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return plaintext.toString('utf8');
}
