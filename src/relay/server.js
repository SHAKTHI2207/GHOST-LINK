import WebSocket, { WebSocketServer } from 'ws';
import { prekeyBundleHasRequiredFields } from '../core/prekeys.js';
import { createRelayStateStore } from './state-store.js';

function sendJson(socket, payload) {
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(payload));
  }
}

function sendError(socket, requestId, message) {
  sendJson(socket, {
    type: 'error',
    requestId: requestId || null,
    message
  });
}

function requireAuthedUser(socket, requestId) {
  if (typeof socket.userId !== 'string' || socket.userId.length === 0) {
    sendError(socket, requestId, 'Authenticate first.');
    return false;
  }

  return true;
}

export async function startRelayServer(options = {}) {
  const host = options.host || '0.0.0.0';
  const port = Number(options.port || 8080);
  const stateFile = options.stateFile || './relay-state.json';
  const onLog = typeof options.onLog === 'function' ? options.onLog : () => {};

  const store = await createRelayStateStore(stateFile);
  const socketsByUser = new Map();

  const server = new WebSocketServer({ host, port });

  function addSocketForUser(userId, socket) {
    if (!socketsByUser.has(userId)) {
      socketsByUser.set(userId, new Set());
    }
    socketsByUser.get(userId).add(socket);
  }

  function removeSocketFromUser(userId, socket) {
    if (!socketsByUser.has(userId)) {
      return;
    }

    const set = socketsByUser.get(userId);
    set.delete(socket);
    if (set.size === 0) {
      socketsByUser.delete(userId);
    }
  }

  server.on('connection', (socket) => {
    socket.on('message', async (rawMessage) => {
      let message;
      try {
        message = JSON.parse(rawMessage.toString('utf8'));
      } catch {
        sendError(socket, null, 'Invalid JSON payload.');
        return;
      }

      const requestId = typeof message.requestId === 'string' ? message.requestId : null;

      try {
        if (message.type === 'auth') {
          if (typeof message.userId !== 'string' || message.userId.length === 0) {
            sendError(socket, requestId, 'userId is required.');
            return;
          }

          if (typeof socket.userId === 'string' && socket.userId !== message.userId) {
            removeSocketFromUser(socket.userId, socket);
          }

          socket.userId = message.userId;
          addSocketForUser(message.userId, socket);

          sendJson(socket, {
            type: 'auth_ok',
            userId: message.userId
          });

          const queuedPackets = await store.drainQueuedPackets(message.userId);
          for (const envelope of queuedPackets) {
            sendJson(socket, {
              type: 'deliver_packet',
              from: envelope.from,
              packet: envelope.packet,
              queuedAt: envelope.queuedAt
            });
          }

          onLog(
            `auth user=${message.userId} queued_delivered=${queuedPackets.length} state=${store.getStatePath()}`
          );
          return;
        }

        if (requireAuthedUser(socket, requestId) !== true) {
          return;
        }

        if (message.type === 'publish_prekeys') {
          if (prekeyBundleHasRequiredFields(message.bundle) !== true) {
            sendError(socket, requestId, 'Invalid prekey bundle.');
            return;
          }

          if (message.bundle.userId !== socket.userId) {
            sendError(socket, requestId, 'bundle.userId must match authenticated user.');
            return;
          }

          const availableOpkCount = await store.publishPrekeyBundle(socket.userId, message.bundle);

          sendJson(socket, {
            type: 'ack',
            requestId,
            op: 'publish_prekeys',
            availableOpkCount
          });

          onLog(`publish_prekeys user=${socket.userId} opk=${availableOpkCount}`);
          return;
        }

        if (message.type === 'fetch_prekey_bundle') {
          if (typeof message.targetId !== 'string' || message.targetId.length === 0) {
            sendError(socket, requestId, 'targetId is required.');
            return;
          }

          const bundle = await store.fetchPrekeyBundle(message.targetId);
          if (bundle === null) {
            sendError(socket, requestId, `No prekey bundle for ${message.targetId}.`);
            return;
          }

          sendJson(socket, {
            type: 'prekey_bundle',
            requestId,
            bundle
          });

          onLog(
            `fetch_prekey requester=${socket.userId} target=${message.targetId} opk=${bundle.oneTimePreKey ? 'yes' : 'no'}`
          );
          return;
        }

        if (message.type === 'send_packet') {
          if (typeof message.to !== 'string' || message.to.length === 0) {
            sendError(socket, requestId, 'to is required.');
            return;
          }

          if (!message.packet || typeof message.packet !== 'object') {
            sendError(socket, requestId, 'packet is required.');
            return;
          }

          const recipients = socketsByUser.get(message.to);
          const envelope = {
            from: socket.userId,
            packet: message.packet,
            queuedAt: new Date().toISOString()
          };

          let deliveredCount = 0;
          if (recipients && recipients.size > 0) {
            for (const recipientSocket of recipients) {
              sendJson(recipientSocket, {
                type: 'deliver_packet',
                from: socket.userId,
                packet: message.packet,
                queuedAt: envelope.queuedAt
              });
              deliveredCount += 1;
            }
          } else {
            await store.enqueuePacket(message.to, envelope);
          }

          sendJson(socket, {
            type: 'ack',
            requestId,
            op: 'send_packet',
            deliveredCount
          });

          onLog(`send_packet from=${socket.userId} to=${message.to} delivered=${deliveredCount}`);
          return;
        }

        sendError(socket, requestId, 'Unknown message type.');
      } catch (error) {
        sendError(socket, requestId, error.message);
      }
    });

    socket.on('close', () => {
      if (typeof socket.userId === 'string') {
        removeSocketFromUser(socket.userId, socket);
      }
    });

    socket.on('error', () => {
      if (typeof socket.userId === 'string') {
        removeSocketFromUser(socket.userId, socket);
      }
    });
  });

  await new Promise((resolve, reject) => {
    if (server.address()) {
      resolve();
      return;
    }

    server.once('listening', resolve);
    server.once('error', reject);
  });

  return {
    host,
    port,
    stateFile: store.getStatePath(),
    close: async () => {
      await new Promise((resolve) => server.close(resolve));
    }
  };
}
