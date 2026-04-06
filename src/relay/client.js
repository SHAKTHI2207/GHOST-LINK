import { randomBytes } from 'node:crypto';
import WebSocket from 'ws';

function requestId() {
  return randomBytes(8).toString('hex');
}

export class RelayClient {
  constructor(webSocket, userId, handlers = {}) {
    this.webSocket = webSocket;
    this.userId = userId;
    this.onPacket = handlers.onPacket;
    this.onError = handlers.onError;
    this.pending = new Map();

    this.authPromise = new Promise((resolve, reject) => {
      this.resolveAuth = resolve;
      this.rejectAuth = reject;
    });

    this.webSocket.on('message', (rawMessage) => {
      this.handleMessage(rawMessage.toString('utf8'));
    });

    this.webSocket.on('close', () => {
      for (const pendingRequest of this.pending.values()) {
        clearTimeout(pendingRequest.timeout);
        pendingRequest.reject(new Error('Relay socket closed.'));
      }
      this.pending.clear();
      this.rejectAuth(new Error('Relay socket closed before auth.'));
    });

    this.webSocket.on('error', (error) => {
      if (typeof this.onError === 'function') {
        this.onError(error);
      }

      for (const pendingRequest of this.pending.values()) {
        clearTimeout(pendingRequest.timeout);
        pendingRequest.reject(error);
      }
      this.pending.clear();
      this.rejectAuth(error);
    });
  }

  static async connect(options) {
    const webSocket = new WebSocket(options.url);

    await new Promise((resolve, reject) => {
      webSocket.once('open', resolve);
      webSocket.once('error', reject);
    });

    const client = new RelayClient(webSocket, options.userId, {
      onPacket: options.onPacket,
      onError: options.onError
    });

    client.sendRaw({
      type: 'auth',
      userId: options.userId
    });

    await client.authPromise;
    return client;
  }

  sendRaw(payload) {
    this.webSocket.send(JSON.stringify(payload));
  }

  handleMessage(serializedMessage) {
    let message;
    try {
      message = JSON.parse(serializedMessage);
    } catch {
      if (typeof this.onError === 'function') {
        this.onError(new Error('Invalid JSON from relay.'));
      }
      return;
    }

    if (message.type === 'auth_ok') {
      this.resolveAuth(message);
      return;
    }

    if (message.type === 'deliver_packet') {
      if (typeof this.onPacket === 'function') {
        this.onPacket(message);
      }
      return;
    }

    if (message.requestId && this.pending.has(message.requestId)) {
      const pendingRequest = this.pending.get(message.requestId);
      clearTimeout(pendingRequest.timeout);
      this.pending.delete(message.requestId);

      if (message.type === 'error') {
        pendingRequest.reject(new Error(message.message || 'Relay error.'));
      } else {
        pendingRequest.resolve(message);
      }
      return;
    }

    if (message.type === 'error' && typeof this.onError === 'function') {
      this.onError(new Error(message.message || 'Relay error.'));
    }
  }

  request(type, payload, timeoutMs = 15000) {
    const id = requestId();

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Relay request timed out for ${type}.`));
      }, timeoutMs);

      this.pending.set(id, {
        resolve,
        reject,
        timeout
      });

      this.sendRaw({
        type,
        requestId: id,
        ...payload
      });
    });
  }

  async publishPrekeys(bundle) {
    return this.request('publish_prekeys', { bundle });
  }

  async fetchPrekeyBundle(targetId) {
    const response = await this.request('fetch_prekey_bundle', { targetId });
    return response.bundle;
  }

  async sendPacket(to, packet) {
    return this.request('send_packet', { to, packet });
  }

  async close() {
    if (this.webSocket.readyState === WebSocket.CLOSED) {
      return;
    }

    await new Promise((resolve) => {
      this.webSocket.once('close', resolve);
      this.webSocket.close();
    });
  }
}
