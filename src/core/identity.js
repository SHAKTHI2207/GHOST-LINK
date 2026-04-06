import { createHash, randomBytes } from 'node:crypto';
import {
  createOneTimePreKeys,
  createSignedPreKey,
  generateEd25519KeyPair,
  generateX25519KeyPair
} from './prekeys.js';
import { getDataPaths, readJson, writeJson } from './storage.js';

const IDENTITY_SCHEMA_VERSION = 2;
const DEFAULT_ONE_TIME_PREKEY_COUNT = 20;

function randomId() {
  return randomBytes(6).toString('hex');
}

function normalizeOneTimePreKey(key) {
  return {
    id: key.id,
    createdAt: key.createdAt || new Date().toISOString(),
    publicKeyPem: key.publicKeyPem,
    privateKeyPem: key.privateKeyPem,
    consumedAt: key.consumedAt || null
  };
}

function createIdentityRecord(id, oneTimePreKeyCount = DEFAULT_ONE_TIME_PREKEY_COUNT) {
  const identityKey = generateX25519KeyPair();
  const identitySigningKey = generateEd25519KeyPair();

  return {
    schemaVersion: IDENTITY_SCHEMA_VERSION,
    id: id || randomId(),
    createdAt: new Date().toISOString(),
    identityKey,
    identitySigningKey,
    signedPreKey: createSignedPreKey(identitySigningKey.privateKeyPem),
    oneTimePreKeys: createOneTimePreKeys(oneTimePreKeyCount)
  };
}

function hydrateIdentity(rawIdentity, fallbackId) {
  if (!rawIdentity) {
    return { identity: null, changed: false };
  }

  if (
    rawIdentity.identityKey &&
    rawIdentity.identitySigningKey &&
    rawIdentity.signedPreKey &&
    Array.isArray(rawIdentity.oneTimePreKeys)
  ) {
    const hydrated = {
      schemaVersion: IDENTITY_SCHEMA_VERSION,
      id: rawIdentity.id || fallbackId || randomId(),
      createdAt: rawIdentity.createdAt || new Date().toISOString(),
      identityKey: {
        publicKeyPem: rawIdentity.identityKey.publicKeyPem,
        privateKeyPem: rawIdentity.identityKey.privateKeyPem
      },
      identitySigningKey: {
        publicKeyPem: rawIdentity.identitySigningKey.publicKeyPem,
        privateKeyPem: rawIdentity.identitySigningKey.privateKeyPem
      },
      signedPreKey: {
        id: rawIdentity.signedPreKey.id,
        createdAt: rawIdentity.signedPreKey.createdAt,
        publicKeyPem: rawIdentity.signedPreKey.publicKeyPem,
        privateKeyPem: rawIdentity.signedPreKey.privateKeyPem,
        signature: rawIdentity.signedPreKey.signature
      },
      oneTimePreKeys: rawIdentity.oneTimePreKeys.map(normalizeOneTimePreKey)
    };

    return {
      identity: hydrated,
      changed: rawIdentity.schemaVersion !== IDENTITY_SCHEMA_VERSION
    };
  }

  const migrated = createIdentityRecord(fallbackId || rawIdentity.id || randomId());

  if (rawIdentity.publicKeyPem && rawIdentity.privateKeyPem) {
    migrated.identityKey = {
      publicKeyPem: rawIdentity.publicKeyPem,
      privateKeyPem: rawIdentity.privateKeyPem
    };
  }

  if (rawIdentity.id) {
    migrated.id = rawIdentity.id;
  }

  if (rawIdentity.createdAt) {
    migrated.createdAt = rawIdentity.createdAt;
  }

  return { identity: migrated, changed: true };
}

export function fingerprintPublicKey(publicKeyPem) {
  return createHash('sha256').update(publicKeyPem).digest('hex');
}

export function formatFingerprint(fingerprintHex) {
  return fingerprintHex.match(/.{1,2}/g).join(':');
}

export function shortFingerprint(publicKeyPem) {
  return fingerprintPublicKey(publicKeyPem).slice(0, 16);
}

export function getPublicIdentity(identity) {
  return {
    id: identity.id,
    identityKey: identity.identityKey.publicKeyPem,
    identitySigningKey: identity.identitySigningKey.publicKeyPem,
    fingerprint: fingerprintPublicKey(identity.identityKey.publicKeyPem),
    fingerprintFormatted: formatFingerprint(fingerprintPublicKey(identity.identityKey.publicKeyPem))
  };
}

export function availableOneTimePreKeys(identity) {
  return identity.oneTimePreKeys.filter((key) => key.consumedAt === null);
}

export async function saveIdentity(baseDir, identity) {
  const dataPaths = getDataPaths(baseDir);
  await writeJson(dataPaths.identityFile, identity);
}

export async function loadIdentity(baseDir) {
  const dataPaths = getDataPaths(baseDir);
  const rawIdentity = await readJson(dataPaths.identityFile, null);
  const hydrated = hydrateIdentity(rawIdentity);
  return hydrated.identity;
}

export async function createOrLoadIdentity(baseDir, requestedId, options = {}) {
  const dataPaths = getDataPaths(baseDir);
  const oneTimePreKeyCount = Number(options.oneTimePreKeyCount || DEFAULT_ONE_TIME_PREKEY_COUNT);
  const rawIdentity = await readJson(dataPaths.identityFile, null);
  const hydrated = hydrateIdentity(rawIdentity, requestedId);

  if (hydrated.identity === null) {
    const created = createIdentityRecord(requestedId, oneTimePreKeyCount);
    await writeJson(dataPaths.identityFile, created);
    return created;
  }

  const identity = hydrated.identity;
  let changed = hydrated.changed;

  const availableCount = availableOneTimePreKeys(identity).length;
  if (availableCount < oneTimePreKeyCount) {
    identity.oneTimePreKeys.push(...createOneTimePreKeys(oneTimePreKeyCount - availableCount));
    changed = true;
  }

  if (changed) {
    await writeJson(dataPaths.identityFile, identity);
  }

  return identity;
}

export async function ensureOneTimePreKeys(baseDir, minimumCount = 10, targetCount = 20) {
  let identity = await loadIdentity(baseDir);
  if (identity === null) {
    identity = await createOrLoadIdentity(baseDir, undefined, { oneTimePreKeyCount: targetCount });
  }

  const availableCount = availableOneTimePreKeys(identity).length;

  if (availableCount >= minimumCount) {
    return identity;
  }

  const required = targetCount - availableCount;
  if (required <= 0) {
    return identity;
  }

  identity.oneTimePreKeys.push(...createOneTimePreKeys(required));
  await saveIdentity(baseDir, identity);
  return identity;
}

export async function consumeOneTimePreKey(baseDir, oneTimePreKeyId) {
  const identity = await loadIdentity(baseDir);
  if (identity === null) {
    throw new Error('Identity missing. Run init first.');
  }

  const matchIndex = identity.oneTimePreKeys.findIndex((key) => key.id === oneTimePreKeyId);
  if (matchIndex < 0) {
    return null;
  }

  const [consumedKey] = identity.oneTimePreKeys.splice(matchIndex, 1);
  consumedKey.consumedAt = new Date().toISOString();
  await saveIdentity(baseDir, identity);

  return consumedKey;
}

export async function rotateSignedPreKey(baseDir) {
  const identity = await loadIdentity(baseDir);
  if (identity === null) {
    throw new Error('Identity missing. Run init first.');
  }

  identity.signedPreKey = createSignedPreKey(identity.identitySigningKey.privateKeyPem);
  await saveIdentity(baseDir, identity);
  return identity.signedPreKey;
}
