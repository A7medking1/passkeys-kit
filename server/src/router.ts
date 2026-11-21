import express, {
  Router,
  type ErrorRequestHandler,
  type Request,
  type RequestHandler,
  type Response,
} from "express";
import { rateLimit } from "express-rate-limit";
import type { ZodType } from "zod";
import { PasskeyError } from "./errors.js";
import { loginVerifySchema, registerVerifySchema } from "./schemas.js";
import { createPasskeyService, type PasskeyServiceOptions } from "./service.js";

export interface PasskeyRateLimits {
  /** `login/options` calls per minute and IP. Every call saves a challenge. Default: 30. */
  optionsPerMinute?: number;
  /** Failed `login/verify` calls per 15 minutes and IP. Default: 10. */
  failedSignInsPer15Minutes?: number;
}

export interface PasskeyOptions<User> extends PasskeyServiceOptions<User> {
  /**
   * Your auth middleware for register, list and delete. It must answer a
   * request with no signed-in user (usually with a 401) and attach the user
   * for {@link currentUser}.
   */
  authenticate: RequestHandler;
  /** Reads the user that `authenticate` attached. */
  currentUser(req: Request, res: Response): User;
  /**
   * Answers a verified passkey sign-in with your own session: the same body
   * your password sign-in returns, so your app saves it the same way. Throw a
   * `PasskeyError` to refuse it (a blocked account, say).
   */
  signIn(user: User, req: Request, res: Response): unknown;
  /** Who may add passkeys, like customers only. Default: every signed-in user. */
  canRegister?(user: User): boolean | Promise<boolean>;
  /** The rate limits, or `false` to bring your own. */
  rateLimit?: false | PasskeyRateLimits;
}

/**
 * Passkey sign-in for an Express app, on the path you mount it on:
 *
 * | Route                    | Who                | Answer                       |
 * | ------------------------ | ------------------ | ---------------------------- |
 * | POST /register/options   | signed-in user     | options for the phone        |
 * | POST /register/verify    | signed-in user     | 201 and the new passkey      |
 * | POST /login/options      | anyone             | options for the phone        |
 * | POST /login/verify       | anyone             | whatever `signIn` returns    |
 * | GET /                    | signed-in user     | the user's passkeys          |
 * | DELETE /:id              | signed-in user     | 204                          |
 *
 * Errors come back as `{ "message": "..." }` with their status.
 */
export const createPasskeys = <User>(options: PasskeyOptions<User>) => {
  const service = createPasskeyService(options);
  const { messages } = service;
  const { authenticate, currentUser, signIn, canRegister } = options;

  const validate =
    (schema: ZodType): RequestHandler =>
    (req, _res, next) => {
      const result = schema.safeParse(req.body);
      if (!result.success) throw new PasskeyError(422, messages.invalidRequest);
      req.body = result.data;
      next();
    };

  const tooManyRequests: RequestHandler = (_req, _res, next) =>
    next(new PasskeyError(429, messages.tooManyRequests));

  const limits = options.rateLimit === false ? null : (options.rateLimit ?? {});
  const passThrough: RequestHandler = (_req, _res, next) => next();
  // Every call saves a challenge, so every call counts.
  const optionsLimiter = limits
    ? rateLimit({
        windowMs: 60 * 1000,
        limit: limits.optionsPerMinute ?? 30,
        standardHeaders: "draft-8",
        legacyHeaders: false,
        handler: tooManyRequests,
      })
    : passThrough;
  // Only failures count, so guessing stops but normal use passes.
  const verifyLimiter = limits
    ? rateLimit({
        windowMs: 15 * 60 * 1000,
        limit: limits.failedSignInsPer15Minutes ?? 10,
        skipSuccessfulRequests: true,
        standardHeaders: "draft-8",
        legacyHeaders: false,
        handler: tooManyRequests,
      })
    : passThrough;

  const allowedToRegister: RequestHandler = async (req, res, next) => {
    if (canRegister && !(await canRegister(currentUser(req, res)))) {
      throw new PasskeyError(403, messages.registrationNotAllowed);
    }
    next();
  };

  const router = Router();
  router.use(express.json({ limit: "64kb" }));

  router.post("/register/options", authenticate, allowedToRegister, async (req, res) => {
    res.json(await service.registrationOptions(currentUser(req, res)));
  });

  router.post(
    "/register/verify",
    authenticate,
    allowedToRegister,
    validate(registerVerifySchema),
    async (req, res) => {
      const passkey = await service.verifyRegistration(currentUser(req, res), req.body);
      res.status(201).json(passkey);
    },
  );

  router.post("/login/options", optionsLimiter, async (_req, res) => {
    res.json(await service.authenticationOptions());
  });

  router.post("/login/verify", verifyLimiter, validate(loginVerifySchema), async (req, res) => {
    const user = await service.verifyAuthentication(req.body);
    const session = await signIn(user, req, res);
    if (!res.headersSent) res.json(session ?? {});
  });

  router.get("/", authenticate, async (req, res) => {
    const user = currentUser(req, res);
    res.json(await service.list(options.users.id(user)));
  });

  router.delete("/:id", authenticate, async (req: Request<{ id: string }>, res) => {
    const user = currentUser(req, res);
    await service.remove(options.users.id(user), req.params.id);
    res.status(204).end();
  });

  const handleErrors: ErrorRequestHandler = (err, _req, res, next) => {
    if (!(err instanceof PasskeyError)) return next(err);
    res.status(err.status).json({ message: err.message });
  };
  router.use(handleErrors);

  return { router, service, removeAll: service.removeAll };
};
