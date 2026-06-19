// Quick local smoke test for /api/health.
// Loads env from ../.env.local, imports the handler, and calls it.
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { config as loadDotenv } from "dotenv";

const here = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(here, "..", "..", ".env.local");
console.log("Loading env from:", envPath);
loadDotenv({ path: envPath, override: true });

const { default: handler } = await import("../api/health.ts");
const req = new Request("http://localhost/api/health", { method: "GET" });
const res = await handler(req);
console.log("Status:", res.status);
console.log("Body:", await res.text());
