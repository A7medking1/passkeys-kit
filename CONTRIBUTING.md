# Contributing

Thanks for helping. This page explains how to work on the kit and what a pull request needs.

## Set up

**Server.** You need Node.js 22.9 or newer and MongoDB at `127.0.0.1:27017`:

```bash
cd server
npm install
npm test
```

The tests use their own `passkeys_kit_test` database and drop it each run. They refuse any other database name.

**Flutter.** You need Flutter 3.41 or newer:

```bash
cd flutter
flutter pub get
flutter test
```

To run the example app end to end, you need a domain set up for passkeys. See [Domain setup](docs/domain-setup.md) and the [example's README](flutter/example/README.md).

## Before you open a pull request

- [ ] `npm run typecheck` and `npm test` pass in `server/`.
- [ ] `flutter analyze` and `flutter test` pass in `flutter/` and in `flutter/example/`.
- [ ] `dart format .` leaves nothing to change in `flutter/`.
- [ ] A change in behavior comes with a test, and with an update to the guide in `docs/` that describes it.
- [ ] `CHANGELOG.md` lists the change under **Unreleased**.
- [ ] Your own ids stay out of the commit. `server/.env` and `flutter/example/ios/Flutter/Local.xcconfig` are git-ignored for this.

## Guidelines

- **Test with real signatures.** Server tests sign with [`VirtualPasskey`](server/tests/virtual-authenticator.ts) and let SimpleWebAuthn verify them. Don't mock the cryptography.
- **Keep failures generic for clients.** A refused sign-in tells the client nothing about why. Put the reason in the `log` hook.
- **Keep the app's ownership.** The kit doesn't own users or sessions. New features go through hooks and adapters, not through assumptions about the app's models.
- **Comments explain why**, not what the next line does.

## Reporting bugs

Open an issue with:

- the platform and OS version (iOS 26 Simulator, Pixel 9 on Android 16…);
- what you did, what you expected, and what happened;
- the server's log line for the refused passkey, if there is one ([Troubleshooting](docs/troubleshooting.md) explains it).

Please report security problems privately, as [SECURITY.md](SECURITY.md) describes.
