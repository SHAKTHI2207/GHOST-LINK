import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { GhostLinkRuntime } from '../src/app/runtime.js';
import { startRelayServer } from '../src/relay/server.js';

function waitForEvent(runtime, eventType, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      runtime.off('event', onEvent);
      reject(new Error(`Timed out waiting for event: ${eventType}`));
    }, timeoutMs);

    function onEvent(event) {
      if (event && event.type === eventType) {
        clearTimeout(timeout);
        runtime.off('event', onEvent);
        resolve(event);
      }
    }

    runtime.on('event', onEvent);
  });
}

test('two runtimes can verify, connect to relay, and exchange an encrypted message', async (t) => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), 'ghostlink-runtime-test-'));
  const relayState = path.join(tempRoot, 'relay-state.json');
  const aliceDir = path.join(tempRoot, 'alice');
  const bobDir = path.join(tempRoot, 'bob');

  let relay;
  try {
    relay = await startRelayServer({
      host: '127.0.0.1',
      port: 0,
      stateFile: relayState
    });
  } catch (error) {
    await rm(tempRoot, { recursive: true, force: true });

    if (error && error.code === 'EPERM') {
      t.skip('Local socket binding is not permitted in this environment.');
      return;
    }

    throw error;
  }

  const relayUrl = `ws://127.0.0.1:${String(relay.port)}`;
  const alice = new GhostLinkRuntime({ dataDir: aliceDir, relayUrl });
  const bob = new GhostLinkRuntime({ dataDir: bobDir, relayUrl });

  try {
    await alice.initIdentity('alice-test', 12);
    await bob.initIdentity('bob-test', 12);

    const aliceVerification = await alice.getOwnVerificationData();
    const bobVerification = await bob.getOwnVerificationData();

    await alice.verifyContactByPayload(bobVerification.uri);
    await bob.verifyContactByPayload(aliceVerification.uri);

    await alice.connectRelay();
    await bob.connectRelay();

    const incomingMessage = waitForEvent(bob, 'message_in');
    const sendResult = await alice.sendMessage({
      to: 'bob-test',
      text: 'hello from alice',
      privacyMode: 'fast',
      selfDestructSeconds: null
    });

    const deliveredEvent = await incomingMessage;
    const bobMessages = await bob.listMessages('alice-test');
    const bobIdentity = await bob.getIdentitySummary();

    assert.equal(sendResult.message.status, 'delivered');
    assert.equal(deliveredEvent.message.text, 'hello from alice');
    assert.equal(bobMessages.length, 1);
    assert.equal(bobMessages[0].text, 'hello from alice');
    assert.equal(bobIdentity.availableOneTimePreKeys, 11);
  } finally {
    await Promise.allSettled([alice.disconnectRelay(), bob.disconnectRelay()]);
    await relay.close();
    await rm(tempRoot, { recursive: true, force: true });
  }
});
