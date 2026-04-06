#!/usr/bin/env node
import fs from 'node:fs/promises';
import process from 'node:process';
import { getContact, listContacts, markContactVerified, upsertContact } from './core/contacts.js';
import {
  availableOneTimePreKeys,
  consumeOneTimePreKey,
  createOrLoadIdentity,
  ensureOneTimePreKeys,
  getPublicIdentity,
  loadIdentity,
  rotateSignedPreKey
} from './core/identity.js';
import { toPublicPrekeyBundle } from './core/prekeys.js';
import {
  createVerificationObject,
  decodeVerificationPayload,
  encodeVerificationPayload,
  renderVerificationQr,
  verificationPayloadToUri
} from './core/verification.js';
import { verifyPrekeyBundleSignature } from './core/x3dh.js';
import { appendLine, getDataPaths } from './core/storage.js';
import { RelayClient } from './relay/client.js';
import { createEncryptedX3dhPacket, decryptX3dhPacket } from './relay/message-flow.js';
import { startRelayServer } from './relay/server.js';

function printUsage() {
  console.log('GhostLink CLI');
  console.log('');
  console.log('Identity & Verification:');
  console.log('  init --data <dir> --id <user-id> [--opk-count <n>]');
  console.log('  identity --data <dir>');
  console.log('  export-pubkey --data <dir>');
  console.log('  show-qr --data <dir>');
  console.log('  verify-contact --data <dir> --payload <qr-payload-or-uri>');
  console.log('  add-contact --data <dir> --id <contact-id> --identity-key-file <path> [--signing-key-file <path>]');
  console.log('  list-contacts --data <dir>');
  console.log('  rotate-spk --data <dir>');
  console.log('');
  console.log('Relay & Messaging:');
  console.log('  relay-start --state <path> [--host <host>] [--port <port>]');
  console.log('  publish-prekeys --data <dir> --url <ws://host:port>');
  console.log('  listen --data <dir> --url <ws://host:port>');
  console.log('  send --data <dir> --url <ws://host:port> --to <contact-id> --message <text>');
}

function parseOptions(args) {
  const options = {};

  let index = 0;
  while (index < args.length) {
    const key = args[index];
    if (key.startsWith('--') === false) {
      throw new Error('Unexpected token: ' + key);
    }

    const next = args[index + 1];
    if (next === undefined || next.startsWith('--')) {
      options[key.slice(2)] = true;
      index += 1;
    } else {
      options[key.slice(2)] = next;
      index += 2;
    }
  }

  return options;
}

function requireOption(options, key) {
  const value = options[key];
  if (value === undefined || value === '') {
    throw new Error('Missing required option --' + key);
  }
  return value;
}

function parseNumberOption(options, key, fallback) {
  if (options[key] === undefined) {
    return fallback;
  }

  const value = Number(options[key]);
  if (Number.isFinite(value) !== true || value <= 0) {
    throw new Error('Option --' + key + ' must be a positive number.');
  }

  return value;
}

function requireVerifiedContact(contact) {
  if (!contact) {
    throw new Error('Unknown contact.');
  }

  if (contact.verified !== true) {
    throw new Error(
      `Contact ${contact.id} is not verified. Run verify-contact with a scanned QR payload first.`
    );
  }

  if (!contact.identitySigningKeyPem) {
    throw new Error(
      `Contact ${contact.id} is missing identity signing key. Re-verify the contact via QR.`
    );
  }
}

async function withRelayClient(identity, relayUrl, handlers, callback) {
  const client = await RelayClient.connect({
    url: relayUrl,
    userId: identity.id,
    onPacket: handlers.onPacket,
    onError: handlers.onError
  });

  try {
    return await callback(client);
  } finally {
    await client.close();
  }
}

async function publishPrekeysViaRelay(client, identity) {
  const bundle = toPublicPrekeyBundle(identity);
  const response = await client.publishPrekeys(bundle);
  return {
    availableOpkCount: response.availableOpkCount || 0
  };
}

async function commandInit(options) {
  const dataDir = requireOption(options, 'data');
  const id = requireOption(options, 'id');
  const opkCount = parseNumberOption(options, 'opk-count', 20);

  const identity = await createOrLoadIdentity(dataDir, id, { oneTimePreKeyCount: opkCount });
  const pub = getPublicIdentity(identity);

  console.log('Identity ready.');
  console.log('id: ' + pub.id);
  console.log('fingerprint: ' + pub.fingerprintFormatted);
  console.log('signedPreKeyId: ' + identity.signedPreKey.id);
  console.log('availableOneTimePreKeys: ' + String(availableOneTimePreKeys(identity).length));
}

async function commandIdentity(options) {
  const dataDir = requireOption(options, 'data');
  const identity = await loadIdentity(dataDir);

  if (identity === null) {
    throw new Error('Identity not found. Run init first.');
  }

  const pub = getPublicIdentity(identity);
  console.log('id: ' + pub.id);
  console.log('fingerprint: ' + pub.fingerprintFormatted);
  console.log('signedPreKeyId: ' + identity.signedPreKey.id);
  console.log('availableOneTimePreKeys: ' + String(availableOneTimePreKeys(identity).length));
}

async function commandExportPubkey(options) {
  const dataDir = requireOption(options, 'data');
  const identity = await loadIdentity(dataDir);

  if (identity === null) {
    throw new Error('Identity not found. Run init first.');
  }

  process.stdout.write(identity.identityKey.publicKeyPem);
}

async function commandShowQr(options) {
  const dataDir = requireOption(options, 'data');
  const identity = await loadIdentity(dataDir);

  if (identity === null) {
    throw new Error('Identity not found. Run init first.');
  }

  const publicIdentity = getPublicIdentity(identity);
  const verificationObject = createVerificationObject(publicIdentity);
  const payload = encodeVerificationPayload(verificationObject);
  const uri = verificationPayloadToUri(payload);
  const qr = await renderVerificationQr(uri);

  console.log('User: ' + publicIdentity.id);
  console.log('Fingerprint: ' + publicIdentity.fingerprintFormatted);
  console.log('Verification URI:');
  console.log(uri);
  console.log('QR:');
  console.log(qr);
}

async function commandVerifyContact(options) {
  const dataDir = requireOption(options, 'data');
  const payload = requireOption(options, 'payload');
  const parsed = decodeVerificationPayload(payload);

  const existing = await getContact(dataDir, parsed.id);
  if (existing) {
    if (
      existing.identityKeyPem !== parsed.identityKey ||
      (existing.identitySigningKeyPem && existing.identitySigningKeyPem !== parsed.identitySigningKey)
    ) {
      throw new Error(
        `Verification failed for ${parsed.id}: scanned keys do not match the already stored contact.`
      );
    }

    const verified = await upsertContact(dataDir, {
      id: parsed.id,
      identityKeyPem: parsed.identityKey,
      identitySigningKeyPem: parsed.identitySigningKey,
      verified: true,
      verificationMethod: 'qr-scan'
    });

    if (verified.verified !== true) {
      await markContactVerified(dataDir, parsed.id, 'qr-scan');
    }

    console.log('Contact verified.');
    console.log('id: ' + verified.id);
    console.log('fingerprint: ' + verified.fingerprint);
    return;
  }

  const contact = await upsertContact(dataDir, {
    id: parsed.id,
    identityKeyPem: parsed.identityKey,
    identitySigningKeyPem: parsed.identitySigningKey,
    verified: true,
    verificationMethod: 'qr-scan'
  });

  console.log('Contact imported and verified.');
  console.log('id: ' + contact.id);
  console.log('fingerprint: ' + contact.fingerprint);
}

async function commandAddContact(options) {
  const dataDir = requireOption(options, 'data');
  const id = requireOption(options, 'id');
  const identityKeyFile = options['identity-key-file'] || options['pubkey-file'];

  if (!identityKeyFile) {
    throw new Error('Missing required option --identity-key-file');
  }

  const identityKeyPem = await fs.readFile(identityKeyFile, 'utf8');
  const signingKeyFile = options['signing-key-file'];
  const signingKeyPem = signingKeyFile ? await fs.readFile(signingKeyFile, 'utf8') : null;

  const contact = await upsertContact(dataDir, {
    id,
    identityKeyPem,
    identitySigningKeyPem: signingKeyPem,
    verified: false,
    verificationMethod: null
  });

  console.log('Contact added (unverified).');
  console.log('id: ' + contact.id);
  console.log('fingerprint: ' + contact.fingerprint);
  console.log('Use show-qr / verify-contact to verify and prevent MITM.');
}

async function commandListContacts(options) {
  const dataDir = requireOption(options, 'data');
  const contacts = await listContacts(dataDir);

  if (contacts.length === 0) {
    console.log('No contacts yet.');
    return;
  }

  for (const contact of contacts) {
    const verificationState = contact.verified ? 'verified' : 'unverified';
    console.log(
      `${contact.id}  ${contact.fingerprint}  ${verificationState}  added=${contact.addedAt}`
    );
  }
}

async function commandRotateSpk(options) {
  const dataDir = requireOption(options, 'data');
  const signedPreKey = await rotateSignedPreKey(dataDir);

  console.log('Signed prekey rotated.');
  console.log('signedPreKeyId: ' + signedPreKey.id);
}

async function commandRelayStart(options) {
  const stateFile = requireOption(options, 'state');
  const host = options.host || '0.0.0.0';
  const port = parseNumberOption(options, 'port', 8080);

  const relay = await startRelayServer({
    host,
    port,
    stateFile,
    onLog: (line) => {
      console.log('[relay] ' + line);
    }
  });

  console.log(`Relay listening on ws://${relay.host}:${String(relay.port)}`);
  console.log('State file: ' + relay.stateFile);

  process.on('SIGINT', async () => {
    await relay.close();
    console.log('Relay stopped.');
    process.exit(0);
  });
}

async function commandPublishPrekeys(options) {
  const dataDir = requireOption(options, 'data');
  const relayUrl = requireOption(options, 'url');

  let identity = await ensureOneTimePreKeys(dataDir, 10, 30);
  await withRelayClient(identity, relayUrl, {}, async (client) => {
    const published = await publishPrekeysViaRelay(client, identity);
    console.log('Prekeys published.');
    console.log('availableOneTimePreKeysOnRelay: ' + String(published.availableOpkCount));
  });

  identity = await loadIdentity(dataDir);
  if (identity) {
    console.log('availableOneTimePreKeysLocal: ' + String(availableOneTimePreKeys(identity).length));
  }
}

async function handleIncomingRelayPacket(baseDir, envelope) {
  const identity = await loadIdentity(baseDir);
  if (identity === null) {
    throw new Error('Identity missing.');
  }

  if (!envelope.packet || typeof envelope.packet !== 'object') {
    throw new Error('Malformed packet envelope.');
  }

  const senderId = envelope.from || envelope.packet.from;
  if (typeof senderId !== 'string') {
    throw new Error('Missing sender id in packet.');
  }

  const contact = await getContact(baseDir, senderId);
  requireVerifiedContact(contact);

  const decrypted = decryptX3dhPacket(identity, contact, envelope.packet);

  if (decrypted.oneTimePreKeyId) {
    await consumeOneTimePreKey(baseDir, decrypted.oneTimePreKeyId);
  }

  const dataPaths = getDataPaths(baseDir);
  await appendLine(
    dataPaths.inboxLogFile,
    JSON.stringify({
      from: senderId,
      sentAt: decrypted.sentAt,
      receivedAt: new Date().toISOString(),
      oneTimePreKeyId: decrypted.oneTimePreKeyId,
      ciphertext: envelope.packet.body ? envelope.packet.body.ciphertext : null
    })
  );

  return {
    from: senderId,
    sentAt: decrypted.sentAt,
    text: decrypted.plaintext
  };
}

async function commandListen(options) {
  const dataDir = requireOption(options, 'data');
  const relayUrl = requireOption(options, 'url');

  const identity = await ensureOneTimePreKeys(dataDir, 10, 30);

  const client = await RelayClient.connect({
    url: relayUrl,
    userId: identity.id,
    onPacket: (envelope) => {
      handleIncomingRelayPacket(dataDir, envelope)
        .then((message) => {
          console.log('[' + new Date().toISOString() + '] ' + message.from + ': ' + message.text);
        })
        .catch((error) => {
          console.error('Receive error: ' + error.message);
        });
    },
    onError: (error) => {
      console.error('Relay error: ' + error.message);
    }
  });

  const published = await publishPrekeysViaRelay(client, identity);

  console.log('Connected to relay as ' + identity.id);
  console.log('Relay URL: ' + relayUrl);
  console.log('Published OPKs: ' + String(published.availableOpkCount));

  process.on('SIGINT', async () => {
    await client.close();
    console.log('Listener stopped.');
    process.exit(0);
  });
}

async function commandSend(options) {
  const dataDir = requireOption(options, 'data');
  const relayUrl = requireOption(options, 'url');
  const to = requireOption(options, 'to');
  const message = requireOption(options, 'message');

  const identity = await loadIdentity(dataDir);
  if (identity === null) {
    throw new Error('Identity not found. Run init first.');
  }

  const contact = await getContact(dataDir, to);
  requireVerifiedContact(contact);

  await withRelayClient(identity, relayUrl, {}, async (client) => {
    const bundle = await client.fetchPrekeyBundle(to);

    if (bundle.userId !== to) {
      throw new Error('Relay returned wrong prekey bundle target.');
    }

    if (bundle.identityKey !== contact.identityKeyPem) {
      throw new Error('Receiver identity key mismatch. Possible MITM or stale contact.');
    }

    if (bundle.identitySigningKey !== contact.identitySigningKeyPem) {
      throw new Error('Receiver identity signing key mismatch. Possible MITM or stale contact.');
    }

    if (verifyPrekeyBundleSignature(bundle) !== true) {
      throw new Error('Signed prekey signature verification failed.');
    }

    const packet = createEncryptedX3dhPacket(identity, bundle, message);
    const response = await client.sendPacket(to, packet);

    console.log('Encrypted message sent to ' + to);
    console.log('deliveryFanout: ' + String(response.deliveredCount || 0));
    console.log(
      'usedOneTimePreKey: ' +
        (bundle.oneTimePreKey ? bundle.oneTimePreKey.id : 'none (fallback without OPK)')
    );
  });
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length === 0) {
    printUsage();
    process.exit(1);
  }

  const command = args[0];
  const options = parseOptions(args.slice(1));

  if (command === 'init') {
    await commandInit(options);
    return;
  }

  if (command === 'identity') {
    await commandIdentity(options);
    return;
  }

  if (command === 'export-pubkey') {
    await commandExportPubkey(options);
    return;
  }

  if (command === 'show-qr') {
    await commandShowQr(options);
    return;
  }

  if (command === 'verify-contact') {
    await commandVerifyContact(options);
    return;
  }

  if (command === 'add-contact') {
    await commandAddContact(options);
    return;
  }

  if (command === 'list-contacts') {
    await commandListContacts(options);
    return;
  }

  if (command === 'rotate-spk') {
    await commandRotateSpk(options);
    return;
  }

  if (command === 'relay-start') {
    await commandRelayStart(options);
    return;
  }

  if (command === 'publish-prekeys') {
    await commandPublishPrekeys(options);
    return;
  }

  if (command === 'listen') {
    await commandListen(options);
    return;
  }

  if (command === 'send') {
    await commandSend(options);
    return;
  }

  throw new Error('Unknown command: ' + command);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
