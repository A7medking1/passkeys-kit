# Domain setup

Passkeys belong to a domain, the **RP ID**. Before a phone lets your app use that domain's passkeys, the domain has to name the app in two files, and the app has to name the domain. This guide sets up both sides and shows how to check them.

- [1. Choose the RP ID](#1-choose-the-rp-id)
- [2. iOS](#2-ios)
- [3. Android](#3-android)
- [4. Serve the files](#4-serve-the-files)
- [5. Check it](#5-check-it)
- [Changing things later](#changing-things-later)

## 1. Choose the RP ID

The RP ID is a domain you control, written with no scheme and no port, like `example.com`.

- **It must serve the two files itself**, at `https://<RP ID>/.well-known/…`, over HTTPS, with no redirect. If `example.com` redirects to `www.example.com`, use `www.example.com`, or serve the files without the redirect.
- **It's permanent.** A passkey made for `example.com` never works for any other domain. Pick the domain you'll keep: usually your main website's.
- **It doesn't have to be where your API runs.** The example API runs on `localhost:3000` during development, while its RP ID is a real domain that serves the files.
- **If you'll add web sign-in later**, a website on `app.example.com` may use the RP ID `example.com`. Add its origin with `passkeyOrigins({ rpID, extra: ["https://app.example.com"] })`.

## 2. iOS

### The app's identity

An iOS app is named by its **App ID**: your Team ID and bundle id, as `TEAMID.bundle.id`. For example, `ABCDE12345.com.example.app`. The Team ID is on the Membership page of your Apple Developer account, and in Xcode under Signing & Capabilities.

> [!NOTE]
> The Associated Domains capability needs a team in the paid Apple Developer Program. A free personal team can't sign it.

### The domain names the app: `apple-app-site-association`

```json
{
  "webcredentials": {
    "apps": ["ABCDE12345.com.example.app"]
  }
}
```

If the file already exists for universal links, add `webcredentials` next to `applinks`. Every app listed shares the RP ID's passkeys.

### The app names the domain: the entitlement

In Xcode, open the Runner target, go to **Signing & Capabilities**, add **Associated Domains**, and add `webcredentials:example.com`. That writes `ios/Runner/Runner.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>webcredentials:example.com</string>
</array>
```

The example app reads all three values from `ios/Flutter/Local.xcconfig`, a git-ignored file you copy from `Local.xcconfig.example`:

```text
PASSKEYS_BUNDLE_ID = com.example.app
PASSKEYS_TEAM_ID = ABCDE12345
PASSKEYS_RP_ID = example.com
```

The project uses them for the bundle id and the team, and its entitlement is `webcredentials:$(PASSKEYS_RP_ID)`. That way your own ids never end up in git.

### Apple's CDN

iPhones don't download the file from your domain. They ask Apple's CDN, which fetches and caches it. After you change the file, check what the CDN serves:

```bash
curl -s https://app-site-association.cdn-apple.com/a/v1/example.com
```

During development you can skip the CDN with `webcredentials:example.com?mode=developer` in the entitlement. On a real device, this also needs **Settings → Developer → Associated Domains Development** turned on. Remove `?mode=developer` before you ship.

## 3. Android

### The app's identity

An Android app is named by its package name (the `applicationId`, like `com.example.app`) and the **SHA-256 fingerprint of every key that signs it**:

| Key | Where to find its SHA-256 |
| --- | --- |
| Debug | `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`, or `./gradlew signingReport` in `android/` |
| Upload (your release keystore) | `keytool -list -v -keystore <your keystore> -alias <your alias>` |
| Play App Signing | If Google Play signs your app, users install Google's signature, not yours. Copy the **App signing key certificate** fingerprint from **App integrity** in the Play Console. |

Fingerprints look like `F7:74:7B:3A:…:75:C9`: 32 bytes in hex, separated by colons. The kit takes them with or without the colons.

### The domain names the app: `assetlinks.json`

```json
[
  {
    "relation": ["delegate_permission/common.get_login_creds"],
    "target": {
      "namespace": "android_app",
      "package_name": "com.example.app",
      "sha256_cert_fingerprints": [
        "F7:74:7B:3A:F3:C1:1B:62:F4:CF:48:48:54:3F:0A:CA:E5:DE:4E:85:AA:41:A5:D9:B6:30:FF:77:65:52:75:C9",
        "6E:83:48:6C:56:1A:5F:92:3A:4F:73:99:B6:37:60:50:C9:E7:73:43:36:D7:C4:87:AF:F1:3E:AE:B3:9D:E0:4A"
      ]
    }
  }
]
```

`delegate_permission/common.get_login_creds` is the relation that shares sign-in credentials with the app. If you use App Links too, the same entry can also carry `delegate_permission/common.handle_all_urls`. The kit adds it when you pass `appLinks: true`.

The app itself needs nothing extra for passkeys: Credential Manager reads its signing key.

### The server accepts the app: origins

Android signs each request with an origin made from the signing key: `android:apk-key-hash:` followed by the key's SHA-256 in base64url. The server refuses origins it doesn't know, so give it the **same fingerprints**:

```ts
origins: passkeyOrigins({
  rpID: "example.com",
  androidSha256: process.env.ANDROID_SHA256!.split(","),
}),
```

Read both lists from one place, like the example's `ANDROID_SHA256` variable, and a key you add for `assetlinks.json` works for passkeys too.

### The phone

Passkeys on Android need Android 9 (API 28) or newer, Google Play services, a Google account, and a screen lock. For an emulator, pick a system image **with Google Play**, sign in to a Google account, and set a PIN.

## 4. Serve the files

Pick whichever fits how your domain is hosted.

**A. The kit serves them.** If your API runs on the RP ID's domain, mount the router at the root, not under a path:

```ts
import { createWellKnownRouter } from "./passkeys/index.js";

app.use(
  createWellKnownRouter({
    iosAppIds: ["ABCDE12345.com.example.app"],
    androidApps: [
      {
        packageName: "com.example.app",
        sha256CertFingerprints: ["F7:74:7B:3A:…:75:C9", "6E:83:48:6C:…:E0:4A"],
      },
    ],
  }),
);
```

**B. You already serve these files** for universal links or App Links. Build the passkey parts with `wellKnownFiles()` and merge them into yours:

```ts
import { wellKnownFiles } from "./passkeys/index.js";

const { appleAppSiteAssociation, assetLinks } = wellKnownFiles({ iosAppIds, androidApps });
// appleAppSiteAssociation is { webcredentials: { apps: [...] } }
// assetLinks is the array of statements for assetlinks.json
```

**C. A static host** for the domain, like the site's own hosting or a CDN. Put both files under `/.well-known/`.

Whichever you pick, the files must be:

- served over **HTTPS** with a valid certificate;
- answered with **200 and no redirect**;
- **JSON**, ideally as `application/json`. The Apple file has no `.json` extension;
- **public**, because Apple's CDN and Google fetch them.

## 5. Check it

```bash
# Your domain
curl -i https://example.com/.well-known/apple-app-site-association
curl -i https://example.com/.well-known/assetlinks.json

# What iPhones get, from Apple's CDN
curl -s https://app-site-association.cdn-apple.com/a/v1/example.com

# What Google reads for your domain
curl -s "https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://example.com&relation=delegate_permission/common.get_login_creds"
```

On the server side, the example prints the RP ID and every origin it accepts when it starts:

```text
Passkeys Kit example on http://localhost:3000
  RP ID    example.com
  Origins  https://example.com
           android:apk-key-hash:93R7OvPBG2L0z0hIVD8KyuXeToWqQaXZtjD_d2VSdck
  Database passkeys_kit
```

If the app still can't use the passkeys, [Troubleshooting](troubleshooting.md) lists the usual causes.

## Changing things later

- **A new Android signing key** (a new upload key, or Play App Signing): add its fingerprint to `assetlinks.json` and to the server's origins. Keep the old one until no installed build is signed with it.
- **Another iOS app or bundle id**: add it to `webcredentials.apps`. It shares the passkeys of every app already listed.
- **A different domain**: passkeys can't move. Keep the old RP ID for the passkeys users already have, or let users sign in another way and add new passkeys on the new RP ID.
