// Load .env.local (one level up from backend/) and call the GET handler.
import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const envPath = resolve(here, "..", "..", ".env.local");
if (!existsSync(envPath)) {
  console.error("No .env.local at", envPath);
  process.exit(1);
}

for (const line of readFileSync(envPath, "utf8").split(/\r?\n/)) {
  const m = line.match(/^([A-Z_][A-Z0-9_]*)=(.*)$/);
  if (!m) continue;
  const k = m[1];
  let v = m[2];
  if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
    v = v.slice(1, -1);
  }
  process.env[k] = v;
}

const { GET } = await import("../api/health.ts");
const req = new Request("http://localhost/api/health", { method: "GET" });
const res = await GET(req);
console.log("status:", res.status);
console.log("body:", await res.text());
