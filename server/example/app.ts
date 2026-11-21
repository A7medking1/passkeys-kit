import express, {
  type ErrorRequestHandler,
  type RequestHandler,
  type Response,
} from "express";
import { z } from "zod";
import {
  createPasskeys,
  createWellKnownRouter,
  PasskeyError,
  passkeyOrigins,
} from "../src/index.js";
import type { Env } from "./env.js";
import {
  checkPassword,
  hashPassword,
  openSession,
  Session,
  User,
  userForToken,
  type UserDocument,
} from "./users.js";

/** An error the example answers with its status and message. */
class HttpError extends Error {
  constructor(
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

const signUpSchema = z.object({
  name: z.string().trim().min(1).max(100),
  email: z.email().trim().toLowerCase(),
  password: z.string().min(8).max(128),
});

const signInSchema = z.object({
  email: z.email().trim().toLowerCase(),
  password: z.string().min(1),
});

const passwordSchema = z.object({
  currentPassword: z.string().min(1),
  newPassword: z.string().min(8).max(128),
});

const parse = <T>(schema: z.ZodType<T>, body: unknown): T => {
  const result = schema.safeParse(body);
  if (!result.success) {
    const issue = result.error.issues[0];
    throw new HttpError(422, `Check the ${issue?.path.join(".") || "request"}.`);
  }
  return result.data;
};

// The signed-in user and their token, set by `authenticate`.
const userOf = (res: Response) => res.locals.user as UserDocument;

/** The example server: accounts with a password, and passkeys on top. */
export const createApp = (env: Env) => {
  const app = express();
  app.use(express.json());

  app.get("/", (_req, res) => {
    res.json({ name: "Passkeys Kit example", rpID: env.RP_ID });
  });

  // The files that tell iOS and Android your apps may use this domain's
  // passkeys. They must be on the RP ID's domain: if this server isn't, serve
  // them there instead.
  app.use(
    createWellKnownRouter({
      iosAppIds: env.IOS_APP_IDS,
      androidApps: env.ANDROID_PACKAGE
        ? [{ packageName: env.ANDROID_PACKAGE, sha256CertFingerprints: env.ANDROID_SHA256 }]
        : [],
    }),
  );

  const authenticate: RequestHandler = async (req, res, next) => {
    const header = req.headers.authorization;
    const token = header?.startsWith("Bearer ") ? header.slice("Bearer ".length) : undefined;
    const user = token ? await userForToken(token) : null;
    if (!user) throw new HttpError(401, "Please sign in first.");
    res.locals.user = user;
    res.locals.token = token;
    next();
  };

  app.post("/auth/register", async (req, res) => {
    const { name, email, password } = parse(signUpSchema, req.body);
    if (await User.exists({ email })) {
      throw new HttpError(409, "This email already has an account.");
    }
    const user = await User.create({ name, email, passwordHash: await hashPassword(password) });
    res.status(201).json(await openSession(user));
  });

  app.post("/auth/login", async (req, res) => {
    const { email, password } = parse(signInSchema, req.body);
    const user = await User.findOne({ email }).select("+passwordHash");
    if (!user || !(await checkPassword(password, user.passwordHash))) {
      throw new HttpError(401, "The email or the password is wrong.");
    }
    res.json(await openSession(user));
  });

  app.get("/auth/me", authenticate, (_req, res) => {
    res.json(userOf(res));
  });

  app.post("/auth/logout", authenticate, async (_req, res) => {
    await Session.deleteOne({ _id: res.locals.token });
    res.status(204).end();
  });

  const passkeys = createPasskeys<UserDocument>({
    config: {
      rpID: env.RP_ID,
      rpName: env.RP_NAME,
      origins: passkeyOrigins({ rpID: env.RP_ID, androidSha256: env.ANDROID_SHA256 }),
    },
    users: {
      id: (user) => user.id,
      name: (user) => user.email,
      displayName: (user) => user.name,
      findById: (id) => User.findById(id).exec(),
    },
    authenticate,
    currentUser: (_req, res) => userOf(res),
    // The same answer as /auth/login, so the app saves it the same way.
    signIn: (user) => openSession(user),
  });
  app.use("/auth/passkeys", passkeys.router);

  app.put("/auth/password", authenticate, async (req, res) => {
    const { currentPassword, newPassword } = parse(passwordSchema, req.body);
    const user = await User.findById(userOf(res).id).select("+passwordHash");
    if (!user || !(await checkPassword(currentPassword, user.passwordHash))) {
      throw new HttpError(422, "Your current password is wrong.");
    }
    user.passwordHash = await hashPassword(newPassword);
    await user.save();
    // Every other session ends, and every passkey goes with them: one added by
    // someone who knew the old password must not outlive it.
    await Promise.all([Session.deleteMany({ userId: user.id }), passkeys.removeAll(user.id)]);
    res.json(await openSession(user));
  });

  const handleErrors: ErrorRequestHandler = (err, _req, res, _next) => {
    if (err instanceof HttpError || err instanceof PasskeyError) {
      res.status(err.status).json({ message: err.message });
      return;
    }
    if (err?.type === "entity.parse.failed") {
      res.status(400).json({ message: "The body is not valid JSON." });
      return;
    }
    console.error(err);
    res.status(500).json({ message: "Something went wrong." });
  };
  app.use(handleErrors);

  return app;
};
