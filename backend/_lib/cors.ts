// Shared CORS handling. Browser clients (the Flutter web build) cannot
// call this API cross-origin unless we echo an Access-Control-Allow-Origin
// header — Vercel serverless functions don't set CORS by default.
//
// Allowed origins:
//   - localhost dev ports (flutter run -d chrome)
//   - any *.vercel.app origin (preview deploys + the landing site)
//
// The helper applies per-request: it echoes the Origin header back only if
// the origin is on the allow-list, and always sets `Vary: Origin` so caches
// don't serve the wrong allow-origin to a different caller.

const ALLOWED_ORIGINS = new Set<string>([
  "http://localhost:8080",
  "http://localhost:8081",
  "http://127.0.0.1:8080",
  "http://127.0.0.1:8081",
  "https://concord.so",
]);

function isAllowedOrigin(origin: string): boolean {
  if (ALLOWED_ORIGINS.has(origin)) return true;
  if (origin.endsWith(".vercel.app")) return true;
  return false;
}

function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  const allowed = isAllowedOrigin(origin) ? origin : "";
  return {
    "access-control-allow-origin": allowed,
    "access-control-allow-headers":
      "authorization, content-type, idempotency-key, x-client-info",
    "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
    "access-control-max-age": "86400",
    vary: "Origin",
  };
}

/// Handle a CORS preflight (OPTIONS) request. Returns a 204 with the
/// appropriate Access-Control-* headers so the browser can proceed with
/// the real request.
export function preflight(req: Request): Response {
  return new Response(null, { status: 204, headers: corsHeadersFor(req) });
}

/// Wrap an existing Response with the CORS headers appropriate for the
/// incoming request. Status, body, and existing headers are preserved.
/// Used to annotate the success and error paths of each endpoint.
export function corsed(req: Request, res: Response): Response {
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(corsHeadersFor(req))) {
    headers.set(k, v);
  }
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}

/// Convenience: build a JSON error response and apply CORS in one step.
/// The companion to `jsonError` in `_lib/auth.ts`; takes the Request so
/// the CORS helper can decide which origin to allow.
export function corsedJsonError(
  req: Request,
  status: number,
  code: string,
  message: string,
): Response {
  const body = JSON.stringify({ error: { code, message } });
  return corsed(
    req,
    new Response(body, {
      status,
      headers: { "content-type": "application/json" },
    }),
  );
}
