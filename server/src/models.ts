import { model, Schema } from "mongoose";

// One passkey a user made on a phone. The phone keeps the private key; the
// server keeps the public one to check the signature of every sign-in.
const passkeySchema = new Schema(
  {
    // The credential id the phone made (base64url).
    _id: { type: String, required: true },
    // Your user's id, as a string. It never changes for one account.
    userId: { type: String, required: true, index: true },
    publicKey: { type: Buffer, required: true },
    // How many times the phone signed. Synced passkeys (iCloud Keychain,
    // Google Password Manager) always send 0; it's only checked once it moves.
    counter: { type: Number, default: 0 },
    transports: { type: [String], default: undefined },
    // singleDevice, or multiDevice for a synced passkey.
    deviceType: { type: String, required: true },
    backedUp: { type: Boolean, required: true },
    // Which password manager made it (a UUID, all zeros when it won't say).
    aaguid: { type: String },
    // What the user sees in your app, like the phone's model.
    name: { type: String, required: true, trim: true },
    lastUsedAt: { type: Date },
  },
  { timestamps: true, collection: "passkeys" },
);

// Only what an app shows: never the public key or the counter.
passkeySchema.set("toJSON", {
  transform: (_doc, ret) => ({
    id: ret._id,
    name: ret.name,
    deviceType: ret.deviceType,
    backedUp: ret.backedUp,
    createdAt: ret.createdAt,
    lastUsedAt: ret.lastUsedAt ?? null,
  }),
});

export const Passkey = model("Passkey", passkeySchema);
export type PasskeyDocument = InstanceType<typeof Passkey>;

export const CHALLENGE_TYPES = ["registration", "authentication"] as const;
export type ChallengeType = (typeof CHALLENGE_TYPES)[number];

// A challenge handed out with the options. The phone signs it, and the verify
// takes it back once. It lives in MongoDB, not in memory, so it works with
// several server instances (serverless included).
const challengeSchema = new Schema(
  {
    _id: { type: String, required: true },
    type: { type: String, enum: CHALLENGE_TYPES, required: true },
    // Registration only: the account the new passkey is for.
    userId: { type: String },
    expiresAt: { type: Date, required: true },
  },
  { collection: "passkey_challenges" },
);

// MongoDB deletes it by itself once it expires (a TTL index). The sweep runs
// about once a minute, so taking a challenge checks expiresAt as well.
challengeSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const PasskeyChallenge = model("PasskeyChallenge", challengeSchema);
