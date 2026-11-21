# passkeys-kit-server

Passkey (WebAuthn) sign-in for **Express 5** and **MongoDB**, made for native iOS and Android apps. It's part of [Passkeys Kit](../README.md); the Flutter side is [`passkeys_kit`](../flutter).

- **`src/`** is the kit: `createPasskeys()` (the router), `createPasskeyService()`, `passkeyOrigins()`, `createWellKnownRouter()`, and the `Passkey` and `PasskeyChallenge` models.
- **`example/`** is a whole API: accounts with a password, sessions, and passkeys on top. The Flutter example talks to it.
- **`tests/`** holds 29 tests that sign with a [virtual authenticator](tests/virtual-authenticator.ts). Nothing is mocked.

## Use it

The package isn't on npm yet. Copy `src/` into your backend and install its dependencies:

```bash
npm install @simplewebauthn/server@^14 express-rate-limit@^8 zod@^4
```

```ts
import { createPasskeys, passkeyOrigins } from "./passkeys/index.js";

const passkeys = createPasskeys<UserDocument>({
  config: {
    rpID: "example.com",
    rpName: "Example",
    origins: passkeyOrigins({ rpID: "example.com", androidSha256: ["F7:74:7B:3A:…:75:C9"] }),
  },
  users: {
    id: (user) => user.id,
    name: (user) => user.email,
    displayName: (user) => user.name,
    findById: (id) => User.findById(id).exec(),
  },
  authenticate: requireAuth,
  currentUser: (_req, res) => res.locals.user,
  signIn: (user) => createSession(user),
});

app.use("/auth/passkeys", passkeys.router);
```

| Route | Auth | Answer |
| --- | --- | --- |
| `POST /register/options` | signed in | options for the phone |
| `POST /register/verify` | signed in | `201` and the new passkey |
| `POST /login/options` | public, rate limited | options for the phone |
| `POST /login/verify` | public, rate limited | whatever `signIn` returns |
| `GET /` | signed in | the user's passkeys, the newest first |
| `DELETE /:id` | signed in | `204` |

The [server guide](../docs/server.md) documents every option, route and error.

## Run the example

```bash
cp .env.example .env   # set RP_ID and your app ids
npm install
npm run dev            # http://localhost:3000
```

The RP ID's domain must list your apps in its `.well-known` files. See [Domain setup](../docs/domain-setup.md).

| Script | What it does |
| --- | --- |
| `npm run dev` | Runs the example and restarts it on changes |
| `npm run build` | Compiles `src/` and `example/` to `dist/` |
| `npm start` | Runs the compiled example |
| `npm run typecheck` | Type-checks everything, tests included |
| `npm test` | Runs the tests against `passkeys_kit_test` on a local MongoDB ([Testing](../docs/testing.md)) |

## Requirements

Node.js 22.9 or newer, Express 5, Mongoose 9, and MongoDB.
