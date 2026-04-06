# GhostLink


Private communication, rebuilt from first principles.

GhostLink is a hybrid secure messaging system designed to deliver end-to-end confidentiality, forward secrecy, and metadata resistance, while maintaining a clean, intuitive user experience.

It combines modern cryptographic protocols with a minimal, privacy-first interface—giving users control without complexity.

GhostLink is now split into two layers:
- Security core: X3DH bootstrap with signed prekeys + one-time prekeys, ChaCha20-Poly1305 payload encryption, WebSocket relay transport.
- UX layer: - dark-mode web app with chat list, contact trust indicators, QR verification, and privacy mode toggle.
-  Flutter mobile MVP scaffold in `mobile/ghostlink_flutter` with onboarding, QR verification, chat, trust profile, and settings.

Why GhostLink?

Most messaging apps optimize for convenience first, privacy second.

GhostLink flips that.
	•	❌ No phone numbers
	•	❌ No centralized identity tracking
	•	❌ No plaintext exposure
	•	✅ Cryptographic identity (public/private keys)
	•	✅ End-to-end encryption by default
	•	✅ Forward secrecy + post-compromise security
	•	✅ User-controlled trust verification (QR + fingerprints)

GhostLink isn’t just another chat app.
It’s a secure communication layer built for:
	•	Privacy-first individuals
	•	Small trusted networks (family, teams)
	•	Experimental secure systems & research

⸻

 Architecture Overview

GhostLink is split into two layers:

   Security Core
	•	X3DH key exchange
	•	Identity Keys (IK)
	•	Signed PreKeys (SPK)
	•	One-Time PreKeys (OPK)
	•	Double Ratchet
	•	Per-message key evolution
	•	Forward secrecy
	•	Post-compromise recovery
	•	Encryption
	•	ChaCha20-Poly1305
	•	Transport
	•	WebSocket relay (zero-knowledge)

⸻

 UX Layer

Web App
	•	Dark-mode interface
	•	Chat list + trust indicators
	•	QR-based contact verification
	•	Privacy mode toggle (fast / stealth)

Mobile (Flutter MVP)
	•	Onboarding with identity generation
	•	QR verification flow
	•	Chat interface
	•	Trust profile (fingerprint + keys)
	•	Settings (privacy mode, self-destruct)

## What Works

- X3DH-style session start with signature verification.
- OPK lifecycle (relay consumes once, receiver consumes once).
- Zero-knowledge WebSocket relay for prekeys + encrypted packet delivery.
- QR-based contact verification (`ghostlink://verify/...`).
- Chat UI with:
  - Contact status indicators (verified/unverified/risk).
  - Message composer with self-destruct timer.
  - Privacy mode toggle (`fast` / `stealth`).
  - Trust center (QR, fingerprint, advanced key details).

## Run It

1. Install dependencies:

```bash
npm install
```

2. Start relay server:

```bash
npm run relay
```

3. Start UI app:

```bash
npm run ui
```

4. Open:

- `http://127.0.0.1:3000`

5. In UI:

- Create identity on first launch.
- Connect relay (`ws://127.0.0.1:8080`).
- Verify contact by scanning/pasting QR payload.
- Chat normally.

## Flutter Mobile MVP

The mobile scaffold lives in:

- `mobile/ghostlink_flutter`

When Flutter is installed:

```bash
cd mobile/ghostlink_flutter
flutter pub get
flutter run
```

It connects to the same relay protocol (`ws://127.0.0.1:8080`) and includes:

- X3DH prekey bundle generation (IK + SPK + OPK).
- Double Ratchet on top of X3DH bootstrap for ongoing message key evolution.
- WebSocket relay auth/publish/fetch/send flow.
- QR verification (`ghostlink://verify/...`) with scanner UI.
- Secure state persistence in platform secure storage (Keychain/Keystore-backed via `flutter_secure_storage`).
- Home/chat/profile/settings screens with privacy mode + self-destruct controls.

## CLI (still available)

Useful low-level commands:

- `node src/cli.js init --data <dir> --id <user-id>`
- `node src/cli.js show-qr --data <dir>`
- `node src/cli.js verify-contact --data <dir> --payload <uri-or-payload>`
- `node src/cli.js relay-start --state <path> --port 8080`
- `node src/cli.js listen --data <dir> --url ws://127.0.0.1:8080`
- `node src/cli.js send --data <dir> --url ws://127.0.0.1:8080 --to <id> --message "hello"`

## Tests

```bash
npm test
```

## Current Limitations
	•	No skipped-message key cache (out-of-order messages not handled yet)
	•	No multi-hop routing (Tor-style relay not implemented)
	•	No cover traffic (stealth mode is partial)
	•	Single-device identity model

⸻
 ## Roadmap
	•	Skipped message key handling
	•	Multi-hop relay routing
	•	Cover traffic engine
	•	Multi-device sync
	•	Post-quantum cryptography (hybrid key exchange)

⸻
## Design Philosophy

GhostLink follows one rule:

Security should be invisible, but always verifiable.

Users shouldn’t need to understand cryptography—
but they should always have the ability to verify trust when it matters.

⸻


## Notes

- UI keeps crypto mostly invisible while preserving verification controls.
- `stealth` mode currently adds randomized send delay; cover traffic and multi-hop routing are not implemented yet.
- Double Ratchet implementation does not yet include skipped-message key cache for out-of-order packet recovery.
- Flutter tooling is not available in this execution environment, so Flutter compile/run was not executed here.
