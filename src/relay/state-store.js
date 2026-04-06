import path from 'node:path';
import { ensureDir, readJson, writeJson } from '../core/storage.js';

function defaultRelayState() {
  return {
    prekeys: {},
    queuedPackets: {}
  };
}

function normalizeState(rawState) {
  if (!rawState || typeof rawState !== 'object') {
    return defaultRelayState();
  }

  return {
    prekeys: rawState.prekeys || {},
    queuedPackets: rawState.queuedPackets || {}
  };
}

export async function createRelayStateStore(stateFilePath) {
  const resolvedPath = path.resolve(stateFilePath);
  await ensureDir(path.dirname(resolvedPath));

  let state = normalizeState(await readJson(resolvedPath, defaultRelayState()));
  let writeChain = Promise.resolve();

  async function persist() {
    writeChain = writeChain.then(() => writeJson(resolvedPath, state));
    await writeChain;
  }

  return {
    getStatePath() {
      return resolvedPath;
    },

    async publishPrekeyBundle(userId, bundle) {
      state.prekeys[userId] = {
        userId,
        publishedAt: new Date().toISOString(),
        identityKey: bundle.identityKey,
        identitySigningKey: bundle.identitySigningKey,
        signedPreKey: bundle.signedPreKey,
        oneTimePreKeys: Array.isArray(bundle.oneTimePreKeys) ? bundle.oneTimePreKeys : []
      };

      await persist();
      return state.prekeys[userId].oneTimePreKeys.length;
    },

    async fetchPrekeyBundle(targetId) {
      const bundle = state.prekeys[targetId];
      if (!bundle) {
        return null;
      }

      const selectedOneTimePreKey = bundle.oneTimePreKeys.length > 0 ? bundle.oneTimePreKeys.shift() : null;
      await persist();

      return {
        version: 1,
        userId: bundle.userId,
        identityKey: bundle.identityKey,
        identitySigningKey: bundle.identitySigningKey,
        signedPreKey: bundle.signedPreKey,
        oneTimePreKey: selectedOneTimePreKey
      };
    },

    async enqueuePacket(targetId, envelope) {
      if (!Array.isArray(state.queuedPackets[targetId])) {
        state.queuedPackets[targetId] = [];
      }

      state.queuedPackets[targetId].push(envelope);
      await persist();
      return state.queuedPackets[targetId].length;
    },

    async drainQueuedPackets(userId) {
      const queued = Array.isArray(state.queuedPackets[userId]) ? state.queuedPackets[userId] : [];
      state.queuedPackets[userId] = [];
      await persist();
      return queued;
    }
  };
}
