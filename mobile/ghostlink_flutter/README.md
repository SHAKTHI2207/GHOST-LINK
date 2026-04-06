# GhostLink Flutter MVP

This module is a Flutter-first mobile UX + protocol wiring scaffold for GhostLink.

## Implemented

- Onboarding screen with one-tap identity creation.
- Identity + QR screen with fingerprint display, copy/share payload, and QR scanner entry.
- Home chat list with trust indicators (verified / unverified / risk).
- Chat screen with reusable bubbles, message composer, and quick self-destruct action.
- Contact profile with re-verification flow and local chat cleanup.
- Settings for privacy mode (`fast` / `stealth`), self-destruct timer, read receipts, key export.

## Security/Transport Wiring

- X3DH prekey bundle generation:
  - Identity key pair (X25519)
  - Signed prekey + signature (Ed25519)
  - One-time prekeys pool
- Relay protocol via WebSocket:
  - `auth`
  - `publish_prekeys`
  - `fetch_prekey_bundle`
  - `send_packet`
- Encrypted packet flow:
  - X3DH bootstrap for initial session setup
  - Double Ratchet for subsequent message keys
  - AES-GCM payload encryption
- QR contact verification payload:
  - `ghostlink://verify/<base64url-json>`
- Secure persistence:
  - `flutter_secure_storage` (Keychain/Keystore-backed)
  - Identity material + ratchet session state persisted across app restarts

## Run (once Flutter is installed)

```bash
cd mobile/ghostlink_flutter
flutter pub get
flutter run
```

Relay target defaults to `ws://127.0.0.1:8080`.
Use your existing Node relay from the project root:

```bash
npm run relay
```

## Notes

- Secure storage uses platform hardware-backed paths where available (iOS Keychain / Android Keystore).
- Ratchet implementation is MVP-grade and does not yet include skipped-message key caching for out-of-order delivery.
- Local testing in this environment could not run Flutter tools until Flutter SDK is installed.
