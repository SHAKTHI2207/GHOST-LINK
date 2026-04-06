import { getDataPaths, readJson, writeJson } from './storage.js';

function defaultState() {
  return {
    sendCounters: {},
    receiveCounters: {}
  };
}

export async function loadState(baseDir) {
  const dataPaths = getDataPaths(baseDir);
  return readJson(dataPaths.stateFile, defaultState());
}

export async function nextSendCounter(baseDir, contactId) {
  const state = await loadState(baseDir);
  const current = state.sendCounters[contactId] || 0;
  const nextValue = current + 1;
  state.sendCounters[contactId] = nextValue;

  const dataPaths = getDataPaths(baseDir);
  await writeJson(dataPaths.stateFile, state);
  return nextValue;
}

export async function markReceiveCounter(baseDir, contactId, counter) {
  const state = await loadState(baseDir);
  const current = state.receiveCounters[contactId] || 0;

  if (counter <= current) {
    return false;
  }

  state.receiveCounters[contactId] = counter;
  const dataPaths = getDataPaths(baseDir);
  await writeJson(dataPaths.stateFile, state);
  return true;
}
