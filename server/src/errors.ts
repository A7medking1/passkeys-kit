/** An error the passkey router answers with its own status and message. */
export class PasskeyError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "PasskeyError";
  }
}

/** Every message the router sends, so you can translate them. */
export interface PasskeyMessages {
  /**
   * An unknown passkey, a wrong signature, a used or expired challenge, or an
   * account that may not sign in: one message for all of them, so nobody can
   * learn which passkeys exist.
   */
  signInFailed: string;
  /** The phone's new passkey didn't verify, or its challenge expired. */
  registrationFailed: string;
  /** The account already has `maxPasskeysPerUser` passkeys. */
  tooManyPasskeys: string;
  /** Deleting a passkey that isn't the user's (or doesn't exist). */
  passkeyNotFound: string;
  /** `canRegister` returned false for this account. */
  registrationNotAllowed: string;
  /** A body that isn't a passkey answer. */
  invalidRequest: string;
  /** The rate limit was reached. */
  tooManyRequests: string;
}

export const defaultMessages: PasskeyMessages = {
  signInFailed:
    "We couldn't sign you in with this passkey. Please sign in with your password.",
  registrationFailed: "We couldn't add this passkey. Please try again.",
  tooManyPasskeys:
    "You've reached the maximum number of passkeys. Delete one to add another.",
  passkeyNotFound: "This passkey doesn't exist.",
  registrationNotAllowed: "This account can't add passkeys.",
  invalidRequest: "The request is not valid.",
  tooManyRequests: "Too many attempts. Please try again in a moment.",
};
