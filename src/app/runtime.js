import { EventEmitter } from 'node:events';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import qrcode from 'qrcode';
import {
  clearContactRisk,
  getContact,
  listContacts,
  markContactRisk,
  upsertContact
} from '../core/contacts.js';
import {
  availableOneTimePreKeys,
  consumeOneTimePreKey,
  createOrLoadIdentity,
  ensureOneTimePreKeys,
  getPublicIdentity,
  loadIdentity
} from '../core/identity.js';
import { toPublicPrekeyBundle } from '../core/prekeys.js';
import { decodeVerificationPayload, encodeVerificationPayload, verificationPayloadToUri } from '../core/verification.js';
import { readJson, writeJson } from '../core/storage.js';
import { verifyPrekeyBundleSignature } from '../core/x3dh.js';
import { RelayClient } from '../relay/client.js';
import { createEncryptedX3dhPacket, decryptX3dhPacket } from '../relay/message-flow.js';

const MESSAGES_FILE = 'messages.json';

function randomMessageId() {
  return randomBytes(8).toString('hex');
}

function nowIso() {
  return new Date().toISOString();
}

function normalizePrivacyMode(value) {
  return value === 'stealth' ? 'stealth' : 'fast';
}

function visibleMessages(messages) {
  const now = Date.now();
  return messages.filter((message) => {
    if (!message.expiresAt) {
      return true;
    }
    return new Date(message.expiresAt).getTime() > now;
  });
}

function contactStatus(contact) {
  if (contact.risk) {
    return 'risk';
  }
  if (contact.verified === true) {
    return 'verified';
  }
  return 'unverified';
}

async function sleep(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

export class GhostLinkRuntime extends EventEmitter {
  constructor(options = {}) {
    super();
    this.dataDir = path.resolve(options.dataDir || './demo/default-user');
    this.relayUrl = options.relayUrl || null;
    this.privacyMode = normalizePrivacyMode(options.privacyMode || 'fast');
    this.relayClient = null;
    this.messagesPath = path.join(this.dataDir, MESSAGES_FILE);
    this.relayConnectedAt = null;
  }

  getConfig() {
    return {
      dataDir: this.dataDir,
      relayUrl: this.relayUrl,
      privacyMode: this.privacyMode,
      relayConnected: this.relayClient !== null,
      relayConnectedAt: this.relayConnectedAt
    };
  }

  async setConfig(input) {
    if (typeof input.dataDir === 'string' && input.dataDir.length > 0) {
      this.dataDir = path.resolve(input.dataDir);
      this.messagesPath = path.join(this.dataDir, MESSAGES_FILE);
    }

    if (typeof input.relayUrl === 'string' && input.relayUrl.length > 0) {
      this.relayUrl = input.relayUrl;
    }

    if (typeof input.privacyMode === 'string') {
      this.privacyMode = normalizePrivacyMode(input.privacyMode);
    }

    this.emit('event', {
      type: 'config_updated',
      config: this.getConfig(),
      at: nowIso()
    });

    return this.getConfig();
  }

  async loadMessages() {
    const value = await readJson(this.messagesPath, { messages: [] });
    if (!value || !Array.isArray(value.messages)) {
      return [];
    }
    return value.messages;
  }

  async saveMessages(messages) {
    await writeJson(this.messagesPath, { messages });
  }

  async appendMessage(message) {
    const messages = await this.loadMessages();
    messages.push(message);
    await this.saveMessages(messages);

    this.emit('event', {
      type: 'message_saved',
      contactId: message.contactId,
      direction: message.direction,
      at: nowIso()
    });

    return message;
  }

  async getIdentitySummary() {
    const identity = await loadIdentity(this.dataDir);
    if (identity === null) {
      return null;
    }

    const pub = getPublicIdentity(identity);
    return {
      id: pub.id,
      fingerprint: pub.fingerprint,
      fingerprintFormatted: pub.fingerprintFormatted,
      signedPreKeyId: identity.signedPreKey.id,
      availableOneTimePreKeys: availableOneTimePreKeys(identity).length
    };
  }

  async initIdentity(id, oneTimePreKeyCount = 20) {
    const identity = await createOrLoadIdentity(this.dataDir, id, { oneTimePreKeyCount });

    this.emit('event', {
      type: 'identity_ready',
      id: identity.id,
      at: nowIso()
    });

    return this.getIdentitySummary();
  }

  async getOwnVerificationData() {
    const identity = await loadIdentity(this.dataDir);
    if (!identity) {
      return null;
    }

    const pub = getPublicIdentity(identity);
    const verificationObject = {
      version: 1,
      id: pub.id,
      identityKey: pub.identityKey,
      identitySigningKey: pub.identitySigningKey,
      fingerprint: pub.fingerprint
    };

    const payload = encodeVerificationPayload(verificationObject);
    const uri = verificationPayloadToUri(payload);
    const qrDataUrl = await qrcode.toDataURL(uri, {
      margin: 1,
      width: 320,
      color: {
        dark: '#f4f6f8',
        light: '#0c1118'
      }
    });

    return {
      userId: pub.id,
      fingerprint: pub.fingerprint,
      fingerprintFormatted: pub.fingerprintFormatted,
      payload,
      uri,
      qrDataUrl
    };
  }

  async verifyContactByPayload(payload) {
    const parsed = decodeVerificationPayload(payload);
    const existing = await getContact(this.dataDir, parsed.id);

    if (existing) {
      if (
        existing.identityKeyPem !== parsed.identityKey ||
        (existing.identitySigningKeyPem && existing.identitySigningKeyPem !== parsed.identitySigningKey)
      ) {
        await markContactRisk(
          this.dataDir,
          parsed.id,
          'QR verification mismatch. Stored and scanned keys differ.'
        );
        throw new Error('Verification failed: contact keys mismatch. Risk flagged.');
      }
    }

    const contact = await upsertContact(this.dataDir, {
      id: parsed.id,
      identityKeyPem: parsed.identityKey,
      identitySigningKeyPem: parsed.identitySigningKey,
      verified: true,
      verificationMethod: 'qr-scan'
    });

    if (contact.risk) {
      await clearContactRisk(this.dataDir, parsed.id);
    }

    this.emit('event', {
      type: 'contact_verified',
      contactId: parsed.id,
      at: nowIso()
    });

    return await getContact(this.dataDir, parsed.id);
  }

  async addManualContact(contactInput) {
    const contact = await upsertContact(this.dataDir, {
      id: contactInput.id,
      identityKeyPem: contactInput.identityKeyPem,
      identitySigningKeyPem: contactInput.identitySigningKeyPem || null,
      verified: false,
      verificationMethod: null
    });

    this.emit('event', {
      type: 'contact_added',
      contactId: contact.id,
      at: nowIso()
    });

    return contact;
  }

  async listContactsWithState() {
    const contacts = await listContacts(this.dataDir);
    return contacts.map((contact) => ({
      ...contact,
      status: contactStatus(contact)
    }));
  }

  async listMessages(contactId) {
    const messages = await this.loadMessages();
    const visible = visibleMessages(messages);

    if (!contactId) {
      return visible;
    }

    return visible.filter((message) => message.contactId === contactId);
  }

  async listChats() {
    const contacts = await this.listContactsWithState();
    const messages = await this.listMessages();

    const latestByContact = new Map();
    for (const message of messages) {
      const existing = latestByContact.get(message.contactId);
      if (!existing || new Date(message.createdAt).getTime() > new Date(existing.createdAt).getTime()) {
        latestByContact.set(message.contactId, message);
      }
    }

    const chatItems = contacts.map((contact) => {
      const latest = latestByContact.get(contact.id) || null;
      return {
        id: contact.id,
        status: contact.status,
        verified: contact.verified,
        risk: contact.risk,
        fingerprint: contact.fingerprint,
        lastMessage: latest
          ? {
              text: latest.text,
              createdAt: latest.createdAt,
              direction: latest.direction
            }
          : null
      };
    });

    chatItems.sort((left, right) => {
      const leftTs = left.lastMessage ? new Date(left.lastMessage.createdAt).getTime() : 0;
      const rightTs = right.lastMessage ? new Date(right.lastMessage.createdAt).getTime() : 0;
      return rightTs - leftTs;
    });

    return chatItems;
  }

  async connectRelay() {
    if (!this.relayUrl) {
      throw new Error('Relay URL is not configured.');
    }

    const identity = await ensureOneTimePreKeys(this.dataDir, 8, 24);

    if (this.relayClient) {
      await this.relayClient.close();
      this.relayClient = null;
    }

    this.relayClient = await RelayClient.connect({
      url: this.relayUrl,
      userId: identity.id,
      onPacket: (envelope) => {
        this.handleIncomingPacket(envelope).catch((error) => {
          this.emit('event', {
            type: 'receive_error',
            error: error.message,
            at: nowIso()
          });
        });
      },
      onError: (error) => {
        this.emit('event', {
          type: 'relay_error',
          error: error.message,
          at: nowIso()
        });
      }
    });

    const publishResult = await this.relayClient.publishPrekeys(toPublicPrekeyBundle(identity));

    this.relayConnectedAt = nowIso();
    this.emit('event', {
      type: 'relay_connected',
      opkOnRelay: publishResult.availableOpkCount || 0,
      at: this.relayConnectedAt
    });

    return {
      connected: true,
      relayUrl: this.relayUrl,
      opkOnRelay: publishResult.availableOpkCount || 0
    };
  }

  async disconnectRelay() {
    if (this.relayClient) {
      await this.relayClient.close();
      this.relayClient = null;
    }

    this.relayConnectedAt = null;
    this.emit('event', {
      type: 'relay_disconnected',
      at: nowIso()
    });

    return { connected: false };
  }

  async ensureRelayConnected() {
    if (!this.relayClient) {
      await this.connectRelay();
    }
  }

  async sendMessage(input) {
    await this.ensureRelayConnected();

    const identity = await loadIdentity(this.dataDir);
    if (!identity) {
      throw new Error('Identity not found.');
    }

    const contact = await getContact(this.dataDir, input.to);
    if (!contact) {
      throw new Error('Unknown contact: ' + input.to);
    }

    if (contact.verified !== true) {
      throw new Error('Contact is not verified yet.');
    }

    if (!contact.identitySigningKeyPem) {
      throw new Error('Contact missing identity signing key. Re-verify contact via QR.');
    }

    const bundle = await this.relayClient.fetchPrekeyBundle(input.to);

    if (bundle.userId !== input.to) {
      throw new Error('Relay returned mismatched bundle target.');
    }

    if (bundle.identityKey !== contact.identityKeyPem) {
      await markContactRisk(this.dataDir, input.to, 'Identity key mismatch from relay bundle.');
      throw new Error('Identity key mismatch for contact. Risk flagged.');
    }

    if (bundle.identitySigningKey !== contact.identitySigningKeyPem) {
      await markContactRisk(this.dataDir, input.to, 'Identity signing key mismatch from relay bundle.');
      throw new Error('Identity signing key mismatch for contact. Risk flagged.');
    }

    if (verifyPrekeyBundleSignature(bundle) !== true) {
      await markContactRisk(this.dataDir, input.to, 'Signed prekey signature check failed.');
      throw new Error('Signed prekey signature invalid. Risk flagged.');
    }

    const expiresAt = input.selfDestructSeconds
      ? new Date(Date.now() + Number(input.selfDestructSeconds) * 1000).toISOString()
      : null;

    const clientMessageId = randomMessageId();
    const packet = createEncryptedX3dhPacket(identity, bundle, input.text);

    packet.meta = {
      clientMessageId,
      expiresAt,
      privacyMode: normalizePrivacyMode(input.privacyMode || this.privacyMode)
    };

    if (packet.meta.privacyMode === 'stealth') {
      const jitterMs = 1200 + Math.floor(Math.random() * 3200);
      await sleep(jitterMs);
    }

    const relayAck = await this.relayClient.sendPacket(input.to, packet);

    const saved = await this.appendMessage({
      id: clientMessageId,
      contactId: input.to,
      direction: 'out',
      text: input.text,
      createdAt: nowIso(),
      expiresAt,
      privacyMode: packet.meta.privacyMode,
      status: relayAck.deliveredCount > 0 ? 'delivered' : 'queued'
    });

    return {
      message: saved,
      deliveredCount: relayAck.deliveredCount || 0,
      usedOneTimePreKey: bundle.oneTimePreKey ? bundle.oneTimePreKey.id : null
    };
  }

  async handleIncomingPacket(envelope) {
    const identity = await loadIdentity(this.dataDir);
    if (!identity) {
      throw new Error('Identity missing.');
    }

    const senderId = envelope.from || (envelope.packet && envelope.packet.from);
    if (!senderId) {
      throw new Error('Invalid incoming packet. Sender missing.');
    }

    let contact = await getContact(this.dataDir, senderId);
    if (!contact && envelope.packet && envelope.packet.x3dh && envelope.packet.x3dh.senderIdentityKey) {
      contact = await upsertContact(this.dataDir, {
        id: senderId,
        identityKeyPem: envelope.packet.x3dh.senderIdentityKey,
        identitySigningKeyPem: null,
        verified: false,
        verificationMethod: null
      });
    }

    const decrypted = decryptX3dhPacket(identity, contact, envelope.packet);

    if (decrypted.oneTimePreKeyId) {
      await consumeOneTimePreKey(this.dataDir, decrypted.oneTimePreKeyId);
    }

    const expiresAt = envelope.packet.meta ? envelope.packet.meta.expiresAt || null : null;
    if (expiresAt && new Date(expiresAt).getTime() <= Date.now()) {
      return null;
    }

    const message = await this.appendMessage({
      id: envelope.packet.meta && envelope.packet.meta.clientMessageId
        ? envelope.packet.meta.clientMessageId
        : randomMessageId(),
      contactId: senderId,
      direction: 'in',
      text: decrypted.plaintext,
      createdAt: nowIso(),
      expiresAt,
      privacyMode: envelope.packet.meta ? envelope.packet.meta.privacyMode || 'fast' : 'fast',
      status: 'received'
    });

    this.emit('event', {
      type: 'message_in',
      contactId: senderId,
      message,
      at: nowIso()
    });

    return message;
  }

  async bootstrapState() {
    return {
      config: this.getConfig(),
      identity: await this.getIdentitySummary(),
      ownVerification: await this.getOwnVerificationData(),
      contacts: await this.listContactsWithState(),
      chats: await this.listChats()
    };
  }
}
