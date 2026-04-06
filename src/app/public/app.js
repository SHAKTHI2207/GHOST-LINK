const state = {
  config: null,
  identity: null,
  ownVerification: null,
  contacts: [],
  chats: [],
  selectedContactId: null,
  messages: [],
  eventStream: null,
  backgroundRefreshId: null,
  reconnectTimerId: null,
  scanner: {
    running: false,
    stream: null,
    rafId: null,
    detector: null
  }
};

const el = {
  relayStatusChip: document.getElementById('relayStatusChip'),
  relayUrlInput: document.getElementById('relayUrlInput'),
  connectRelayBtn: document.getElementById('connectRelayBtn'),
  refreshBtn: document.getElementById('refreshBtn'),
  contactsList: document.getElementById('contactsList'),
  chatTitle: document.getElementById('chatTitle'),
  chatSubtitle: document.getElementById('chatSubtitle'),
  privacyModeSelect: document.getElementById('privacyModeSelect'),
  messagesArea: document.getElementById('messagesArea'),
  messageInput: document.getElementById('messageInput'),
  sendBtn: document.getElementById('sendBtn'),
  selfDestructSelect: document.getElementById('selfDestructSelect'),
  receiptToggle: document.getElementById('receiptToggle'),
  identityCard: document.getElementById('identityCard'),
  verifyPayloadInput: document.getElementById('verifyPayloadInput'),
  verifyPayloadBtn: document.getElementById('verifyPayloadBtn'),
  scanQrBtn: document.getElementById('scanQrBtn'),
  scannerVideo: document.getElementById('scannerVideo'),
  scannerHint: document.getElementById('scannerHint'),
  contactProfileCard: document.getElementById('contactProfileCard'),
  toast: document.getElementById('toast'),
  onboardingOverlay: document.getElementById('onboardingOverlay'),
  identityNameInput: document.getElementById('identityNameInput'),
  createIdentityBtn: document.getElementById('createIdentityBtn')
};

async function apiRequest(path, options = {}) {
  const response = await fetch(path, {
    headers: {
      'Content-Type': 'application/json'
    },
    ...options
  });

  const data = await response.json().catch(() => ({}));

  if (response.ok !== true || data.ok === false) {
    throw new Error(data.error || `Request failed: ${response.status}`);
  }

  return data;
}

function showToast(message) {
  el.toast.textContent = message;
  el.toast.classList.add('show');
  clearTimeout(showToast.timeout);
  showToast.timeout = setTimeout(() => {
    el.toast.classList.remove('show');
  }, 2800);
}

function formatTime(iso) {
  if (!iso) {
    return '';
  }

  const date = new Date(iso);
  return date.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit'
  });
}

function escapeHtml(value) {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function statusMeta(status) {
  if (status === 'verified') {
    return {
      label: 'Verified Secure Connection',
      dotClass: 'status-verified',
      badgeClass: 'verified'
    };
  }

  if (status === 'risk') {
    return {
      label: 'Security Risk Detected',
      dotClass: 'status-risk',
      badgeClass: 'risk'
    };
  }

  return {
    label: 'Unverified Contact',
    dotClass: 'status-unverified',
    badgeClass: 'unverified'
  };
}

function currentContact() {
  return state.contacts.find((contact) => contact.id === state.selectedContactId) || null;
}

function setRelayChip(connected) {
  el.relayStatusChip.className = connected ? 'status-chip online' : 'status-chip offline';
  el.relayStatusChip.textContent = connected ? 'Relay Online' : 'Relay Offline';
}

async function refreshConfig() {
  const health = await apiRequest('/api/health');
  state.config = health.config;
  el.privacyModeSelect.value = state.config.privacyMode || 'fast';
  el.relayUrlInput.value = state.config.relayUrl || '';
  setRelayChip(Boolean(state.config.relayConnected));
}

function renderIdentityCard() {
  if (!state.identity || !state.ownVerification) {
    el.identityCard.innerHTML = '<p class="small-meta">Identity not initialized.</p>';
    return;
  }

  el.identityCard.innerHTML = `
    <h3>${escapeHtml(state.identity.id)}</h3>
    <p class="small-meta">${escapeHtml(state.identity.fingerprintFormatted)}</p>
    <img src="${state.ownVerification.qrDataUrl}" alt="Verification QR" />
    <p class="small-meta">Share this QR in person to establish trust.</p>
  `;
}

function renderContacts() {
  if (state.chats.length === 0) {
    el.contactsList.innerHTML = '<p class="small-meta">No contacts yet. Verify one via QR.</p>';
    return;
  }

  el.contactsList.innerHTML = '';

  for (const chat of state.chats) {
    const status = statusMeta(chat.status);
    const item = document.createElement('article');
    item.className = 'contact-item' + (chat.id === state.selectedContactId ? ' active' : '');
    item.innerHTML = `
      <div class="contact-head">
        <span class="contact-name">${escapeHtml(chat.id)}</span>
        <span class="status-dot ${status.dotClass}" aria-label="${escapeHtml(status.label)}"></span>
      </div>
      <p class="contact-preview">${escapeHtml(chat.lastMessage ? chat.lastMessage.text : 'No messages yet')}</p>
    `;
    item.addEventListener('click', () => {
      selectContact(chat.id);
    });

    el.contactsList.appendChild(item);
  }
}

function renderChatHeader() {
  const contact = currentContact();

  if (!contact) {
    el.chatTitle.textContent = 'No Contact Selected';
    el.chatSubtitle.textContent = 'End-to-end encrypted';
    return;
  }

  const status = statusMeta(contact.status);
  el.chatTitle.textContent = contact.id;
  el.chatSubtitle.textContent = `End-to-end encrypted • ${status.label}`;
}

function renderMessages() {
  const contact = currentContact();

  if (!contact) {
    el.messagesArea.innerHTML = `
      <div class="empty-chat">
        <h3>Start Secure Messaging</h3>
        <p>Choose a contact and send your first message.</p>
      </div>
    `;
    return;
  }

  if (state.messages.length === 0) {
    el.messagesArea.innerHTML = `
      <div class="empty-chat">
        <h3>No messages yet</h3>
        <p>Send a message to begin this secure conversation.</p>
      </div>
    `;
    return;
  }

  const showReceipt = el.receiptToggle.checked;

  const rows = state.messages
    .map((message) => {
      const directionClass = message.direction === 'out' ? 'out' : 'in';
      const metaParts = [formatTime(message.createdAt)];

      if (showReceipt && message.direction === 'out') {
        metaParts.push(message.status || 'sent');
      }

      if (message.expiresAt) {
        metaParts.push('self-destruct');
      }

      return `
        <div class="message-row ${directionClass}">
          <div class="message-bubble">
            <div>${escapeHtml(message.text)}</div>
            <div class="message-meta">${escapeHtml(metaParts.join(' • '))}</div>
          </div>
        </div>
      `;
    })
    .join('');

  el.messagesArea.innerHTML = rows;
  el.messagesArea.scrollTop = el.messagesArea.scrollHeight;
}

function renderContactProfile() {
  const contact = currentContact();

  if (!contact) {
    el.contactProfileCard.innerHTML = '<p class="small-meta">Select a contact to view security details.</p>';
    return;
  }

  const status = statusMeta(contact.status);
  const riskText = contact.risk ? `<p class="small-meta">Risk: ${escapeHtml(contact.risk)}</p>` : '';

  el.contactProfileCard.innerHTML = `
    <h3>${escapeHtml(contact.id)}</h3>
    <p class="badge ${status.badgeClass}">🛡 ${escapeHtml(status.label)}</p>
    ${riskText}
    <p class="small-meta">Fingerprint</p>
    <p class="small-meta">${escapeHtml(contact.fingerprint)}</p>
    <details>
      <summary>Advanced Keys</summary>
      <p class="small-meta">Identity Key</p>
      <p class="small-meta">${escapeHtml(contact.identityKeyPem || 'Unavailable')}</p>
      <p class="small-meta">Signing Key</p>
      <p class="small-meta">${escapeHtml(contact.identitySigningKeyPem || 'Unavailable')}</p>
    </details>
  `;
}

async function refreshChatsAndContacts() {
  const [contactsRes, chatsRes] = await Promise.all([
    apiRequest('/api/contacts'),
    apiRequest('/api/chats')
  ]);

  state.contacts = contactsRes.contacts;
  state.chats = chatsRes.chats;

  if (!state.selectedContactId && state.chats.length > 0) {
    state.selectedContactId = state.chats[0].id;
  }

  if (
    state.selectedContactId &&
    state.contacts.some((contact) => contact.id === state.selectedContactId) !== true
  ) {
    state.selectedContactId = state.chats.length > 0 ? state.chats[0].id : null;
  }

  renderContacts();
  renderChatHeader();
  renderContactProfile();
}

async function refreshMessages() {
  if (!state.selectedContactId) {
    state.messages = [];
    renderMessages();
    return;
  }

  const response = await apiRequest(`/api/messages?contactId=${encodeURIComponent(state.selectedContactId)}`);
  state.messages = response.messages;
  renderMessages();
}

async function selectContact(contactId) {
  state.selectedContactId = contactId;
  renderContacts();
  renderChatHeader();
  renderContactProfile();
  await refreshMessages();
}

async function bootstrap() {
  const data = await apiRequest('/api/bootstrap');

  state.config = data.config;
  state.identity = data.identity;
  state.ownVerification = data.ownVerification;
  state.contacts = data.contacts;
  state.chats = data.chats;

  el.privacyModeSelect.value = state.config.privacyMode || 'fast';
  el.relayUrlInput.value = state.config.relayUrl || '';

  if (!state.selectedContactId && state.chats.length > 0) {
    state.selectedContactId = state.chats[0].id;
  }

  setRelayChip(Boolean(state.config.relayConnected));
  renderIdentityCard();
  renderContacts();
  renderChatHeader();
  renderContactProfile();
  await refreshMessages();

  if (!state.identity) {
    el.onboardingOverlay.classList.remove('hidden');
  } else {
    el.onboardingOverlay.classList.add('hidden');
  }
}

async function createIdentity() {
  const id = el.identityNameInput.value.trim();
  if (!id) {
    showToast('Enter a username for your identity.');
    return;
  }

  await apiRequest('/api/init', {
    method: 'POST',
    body: JSON.stringify({
      id,
      oneTimePreKeyCount: 24
    })
  });

  showToast('Identity created.');
  await bootstrap();

  if (el.relayUrlInput.value.trim()) {
    await connectRelay();
  }
}

async function connectRelay() {
  const relayUrl = el.relayUrlInput.value.trim();
  if (!relayUrl) {
    showToast('Enter relay URL first.');
    return;
  }

  await apiRequest('/api/config', {
    method: 'POST',
    body: JSON.stringify({ relayUrl })
  });

  await apiRequest('/api/connect-relay', {
    method: 'POST',
    body: JSON.stringify({ relayUrl })
  });

  await refreshConfig();
  showToast('Relay connected and prekeys published.');
}

async function verifyPayload() {
  const payload = el.verifyPayloadInput.value.trim();
  if (!payload) {
    showToast('Paste or scan a verification payload.');
    return;
  }

  await apiRequest('/api/verify-contact', {
    method: 'POST',
    body: JSON.stringify({ payload })
  });

  el.verifyPayloadInput.value = '';
  showToast('Contact verified successfully.');
  await refreshChatsAndContacts();

  if (!state.selectedContactId && state.chats.length > 0) {
    await selectContact(state.chats[0].id);
  }
}

async function sendMessage() {
  const contactId = state.selectedContactId;
  if (!contactId) {
    showToast('Select a contact first.');
    return;
  }

  const text = el.messageInput.value.trim();
  if (!text) {
    showToast('Type a message.');
    return;
  }

  const selfDestructSeconds = el.selfDestructSelect.value
    ? Number(el.selfDestructSelect.value)
    : null;

  const privacyMode = el.privacyModeSelect.value;

  el.sendBtn.disabled = true;
  try {
    await apiRequest('/api/send', {
      method: 'POST',
      body: JSON.stringify({
        to: contactId,
        text,
        privacyMode,
        selfDestructSeconds
      })
    });

    el.messageInput.value = '';
    await refreshChatsAndContacts();
    await refreshMessages();

    if (privacyMode === 'stealth') {
      showToast('Sent in stealth mode with timing obfuscation.');
    }
  } finally {
    el.sendBtn.disabled = false;
  }
}

async function applyPrivacyMode() {
  await apiRequest('/api/config', {
    method: 'POST',
    body: JSON.stringify({ privacyMode: el.privacyModeSelect.value })
  });
}

async function onRuntimeEvent(event) {
  if (!event || typeof event.type !== 'string') {
    return;
  }

  if (event.type === 'relay_connected') {
    await refreshConfig();
  }

  if (event.type === 'relay_disconnected') {
    await refreshConfig();
  }

  if (
    event.type === 'message_in' ||
    event.type === 'message_saved' ||
    event.type === 'contact_verified' ||
    event.type === 'contact_added' ||
    event.type === 'config_updated'
  ) {
    await refreshChatsAndContacts();
    await refreshMessages();
    renderIdentityCard();
  }

  if (event.type === 'receive_error' || event.type === 'relay_error') {
    showToast(event.error || 'Secure transport warning.');
  }
}

async function startEventStream() {
  if (state.eventStream) {
    state.eventStream.close();
  }

  const events = new EventSource('/api/events');
  state.eventStream = events;

  events.addEventListener('update', async (message) => {
    try {
      const event = JSON.parse(message.data);
      await onRuntimeEvent(event);
    } catch {
      // ignore
    }
  });

  events.onerror = () => {
    events.close();

    if (state.eventStream === events) {
      state.eventStream = null;
    }

    clearTimeout(state.reconnectTimerId);
    state.reconnectTimerId = setTimeout(() => {
      startEventStream().catch((error) => showToast(error.message));
    }, 2500);
  };
}

function startBackgroundRefresh() {
  clearInterval(state.backgroundRefreshId);
  state.backgroundRefreshId = setInterval(() => {
    if (document.hidden) {
      return;
    }

    Promise.all([refreshConfig(), refreshChatsAndContacts(), refreshMessages()]).catch(() => {
      // keep the UI eventually consistent even if the event stream drops
    });
  }, 3000);
}

async function startScanner() {
  if (state.scanner.running) {
    return;
  }

  if (!('BarcodeDetector' in window)) {
    el.scannerHint.textContent = 'BarcodeDetector not supported here. Paste payload manually.';
    return;
  }

  try {
    state.scanner.detector = new BarcodeDetector({ formats: ['qr_code'] });
    state.scanner.stream = await navigator.mediaDevices.getUserMedia({
      video: {
        facingMode: 'environment'
      }
    });

    el.scannerVideo.srcObject = state.scanner.stream;
    el.scannerVideo.style.display = 'block';
    el.scannerHint.textContent = 'Scanning QR...';
    state.scanner.running = true;

    const scanLoop = async () => {
      if (!state.scanner.running) {
        return;
      }

      try {
        const codes = await state.scanner.detector.detect(el.scannerVideo);
        if (codes.length > 0 && codes[0].rawValue) {
          el.verifyPayloadInput.value = codes[0].rawValue;
          stopScanner();
          try {
            await verifyPayload();
          } catch (error) {
            showToast(error.message);
          }
          return;
        }
      } catch {
        // keep scanning
      }

      state.scanner.rafId = requestAnimationFrame(scanLoop);
    };

    state.scanner.rafId = requestAnimationFrame(scanLoop);
  } catch {
    el.scannerHint.textContent = 'Camera access denied. Paste payload manually.';
    stopScanner();
  }
}

function stopScanner() {
  state.scanner.running = false;

  if (state.scanner.rafId) {
    cancelAnimationFrame(state.scanner.rafId);
    state.scanner.rafId = null;
  }

  if (state.scanner.stream) {
    for (const track of state.scanner.stream.getTracks()) {
      track.stop();
    }
    state.scanner.stream = null;
  }

  el.scannerVideo.style.display = 'none';
}

function bindEvents() {
  el.createIdentityBtn.addEventListener('click', () => {
    createIdentity().catch((error) => showToast(error.message));
  });

  el.connectRelayBtn.addEventListener('click', () => {
    connectRelay().catch((error) => showToast(error.message));
  });

  el.refreshBtn.addEventListener('click', () => {
    Promise.all([refreshChatsAndContacts(), refreshMessages()]).catch((error) => showToast(error.message));
  });

  el.verifyPayloadBtn.addEventListener('click', () => {
    verifyPayload().catch((error) => showToast(error.message));
  });

  el.scanQrBtn.addEventListener('click', () => {
    if (state.scanner.running) {
      stopScanner();
      el.scannerHint.textContent = 'Scanner stopped.';
      return;
    }

    startScanner().catch((error) => showToast(error.message));
  });

  el.sendBtn.addEventListener('click', () => {
    sendMessage().catch((error) => showToast(error.message));
  });

  el.messageInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && event.shiftKey !== true) {
      event.preventDefault();
      sendMessage().catch((error) => showToast(error.message));
    }
  });

  el.privacyModeSelect.addEventListener('change', () => {
    applyPrivacyMode().catch((error) => showToast(error.message));
  });

  window.addEventListener('beforeunload', () => {
    stopScanner();
    clearInterval(state.backgroundRefreshId);
    clearTimeout(state.reconnectTimerId);

    if (state.eventStream) {
      state.eventStream.close();
      state.eventStream = null;
    }
  });
}

async function init() {
  bindEvents();
  await bootstrap();
  startBackgroundRefresh();
  await startEventStream();
}

init().catch((error) => {
  showToast(error.message);
});
