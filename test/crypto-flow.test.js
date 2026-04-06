import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { decryptMessage, encryptMessage } from '../src/core/message-crypto.js';
import {
  availableOneTimePreKeys,
  consumeOneTimePreKey,
  createOrLoadIdentity,
  ensureOneTimePreKeys,
  loadIdentity
} from '../src/core/identity.js';
import {
  createOneTimePreKey,
  createSignedPreKey,
  generateEd25519KeyPair,
  generateX25519KeyPair
} from '../src/core/prekeys.js';
import {
  deriveX3dhInitiatorSecret,
  deriveX3dhMessageKey,
  deriveX3dhResponderSecret,
  generateEphemeralKeyPair,
  verifyPrekeyBundleSignature
} from '../src/core/x3dh.js';
import { createRelayStateStore } from '../src/relay/state-store.js';

test('x3dh initiator and responder derive same secret and decrypt payload', () => {
  const senderIdentity = generateX25519KeyPair();
  const receiverIdentity = generateX25519KeyPair();
  const receiverSigning = generateEd25519KeyPair();
  const signedPreKey = createSignedPreKey(receiverSigning.privateKeyPem, 'spk-test');
  const oneTimePreKey = createOneTimePreKey('opk-test');

  const bundle = {
    userId: 'bob',
    identityKey: receiverIdentity.publicKeyPem,
    identitySigningKey: receiverSigning.publicKeyPem,
    signedPreKey: {
      id: signedPreKey.id,
      publicKeyPem: signedPreKey.publicKeyPem,
      signature: signedPreKey.signature
    },
    oneTimePreKey: {
      id: oneTimePreKey.id,
      publicKeyPem: oneTimePreKey.publicKeyPem
    }
  };

  assert.equal(verifyPrekeyBundleSignature(bundle), true);

  const senderEphemeral = generateEphemeralKeyPair();

  const initiatorMaster = deriveX3dhInitiatorSecret({
    senderIdentityPrivateKeyPem: senderIdentity.privateKeyPem,
    senderEphemeralPrivateKeyPem: senderEphemeral.privateKeyPem,
    receiverIdentityPublicKeyPem: receiverIdentity.publicKeyPem,
    receiverSignedPreKeyPublicKeyPem: signedPreKey.publicKeyPem,
    receiverOneTimePreKeyPublicKeyPem: oneTimePreKey.publicKeyPem
  });

  const responderMaster = deriveX3dhResponderSecret({
    receiverIdentityPrivateKeyPem: receiverIdentity.privateKeyPem,
    receiverSignedPreKeyPrivateKeyPem: signedPreKey.privateKeyPem,
    receiverOneTimePreKeyPrivateKeyPem: oneTimePreKey.privateKeyPem,
    senderIdentityPublicKeyPem: senderIdentity.publicKeyPem,
    senderEphemeralPublicKeyPem: senderEphemeral.publicKeyPem
  });

  assert.deepEqual(initiatorMaster, responderMaster);

  const senderMessageKey = deriveX3dhMessageKey(initiatorMaster);
  const receiverMessageKey = deriveX3dhMessageKey(responderMaster);
  assert.deepEqual(senderMessageKey, receiverMessageKey);

  const payload = encryptMessage('hello from x3dh', senderMessageKey);
  const plaintext = decryptMessage(payload, receiverMessageKey);
  assert.equal(plaintext, 'hello from x3dh');
});

test('signed prekey verification fails for tampered signature', () => {
  const receiverSigning = generateEd25519KeyPair();
  const signedPreKey = createSignedPreKey(receiverSigning.privateKeyPem, 'spk-tamper');

  const invalidBundle = {
    userId: 'bob',
    identityKey: generateX25519KeyPair().publicKeyPem,
    identitySigningKey: receiverSigning.publicKeyPem,
    signedPreKey: {
      id: signedPreKey.id,
      publicKeyPem: signedPreKey.publicKeyPem,
      signature: signedPreKey.signature.slice(2) + 'ab'
    }
  };

  assert.equal(verifyPrekeyBundleSignature(invalidBundle), false);
});

test('relay store consumes one-time prekeys only once', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'ghostlink-relay-test-'));

  try {
    const store = await createRelayStateStore(path.join(tempDir, 'relay-state.json'));

    await store.publishPrekeyBundle('bob', {
      userId: 'bob',
      identityKey: 'IK',
      identitySigningKey: 'ISK',
      signedPreKey: {
        id: 'spk1',
        publicKeyPem: 'SPK',
        signature: 'SIG'
      },
      oneTimePreKeys: [
        { id: 'opk1', publicKeyPem: 'OPK1' },
        { id: 'opk2', publicKeyPem: 'OPK2' }
      ]
    });

    const first = await store.fetchPrekeyBundle('bob');
    const second = await store.fetchPrekeyBundle('bob');
    const third = await store.fetchPrekeyBundle('bob');

    assert.equal(first.oneTimePreKey.id, 'opk1');
    assert.equal(second.oneTimePreKey.id, 'opk2');
    assert.equal(third.oneTimePreKey, null);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});

test('local identity consumes one-time prekeys after use', async () => {
  const tempDir = await mkdtemp(path.join(os.tmpdir(), 'ghostlink-identity-test-'));

  try {
    await createOrLoadIdentity(tempDir, 'alice', { oneTimePreKeyCount: 3 });
    const identity = await loadIdentity(tempDir);
    const firstOpk = availableOneTimePreKeys(identity)[0];

    await consumeOneTimePreKey(tempDir, firstOpk.id);

    const afterConsume = await loadIdentity(tempDir);
    assert.equal(availableOneTimePreKeys(afterConsume).length, 2);

    await ensureOneTimePreKeys(tempDir, 5, 6);
    const replenished = await loadIdentity(tempDir);
    assert.equal(availableOneTimePreKeys(replenished).length, 6);
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
});
