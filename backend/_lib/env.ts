// Type-safe environment loading. Validated once at module load; throws fast if
// anything required is missing. Never logs values.

import { z } from "zod";

const EnvSchema = z.object({
  // AI
  GEMINI_API_KEY: z.string().min(20),
  ANTHROPIC_API_KEY: z.string().min(20).optional(),
  AI_PRIMARY: z.enum(["gemini", "claude"]).default("gemini"),
  AI_FALLBACK: z.enum(["gemini", "claude"]).optional(),

  // Supabase
  SUPABASE_URL: z.string().url(),
  SUPABASE_ANON_KEY: z.string().min(20),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(20),

  // Sentry
  SENTRY_DSN_BACKEND: z.string().url().optional(),

  // PostHog (server-side capture, not used at boot)
  POSTHOG_API_KEY: z.string().optional(),
  POSTHOG_HOST: z.string().url().optional(),

  // Resend
  RESEND_API_KEY: z.string().optional(),
  RESEND_FROM_EMAIL: z.string().email().optional(),

  // Node env
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  VERCEL_ENV: z.enum(["development", "preview", "production"]).optional(),
});

export type Env = z.infer<typeof EnvSchema>;

let cached: Env | null = null;

export function getEnv(): Env {
  if (cached) return cached;
  const parsed = EnvSchema.safeParse(process.env);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  - ${i.path.join(".")}: ${i.message}`)
      .join("\n");
    throw new Error(`Invalid environment:\n${issues}`);
  }
  cached = parsed.data;
  return cached;
}

// Convenience: mask a value for logging.
export function mask(value: string, head = 4, tail = 4): string {
  if (value.length <= head + tail) return "***";
  return `${value.slice(0, head)}…${value.slice(-tail)}`;
}
