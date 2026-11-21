import { z } from "zod";

// "a, b ,c" → ["a", "b", "c"], and nothing → [].
const list = z
  .string()
  .optional()
  .transform((value) =>
    (value ?? "")
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean),
  );

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  MONGODB_URI: z.string().min(1).default("mongodb://127.0.0.1:27017/passkeys_kit"),
  // The domain the passkeys belong to, with no https://.
  RP_ID: z.string().min(1, "Set RP_ID in .env (copy .env.example)"),
  RP_NAME: z.string().min(1).default("Passkeys Kit"),
  // TEAMID.bundle.id of every iOS app, for apple-app-site-association.
  IOS_APP_IDS: list,
  // The Android app, and the SHA-256 of every key that signs it.
  ANDROID_PACKAGE: z.string().optional(),
  ANDROID_SHA256: list,
});

export type Env = z.infer<typeof schema>;

export const readEnv = (source: Record<string, string | undefined> = process.env): Env => {
  const result = schema.safeParse(source);
  if (!result.success) {
    const problems = result.error.issues.map(
      (issue) => `  ${issue.path.join(".")}: ${issue.message}`,
    );
    throw new Error(`The environment is not set up:\n${problems.join("\n")}`);
  }
  return result.data;
};
