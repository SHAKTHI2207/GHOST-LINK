#!/usr/bin/env node
import http from 'node:http';
import path from 'node:path';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { GhostLinkRuntime } from './runtime.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const PUBLIC_DIR = path.join(__dirname, 'public');

function parseArgs(args) {
  const options = {
    host: '127.0.0.1',
    port: 3000,
    dataDir: './demo/ui-user',
    relayUrl: '',
    privacyMode: 'fast'
  };

  let index = 0;
  while (index < args.length) {
    const key = args[index];
    const value = args[index + 1];

    if (key === '--host' && value) {
      options.host = value;
      index += 2;
      continue;
    }

    if (key === '--port' && value) {
      options.port = Number(value);
      index += 2;
      continue;
    }

    if (key === '--data' && value) {
      options.dataDir = value;
      index += 2;
      continue;
    }

    if (key === '--relay' && value) {
      options.relayUrl = value;
      index += 2;
      continue;
    }

    if (key === '--privacy' && value) {
      options.privacyMode = value;
      index += 2;
      continue;
    }

    throw new Error('Unknown or incomplete argument: ' + key);
  }

  if (Number.isFinite(options.port) !== true || options.port <= 0) {
    throw new Error('Invalid --port');
  }

  return options;
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  response.end(JSON.stringify(payload));
}

function sendText(response, statusCode, text) {
  response.writeHead(statusCode, {
    'Content-Type': 'text/plain; charset=utf-8',
    'Cache-Control': 'no-store'
  });
  response.end(text);
}

function parseJsonBody(request) {
  return new Promise((resolve, reject) => {
    let raw = '';

    request.on('data', (chunk) => {
      raw += chunk.toString('utf8');
      if (raw.length > 2 * 1024 * 1024) {
        reject(new Error('Payload too large.'));
        request.destroy();
      }
    });

    request.on('end', () => {
      if (raw.trim() === '') {
        resolve({});
        return;
      }

      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error('Invalid JSON body.'));
      }
    });

    request.on('error', reject);
  });
}

function contentTypeFor(filePath) {
  if (filePath.endsWith('.html')) {
    return 'text/html; charset=utf-8';
  }
  if (filePath.endsWith('.css')) {
    return 'text/css; charset=utf-8';
  }
  if (filePath.endsWith('.js')) {
    return 'application/javascript; charset=utf-8';
  }
  if (filePath.endsWith('.json')) {
    return 'application/json; charset=utf-8';
  }
  if (filePath.endsWith('.svg')) {
    return 'image/svg+xml';
  }
  if (filePath.endsWith('.png')) {
    return 'image/png';
  }
  return 'application/octet-stream';
}

async function serveStatic(pathname, response) {
  const requested = pathname === '/' ? '/index.html' : pathname;
  const safePath = path.normalize(requested).replace(/^\.+/, '');
  const absPath = path.resolve(PUBLIC_DIR, `.${safePath}`);

  if (absPath.startsWith(PUBLIC_DIR) !== true) {
    sendText(response, 403, 'Forbidden');
    return;
  }

  try {
    const body = await readFile(absPath);
    response.writeHead(200, {
      'Content-Type': contentTypeFor(absPath),
      'Cache-Control': 'no-cache'
    });
    response.end(body);
  } catch {
    sendText(response, 404, 'Not found');
  }
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const runtime = new GhostLinkRuntime({
    dataDir: options.dataDir,
    relayUrl: options.relayUrl || null,
    privacyMode: options.privacyMode
  });

  const sseClients = new Set();

  function broadcastEvent(event) {
    const line = `event: update\ndata: ${JSON.stringify(event)}\n\n`;
    for (const client of sseClients) {
      client.write(line);
    }
  }

  runtime.on('event', (event) => {
    broadcastEvent(event);
  });

  const server = http.createServer(async (request, response) => {
    const parsedUrl = new URL(request.url, `http://${request.headers.host}`);
    const pathname = parsedUrl.pathname;

    try {
      if (request.method === 'GET' && pathname === '/api/health') {
        sendJson(response, 200, {
          ok: true,
          now: new Date().toISOString(),
          config: runtime.getConfig()
        });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/bootstrap') {
        const payload = await runtime.bootstrapState();
        sendJson(response, 200, payload);
        return;
      }

      if (request.method === 'GET' && pathname === '/api/messages') {
        const contactId = parsedUrl.searchParams.get('contactId') || '';
        const messages = await runtime.listMessages(contactId || null);
        sendJson(response, 200, { messages });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/chats') {
        const chats = await runtime.listChats();
        sendJson(response, 200, { chats });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/contacts') {
        const contacts = await runtime.listContactsWithState();
        sendJson(response, 200, { contacts });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/identity') {
        sendJson(response, 200, {
          identity: await runtime.getIdentitySummary()
        });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/own-verification') {
        sendJson(response, 200, {
          ownVerification: await runtime.getOwnVerificationData()
        });
        return;
      }

      if (request.method === 'GET' && pathname === '/api/events') {
        response.writeHead(200, {
          'Content-Type': 'text/event-stream; charset=utf-8',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive'
        });
        response.write(': connected\n\n');

        sseClients.add(response);
        request.on('close', () => {
          sseClients.delete(response);
        });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/init') {
        const body = await parseJsonBody(request);
        const identity = await runtime.initIdentity(body.id, Number(body.oneTimePreKeyCount || 20));
        sendJson(response, 200, {
          identity,
          ownVerification: await runtime.getOwnVerificationData()
        });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/config') {
        const body = await parseJsonBody(request);
        const config = await runtime.setConfig(body);
        sendJson(response, 200, { config });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/connect-relay') {
        const body = await parseJsonBody(request);
        if (body.relayUrl) {
          await runtime.setConfig({ relayUrl: body.relayUrl });
        }

        const relay = await runtime.connectRelay();
        sendJson(response, 200, { relay });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/disconnect-relay') {
        const relay = await runtime.disconnectRelay();
        sendJson(response, 200, { relay });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/verify-contact') {
        const body = await parseJsonBody(request);
        const contact = await runtime.verifyContactByPayload(body.payload || '');
        sendJson(response, 200, { contact });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/add-contact') {
        const body = await parseJsonBody(request);
        const contact = await runtime.addManualContact(body);
        sendJson(response, 200, { contact });
        return;
      }

      if (request.method === 'POST' && pathname === '/api/send') {
        const body = await parseJsonBody(request);
        const result = await runtime.sendMessage({
          to: body.to,
          text: body.text,
          privacyMode: body.privacyMode,
          selfDestructSeconds: body.selfDestructSeconds
        });
        sendJson(response, 200, result);
        return;
      }

      await serveStatic(pathname, response);
    } catch (error) {
      sendJson(response, 400, {
        ok: false,
        error: error.message
      });
    }
  });

  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(options.port, options.host, resolve);
  });

  console.log(`GhostLink UI running on http://${options.host}:${String(options.port)}`);
  console.log('Data dir: ' + runtime.getConfig().dataDir);
  console.log('Relay URL: ' + (runtime.getConfig().relayUrl || '(not set)'));

  process.on('SIGINT', async () => {
    for (const client of sseClients) {
      client.end();
    }

    try {
      await runtime.disconnectRelay();
    } catch {
      // ignore
    }

    server.close(() => {
      process.exit(0);
    });
  });
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
