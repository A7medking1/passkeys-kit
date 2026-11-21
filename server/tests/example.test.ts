import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { createApp } from "../example/app.js";
import { readEnv } from "../example/env.js";
import { Passkey } from "../src/index.js";
import {
  connectDatabase,
  DEBUG_SHA256,
  disconnectDatabase,
  IOS_ORIGIN,
  RELEASE_SHA256,
  RP_ID,
  serve,
} from "./helpers.js";
import { userHandleOf, VirtualPasskey } from "./virtual-authenticator.js";

const env = readEnv({
  RP_ID,
  RP_NAME: "Example",
  IOS_APP_IDS: "ABCDE12345.com.example.app",
  ANDROID_PACKAGE: "com.example.app",
  ANDROID_SHA256: `${RELEASE_SHA256},${DEBUG_SHA256}`,
});

let call: Awaited<ReturnType<typeof serve>>["call"];
let close: () => Promise<void>;

before(async () => {
  await connectDatabase();
  ({ call, close } = await serve(createApp(env)));
});

after(async () => {
  await close();
  await disconnectDatabase();
});

const signUp = async (email: string) => {
  const { status, json } = await call("POST", "/auth/register", {
    body: { name: "Ahmed Nasr", email, password: "correct horse" },
  });
  assert.equal(status, 201);
  return json as { token: string; user: { id: string; name: string; email: string } };
};

const addPasskey = async (token: string) => {
  const passkey = new VirtualPasskey(RP_ID, IOS_ORIGIN);
  const options = (await call("POST", "/auth/passkeys/register/options", { token, body: {} })).json;
  const saved = await call("POST", "/auth/passkeys/register/verify", {
    token,
    body: { response: passkey.register(options), name: "iPhone 17 Pro" },
  });
  assert.equal(saved.status, 201);
  return passkey;
};

describe("the example's accounts", () => {
  it("signs up and in with a password", async () => {
    const { token, user } = await signUp("ahmed.nasr@example.com");
    assert.deepEqual(user, { id: user.id, name: "Ahmed Nasr", email: "ahmed.nasr@example.com" });
    assert.equal((await call("GET", "/auth/me", { token })).json.email, "ahmed.nasr@example.com");

    const login = await call("POST", "/auth/login", {
      body: { email: "AHMED.NASR@example.com", password: "correct horse" },
    });
    assert.equal(login.status, 200);
    assert.ok(login.json.token);

    const wrong = await call("POST", "/auth/login", {
      body: { email: "ahmed.nasr@example.com", password: "wrong" },
    });
    assert.equal(wrong.status, 401);

    const again = await call("POST", "/auth/register", {
      body: { name: "Ahmed Nasr", email: "ahmed.nasr@example.com", password: "correct horse" },
    });
    assert.equal(again.status, 409);
  });
});

describe("passkeys in the example", () => {
  it("add a passkey, sign out, and sign back in with it, like the Flutter example", async () => {
    const { token, user } = await signUp("nour@example.com");
    const passkey = await addPasskey(token);
    assert.equal((await call("POST", "/auth/logout", { token })).status, 204);
    assert.equal((await call("GET", "/auth/me", { token })).status, 401);

    const options = (await call("POST", "/auth/passkeys/login/options", { body: {} })).json;
    const { status, json } = await call("POST", "/auth/passkeys/login/verify", {
      body: { response: passkey.signIn(options, userHandleOf(user.id)) },
    });

    assert.equal(status, 200);
    // The same answer as the password sign-in.
    assert.deepEqual(Object.keys(json).sort(), ["token", "user"]);
    assert.deepEqual(json.user, user);
    assert.equal((await call("GET", "/auth/me", { token: json.token })).json.id, user.id);
  });

  it("a password change ends the other sessions and deletes every passkey", async () => {
    const { token, user } = await signUp("lina@example.com");
    await addPasskey(token);
    await addPasskey(token);

    const { status, json } = await call("PUT", "/auth/password", {
      token,
      body: { currentPassword: "correct horse", newPassword: "battery staple" },
    });

    assert.equal(status, 200);
    assert.equal(await Passkey.countDocuments({ userId: user.id }), 0);
    assert.equal((await call("GET", "/auth/me", { token })).status, 401);
    assert.equal((await call("GET", "/auth/me", { token: json.token })).status, 200);
  });
});

describe("the example's .well-known files", () => {
  it("let the iOS and Android apps use the passkeys", async () => {
    const aasa = await call("GET", "/.well-known/apple-app-site-association");
    assert.deepEqual(aasa.json, { webcredentials: { apps: ["ABCDE12345.com.example.app"] } });

    const assetLinks = await call("GET", "/.well-known/assetlinks.json");
    assert.deepEqual(assetLinks.json, [
      {
        relation: ["delegate_permission/common.get_login_creds"],
        target: {
          namespace: "android_app",
          package_name: "com.example.app",
          sha256_cert_fingerprints: [RELEASE_SHA256, DEBUG_SHA256],
        },
      },
    ]);
  });
});
