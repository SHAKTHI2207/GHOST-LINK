import qrcode from 'qrcode-terminal';
import { fromBase64Url, toBase64Url } from './encoding.js';
import { fingerprintPublicKey } from './identity.js';

function parsePayloadToken(rawInput) {
  if (rawInput.startsWith('ghostlink://verify/')) {
    return rawInput.slice('ghostlink://verify/'.length);
  }
  return rawInput;
}

export function createVerificationObject(publicIdentity) {
  return {
    version: 1,
    id: publicIdentity.id,
    identityKey: publicIdentity.identityKey,
    identitySigningKey: publicIdentity.identitySigningKey,
    fingerprint: fingerprintPublicKey(publicIdentity.identityKey)
  };
}

export function encodeVerificationPayload(verificationObject) {
  return toBase64Url(Buffer.from(JSON.stringify(verificationObject), 'utf8'));
}

export function decodeVerificationPayload(rawPayload) {
  const payloadToken = parsePayloadToken(rawPayload.trim());
  const decoded = fromBase64Url(payloadToken).toString('utf8');
  const parsed = JSON.parse(decoded);

  if (
    typeof parsed.id !== 'string' ||
    typeof parsed.identityKey !== 'string' ||
    typeof parsed.identitySigningKey !== 'string'
  ) {
    throw new Error('Invalid verification payload.');
  }

  return {
    ...parsed,
    fingerprint: parsed.fingerprint || fingerprintPublicKey(parsed.identityKey)
  };
}

export function verificationPayloadToUri(payload) {
  return `ghostlink://verify/${payload}`;
}

export async function renderVerificationQr(verificationUri) {
  return new Promise((resolve) => {
    qrcode.generate(verificationUri, { small: true }, (ascii) => {
      resolve(ascii);
    });
  });
}
