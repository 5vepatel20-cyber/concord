// Auth middleware. Reads the Supabase JWT from the Authorization header,
// verifies it with the anon client, and returns the user. Endpoints that
// require auth call requireUser() and bail to 401 if the JWT is missing/invalid.

import { userClient } from "./supabase.js";

export interface AuthedUser {
  id: string;
  email: string | null;
  /** Decoded user_metadata.role, defaulting to "patient" if absent. */
  role: "patient" | "caregiver" | "clinician" | "admin";
}

export async function requireUser(req: Request): Promise<AuthedUser | Response> {
  const auth = req.headers.get("authorization") ?? req.headers.get("Authorization");
  if (!auth?.toLowerCase().startsWith("bearer ")) {
    return jsonError(401, "missing_bearer", "Authorization: Bearer <jwt> required");
  }
  const jwt = auth.slice(7).trim();
  if (!jwt) {
    return jsonError(401, "empty_token", "Bearer token is empty");
  }

  const supabase = userClient(jwt);
  const { data, error } = await supabase.auth.getUser(jwt);
  if (error || !data.user) {
    return jsonError(401, "invalid_token", "JWT is invalid or expired");
  }

  const meta = (data.user.user_metadata ?? {}) as Record<string, unknown>;
  const role = (meta.role as AuthedUser["role"]) ?? "patient";

  return {
    id: data.user.id,
    email: data.user.email ?? null,
    role,
  };
}

export function jsonError(status: number, code: string, message: string): Response {
  return new Response(JSON.stringify({ error: { code, message } }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
