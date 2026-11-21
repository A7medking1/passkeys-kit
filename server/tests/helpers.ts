import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import type { Express } from "express";
import mongoose from "mongoose";

// A database of its own, emptied before and after: never your real one.
const TEST_DATABASE =
  process.env.TEST_MONGODB_URI ?? "mongodb://127.0.0.1:27017/passkeys_kit_test";

export const RP_ID = "example.com";
export const IOS_ORIGIN = "https://example.com";
export const RELEASE_SHA256 =
  "F7:74:7B:3A:F3:C1:1B:62:F4:CF:48:48:54:3F:0A:CA:E5:DE:4E:85:AA:41:A5:D9:B6:30:FF:77:65:52:75:C9";
export const DEBUG_SHA256 =
  "6E:83:48:6C:56:1A:5F:92:3A:4F:73:99:B6:37:60:50:C9:E7:73:43:36:D7:C4:87:AF:F1:3E:AE:B3:9D:E0:4A";
// The same two keys as Android sends them (worked out apart from the kit).
export const RELEASE_ORIGIN = "android:apk-key-hash:93R7OvPBG2L0z0hIVD8KyuXeToWqQaXZtjD_d2VSdck";
export const DEBUG_ORIGIN = "android:apk-key-hash:boNIbFYaX5I6T3OZtjdgUMnnc0M218SHr_E-rrOd4Eo";

export const connectDatabase = async () => {
  await mongoose.connect(TEST_DATABASE);
  if (!mongoose.connection.name.endsWith("_test")) {
    throw new Error("The tests only run on a database whose name ends with _test");
  }
  await mongoose.connection.dropDatabase();
  await Promise.all(Object.values(mongoose.models).map((model) => model.syncIndexes()));
};

export const disconnectDatabase = async () => {
  await mongoose.connection.dropDatabase();
  await mongoose.disconnect();
};

/** Starts an app on a free port and returns its fetch helper. */
export const serve = async (app: Express) => {
  const server = await new Promise<Server>((resolve) => {
    const started = app.listen(0, () => resolve(started));
  });
  const { port } = server.address() as AddressInfo;
  const base = `http://127.0.0.1:${port}`;

  const call = async (
    method: string,
    path: string,
    { body, token }: { body?: unknown; token?: string } = {},
  ) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        ...(body !== undefined && { "content-type": "application/json" }),
        ...(token && { authorization: `Bearer ${token}` }),
      },
      ...(body !== undefined && { body: JSON.stringify(body) }),
    });
    const text = await res.text();
    return {
      status: res.status,
      headers: res.headers,
      json: (text ? JSON.parse(text) : null) as any,
    };
  };

  const close = () => new Promise<void>((resolve) => server.close(() => resolve()));
  return { call, close };
};
