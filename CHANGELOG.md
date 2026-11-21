# Changelog

All notable changes to this project are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-11-21

The first release.

### Added

- **Server (`passkeys-kit-server`)**
  - `createPasskeys()`: an Express 5 router with `register/options`, `register/verify`, `login/options`, `login/verify`, the user's list, and delete.
  - Single-use challenges in MongoDB, tied to their type and (for registration) to the user, and deleted by a TTL index once expired.
  - Usernameless sign-in with discoverable passkeys, user verification required, and platform authenticators.
  - One generic 401 for every failed sign-in. The reason goes to a `log` hook.
  - `passkeyOrigins()` and `androidOrigin()`: the iOS origin, plus Android origins built from signing-key fingerprints.
  - `createWellKnownRouter()` and `wellKnownFiles()` for `apple-app-site-association` and `assetlinks.json`.
  - Rate limits on the public routes, a `canRegister` hook, replaceable messages, and a passkey limit per user.
  - `createPasskeyService()` for using the logic without the router, and `removeAll()` for password changes.
- **Flutter (`passkeys_kit`)**
  - `PasskeyClient` with `isAvailable()`, `signIn()`, `register()`, `list()` and `delete()`.
  - `HttpPasskeyServerApi` over `package:http`, and the `PasskeyServerApi` interface for other clients.
  - `SystemPasskeyDevice` over the `passkeys` package, which names new passkeys after the phone.
  - `PasskeyException` with a `PasskeyFailure` reason, the server's message, and the status code.
- **Examples**
  - A server with password accounts, token sessions and passkeys. A password change ends the other sessions and removes every passkey.
  - A Flutter app with a dark UI: sign up, sign in with a password or a passkey, and add, list or delete passkeys.
- **Docs and tests**
  - Guides for how it works, domain setup, the server, Flutter, testing, troubleshooting and security.
  - 29 server tests signed by a virtual P-256 authenticator, and 14 Flutter tests.

### Known limitations

- Not published to npm or pub.dev yet: copy the server's `src/`, and add the Flutter package as a git dependency.
- Run end to end on the iOS Simulator (iOS 26.5). Not yet run on an Android device.

[Unreleased]: https://github.com/A7medking1/passkeys-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/A7medking1/passkeys-kit/releases/tag/v0.1.0
