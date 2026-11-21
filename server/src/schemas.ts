import { z } from "zod";

export const PASSKEY_NAME_MAX = 60;

// Only the strings every answer from the phone must have. SimpleWebAuthn
// checks everything else, so unknown fields pass through as they are.
const required = z.string().min(1);

const credential = {
  id: required,
  rawId: required,
  type: z.literal("public-key"),
  clientExtensionResults: z.looseObject({}).default({}),
};

export const registerVerifySchema = z.object({
  response: z.looseObject({
    ...credential,
    response: z.looseObject({
      clientDataJSON: required,
      attestationObject: required,
      transports: z.array(z.string()).optional(),
    }),
  }),
  // What the user will see in the list, like the phone's model.
  name: z.string().trim().min(1).max(PASSKEY_NAME_MAX).optional(),
});

export const loginVerifySchema = z.object({
  response: z.looseObject({
    ...credential,
    response: z.looseObject({
      clientDataJSON: required,
      authenticatorData: required,
      signature: required,
      // Missing or wrong, it gets the same answer as a wrong signature.
      userHandle: z.string().nullish(),
    }),
  }),
});

export type RegisterVerifyInput = z.infer<typeof registerVerifySchema>;
export type LoginVerifyInput = z.infer<typeof loginVerifySchema>;
