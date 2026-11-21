/**
 * Where your passkeys live and who may use them.
 *
 * The RP ID is the domain every passkey is bound to, for good: a passkey made
 * for `example.com` never works anywhere else. Use the domain that serves your
 * `.well-known` files (the one your app links already use, if any).
 */
export interface PasskeyConfig {
  /** The domain, with no scheme and no port, like `example.com`. */
  rpID: string;
  /** Your app's name. Some password managers show it next to the passkey. */
  rpName: string;
  /**
   * Where a sign-in may come from. iOS sends `https://<rpID>`, and Android
   * sends `android:apk-key-hash:<…>` for the key that signed the app. Build
   * the list with {@link passkeyOrigins}.
   */
  origins: string[];
  /** How long the phone has between the options and the verify. Default: 5 minutes. */
  challengeTtlMs?: number;
  /** How many passkeys one account may have. Default: 10. */
  maxPasskeysPerUser?: number;
}

export const DEFAULT_CHALLENGE_TTL_MS = 5 * 60 * 1000;
export const DEFAULT_MAX_PASSKEYS_PER_USER = 10;

/**
 * The origin an Android app signs in from: the SHA-256 of its signing
 * certificate in base64url, with no padding. `sha256` is the colon-separated
 * hex that `keytool` and the Play Console show (`04:71:AE:…`).
 */
export const androidOrigin = (sha256: string) => {
  const hex = sha256.replaceAll(":", "").trim();
  if (!/^[0-9a-fA-F]{64}$/.test(hex)) {
    throw new Error(`Not a SHA-256 certificate fingerprint: "${sha256}"`);
  }
  return `android:apk-key-hash:${Buffer.from(hex, "hex").toString("base64url")}`;
};

/**
 * Every origin your apps sign in from: `https://<rpID>` for iOS, and one per
 * Android signing key (debug, upload and Play App Signing). Pass the same
 * fingerprints you put in `assetlinks.json`, so a key added there works for
 * passkeys too.
 */
export const passkeyOrigins = ({
  rpID,
  androidSha256 = [],
  extra = [],
}: {
  rpID: string;
  androidSha256?: string[];
  /** Anything else, like a web origin if you also sign in on the web. */
  extra?: string[];
}) => [`https://${rpID}`, ...androidSha256.map(androidOrigin), ...extra];
