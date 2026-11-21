import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import express from "express";
import { createWellKnownRouter, wellKnownFiles } from "../src/index.js";
import { DEBUG_SHA256, RELEASE_SHA256, serve } from "./helpers.js";

const options = {
  iosAppIds: ["ABCDE12345.com.example.app", "ABCDE12345.com.example.app.beta"],
  androidApps: [
    {
      packageName: "com.example.app",
      sha256CertFingerprints: [RELEASE_SHA256, DEBUG_SHA256],
      appLinks: true,
    },
    { packageName: "com.example.app.beta", sha256CertFingerprints: [DEBUG_SHA256] },
  ],
};

describe("wellKnownFiles", () => {
  it("lists every iOS app under webcredentials", () => {
    assert.deepEqual(wellKnownFiles(options).appleAppSiteAssociation, {
      webcredentials: { apps: ["ABCDE12345.com.example.app", "ABCDE12345.com.example.app.beta"] },
    });
  });

  it("gives every Android app get_login_creds, and app links only when asked", () => {
    const [main, beta] = wellKnownFiles(options).assetLinks;
    assert.deepEqual(main?.relation, [
      "delegate_permission/common.handle_all_urls",
      "delegate_permission/common.get_login_creds",
    ]);
    assert.deepEqual(beta?.relation, ["delegate_permission/common.get_login_creds"]);
    assert.deepEqual(main?.target, {
      namespace: "android_app",
      package_name: "com.example.app",
      sha256_cert_fingerprints: [RELEASE_SHA256, DEBUG_SHA256],
    });
  });
});

describe("createWellKnownRouter", () => {
  let call: Awaited<ReturnType<typeof serve>>["call"];
  let close: () => Promise<void>;

  before(async () => {
    const app = express();
    app.use(createWellKnownRouter(options));
    ({ call, close } = await serve(app));
  });

  after(() => close());

  it("serves both files as JSON, cached for an hour, with no redirect", async () => {
    for (const path of ["/.well-known/apple-app-site-association", "/.well-known/assetlinks.json"]) {
      const { status, headers } = await call("GET", path);
      assert.equal(status, 200, path);
      assert.match(headers.get("content-type")!, /^application\/json/);
      assert.equal(headers.get("cache-control"), "public, max-age=3600");
    }
  });
});
