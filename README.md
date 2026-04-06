# GhostLink

GhostLink is now split into two layers:
- Security core: X3DH bootstrap with signed prekeys + one-time prekeys, ChaCha20-Poly1305 payload encryption, WebSocket relay transport.
- UX layer:
  - dark-mode web app with chat list, contact trust indicators, QR verification, and privacy mode toggle.
  - Flutter mobile MVP scaffold in `mobile/ghostlink_flutter` with onboarding, QR verification, chat, trust profile, and settings.

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

## Notes

- UI keeps crypto mostly invisible while preserving verification controls.
- `stealth` mode currently adds randomized send delay; cover traffic and multi-hop routing are not implemented yet.
- Double Ratchet implementation does not yet include skipped-message key cache for out-of-order packet recovery.
- Flutter tooling is not available in this execution environment, so Flutter compile/run was not executed here.
