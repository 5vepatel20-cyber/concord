// Shared types for the swappable AI provider layer.

export type Role = "system" | "user" | "assistant";

export interface ChatMessage {
  role: Role;
  content: string;
}

export interface ChatRequest {
  messages: ChatMessage[];
  /** Optional model hint. Providers may ignore or override. */
  model?: "flash" | "pro";
  /** Hard upper bound on tokens to generate. */
  maxOutputTokens?: number;
  /** Sampling temperature. Default 0.7. */
  temperature?: number;
}

/** A single chunk from a streaming chat completion. */
export interface ChatChunk {
  text: string;
  done: boolean;
}

export interface AIProvider {
  /** Provider name (for logging/observability). */
  readonly name: string;
  /** Stream a chat completion. Caller iterates until done. */
  chat(req: ChatRequest): AsyncIterable<ChatChunk>;
  /** Non-streaming structured call: returns parsed JSON. Throws on parse failure. */
  chatJSON<T>(req: ChatRequest & { schema: JSONSchema }): Promise<T>;
}

/** Minimal JSON Schema type — what the LLM needs to see to produce structured output. */
export interface JSONSchema {
  type: "object";
  properties: Record<string, { type: string; description?: string; enum?: string[] }>;
  required?: string[];
  additionalProperties?: boolean;
}
