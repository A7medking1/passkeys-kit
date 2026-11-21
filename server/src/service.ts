import {
  generateAuthenticationOptions,
  generateRegistrationOptions,
  verifyAuthenticationResponse,
  verifyRegistrationResponse,
  type AuthenticationResponseJSON,
  type RegistrationResponseJSON,
} from "@simplewebauthn/server";
import { isoUint8Array } from "@simplewebauthn/server/helpers";
import {
  DEFAULT_CHALLENGE_TTL_MS,
  DEFAULT_MAX_PASSKEYS_PER_USER,
  type PasskeyConfig,
} from "./config.js";
import { defaultMessages, PasskeyError, type PasskeyMessages } from "./errors.js";
import {
  Passkey,
  PasskeyChallenge,
  type ChallengeType,
  type PasskeyDocument,
} from "./models.js";
import type { LoginVerifyInput, RegisterVerifyInput } from "./schemas.js";

/** How the kit reads your users. Your user model stays yours. */
export interface PasskeyUserAdapter<User> {
  /**
   * The user's id, as a string that never changes. Its UTF-8 bytes become the
   * passkey's user handle, so it must be 64 bytes at most (a MongoDB ObjectId
   * or a UUID is fine). Don't use an email or a phone number: they change.
   */
  id(user: User): string;
  /** Shown in the password manager to tell accounts apart: an email or a phone number. */
  name(user: User): string;
  /** Shown next to it: the person's name. */
  displayName(user: User): string;
  /** Loads the account a passkey belongs to, at sign-in. Null if it's gone. */
  findById(id: string): Promise<User | null>;
}

export interface PasskeyServiceOptions<User> {
  config: PasskeyConfig;
  users: PasskeyUserAdapter<User>;
  messages?: Partial<PasskeyMessages>;
  /** Where to log why a passkey was refused. Default: `console.warn`. */
  log?: (message: string) => void;
}

const DEFAULT_PASSKEY_NAME = "Passkey";
const MAX_USER_ID_BYTES = 64;

/**
 * The passkey logic with no HTTP in it: options, verification, and the list.
 * `createPasskeys()` puts a router in front of it; use this directly to call
 * it from your own routes or jobs.
 */
export const createPasskeyService = <User>({
  config,
  users,
  messages: overrides,
  log = (message) => console.warn(message),
}: PasskeyServiceOptions<User>) => {
  const messages = { ...defaultMessages, ...overrides };
  const challengeTtlMs = config.challengeTtlMs ?? DEFAULT_CHALLENGE_TTL_MS;
  const maxPasskeys = config.maxPasskeysPerUser ?? DEFAULT_MAX_PASSKEYS_PER_USER;

  // The user handle is the id's bytes, the same for every passkey of an
  // account, so a second passkey on the same phone replaces the first one.
  const userHandleOf = (userId: string) => {
    const bytes = isoUint8Array.fromUTF8String(userId);
    if (bytes.length > MAX_USER_ID_BYTES) {
      throw new Error(`User ids must be ${MAX_USER_ID_BYTES} bytes at most`);
    }
    return bytes;
  };

  // The phone sends the user handle back on every sign-in. It must be the
  // account the passkey was made for.
  const isOwner = (passkey: PasskeyDocument, userHandle?: string | null) =>
    !!userHandle &&
    Buffer.from(userHandle, "base64url").toString("utf8") === passkey.userId;

  const registrationFailed = () => new PasskeyError(422, messages.registrationFailed);
  const signInFailed = () => new PasskeyError(401, messages.signInFailed);
  const tooManyPasskeys = () => new PasskeyError(409, messages.tooManyPasskeys);

  // Why SimpleWebAuthn said no goes to your logs (like the real origin of an
  // app signed with a key you didn't list); the app only gets the message.
  const rejected =
    (step: string, failure: () => PasskeyError) =>
    (err: unknown): never => {
      log(`Passkey ${step} refused: ${err instanceof Error ? err.message : String(err)}`);
      throw failure();
    };

  const saveChallenge = (challenge: string, type: ChallengeType, userId?: string) =>
    PasskeyChallenge.create({
      _id: challenge,
      type,
      ...(userId && { userId }),
      expiresAt: new Date(Date.now() + challengeTtlMs),
    });

  /**
   * SimpleWebAuthn calls this with the challenge the phone signed. Taking it is
   * one `findOneAndDelete`, so it works once: a second try, or one after it
   * expired, finds nothing. A registration challenge only works for the
   * account it was made for.
   */
  const takeChallenge =
    (type: ChallengeType, userId?: string) => async (challenge: unknown) => {
      // It comes from the phone's JSON: an object here would be a query operator.
      if (typeof challenge !== "string") return false;
      const taken = await PasskeyChallenge.findOneAndDelete({
        _id: challenge,
        type,
        ...(userId && { userId }),
        expiresAt: { $gt: new Date() },
      });
      return taken !== null;
    };

  /** What the phone needs to make a passkey for this user. */
  const registrationOptions = async (user: User) => {
    const userId = users.id(user);
    const passkeys = await Passkey.find({ userId }).select("transports");
    if (passkeys.length >= maxPasskeys) throw tooManyPasskeys();

    const options = await generateRegistrationOptions({
      rpName: config.rpName,
      rpID: config.rpID,
      userName: users.name(user),
      userDisplayName: users.displayName(user),
      userID: userHandleOf(userId),
      attestationType: "none",
      // The user's passkeys: a phone that has one says so instead of making another.
      excludeCredentials: passkeys.map(({ id, transports }) => ({
        id,
        ...(transports && { transports }),
      })),
      authenticatorSelection: {
        // A discoverable passkey, so signing in needs no username.
        residentKey: "required",
        userVerification: "required",
        // The phone's own passkeys. Without it iOS also offers a USB security
        // key, which the sign-in never asks for.
        authenticatorAttachment: "platform",
      },
    });
    await saveChallenge(options.challenge, "registration", userId);
    return options;
  };

  /** Checks the phone's new passkey and saves it. */
  const verifyRegistration = async (user: User, { response, name }: RegisterVerifyInput) => {
    const userId = users.id(user);
    if ((await Passkey.countDocuments({ userId })) >= maxPasskeys) {
      throw tooManyPasskeys();
    }

    const verification = await verifyRegistrationResponse({
      response: response as RegistrationResponseJSON,
      expectedChallenge: takeChallenge("registration", userId),
      expectedOrigin: config.origins,
      expectedRPID: config.rpID,
      requireUserVerification: true,
    }).catch(rejected("registration", registrationFailed));
    if (!verification.verified) throw registrationFailed();

    const { credential, credentialDeviceType, credentialBackedUp, aaguid } =
      verification.registrationInfo;
    return Passkey.create({
      _id: credential.id,
      userId,
      publicKey: Buffer.from(credential.publicKey),
      counter: credential.counter,
      ...(credential.transports && { transports: credential.transports }),
      deviceType: credentialDeviceType,
      backedUp: credentialBackedUp,
      aaguid,
      name: name ?? DEFAULT_PASSKEY_NAME,
    });
  };

  /** A challenge any passkey of yours on the phone can sign: no username needed. */
  const authenticationOptions = async () => {
    const options = await generateAuthenticationOptions({
      rpID: config.rpID,
      // Empty on purpose: the phone offers every passkey it has for the RP ID.
      allowCredentials: [],
      userVerification: "required",
    });
    await saveChallenge(options.challenge, "authentication");
    return options;
  };

  /** Checks a sign-in and returns the account. Your `signIn` hook decides the rest. */
  const verifyAuthentication = async ({ response }: LoginVerifyInput) => {
    const passkey = await Passkey.findById(response.id);
    if (!passkey || !isOwner(passkey, response.response.userHandle)) {
      throw signInFailed();
    }

    const verification = await verifyAuthenticationResponse({
      response: response as AuthenticationResponseJSON,
      expectedChallenge: takeChallenge("authentication"),
      expectedOrigin: config.origins,
      expectedRPID: config.rpID,
      credential: {
        id: passkey.id,
        publicKey: new Uint8Array(passkey.publicKey),
        counter: passkey.counter,
      },
      requireUserVerification: true,
    }).catch(rejected("sign-in", signInFailed));
    if (!verification.verified) throw signInFailed();

    passkey.counter = verification.authenticationInfo.newCounter;
    passkey.lastUsedAt = new Date();
    await passkey.save();

    const user = await users.findById(passkey.userId);
    if (!user) throw signInFailed();
    return user;
  };

  /** The user's passkeys, the newest first. */
  const list = (userId: string) => Passkey.find({ userId }).sort({ createdAt: -1 });

  /** Deletes one of the user's passkeys. Someone else's is "not found" too. */
  const remove = async (userId: string, passkeyId: string) => {
    const deleted = await Passkey.findOneAndDelete({ _id: passkeyId, userId });
    if (!deleted) throw new PasskeyError(404, messages.passkeyNotFound);
  };

  /**
   * Deletes every passkey of a user. Call it when the password changes or the
   * account is deleted, like you end the other sessions: a passkey that
   * someone else added must not outlive the password they used.
   */
  const removeAll = async (userId: string) => {
    await Passkey.deleteMany({ userId });
  };

  return {
    messages,
    registrationOptions,
    verifyRegistration,
    authenticationOptions,
    verifyAuthentication,
    list,
    remove,
    removeAll,
    takeChallenge,
  };
};

export type PasskeyService<User> = ReturnType<typeof createPasskeyService<User>>;
