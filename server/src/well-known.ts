import { Router, type Response } from "express";

export interface AndroidApp {
  /** The application id, like `com.example.app`. */
  packageName: string;
  /**
   * The SHA-256 of every key that signs it, as `keytool` shows it
   * (`04:71:AE:…`): your debug key, your upload key, and Play App Signing.
   */
  sha256CertFingerprints: string[];
  /** Also let it open this domain's links (App Links). Default: false. */
  appLinks?: boolean;
}

export interface WellKnownOptions {
  /** iOS apps that may use this domain's passkeys, as `TEAMID.bundle.id`. */
  iosAppIds?: string[];
  /** Android apps that may use them. */
  androidApps?: AndroidApp[];
}

/**
 * The two files that tell iOS and Android your apps may use the passkeys of
 * this domain. Serve them yourself with {@link createWellKnownRouter}, or merge
 * these objects into the files you already serve (for app links, say).
 */
export const wellKnownFiles = ({ iosAppIds = [], androidApps = [] }: WellKnownOptions) => ({
  appleAppSiteAssociation: {
    webcredentials: { apps: iosAppIds },
  },
  assetLinks: androidApps.map((app) => ({
    relation: [
      ...(app.appLinks ? ["delegate_permission/common.handle_all_urls"] : []),
      "delegate_permission/common.get_login_creds",
    ],
    target: {
      namespace: "android_app",
      package_name: app.packageName,
      sha256_cert_fingerprints: app.sha256CertFingerprints,
    },
  })),
});

/**
 * Serves `/.well-known/apple-app-site-association` and
 * `/.well-known/assetlinks.json`. Mount it at the root of the RP ID's domain
 * (`app.use(createWellKnownRouter(...))`): both files must answer 200 with
 * JSON and no redirect, or the phones ignore them.
 */
export const createWellKnownRouter = (options: WellKnownOptions) => {
  const files = wellKnownFiles(options);
  const send = (res: Response, body: unknown) => {
    res.set("Cache-Control", "public, max-age=3600").json(body);
  };

  const router = Router();
  router.get("/.well-known/apple-app-site-association", (_req, res) =>
    send(res, files.appleAppSiteAssociation),
  );
  router.get("/.well-known/assetlinks.json", (_req, res) => send(res, files.assetLinks));
  return router;
};
