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
  identitySummaryCard: document.getElementById('identitySummaryCard'),
  contactsList: document.getElementById('contactsList'),
  chatAvatar: document.getElementById('chatAvatar'),
  chatTitle: document.getElementById('chatTitle'),
  chatSubtitle: document.getElementById('chatSubtitle'),
  chatNoticeText: document.getElementById('chatNoticeText'),
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

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function formatTime(iso) {
  if (!iso) {
    return '';
  }

  return new Date(iso).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit'
  });
}

function formatChatTime(iso) {
  if (!iso) {
    return '';
  }

  const date = new Date(iso);
  const now = new Date();
  const sameDay = date.toDateString() === now.toDateString();

  if (sameDay) {
    return formatTime(iso);
  }

  return date.toLocaleDateString([], {
    month: 'short',
    day: 'numeric'
  });
}

function formatDayLabel(iso) {
  return new Date(iso).toLocaleDateString([], {
    weekday: 'short',
    month: 'short',
    day: 'numeric'
  });
}

function initialsFor(value) {
  const clean = String(value ?? '')
    .replace(/[^a-zA-Z0-9]+/g, ' ')
    .trim();

  if (!clean) {
    return 'GL';
  }

  const parts = clean.split(/\s+/).slice(0, 2);
  return parts.map((part) => part[0]).join('').toUpperCase();
}

function shortFingerprint(value) {
  if (!value) {
    return 'Unavailable';
  }

  return `${value.slice(0, 12)}...${value.slice(-8)}`;
}

function statusMeta(status) {
  if (status === 'verified') {
    return {
      label: 'Verified Secure Connection',
      shortLabel: 'Verified',
      dotClass: 'status-verified',
      badgeClass: 'verified',
      avatarClass: 'verified'
    };
  }

  if (status === 'risk') {
    return {
      label: 'Security Risk Detected',
      shortLabel: 'Risk',
      dotClass: 'status-risk',
      badgeClass: 'risk',
      avatarClass: 'risk'
    };
  }

  return {
    label: 'Unverified Contact',
    shortLabel: 'Unverified',
    dotClass: 'status-unverified',
    badgeClass: 'unverified',
    avatarClass: 'unverified'
  };
}

function currentContact() {
  return state.contacts.find((contact) => contact.id === state.selectedContactId) || null;
}

function setRelayChip(connected) {
  el.relayStatusChip.className = connected ? 'status-chip online' : 'status-chip offline';
  el.relayStatusChip.textContent = connected ? 'Relay Online' : 'Relay Offline';
}

function autoSizeComposer() {
  el.messageInput.style.height = 'auto';
  el.messageInput.style.height = `${Math.min(el.messageInput.scrollHeight, 150)}px`;
}

async function refreshConfig() {
  const health = await apiRequest('/api/health');
  state.config = health.config;
  el.privacyModeSelect.value = state.config.privacyMode || 'fast';
  el.relayUrlInput.value = state.config.relayUrl || '';
  setRelayChip(Boolean(state.config.relayConnected));
}

function renderOwnSummaryCard() {
  if (!state.identity) {
    el.identitySummaryCard.innerHTML = `
      <p class="small-meta">Create your identity to start local-first secure messaging.</p>
    `;
    return;
  }

  const relayState = state.config && state.config.relayConnected ? 'Connected' : 'Offline';

  el.identitySummaryCard.innerHTML = `
    <div class="identity-hero">
      <div class="avatar avatar-large verified">${escapeHtml(initialsFor(state.identity.id))}</div>
      <div>
        <p class="eyebrow">You</p>
        <h2>${escapeHtml(state.identity.id)}</h2>
        <p class="identity-summary-copy">Private identity ready for verified messaging.</p>
      </div>
    </div>
    <div class="identity-summary-stats">
      <div class="mini-stat">
        <span class="mini-stat-label">Contacts</span>
        <span class="mini-stat-value">${String(state.contacts.length)}</span>
      </div>
      <div class="mini-stat">
        <span class="mini-stat-label">Relay</span>
        <span class="mini-stat-value">${escapeHtml(relayState)}</span>
      </div>
      <div class="mini-stat">
        <span class="mini-stat-label">OPKs</span>
        <span class="mini-stat-value">${String(state.identity.availableOneTimePreKeys || 0)}</span>
      </div>
      <div class="mini-stat">
        <span class="mini-stat-label">Fingerprint</span>
        <span class="mini-stat-value">${escapeHtml(shortFingerprint(state.identity.fingerprint))}</span>
      </div>
    </div>
  `;
}

function renderIdentityCard() {
  if (!state.identity || !state.ownVerification) {
    el.identityCard.innerHTML = '<p class="small-meta">Identity not initialized.</p>';
    return;
  }

  el.identityCard.innerHTML = `
    <div class="identity-title">
      <div>
        <p class="eyebrow">Your QR Identity</p>
        <h3>${escapeHtml(state.identity.id)}</h3>
      </div>
      <span class="code-pill">Share in person</span>
    </div>
    <p class="section-copy">This QR is the human-friendly trust layer for your cryptographic identity.</p>
    <img src="${state.ownVerification.qrDataUrl}" alt="Verification QR" />
    <div class="identity-meta-grid">
      <div class="mini-stat">
        <span class="mini-stat-label">Fingerprint</span>
        <span class="mini-stat-value">${escapeHtml(shortFingerprint(state.identity.fingerprint))}</span>
      </div>
      <div class="mini-stat">
        <span class="mini-stat-label">Signed Prekey</span>
        <span class="mini-stat-value">${escapeHtml(state.identity.signedPreKeyId)}</span>
      </div>
    </div>
    <div class="fingerprint-block">
      <p class="eyebrow">Full Fingerprint</p>
      <p class="mono-text">${escapeHtml(state.ownVerification.fingerprintFormatted)}</p>
    </div>
  `;
}

function renderContacts() {
  if (state.chats.length === 0) {
    el.contactsList.innerHTML = '<p class="small-meta">No contacts yet. Verify one from the trust center.</p>';
    return;
  }

  el.contactsList.innerHTML = '';

  for (const chat of state.chats) {
    const status = statusMeta(chat.status);
    const item = document.createElement('article');
    item.className = 'contact-item' + (chat.id === state.selectedContactId ? ' active' : '');
    item.innerHTML = `
      <div class="avatar ${status.avatarClass}">${escapeHtml(initialsFor(chat.id))}</div>
      <div class="contact-body">
        <div class="contact-topline">
          <span class="contact-name">${escapeHtml(chat.id)}</span>
          <span class="contact-time">${escapeHtml(
            chat.lastMessage ? formatChatTime(chat.lastMessage.createdAt) : ''
          )}</span>
        </div>
        <div class="contact-bottomline">
          <p class="contact-preview">${escapeHtml(
            chat.lastMessage ? chat.lastMessage.text : 'No messages yet'
          )}</p>
          <div class="inline-row">
            <span class="status-dot ${status.dotClass}" aria-hidden="true"></span>
            <span class="contact-status-label">${escapeHtml(status.shortLabel)}</span>
          </div>
        </div>
      </div>
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
    el.chatAvatar.className = 'avatar avatar-large verified';
    el.chatAvatar.textContent = 'GL';
    el.chatTitle.textContent = 'GhostLink';
    el.chatSubtitle.textContent = 'End-to-end encrypted messaging ready when you are.';
    el.chatNoticeText.textContent = 'Messages stay encrypted in transit and local on this device.';
    return;
  }

  const status = statusMeta(contact.status);
  el.chatAvatar.className = `avatar avatar-large ${status.avatarClass}`;
  el.chatAvatar.textContent = initialsFor(contact.id);
  el.chatTitle.textContent = contact.id;
  el.chatSubtitle.textContent = status.label;
  el.chatNoticeText.textContent =
    contact.verified === true
      ? 'Verified contact. Secure messaging runs invisibly in the background.'
      : 'Unverified contact. Scan their QR in person to lock identity trust.';
}

function renderMessages() {
  const contact = currentContact();

  if (!contact) {
    el.messagesArea.innerHTML = `
      <div class="empty-chat">
        <div class="empty-chat-badge">Secure Chat Ready</div>
        <h3>Pick a contact and send your first message</h3>
        <p>GhostLink keeps the crypto invisible so the conversation feels familiar.</p>
      </div>
    `;
    return;
  }

  if (state.messages.length === 0) {
    el.messagesArea.innerHTML = `
      <div class="empty-chat">
        <div class="empty-chat-badge">${escapeHtml(contact.verified ? 'Verified Contact' : 'Waiting for First Message')}</div>
        <h3>No messages yet with ${escapeHtml(contact.id)}</h3>
        <p>Write a message below and GhostLink will handle the secure session setup automatically.</p>
      </div>
    `;
    return;
  }

  const showReceipt = el.receiptToggle.checked;
  let lastDayKey = '';
  const rows = [];

  for (const message of state.messages) {
    const dayKey = new Date(message.createdAt).toDateString();
    if (dayKey !== lastDayKey) {
      rows.push(`
        <div class="day-divider">
          <span>${escapeHtml(formatDayLabel(message.createdAt))}</span>
        </div>
      `);
      lastDayKey = dayKey;
    }

    const directionClass = message.direction === 'out' ? 'out' : 'in';
    const metaParts = [formatTime(message.createdAt)];

    if (showReceipt && message.direction === 'out') {
      metaParts.push(message.status || 'sent');
    }

    if (message.expiresAt) {
      metaParts.push('self-destruct');
    }

    rows.push(`
      <div class="message-row ${directionClass}">
        <div class="message-bubble">
          <div class="message-text">${escapeHtml(message.text)}</div>
          <div class="message-meta">${escapeHtml(metaParts.join(' • '))}</div>
        </div>
      </div>
    `);
  }

  el.messagesArea.innerHTML = rows.join('');
  el.messagesArea.scrollTop = el.messagesArea.scrollHeight;
}

function renderContactProfile() {
  const contact = currentContact();

  if (!contact) {
    el.contactProfileCard.innerHTML = `
      <p class="small-meta">Select a contact to view verification status, fingerprint, and key details.</p>
    `;
    return;
  }

  const status = statusMeta(contact.status);
  const riskText = contact.risk
    ? `
        <div class="fingerprint-block">
          <p class="eyebrow">Risk Alert</p>
          <p class="small-meta">${escapeHtml(contact.risk)}</p>
        </div>
      `
    : '';

  el.contactProfileCard.innerHTML = `
    <div class="profile-persona">
      <div class="avatar avatar-large ${status.avatarClass}">${escapeHtml(initialsFor(contact.id))}</div>
      <div>
        <p class="eyebrow">Current Contact</p>
        <h3>${escapeHtml(contact.id)}</h3>
        <span class="verification-badge ${status.badgeClass}">${escapeHtml(status.label)}</span>
      </div>
    </div>
    <div class="profile-meta-grid">
      <div class="mini-stat">
        <span class="mini-stat-label">Verification</span>
        <span class="mini-stat-value">${escapeHtml(contact.verificationMethod || 'pending')}</span>
      </div>
      <div class="mini-stat">
        <span class="mini-stat-label">Fingerprint</span>
        <span class="mini-stat-value">${escapeHtml(shortFingerprint(contact.fingerprint))}</span>
      </div>
    </div>
    <div class="fingerprint-block">
      <p class="eyebrow">Full Fingerprint</p>
      <p class="mono-text">${escapeHtml(contact.fingerprint)}</p>
    </div>
    ${riskText}
    <details>
      <summary>Advanced Key Material</summary>
      <div class="key-block">
        <p class="eyebrow">Identity Key</p>
        <p class="mono-text">${escapeHtml(contact.identityKeyPem || 'Unavailable')}</p>
      </div>
      <div class="key-block">
        <p class="eyebrow">Signing Key</p>
        <p class="mono-text">${escapeHtml(contact.identitySigningKeyPem || 'Unavailable')}</p>
      </div>
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

  renderOwnSummaryCard();
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
  renderOwnSummaryCard();
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
  renderOwnSummaryCard();
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
    autoSizeComposer();
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

  if (event.type === 'relay_connected' || event.type === 'relay_disconnected') {
    await refreshConfig();
    renderOwnSummaryCard();
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
    renderOwnSummaryCard();
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
      // ignore malformed event payloads
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
      // keep the UI eventually consistent if the event stream drops
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
    Promise.all([refreshConfig(), refreshChatsAndContacts(), refreshMessages()]).catch((error) => {
      showToast(error.message);
    });
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

  el.messageInput.addEventListener('input', () => {
    autoSizeComposer();
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
  autoSizeComposer();
  await bootstrap();
  startBackgroundRefresh();
  await startEventStream();
}

init().catch((error) => {
  showToast(error.message);
});
