# Server guide

The server side is an Express 5 router plus two Mongoose models. It does the WebAuthn work and leaves your users and sessions to you.

- [Install](#install)
- [Mount the router](#mount-the-router)
- [Options](#options)
- [Routes](#routes)
- [The `signIn` hook](#the-signin-hook)
- [When the password changes](#when-the-password-changes)
- [Errors and status codes](#errors-and-status-codes)
- [Messages and translations](#messages-and-translations)
- [Rate limits](#rate-limits)
- [The service, without the router](#the-service-without-the-router)
- [Models and indexes](#models-and-indexes)
- [The `.well-known` files](#the-well-known-files)
- [JavaScript, CommonJS and Express 4](#javascript-commonjs-and-express-4)
- [The example server](#the-example-server)

## Install

The package isn't on npm yet. Copy [`server/src/`](../server/src) into your backend, as `src/passkeys/` for example, then install its three dependencies:

```bash
npm install @simplewebauthn/server@^14 express-rate-limit@^8 zod@^4
```

Your app provides `express@^5` and `mongoose@^9`. The models use Mongoose's default connection, the one `mongoose.connect()` opens.

## Mount the router

```ts
import { createPasskeys, passkeyOrigins } from "./passkeys/index.js";

const passkeys = createPasskeys<UserDocument>({
  config: {
    rpID: process.env.RP_ID!, // "example.com"
    rpName: "Example",
    origins: passkeyOrigins({
      rpID: process.env.RP_ID!,
      androidSha256: process.env.ANDROID_SHA256?.split(",") ?? [],
    }),
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

`createPasskeys` returns:

| Field | What it is |
| --- | --- |
| `router` | The Express router. Mount it wherever you like. |
| `service` | The same logic with no HTTP in it. See [the service](#the-service-without-the-router). |
| `removeAll(userId)` | Deletes every passkey of a user. See [when the password changes](#when-the-password-changes). |

## Options

### `config`

| Field | Type | Default | What it is |
| --- | --- | --- | --- |
| `rpID` | `string` | required | The domain the passkeys belong to, with no scheme and no port: `example.com`. See [Domain setup](domain-setup.md#1-choose-the-rp-id). |
| `rpName` | `string` | required | Your app's name. Some password managers show it next to the passkey. |
| `origins` | `string[]` | required | Every origin a sign-in may come from. Build it with `passkeyOrigins()`. |
| `challengeTtlMs` | `number` | `300000` (5 minutes) | How long the phone has between the options and the verify. |
| `maxPasskeysPerUser` | `number` | `10` | How many passkeys one account may have. |

**`passkeyOrigins({ rpID, androidSha256?, extra? })`** returns `https://<rpID>` (what iOS sends), one `android:apk-key-hash:…` origin per Android signing key, and anything in `extra`, like a website's origin.

**`androidOrigin(sha256)`** turns one fingerprint into its origin. It takes the colon-separated hex that `keytool` and the Play Console show, with or without the colons, and throws on anything that isn't a SHA-256:

```ts
androidOrigin("F7:74:7B:3A:F3:C1:1B:62:F4:CF:48:48:54:3F:0A:CA:E5:DE:4E:85:AA:41:A5:D9:B6:30:FF:77:65:52:75:C9");
// "android:apk-key-hash:93R7OvPBG2L0z0hIVD8KyuXeToWqQaXZtjD_d2VSdck"
```

### `users`: how the kit reads your users

The kit never imports your user model. It goes through this adapter:

| Method | What it returns |
| --- | --- |
| `id(user)` | The user's id as a string that never changes. Its UTF-8 bytes become the passkey's **user handle**, so it must be 64 bytes at most. A MongoDB ObjectId or a UUID is fine. Don't use an email or a phone number: those change. |
| `name(user)` | What the password manager shows to tell accounts apart: an email or a phone number. |
| `displayName(user)` | What it shows next to that: the person's name. |
| `findById(id)` | The account a passkey belongs to, loaded at sign-in. Return `null` if it's gone, and the sign-in fails. |

### `authenticate` and `currentUser`

`authenticate` is **your** auth middleware. The kit runs it before `register/options`, `register/verify`, `GET /` and `DELETE /:id`. It must answer a request that has no signed-in user (usually with a 401) and attach the user for `currentUser` to read.

```ts
authenticate: requireAuth,                    // sets res.locals.user, or answers 401
currentUser: (_req, res) => res.locals.user,  // reads it back
```

If your middleware sets `req.user` instead, read it there: `currentUser: (req) => req.user!`.

### `signIn`

`signIn(user, req, res)` answers a verified passkey sign-in. Return the body your password sign-in returns, and the app can save both the same way. It may be async. See [the `signIn` hook](#the-signin-hook).

### `canRegister`

`canRegister(user)` decides who may add passkeys. By default every signed-in user can. Return `false` (or a promise of it) to refuse with a 403:

```ts
canRegister: (user) => user.role === "customer",
```

### `rateLimit`

Limits per IP on the public routes. Pass your own numbers, or `false` to bring your own limiter. See [Rate limits](#rate-limits).

| Field | Default | What it counts |
| --- | --- | --- |
| `optionsPerMinute` | `30` | `login/options` calls. Each one saves a challenge, so each one counts. |
| `failedSignInsPer15Minutes` | `10` | Failed `login/verify` calls. Successful ones don't count. |

### `messages`

Any of the [messages](#messages-and-translations) to replace. The rest keep their English defaults.

### `log`

`log(message)` receives the reason behind each refused registration or sign-in, like `Passkey sign-in refused: Unexpected authentication response origin "android:apk-key-hash:…"`. The app only ever gets the generic message. The default is `console.warn`.

## Routes

The paths below are relative to where you mount the router: `/auth/passkeys` in the examples. Each route takes and returns JSON. The router parses bodies up to 64 kB itself.

| Route | Auth | Success |
| --- | --- | --- |
| `POST /register/options` | signed in | `200`, options for the phone |
| `POST /register/verify` | signed in | `201`, the new passkey |
| `POST /login/options` | public, rate limited | `200`, options for the phone |
| `POST /login/verify` | public, rate limited | `200`, whatever `signIn` returns |
| `GET /` | signed in | `200`, the user's passkeys, the newest first |
| `DELETE /:id` | signed in | `204` |

### `POST /register/options`

The body is ignored. The answer is passed to the phone as it is. These are real values from the example server:

```json
{
  "challenge": "2MUKHKJDiHp1SxGI5_ye6mX7TKxcxqUOm31IQASpwsM",
  "rp": { "name": "Passkeys Kit", "id": "example.com" },
  "user": {
    "id": "NmIwMWJiOTlkMjgxYTZiN2RmOThmZDA3",
    "name": "ahmed.nasr@example.com",
    "displayName": "Ahmed Nasr"
  },
  "pubKeyCredParams": [
    { "alg": -48, "type": "public-key" },
    { "alg": -8, "type": "public-key" },
    { "alg": -7, "type": "public-key" },
    { "alg": -257, "type": "public-key" }
  ],
  "timeout": 60000,
  "attestation": "none",
  "excludeCredentials": [],
  "authenticatorSelection": {
    "residentKey": "required",
    "userVerification": "required",
    "authenticatorAttachment": "platform",
    "requireResidentKey": true
  },
  "extensions": { "credProps": true },
  "hints": []
}
```

`user.id` is the user handle: the user's id (`6b01bb99d281a6b7df98fd07`) in base64url. `excludeCredentials` lists the passkeys the user already has.

### `POST /register/verify`

```json
{
  "response": { "id": "…", "rawId": "…", "type": "public-key", "response": { "clientDataJSON": "…", "attestationObject": "…", "transports": ["internal", "hybrid"] }, "clientExtensionResults": {} },
  "name": "iPhone 17 Pro"
}
```

`response` is what the phone returned. `name` is optional (1 to 60 characters, `"Passkey"` when missing). The answer is `201` with the passkey:

```json
{
  "id": "hY7m2Q5mH3oN0w2c8f0hYg",
  "name": "iPhone 17 Pro",
  "deviceType": "multiDevice",
  "backedUp": true,
  "createdAt": "2026-11-21T15:44:20.118Z",
  "lastUsedAt": null
}
```

### `POST /login/options`

The body is ignored. Anyone may call it.

```json
{
  "rpId": "example.com",
  "challenge": "jk4U-NLR3G3IfI6hEI1G4cYCCmJIrcjOWIBfwCzGHJI",
  "allowCredentials": [],
  "timeout": 60000,
  "userVerification": "required"
}
```

### `POST /login/verify`

```json
{
  "response": { "id": "…", "rawId": "…", "type": "public-key", "response": { "clientDataJSON": "…", "authenticatorData": "…", "signature": "…", "userHandle": "NmIwMWJiOTlkMjgxYTZiN2RmOThmZDA3" }, "clientExtensionResults": {} }
}
```

The answer is whatever your `signIn` hook returned. In the example:

```json
{
  "token": "pS3x…",
  "user": { "id": "6b01bb99d281a6b7df98fd07", "name": "Ahmed Nasr", "email": "ahmed.nasr@example.com" }
}
```

### `GET /`

The signed-in user's passkeys, the newest first, in the same shape `register/verify` returns. Public keys and counters are never included.

### `DELETE /:id`

Deletes one of the signed-in user's passkeys by its id and answers `204`. Another user's passkey, or an unknown id, gets a `404`, so nobody can tell the two apart.

## The `signIn` hook

`signIn` runs after the passkey is verified and the account is loaded. What it returns becomes the response.

**A token, like the example:**

```ts
signIn: (user) => createSession(user), // { token, user }, the same as POST /auth/login
```

**A JWT:**

```ts
import jwt from "jsonwebtoken";

signIn: (user) => ({
  token: jwt.sign({ sub: user.id }, process.env.JWT_SECRET!, { expiresIn: "30d" }),
  user: user.toJSON(),
}),
```

**A cookie session** (with `express-session`):

```ts
signIn: (user, req) => {
  req.session.userId = user.id;
  return { user: user.toJSON() };
},
```

**Refusing an account.** Throw a `PasskeyError` and its status and message reach the app:

```ts
import { PasskeyError } from "./passkeys/index.js";

signIn: (user) => {
  if (user.blocked) throw new PasskeyError(403, "This account is blocked.");
  return createSession(user);
},
```

If the hook sends the response itself (`res.redirect(...)`, say), the router doesn't send another one.

## When the password changes

Call `removeAll(userId)` when a user changes or resets their password, and when an account is deleted:

```ts
await Promise.all([
  Session.deleteMany({ userId: user.id }), // end the other sessions
  passkeys.removeAll(user.id),             // and every passkey with them
]);
```

Here's why. Someone who knew the old password could have signed in and added their own passkey. Without `removeAll`, that passkey would keep working after the password change. The example does this in `PUT /auth/password`. After it, the user adds a passkey again from the app.

## Errors and status codes

Every error the router raises comes back as `{ "message": "…" }` with its status:

| Status | When | Message |
| --- | --- | --- |
| `401` | `login/verify` failed for any reason: an unknown passkey, a wrong signature, origin or user handle, a used or expired challenge, a deleted account | `signInFailed` |
| `403` | `canRegister` returned false | `registrationNotAllowed` |
| `404` | `DELETE` of a passkey that isn't the user's, or doesn't exist | `passkeyNotFound` |
| `409` | The user already has `maxPasskeysPerUser` passkeys | `tooManyPasskeys` |
| `422` | `register/verify` failed: a wrong signature or origin, or a used or expired challenge | `registrationFailed` |
| `422` | A verify body that isn't a passkey answer | `invalidRequest` |
| `429` | A rate limit was reached | `tooManyRequests` |

Your `authenticate` middleware answers for itself, usually with a 401. Errors that aren't a `PasskeyError` go on to your app's error handler: a body over 64 kB, malformed JSON, a database error.

`PasskeyError(status, message)` is exported, so your hooks can throw it too.

## Messages and translations

These are the defaults. Replace any of them with `messages`:

| Key | Default |
| --- | --- |
| `signInFailed` | We couldn't sign you in with this passkey. Please sign in with your password. |
| `registrationFailed` | We couldn't add this passkey. Please try again. |
| `tooManyPasskeys` | You've reached the maximum number of passkeys. Delete one to add another. |
| `passkeyNotFound` | This passkey doesn't exist. |
| `registrationNotAllowed` | This account can't add passkeys. |
| `invalidRequest` | The request is not valid. |
| `tooManyRequests` | Too many attempts. Please try again in a moment. |

```ts
createPasskeys({
  // ...
  messages: {
    signInFailed: "Ce passkey ne fonctionne pas. Connectez-vous avec votre mot de passe.",
  },
});
```

The messages are fixed for each router. If your app speaks several languages, translate on the client by status code instead: the Flutter package gives you `PasskeyException.statusCode`.

## Rate limits

`login/options` and `login/verify` are public, so the router limits them per IP with [express-rate-limit](https://github.com/express-rate-limit/express-rate-limit):

- **`login/options`**: 30 calls a minute. Each call writes a challenge to MongoDB.
- **`login/verify`**: 10 **failed** calls in 15 minutes. Successful sign-ins don't count, so guessing stops but normal use passes.

Two things to know before production:

- **Behind a proxy or load balancer** (Nginx, Cloudflare, Render, Fly.io, Vercel…), set Express's `trust proxy` so `req.ip` is the user's IP and not the proxy's. Otherwise all your users share one limit: `app.set("trust proxy", 1)` for one proxy hop.
- **The counts live in memory**, per instance. With several instances, each one counts on its own. If that matters, pass `rateLimit: false` and put a limiter with a shared store (Redis or MongoDB) in front of the router.

## The service, without the router

`createPasskeys` also returns `service`, the same logic with no HTTP in it. You can also build it alone with `createPasskeyService({ config, users, messages, log })`. Use it from your own routes, jobs or admin tools:

| Method | What it does |
| --- | --- |
| `registrationOptions(user)` | Options for a new passkey, with the challenge saved |
| `verifyRegistration(user, { response, name })` | Checks the phone's answer and saves the passkey |
| `authenticationOptions()` | Options for a sign-in, with the challenge saved |
| `verifyAuthentication({ response })` | Checks a sign-in and returns the user |
| `list(userId)` | The user's passkeys, the newest first |
| `remove(userId, passkeyId)` | Deletes one, or throws a 404 `PasskeyError` |
| `removeAll(userId)` | Deletes every passkey of the user |

```ts
// An admin page listing a user's passkeys.
adminRouter.get("/users/:id/passkeys", async (req, res) => {
  res.json(await passkeys.service.list(req.params.id));
});
```

## Models and indexes

| Model | Collection | Indexes |
| --- | --- | --- |
| `Passkey` | `passkeys` | `_id` (the credential id), `userId` |
| `PasskeyChallenge` | `passkey_challenges` | `_id` (the challenge), a TTL index on `expiresAt` |

Mongoose builds these indexes when the app starts, unless you turned `autoIndex` off. If you did, build them once yourself. **The TTL index is what deletes old challenges.**

```ts
await Promise.all([Passkey.syncIndexes(), PasskeyChallenge.syncIndexes()]);
```

MongoDB's TTL sweep runs about once a minute, so an expired challenge can linger briefly. It still can't be used: taking a challenge checks `expiresAt` as well.

## The `.well-known` files

`createWellKnownRouter({ iosAppIds, androidApps })` serves `/.well-known/apple-app-site-association` and `/.well-known/assetlinks.json`, cached for an hour. `wellKnownFiles(...)` builds the same two objects for you to merge into files you already serve. [Domain setup](domain-setup.md#4-serve-the-files) shows both.

## JavaScript, CommonJS and Express 4

- **JavaScript projects:** run `npm run build` in `server/` and copy `dist/src/` instead of `src/`. It's plain JavaScript (ES modules) with `.d.ts` types next to it.
- **CommonJS projects:** Node.js 22.12 and newer can `require()` ES modules, so `require("./passkeys/index.js")` works.
- **Express 4:** not supported as it is. The router's handlers are `async` and rely on Express 5 passing rejected promises to the error handler. Express 4 doesn't do that. The [Express 5 migration guide](https://expressjs.com/en/guide/migrating-5.html) covers the upgrade.

## The example server

[`server/example/`](../server/example) is a whole API: accounts with a password, random-token sessions, the passkey router, and the `.well-known` files. The Flutter example talks to it.

```bash
cd server
cp .env.example .env
npm install
npm run dev          # watches and restarts: tsx watch
npm run build        # compiles src and example to dist/
npm start            # runs dist/example/server.js
npm run typecheck
npm test             # see docs/testing.md
```

| Variable | Default | What it is |
| --- | --- | --- |
| `RP_ID` | required | The domain the passkeys belong to |
| `RP_NAME` | `Passkeys Kit` | The name shown next to the passkey |
| `PORT` | `3000` | |
| `MONGODB_URI` | `mongodb://127.0.0.1:27017/passkeys_kit` | |
| `IOS_APP_IDS` | none | `TEAMID.bundle.id` of each iOS app, comma separated |
| `ANDROID_PACKAGE` | none | The Android application id |
| `ANDROID_SHA256` | none | The SHA-256 of each Android signing key, comma separated |

| Route | Body | Answer |
| --- | --- | --- |
| `POST /auth/register` | `{ name, email, password }` | `201 { token, user }` |
| `POST /auth/login` | `{ email, password }` | `{ token, user }` |
| `GET /auth/me` | | the user |
| `POST /auth/logout` | | `204` |
| `PUT /auth/password` | `{ currentPassword, newPassword }` | `{ token, user }`. Ends every other session and deletes every passkey. |
| `/auth/passkeys/…` | | [the kit's routes](#routes) |
| `GET /.well-known/…` | | [the two files](#the-well-known-files) |

Signed-in routes take `Authorization: Bearer <token>`.
