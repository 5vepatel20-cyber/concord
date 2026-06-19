// Supabase client factories. Two flavors:
//  - serviceClient(): full admin access (server-only, bypasses RLS). Use for
//    trusted backend jobs (alert engine, report assembly, migrations).
//  - userClient(jwt): a per-request client that runs as the authenticated user
//    and respects RLS. Use for any endpoint that reads/writes user data.
//
// Both are stateless — no module-level connection pooling beyond what
// @supabase/supabase-js does internally (which is fine on serverless).

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { getEnv } from "./env.js";

let cachedService: SupabaseClient | null = null;

export function serviceClient(): SupabaseClient {
  if (cachedService) return cachedService;
  const env = getEnv();
  cachedService = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  return cachedService;
}

export function userClient(jwt: string): SupabaseClient {
  const env = getEnv();
  return createClient(env.SUPABASE_URL, env.SUPABASE_ANON_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
    global: {
      headers: { Authorization: `Bearer ${jwt}` },
    },
  });
}
