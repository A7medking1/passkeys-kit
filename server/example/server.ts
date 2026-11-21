import mongoose from "mongoose";
import { passkeyOrigins } from "../src/index.js";
import { createApp } from "./app.js";
import { readEnv } from "./env.js";

const env = readEnv();

await mongoose.connect(env.MONGODB_URI);

createApp(env).listen(env.PORT, () => {
  const origins = passkeyOrigins({ rpID: env.RP_ID, androidSha256: env.ANDROID_SHA256 });
  console.log(`Passkeys Kit example on http://localhost:${env.PORT}`);
  console.log(`  RP ID    ${env.RP_ID}`);
  console.log(`  Origins  ${origins.join("\n           ")}`);
  console.log(`  Database ${mongoose.connection.name}`);
});
