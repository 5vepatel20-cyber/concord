// AI provider factory with fallback support (AI-08).
// Primary provider is selected by AI_PRIMARY env var (gemini | claude).
// On failure, the fallback provider specified by AI_FALLBACK is tried.
// Consumer code only knows about the AIProvider interface.

import { getEnv } from "../env.js";
import type { AIProvider, ChatChunk, ChatRequest } from "./types.js";
import { GeminiProvider } from "./gemini.js";
import { ClaudeProvider } from "./claude.js";

let primary: AIProvider | null = null;
let fallback: AIProvider | null = null;

function buildProvider(name: string): AIProvider {
  switch (name) {
    case "claude":
      return new ClaudeProvider();
    case "gemini":
    default:
      return new GeminiProvider();
  }
}

function getProviders(): { primary: AIProvider; fallback: AIProvider | null } {
  if (!primary) {
    const env = getEnv();
    primary = buildProvider(env.AI_PRIMARY);
    if (env.AI_FALLBACK) {
      try {
        fallback = buildProvider(env.AI_FALLBACK);
      } catch {
        fallback = null;
      }
    }
  }
  return { primary, fallback };
}

export function getAIProvider(): AIProvider {
  const { primary: p } = getProviders();
  return p;
}

/**
 * Stream a chat completion with automatic fallback.
 * Tries the primary provider; on failure, tries the fallback (if configured).
 * If both fail, the last error is thrown.
 */
export async function* chatWithFallback(
  req: ChatRequest,
): AsyncIterable<ChatChunk> {
  const { primary, fallback: fb } = getProviders();
  let lastError: unknown;

  try {
    for await (const chunk of primary.chat(req)) {
      yield chunk;
    }
    return;
  } catch (e) {
    lastError = e;
  }

  if (fb) {
    try {
      for await (const chunk of fb.chat(req)) {
        yield chunk;
      }
      return;
    } catch (e) {
      lastError = e;
    }
  }

  throw lastError;
}

/**
 * Non-streaming structured call with automatic fallback.
 * Tries the primary provider; on failure, tries the fallback (if configured).
 */
export async function chatJSONWithFallback<T>(
  req: ChatRequest & { schema: import("./types.js").JSONSchema },
): Promise<T> {
  const { primary, fallback: fb } = getProviders();
  let lastError: unknown;

  try {
    return await primary.chatJSON<T>(req);
  } catch (e) {
    lastError = e;
  }

  if (fb) {
    try {
      return await fb.chatJSON<T>(req);
    } catch (e) {
      lastError = e;
    }
  }

  throw lastError;
}

export type { AIProvider, ChatRequest, ChatMessage, ChatChunk, ChatChunk as Chunk, TokenUsage, JSONSchema } from "./types.js";
