import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";
import { model, Schema } from "mongoose";

// The example's own accounts: a name, an email and a password, like most apps
// have before they add passkeys. Your app keeps its own user model.
const userSchema = new Schema(
  {
    name: { type: String, required: true, trim: true },
    email: { type: String, required: true, trim: true, lowercase: true, unique: true },
    passwordHash: { type: String, required: true, select: false },
  },
  { timestamps: true, collection: "users" },
);

userSchema.set("toJSON", {
  transform: (_doc, ret) => ({ id: String(ret._id), name: ret.name, email: ret.email }),
});

export const User = model("User", userSchema);
export type UserDocument = InstanceType<typeof User>;

// A session is a random token the app sends as `Authorization: Bearer <token>`.
const SESSION_DAYS = 30;

const sessionSchema = new Schema(
  {
    _id: { type: String, required: true },
    userId: { type: String, required: true, index: true },
    expiresAt: { type: Date, required: true },
  },
  { collection: "sessions" },
);
sessionSchema.index({ expiresAt: 1 }, { expireAfterSeconds: 0 });

export const Session = model("Session", sessionSchema);

const derive = (password: string, salt: Buffer, length: number) =>
  new Promise<Buffer>((resolve, reject) => {
    scrypt(password, salt, length, (err, key) => (err ? reject(err) : resolve(key)));
  });

export const hashPassword = async (password: string) => {
  const salt = randomBytes(16);
  const hash = await derive(password, salt, 64);
  return `scrypt$${salt.toString("base64url")}$${hash.toString("base64url")}`;
};

export const checkPassword = async (password: string, stored: string) => {
  const [, salt, hash] = stored.split("$");
  if (!salt || !hash) return false;
  const expected = Buffer.from(hash, "base64url");
  const actual = await derive(password, Buffer.from(salt, "base64url"), expected.length);
  return timingSafeEqual(actual, expected);
};

/** What every sign-in answers with: the password one and the passkey one. */
export const openSession = async (user: UserDocument) => {
  const token = randomBytes(32).toString("base64url");
  await Session.create({
    _id: token,
    userId: user.id,
    expiresAt: new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000),
  });
  return { token, user: user.toJSON() };
};

export const userForToken = async (token: string) => {
  const session = await Session.findOne({ _id: token, expiresAt: { $gt: new Date() } });
  return session ? User.findById(session.userId) : null;
};
