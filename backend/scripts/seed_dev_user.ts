// One-shot: create a confirmed dev user in Supabase so the Flutter web
// build has something to sign in with during browser-based dev iteration.
//
// Run with:
//   cd backend && npx tsx scripts/seed_dev_user.ts
//
// Idempotent: if the user already exists, prints the existing id and exits.
//
// Reads SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY from .env.local (created
// via `vercel env pull`) or the process environment.

import { createClient } from "@supabase/supabase-js";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

const ENV_PATH = resolve(process.cwd(), ".env.local");

if (existsSync(ENV_PATH)) {
  for (const line of readFileSync(ENV_PATH, "utf8").split(/\r?\n/)) {
    const m = line.match(/^([A-Z0-9_]+)="?([^"]*)"?$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2];
  }
}

const url = process.env.SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !serviceKey) {
  console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.");
  console.error("Run `vercel env pull .env.local` first.");
  process.exit(1);
}

const EMAIL = "dev@concord.test";
const PASSWORD = "concord-dev-2026";

const admin = createClient(url, serviceKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function findOrCreate(): Promise<{ id: string; created: boolean }> {
  // Look up first — idempotent re-runs are useful while iterating.
  const { data: existing, error: lookupErr } =
    await admin.auth.admin.listUsers();
  if (lookupErr) throw lookupErr;
  const hit = existing?.users.find((u) => u.email === EMAIL);
  if (hit) return { id: hit.id, created: false };

  const { data, error } = await admin.auth.admin.createUser({
    email: EMAIL,
    password: PASSWORD,
    email_confirm: true,
    user_metadata: { full_name: "Dev Patient", role: "patient" },
  });
  if (error) throw error;
  return { id: data.user.id, created: true };
}

const { id, created } = await findOrCreate();
console.log(
  created
    ? `✓ Created dev user: ${EMAIL} (${id})`
    : `= Dev user already exists: ${EMAIL} (${id})`,
);
console.log(`  Sign in:  email=${EMAIL}  password=${PASSWORD}`);
console.log(`  URL:      ${url}`);
