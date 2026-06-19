// AI provider factory. The whole point: swap providers (Gemini → Claude via
// Vertex / Bedrock) by changing this one file. Consumer code only knows
// about the AIProvider interface.

import type { AIProvider } from "./types.js";
import { GeminiProvider } from "./gemini.js";

let cached: AIProvider | null = null;

export function getAIProvider(): AIProvider {
  if (cached) return cached;
  // Pre-Phase-2: switch on an env flag like AI_PROVIDER=claude-vertex and
  // construct a ClaudeVertexProvider here. Today, only Gemini is built.
  cached = new GeminiProvider();
  return cached;
}

export type { AIProvider, ChatRequest, ChatMessage, ChatChunk, JSONSchema } from "./types.js";
