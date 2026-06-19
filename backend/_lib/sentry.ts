// Sentry init. No-op if SENTRY_DSN_BACKEND is unset (e.g. local dev).
// Called once at function boot; safe to call from any endpoint.

import * as Sentry from "@sentry/node";
import { getEnv, mask } from "./env.js";

let initialized = false;

export function initSentry(): void {
  if (initialized) return;
  const env = getEnv();
  if (!env.SENTRY_DSN_BACKEND) {
    // Local dev: do nothing. Errors still go to console.
    return;
  }
  Sentry.init({
    dsn: env.SENTRY_DSN_BACKEND,
    environment: env.VERCEL_ENV ?? env.NODE_ENV,
    // Sample 20% of transactions in prod; 100% in dev/preview for debugging.
    tracesSampleRate: env.VERCEL_ENV === "production" ? 0.2 : 1.0,
    // PHI rule: never send request/response bodies, headers, or user PII
    // (email, name, DOB). Sentry's default is to scrub known auth headers,
    // but we add explicit denyList + beforeSend to be safe.
    sendDefaultPii: false,
    denyUrls: [/\/api\/health/], // don't track health checks
    beforeSend(event) {
      // Strip any breadcrumbs that captured a request body.
      if (event.breadcrumbs) {
        for (const bc of event.breadcrumbs) {
          if (bc.data) delete bc.data.body;
          if (bc.data) delete bc.data.request_body;
        }
      }
      return event;
    },
  });
  initialized = true;
  // Log a single breadcrumb so we can confirm in the Sentry UI that the
  // project is wired up. Mask the DSN so we don't leak the public key.
  Sentry.addBreadcrumb({
    category: "boot",
    message: `sentry init dsn=${mask(env.SENTRY_DSN_BACKEND, 10, 6)}`,
    level: "info",
  });
}

export { Sentry };
