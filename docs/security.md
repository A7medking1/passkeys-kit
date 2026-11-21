# Security

This page covers what the kit checks, the choices behind those checks, and what stays your job. To report a vulnerability, see [SECURITY.md](../SECURITY.md).

- [What every sign-in has to pass](#what-every-sign-in-has-to-pass)
- [Challenges](#challenges)
- [Nothing to learn from a failure](#nothing-to-learn-from-a-failure)
- [What the API gives out](#what-the-api-gives-out)
- [Rate limits and input](#rate-limits-and-input)
- [No attestation](#no-attestation)
- [Passwords, recovery, and removing passkeys](#passwords-recovery-and-removing-passkeys)
- [Your checklist](#your-checklist)

## What every sign-in has to pass

| Check | What it stops |
| --- | --- |
| The passkey exists on the server | Passkeys the server never saw, or deleted |
| The **user handle** the phone sends matches the account the passkey was made for | A passkey presented as someone else's |
| The **challenge** is one the server handed out, unused, and not expired | Replaying an old answer |
| The **origin** is in your list: `https://<RP ID>` or one of your Android signing keys | Other apps and sites, including phishing ones |
| The **RP ID hash** in the signed data is your RP ID's | Passkeys made for another domain |
| The **user verified** flag is set | A passkey used without Face ID, a fingerprint or the passcode |
| The **signature** checks out with the stored public key | Anyone without the private key |
| The **signature counter** went up, for authenticators that count | Some cloned authenticators. Synced passkeys always send 0, and SimpleWebAuthn skips the check then. |
| The account still exists (`users.findById`) | Signing in to a deleted account |
| Your **`signIn` hook** accepts it | Blocked accounts, or anything else you decide |

Registration has the same origin, RP ID, user verification and challenge checks. Its challenge is also tied to the account that asked for it.

The cryptography is [SimpleWebAuthn](https://simplewebauthn.dev)'s, a widely used WebAuthn library. The kit adds the challenge store, the owner check, the error policy and the routes around it.

## Challenges

- **Random.** SimpleWebAuthn makes each one from 32 random bytes.
- **Stored on the server**, in MongoDB, with their type (`registration` or `authentication`), the account for registrations, and an expiry (5 minutes by default).
- **Single use.** Verifying takes the challenge back with one `findOneAndDelete` filtered on the challenge, its type, its account and `expiresAt > now`. Two requests racing with the same answer can't both succeed, because only one of them gets the document.
- **Typed before the query.** The challenge comes from JSON the client wrote. If it isn't a plain string, it's refused before it reaches MongoDB, so an object like `{ "$ne": "" }` can't act as a query operator.
- **Cleaned up** by a TTL index once expired.

## Nothing to learn from a failure

Every failed `login/verify` gets the same `401` and the same message: an unknown passkey, a wrong signature, origin or user handle, a used or expired challenge, a deleted account. An attacker can't tell which passkeys or accounts exist. The real reason goes to the server's log only.

In the same way, deleting someone else's passkey gets the same `404` as deleting one that doesn't exist.

## What the API gives out

A passkey in a response is `id`, `name`, `deviceType`, `backedUp`, `createdAt` and `lastUsedAt`. Public keys, counters, AAGUIDs and user ids never leave the server.

The kit saves nothing about the person beyond your user's id and the passkey's name. Names and emails live in your own user model.

## Rate limits and input

- `login/options` is limited to 30 calls a minute per IP, since each call writes to the database.
- `login/verify` is limited to 10 **failed** calls in 15 minutes per IP. Successful sign-ins don't count.
- The register and list routes sit behind your `authenticate` middleware.
- The router reads bodies of 64 kB at most, and checks their shape with zod before SimpleWebAuthn reads them.

Behind a proxy, set Express's `trust proxy`, or every user shares the proxy's limit. See [Rate limits](server.md#rate-limits).

## No attestation

The kit asks for `attestation: "none"`, so it doesn't verify which authenticator model made a passkey. Synced passkeys in iCloud Keychain and Google Password Manager mostly don't provide attestation anyway, and consumer apps rarely need it. If you need to allow only certain authenticators, as some enterprise policies require, the kit isn't built for that.

## Passwords, recovery, and removing passkeys

- **Passkeys add a way in. They don't replace recovery.** While an account also has a password, the password and your reset flow are still targets. Protect them the way you already do.
- **Remove every passkey when the password changes.** Someone who knew the old password could have added their own passkey. Call `removeAll(userId)` when a password is changed or reset, and when an account is deleted. The example does it in `PUT /auth/password`, along with ending the other sessions.
- **Deleting a passkey works on the server only.** The phone keeps the private key, because apps can't delete from a password manager, but the server no longer accepts it.
- **Sessions are yours.** The kit hands the verified account to your `signIn` hook and never issues tokens itself. Keep them on HTTPS, and in secure storage on the phone.

## Your checklist

- [ ] Your API and the RP ID's domain use **HTTPS** in production.
- [ ] Express's **`trust proxy`** matches your hosting.
- [ ] The **origins** list only keys that sign builds you ship. Keep your debug key out of production if you can, with a separate RP ID or environment for development.
- [ ] **`removeAll`** runs on password changes, password resets and account deletion.
- [ ] The **refusal logs** go somewhere you read. They show unexpected origins and failures.
- [ ] **Session tokens** are stored securely on the phone, with `flutter_secure_storage` or the like.
