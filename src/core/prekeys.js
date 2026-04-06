import {
  createPrivateKey,
  createPublicKey,
  generateKeyPairSync,
  randomBytes,
  sign,
  verify
} from 'node:crypto';

function randomKeyId(prefix) {
  return `${prefix}-${randomBytes(5).toString('hex')}`;
}

export function generateX25519KeyPair() {
  const keyPair = generateKeyPairSync('x25519');
  return {
    publicKeyPem: keyPair.publicKey.export({ type: 'spki', format: 'pem' }).toString(),
    privateKeyPem: keyPair.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
  };
}

export function generateEd25519KeyPair() {
  const keyPair = generateKeyPairSync('ed25519');
  return {
    publicKeyPem: keyPair.publicKey.export({ type: 'spki', format: 'pem' }).toString(),
    privateKeyPem: keyPair.privateKey.export({ type: 'pkcs8', format: 'pem' }).toString()
  };
}

export function signedPreKeyMessage(signedPreKeyId, signedPreKeyPublicKeyPem) {
  return Buffer.from(
    `ghostlink/spk/v1/${signedPreKeyId}/${signedPreKeyPublicKeyPem.trim()}`,
    'utf8'
  );
}

export function signSignedPreKey(signedPreKeyId, signedPreKeyPublicKeyPem, identitySigningPrivateKeyPem) {
  const payload = signedPreKeyMessage(signedPreKeyId, signedPreKeyPublicKeyPem);
  const identitySigningPrivateKey = createPrivateKey(identitySigningPrivateKeyPem);
  return sign(null, payload, identitySigningPrivateKey).toString('base64');
}

export function verifySignedPreKey(
  signedPreKeyId,
  signedPreKeyPublicKeyPem,
  signatureBase64,
  identitySigningPublicKeyPem
) {
  try {
    const payload = signedPreKeyMessage(signedPreKeyId, signedPreKeyPublicKeyPem);
    const identitySigningPublicKey = createPublicKey(identitySigningPublicKeyPem);
    return verify(
      null,
      payload,
      identitySigningPublicKey,
      Buffer.from(signatureBase64, 'base64')
    );
  } catch {
    return false;
  }
}

export function createSignedPreKey(identitySigningPrivateKeyPem, id) {
  const keyPair = generateX25519KeyPair();
  const signedPreKeyId = id || randomKeyId('spk');

  return {
    id: signedPreKeyId,
    createdAt: new Date().toISOString(),
    publicKeyPem: keyPair.publicKeyPem,
    privateKeyPem: keyPair.privateKeyPem,
    signature: signSignedPreKey(signedPreKeyId, keyPair.publicKeyPem, identitySigningPrivateKeyPem)
  };
}

export function createOneTimePreKey(id) {
  const keyPair = generateX25519KeyPair();
  return {
    id: id || randomKeyId('opk'),
    createdAt: new Date().toISOString(),
    publicKeyPem: keyPair.publicKeyPem,
    privateKeyPem: keyPair.privateKeyPem,
    consumedAt: null
  };
}

export function createOneTimePreKeys(count) {
  const keys = [];
  for (let index = 0; index < count; index += 1) {
    keys.push(createOneTimePreKey());
  }
  return keys;
}

export function toPublicPrekeyBundle(identity) {
  const availableOneTimePreKeys = identity.oneTimePreKeys
    .filter((key) => key.consumedAt === null)
    .map((key) => ({
      id: key.id,
      publicKeyPem: key.publicKeyPem
    }));

  return {
    version: 1,
    userId: identity.id,
    identityKey: identity.identityKey.publicKeyPem,
    identitySigningKey: identity.identitySigningKey.publicKeyPem,
    signedPreKey: {
      id: identity.signedPreKey.id,
      publicKeyPem: identity.signedPreKey.publicKeyPem,
      signature: identity.signedPreKey.signature,
      createdAt: identity.signedPreKey.createdAt
    },
    oneTimePreKeys: availableOneTimePreKeys
  };
}

export function prekeyBundleHasRequiredFields(bundle) {
  return (
    bundle &&
    typeof bundle === 'object' &&
    typeof bundle.userId === 'string' &&
    typeof bundle.identityKey === 'string' &&
    typeof bundle.identitySigningKey === 'string' &&
    bundle.signedPreKey &&
    typeof bundle.signedPreKey.id === 'string' &&
    typeof bundle.signedPreKey.publicKeyPem === 'string' &&
    typeof bundle.signedPreKey.signature === 'string'
  );
}
