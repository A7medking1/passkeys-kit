import assert from "node:assert/strict";
import { after, before, beforeEach, describe, it } from "node:test";
import express, { type RequestHandler } from "express";
import {
  androidOrigin,
  createPasskeys,
  Passkey,
  PasskeyChallenge,
  PasskeyError,
  passkeyOrigins,
  type PasskeyOptions,
} from "../src/index.js";
import {
  connectDatabase,
  DEBUG_ORIGIN,
  DEBUG_SHA256,
  disconnectDatabase,
  IOS_ORIGIN,
  RELEASE_ORIGIN,
  RELEASE_SHA256,
  RP_ID,
  serve,
} from "./helpers.js";
import { userHandleOf, VirtualPasskey } from "./virtual-authenticator.js";

type TestUser = {
  id: string;
  email: string;
  name: string;
  role: "customer" | "staff";
  blocked?: boolean;
};

const users = new Map<string, TestUser>();
let nextUser = 0;

const addUser = (extra: Partial<TestUser> = {}) => {
  nextUser += 1;
  const id = `user-${nextUser}`;
  const user: TestUser = { id, email: `${id}@example.com`, name: `User ${nextUser}`, role: "customer", ...extra };
  users.set(id, user);
  return user;
};

// The app's own auth. For a test, "Bearer <user id>" is enough.
const authenticate: RequestHandler = (req, res, next) => {
  const id = req.headers.authorization?.replace("Bearer ", "");
  const user = id ? users.get(id) : undefined;
  if (!user) {
    res.status(401).json({ message: "Sign in first." });
    return;
  }
  res.locals.user = user;
  next();
};

// Why SimpleWebAuthn refused, so a test can check the reason as well.
const refusals: string[] = [];

const makeApp = (overrides: Partial<PasskeyOptions<TestUser>> = {}) => {
  const app = express();
  const passkeys = createPasskeys<TestUser>({
    config: {
      rpID: RP_ID,
      rpName: "Example",
      origins: passkeyOrigins({ rpID: RP_ID, androidSha256: [RELEASE_SHA256, DEBUG_SHA256] }),
    },
    users: {
      id: (user) => user.id,
      name: (user) => user.email,
      displayName: (user) => user.name,
      findById: async (id) => users.get(id) ?? null,
    },
    authenticate,
    currentUser: (_req, res) => res.locals.user,
    signIn: (user) => {
      if (user.blocked) throw new PasskeyError(403, "This account is blocked.");
      return { token: `session-for-${user.id}`, userId: user.id };
    },
    canRegister: (user) => user.role === "customer",
    rateLimit: false,
    log: (message) => refusals.push(message),
    ...overrides,
  });
  app.use("/auth/passkeys", passkeys.router);
  return { app, passkeys };
};

const SIGN_IN_FAILED =
  "We couldn't sign you in with this passkey. Please sign in with your password.";
const REGISTRATION_FAILED = "We couldn't add this passkey. Please try again.";

let call: Awaited<ReturnType<typeof serve>>["call"];
let close: () => Promise<void>;
let removeAll: (userId: string) => Promise<void>;

before(async () => {
  await connectDatabase();
  const { app, passkeys } = makeApp();
  ({ call, close } = await serve(app));
  removeAll = passkeys.removeAll;
});

after(async () => {
  await close();
  await disconnectDatabase();
});

beforeEach(() => {
  refusals.length = 0;
});

const registerOptions = (user: TestUser) =>
  call("POST", "/auth/passkeys/register/options", { token: user.id, body: {} });

const registerVerify = (user: TestUser, response: unknown, name?: string) =>
  call("POST", "/auth/passkeys/register/verify", {
    token: user.id,
    body: { response, ...(name && { name }) },
  });

const loginOptions = () => call("POST", "/auth/passkeys/login/options", { body: {} });

const loginVerify = (response: unknown) =>
  call("POST", "/auth/passkeys/login/verify", { body: { response } });

/** A passkey made the whole way, like an app does it. */
const addPasskey = async (user: TestUser, origin = IOS_ORIGIN) => {
  const passkey = new VirtualPasskey(RP_ID, origin);
  const options = (await registerOptions(user)).json;
  const saved = await registerVerify(user, passkey.register(options), "iPhone 17 Pro");
  assert.equal(saved.status, 201);
  return passkey;
};

const signIn = async (passkey: VirtualPasskey, userId: string, origin?: string) => {
  const options = (await loginOptions()).json;
  return loginVerify(passkey.signIn(options, userHandleOf(userId), origin));
};

describe("origins", () => {
  it("are the iOS domain and one per Android signing key", () => {
    assert.deepEqual(
      passkeyOrigins({ rpID: RP_ID, androidSha256: [RELEASE_SHA256, DEBUG_SHA256] }),
      [IOS_ORIGIN, RELEASE_ORIGIN, DEBUG_ORIGIN],
    );
  });

  it("take the fingerprint with or without colons, and refuse anything else", () => {
    assert.equal(androidOrigin(RELEASE_SHA256.replaceAll(":", "").toLowerCase()), RELEASE_ORIGIN);
    assert.throws(() => androidOrigin("AB:CD"), /Not a SHA-256/);
  });
});

describe("adding a passkey", () => {
  it("register/options: for the user's name, and the challenge is saved", async () => {
    const ahmed = addUser({ name: "Ahmed Nasr", email: "ahmed.nasr@example.com" });
    const { status, json } = await registerOptions(ahmed);

    assert.equal(status, 200);
    assert.deepEqual(json.rp, { name: "Example", id: RP_ID });
    assert.equal(json.user.name, "ahmed.nasr@example.com");
    assert.equal(json.user.displayName, "Ahmed Nasr");
    assert.equal(json.user.id, userHandleOf(ahmed.id));
    assert.deepEqual(json.excludeCredentials, []);
    assert.deepEqual(json.authenticatorSelection, {
      residentKey: "required",
      requireResidentKey: true,
      userVerification: "required",
      authenticatorAttachment: "platform",
    });

    const saved = await PasskeyChallenge.findById(json.challenge);
    assert.equal(saved?.type, "registration");
    assert.equal(saved?.userId, ahmed.id);
    const minutes = (saved!.expiresAt.getTime() - Date.now()) / 60_000;
    assert.ok(minutes > 4 && minutes <= 5);
  });

  it("register/verify saves it, and the answer never has the public key", async () => {
    const ahmed = addUser();
    const passkey = new VirtualPasskey(RP_ID, IOS_ORIGIN);
    const options = (await registerOptions(ahmed)).json;
    const { status, json } = await registerVerify(ahmed, passkey.register(options), "iPhone 17 Pro");

    assert.equal(status, 201);
    assert.deepEqual(Object.keys(json).sort(), [
      "backedUp",
      "createdAt",
      "deviceType",
      "id",
      "lastUsedAt",
      "name",
    ]);
    assert.equal(json.id, passkey.id);
    assert.equal(json.name, "iPhone 17 Pro");
    assert.equal(json.lastUsedAt, null);

    const saved = await Passkey.findById(passkey.id);
    assert.equal(saved?.userId, ahmed.id);
    assert.ok(saved?.publicKey.length);
    // Taken, so it can't make a second one.
    assert.equal(await PasskeyChallenge.findById(options.challenge), null);
  });

  it('without a name, it is saved as "Passkey"', async () => {
    const ahmed = addUser();
    const options = (await registerOptions(ahmed)).json;
    const { json } = await registerVerify(ahmed, new VirtualPasskey(RP_ID, IOS_ORIGIN).register(options));
    assert.equal(json.name, "Passkey");
  });

  it("the next options exclude the user's passkeys", async () => {
    const ahmed = addUser();
    const first = await addPasskey(ahmed);
    const second = await addPasskey(ahmed);
    const { json } = await registerOptions(ahmed);
    const excluded = json.excludeCredentials.map((credential: { id: string }) => credential.id);
    assert.deepEqual(excluded.sort(), [first.id, second.id].sort());
  });

  it("refuses a challenge that is used, unknown, expired or another user's", async () => {
    const nour = addUser();
    // The same answer twice: the second finds its challenge taken.
    const answer = new VirtualPasskey(RP_ID, IOS_ORIGIN).register((await registerOptions(nour)).json);
    assert.equal((await registerVerify(nour, answer)).status, 201);
    const used = await registerVerify(nour, answer);
    assert.equal(used.status, 422);
    assert.equal(used.json.message, REGISTRATION_FAILED);
    assert.match(refusals.at(-1)!, /challenge verifier returned false/);

    const unknown = await registerVerify(
      nour,
      new VirtualPasskey(RP_ID, IOS_ORIGIN).register({ challenge: "bm90LWEtY2hhbGxlbmdl" }),
    );
    assert.equal(unknown.status, 422);

    // Expired, though still in the database until MongoDB sweeps it.
    await PasskeyChallenge.create({
      _id: "ZXhwaXJlZA",
      type: "registration",
      userId: nour.id,
      expiresAt: new Date(Date.now() - 1000),
    });
    const expired = await registerVerify(
      nour,
      new VirtualPasskey(RP_ID, IOS_ORIGIN).register({ challenge: "ZXhwaXJlZA" }),
    );
    assert.equal(expired.status, 422);

    // Ahmed's challenge makes nothing for Nour, and stays Ahmed's.
    const ahmed = addUser();
    const ahmeds = (await registerOptions(ahmed)).json;
    const stolen = await registerVerify(nour, new VirtualPasskey(RP_ID, IOS_ORIGIN).register(ahmeds));
    assert.equal(stolen.status, 422);
    assert.ok(await PasskeyChallenge.findById(ahmeds.challenge));
  });

  it("refuses an origin that isn't yours, and takes your Android signing keys", async () => {
    const nour = addUser();
    const options = (await registerOptions(nour)).json;
    const wrong = await registerVerify(
      nour,
      new VirtualPasskey(RP_ID, "https://evil.example").register(options),
    );
    assert.equal(wrong.status, 422);
    assert.match(refusals.at(-1)!, /Unexpected response origin "https:\/\/evil.example"/);

    const release = await addPasskey(nour, RELEASE_ORIGIN);
    const debug = await addPasskey(nour, DEBUG_ORIGIN);
    assert.equal(await Passkey.countDocuments({ _id: { $in: [release.id, debug.id] } }), 2);
  });

  it("asks your app who may add passkeys (canRegister)", async () => {
    const staff = addUser({ role: "staff" });
    const { status, json } = await registerOptions(staff);
    assert.equal(status, 403);
    assert.equal(json.message, "This account can't add passkeys.");
  });

  it("leaves the auth to your middleware", async () => {
    const { status, json } = await call("POST", "/auth/passkeys/register/options", { body: {} });
    assert.equal(status, 401);
    assert.equal(json.message, "Sign in first.");
  });

  it("stops at maxPasskeysPerUser (10 by default)", async () => {
    const full = addUser();
    await Passkey.insertMany(
      Array.from({ length: 10 }, (_, i) => ({
        _id: `${full.id}-${i}`,
        userId: full.id,
        publicKey: Buffer.from([i]),
        deviceType: "multiDevice",
        backedUp: true,
        name: "iPhone",
      })),
    );
    const options = await registerOptions(full);
    assert.equal(options.status, 409);

    // Even with a challenge from before the 10th passkey.
    await PasskeyChallenge.create({
      _id: "YmVmb3JlLWZ1bGw",
      type: "registration",
      userId: full.id,
      expiresAt: new Date(Date.now() + 60_000),
    });
    const verify = await registerVerify(
      full,
      new VirtualPasskey(RP_ID, IOS_ORIGIN).register({ challenge: "YmVmb3JlLWZ1bGw" }),
    );
    assert.equal(verify.status, 409);
  });

  it("refuses a body that isn't a passkey answer", async () => {
    const ahmed = addUser();
    const { status, json } = await registerVerify(ahmed, { id: "x" });
    assert.equal(status, 422);
    assert.equal(json.message, "The request is not valid.");
  });
});

describe("signing in with a passkey", () => {
  let ahmed: TestUser;
  let passkey: VirtualPasskey;

  before(async () => {
    ahmed = addUser();
    passkey = await addPasskey(ahmed);
  });

  it("login/options: no username, and the challenge is saved", async () => {
    const { status, json } = await loginOptions();
    assert.equal(status, 200);
    assert.equal(json.rpId, RP_ID);
    assert.deepEqual(json.allowCredentials, []);
    assert.equal(json.userVerification, "required");

    const saved = await PasskeyChallenge.findById(json.challenge);
    assert.equal(saved?.type, "authentication");
    assert.equal(saved?.userId, undefined);
  });

  it("answers with your signIn hook, and records the use", async () => {
    const startedAt = Date.now();
    const { status, json } = await signIn(passkey, ahmed.id);

    assert.equal(status, 200);
    assert.deepEqual(json, { token: `session-for-${ahmed.id}`, userId: ahmed.id });
    const saved = await Passkey.findById(passkey.id);
    assert.equal(saved?.counter, 1);
    assert.ok(saved!.lastUsedAt!.getTime() >= startedAt);
  });

  it("gives one 401 for a used challenge, an unknown passkey, a wrong key, origin or user", async () => {
    const answer = passkey.signIn((await loginOptions()).json, userHandleOf(ahmed.id));
    assert.equal((await loginVerify(answer)).status, 200);

    const forgedKey = new VirtualPasskey(RP_ID, IOS_ORIGIN);
    // Ahead of the real one, so the signature itself is what fails.
    forgedKey.counter = 100;
    const forged = forgedKey.signIn((await loginOptions()).json, userHandleOf(ahmed.id));

    const failures = [
      // The same answer again: its challenge is taken.
      await loginVerify(answer),
      // A passkey the server never saw.
      await signIn(new VirtualPasskey(RP_ID, IOS_ORIGIN), ahmed.id),
      // Ahmed's passkey id, signed by another key.
      await loginVerify({ ...forged, id: passkey.id, rawId: passkey.id }),
      // Ahmed's passkey, from an app signed with a key you didn't list.
      await signIn(passkey, ahmed.id, "android:apk-key-hash:bm90LW91ci1rZXk"),
      // Ahmed's passkey, claiming to be someone else's.
      await signIn(passkey, "someone-else"),
    ];
    for (const { status, json } of failures) {
      assert.equal(status, 401);
      assert.equal(json.message, SIGN_IN_FAILED);
    }
    assert.equal(refusals.length, 2);
    assert.match(refusals[0]!, /challenge verifier returned false/);
    assert.match(refusals[1]!, /Unexpected response origin "android:apk-key-hash:bm90LW91ci1rZXk"/);
  });

  it("is refused once the account is gone", async () => {
    const gone = addUser();
    const key = await addPasskey(gone);
    users.delete(gone.id);
    const { status } = await signIn(key, gone.id);
    assert.equal(status, 401);
  });

  it("passes on your signIn hook's refusal (a blocked account)", async () => {
    const blocked = addUser();
    const key = await addPasskey(blocked);
    blocked.blocked = true;
    const { status, json } = await signIn(key, blocked.id);
    assert.equal(status, 403);
    assert.equal(json.message, "This account is blocked.");
  });
});

describe("the user's passkeys", () => {
  it("lists theirs only, newest first, without public keys", async () => {
    const ahmed = addUser();
    const nour = addUser();
    const first = await addPasskey(ahmed);
    const second = await addPasskey(ahmed);
    await addPasskey(nour);

    const { status, json } = await call("GET", "/auth/passkeys", { token: ahmed.id });
    assert.equal(status, 200);
    assert.deepEqual(
      json.map((passkey: { id: string }) => passkey.id),
      [second.id, first.id],
    );
    assert.equal(json[0].publicKey, undefined);
  });

  it("deletes the user's own, and someone else's is not found", async () => {
    const ahmed = addUser();
    const nour = addUser();
    const mine = await addPasskey(ahmed);
    const theirs = await addPasskey(nour);

    const other = await call("DELETE", `/auth/passkeys/${theirs.id}`, { token: ahmed.id });
    assert.equal(other.status, 404);
    assert.equal(other.json.message, "This passkey doesn't exist.");
    assert.ok(await Passkey.findById(theirs.id));

    const own = await call("DELETE", `/auth/passkeys/${mine.id}`, { token: ahmed.id });
    assert.equal(own.status, 204);
    assert.equal(await Passkey.findById(mine.id), null);
  });

  it("removeAll() deletes one user's passkeys, for a password change", async () => {
    const ahmed = addUser();
    const nour = addUser();
    await addPasskey(ahmed);
    await addPasskey(ahmed);
    await addPasskey(nour);

    await removeAll(ahmed.id);

    assert.equal(await Passkey.countDocuments({ userId: ahmed.id }), 0);
    assert.equal(await Passkey.countDocuments({ userId: nour.id }), 1);
  });
});

describe("options", () => {
  it("rate limits login/options and failed sign-ins", async () => {
    const { app } = makeApp({ rateLimit: { optionsPerMinute: 2, failedSignInsPer15Minutes: 1 } });
    const limited = await serve(app);
    try {
      await limited.call("POST", "/auth/passkeys/login/options", { body: {} });
      await limited.call("POST", "/auth/passkeys/login/options", { body: {} });
      const third = await limited.call("POST", "/auth/passkeys/login/options", { body: {} });
      assert.equal(third.status, 429);
      assert.equal(third.json.message, "Too many attempts. Please try again in a moment.");

      const bad = { response: { id: "x" } };
      assert.equal((await limited.call("POST", "/auth/passkeys/login/verify", { body: bad })).status, 422);
      assert.equal((await limited.call("POST", "/auth/passkeys/login/verify", { body: bad })).status, 429);
    } finally {
      await limited.close();
    }
  });

  it("takes your own messages and limits", async () => {
    const { app } = makeApp({
      config: {
        rpID: RP_ID,
        rpName: "Example",
        origins: [IOS_ORIGIN],
        maxPasskeysPerUser: 1,
      },
      messages: { tooManyPasskeys: "Une seule clé d'accès par compte." },
    });
    const custom = await serve(app);
    try {
      const lina = addUser();
      const options = (await custom.call("POST", "/auth/passkeys/register/options", { token: lina.id, body: {} })).json;
      const response = new VirtualPasskey(RP_ID, IOS_ORIGIN).register(options);
      const saved = await custom.call("POST", "/auth/passkeys/register/verify", { token: lina.id, body: { response } });
      assert.equal(saved.status, 201);

      const second = await custom.call("POST", "/auth/passkeys/register/options", { token: lina.id, body: {} });
      assert.equal(second.status, 409);
      assert.equal(second.json.message, "Une seule clé d'accès par compte.");
    } finally {
      await custom.close();
    }
  });
});
