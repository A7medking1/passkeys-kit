import { createHash, generateKeyPairSync, randomBytes, sign } from "node:crypto";
import { isoBase64URL, isoCBOR } from "@simplewebauthn/server/helpers";

const sha256 = (data: Uint8Array | string) => createHash("sha256").update(data).digest();

// Flags in authenticatorData: the user was there, the user was verified (Face
// ID or a fingerprint), and a new credential is attached (registration only).
const USER_PRESENT = 0x01;
const USER_VERIFIED = 0x04;
const ATTESTED_DATA = 0x40;

/**
 * A passkey made inside the test: a real P-256 key that signs the way a phone
 * does. Nothing is mocked, SimpleWebAuthn checks these signatures for real.
 * What only a phone does (Face ID, iCloud Keychain, checking the domain's
 * `.well-known` files) is tried on the phones themselves.
 */
export class VirtualPasskey {
  readonly id = isoBase64URL.fromBuffer(randomBytes(16));
  private readonly keys = generateKeyPairSync("ec", { namedCurve: "P-256" });
  /** How many times it signed. SimpleWebAuthn checks it before the signature. */
  counter = 0;

  constructor(
    private readonly rpID: string,
    private readonly origin: string,
  ) {}

  /** The public key the way a phone hands it over: COSE, in CBOR. */
  publicKey() {
    const { x, y } = this.keys.publicKey.export({ format: "jwk" });
    return isoCBOR.encode(
      new Map<number, number | Uint8Array>([
        [1, 2], // kty: EC2
        [3, -7], // alg: ES256
        [-1, 1], // crv: P-256
        [-2, isoBase64URL.toBuffer(x!)],
        [-3, isoBase64URL.toBuffer(y!)],
      ]),
    );
  }

  private authenticatorData(flags: number, attested: Uint8Array[] = []) {
    const counter = Buffer.alloc(4);
    counter.writeUInt32BE(this.counter);
    return Buffer.concat([sha256(this.rpID), Buffer.from([flags]), counter, ...attested]);
  }

  private clientDataJSON(type: string, challenge: string, origin: string) {
    return Buffer.from(JSON.stringify({ type, challenge, origin, crossOrigin: false }));
  }

  /** What an app sends to `register/verify` once the phone made the passkey. */
  register({ challenge }: { challenge: string }, origin = this.origin) {
    const id = isoBase64URL.toBuffer(this.id);
    const idLength = Buffer.alloc(2);
    idLength.writeUInt16BE(id.length);
    const aaguid = Buffer.alloc(16);
    const authData = this.authenticatorData(USER_PRESENT | USER_VERIFIED | ATTESTED_DATA, [
      aaguid,
      idLength,
      id,
      this.publicKey(),
    ]);
    const attestationObject = isoCBOR.encode(
      new Map<string, unknown>([
        ["fmt", "none"],
        ["attStmt", new Map()],
        ["authData", authData],
      ]) as never,
    );
    return {
      id: this.id,
      rawId: this.id,
      type: "public-key",
      response: {
        clientDataJSON: isoBase64URL.fromBuffer(
          this.clientDataJSON("webauthn.create", challenge, origin),
        ),
        attestationObject: isoBase64URL.fromBuffer(attestationObject),
        transports: ["internal", "hybrid"],
      },
      clientExtensionResults: {},
    };
  }

  /** What an app sends to `login/verify`: the challenge, signed with the private key. */
  signIn({ challenge }: { challenge: string }, userHandle: string, origin = this.origin) {
    this.counter += 1;
    const authData = this.authenticatorData(USER_PRESENT | USER_VERIFIED);
    const clientDataJSON = this.clientDataJSON("webauthn.get", challenge, origin);
    const signature = sign(
      "sha256",
      Buffer.concat([authData, sha256(clientDataJSON)]),
      this.keys.privateKey,
    );
    return {
      id: this.id,
      rawId: this.id,
      type: "public-key",
      response: {
        clientDataJSON: isoBase64URL.fromBuffer(clientDataJSON),
        authenticatorData: isoBase64URL.fromBuffer(authData),
        signature: isoBase64URL.fromBuffer(signature),
        userHandle,
      },
      clientExtensionResults: {},
    };
  }
}

/** What a phone sends back as the user handle: the user id's UTF-8 bytes. */
export const userHandleOf = (userId: string) => Buffer.from(userId, "utf8").toString("base64url");
