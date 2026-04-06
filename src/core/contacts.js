import { fingerprintPublicKey } from './identity.js';
import { getDataPaths, readJson, writeJson } from './storage.js';

function defaultContacts() {
  return { contacts: {} };
}

function normalizeContact(id, rawContact) {
  const identityKeyPem = rawContact.identityKeyPem || rawContact.publicKeyPem;
  const identitySigningKeyPem = rawContact.identitySigningKeyPem || null;
  const fingerprint = rawContact.fingerprint || fingerprintPublicKey(identityKeyPem);

  return {
    id,
    identityKeyPem,
    identitySigningKeyPem,
    fingerprint,
    addedAt: rawContact.addedAt || new Date().toISOString(),
    verified: rawContact.verified === true,
    verifiedAt: rawContact.verifiedAt || null,
    verificationMethod: rawContact.verificationMethod || null,
    note: rawContact.note || null,
    risk: rawContact.risk || null,
    riskAt: rawContact.riskAt || null
  };
}

export async function loadContacts(baseDir) {
  const dataPaths = getDataPaths(baseDir);
  const rawBook = await readJson(dataPaths.contactsFile, defaultContacts());

  const normalizedContacts = {};
  for (const [id, rawContact] of Object.entries(rawBook.contacts || {})) {
    normalizedContacts[id] = normalizeContact(id, rawContact);
  }

  return { contacts: normalizedContacts };
}

export async function saveContacts(baseDir, contactBook) {
  const dataPaths = getDataPaths(baseDir);
  await writeJson(dataPaths.contactsFile, contactBook);
}

export async function upsertContact(baseDir, contactInput) {
  if (!contactInput || typeof contactInput.id !== 'string') {
    throw new Error('Contact id is required.');
  }

  if (typeof contactInput.identityKeyPem !== 'string') {
    throw new Error('Contact identity key is required.');
  }

  const contactBook = await loadContacts(baseDir);
  const existing = contactBook.contacts[contactInput.id] || null;

  const merged = normalizeContact(contactInput.id, {
    ...existing,
    ...contactInput,
    fingerprint: fingerprintPublicKey(contactInput.identityKeyPem),
    addedAt: existing ? existing.addedAt : new Date().toISOString()
  });

  if (existing && existing.verified === true && contactInput.verified !== true) {
    merged.verified = true;
    merged.verifiedAt = existing.verifiedAt;
    merged.verificationMethod = existing.verificationMethod;
  }

  if (contactInput.verified === true) {
    merged.verified = true;
    merged.verifiedAt = contactInput.verifiedAt || new Date().toISOString();
    merged.verificationMethod = contactInput.verificationMethod || 'manual';
  }

  contactBook.contacts[contactInput.id] = merged;
  await saveContacts(baseDir, contactBook);
  return merged;
}

export async function markContactRisk(baseDir, id, reason) {
  const contactBook = await loadContacts(baseDir);
  const contact = contactBook.contacts[id];

  if (!contact) {
    throw new Error('Unknown contact: ' + id);
  }

  contact.risk = reason || 'Security mismatch detected.';
  contact.riskAt = new Date().toISOString();
  contactBook.contacts[id] = contact;
  await saveContacts(baseDir, contactBook);
  return contact;
}

export async function clearContactRisk(baseDir, id) {
  const contactBook = await loadContacts(baseDir);
  const contact = contactBook.contacts[id];

  if (!contact) {
    throw new Error('Unknown contact: ' + id);
  }

  contact.risk = null;
  contact.riskAt = null;
  contactBook.contacts[id] = contact;
  await saveContacts(baseDir, contactBook);
  return contact;
}

export async function addContact(baseDir, id, identityKeyPem, identitySigningKeyPem = null) {
  return upsertContact(baseDir, {
    id,
    identityKeyPem,
    identitySigningKeyPem,
    verified: false,
    verificationMethod: null
  });
}

export async function markContactVerified(baseDir, id, verificationMethod = 'qr') {
  const contactBook = await loadContacts(baseDir);
  const contact = contactBook.contacts[id];

  if (!contact) {
    throw new Error('Unknown contact: ' + id);
  }

  contact.verified = true;
  contact.verifiedAt = new Date().toISOString();
  contact.verificationMethod = verificationMethod;

  contactBook.contacts[id] = contact;
  await saveContacts(baseDir, contactBook);
  return contact;
}

export async function getContact(baseDir, id) {
  const contactBook = await loadContacts(baseDir);
  return contactBook.contacts[id] || null;
}

export async function listContacts(baseDir) {
  const contactBook = await loadContacts(baseDir);
  return Object.values(contactBook.contacts);
}
