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

export interface CitationSource {
  uri: string;
  title?: string;
}

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
}

/** A single chunk from a streaming chat completion. */
export interface ChatChunk {
  text: string;
  done: boolean;
  citations?: CitationSource[];
  usage?: TokenUsage;
}

export interface AIProvider {
  /** Provider name (for logging/observability). */
  readonly name: string;
  /** Stream a chat completion. Caller iterates until done. */
  chat(req: ChatRequest): AsyncIterable<ChatChunk>;
  /** Non-streaming structured call: returns parsed JSON. Throws on parse failure. */
  chatJSON<T>(req: ChatRequest & { schema: JSONSchema }): Promise<T>;
}

/** A single property within a JSON Schema node. Recursive to support nested
 *  object and array schemas for structured LLM output. */
export interface JSONSchemaProperty {
  type: string;
  description?: string;
  enum?: string[];
  items?: JSONSchemaProperty;
  properties?: Record<string, JSONSchemaProperty>;
  required?: string[];
}

/** Minimal JSON Schema type — what the LLM needs to see to produce structured output. */
export interface JSONSchema {
  type: "object";
  properties: Record<string, JSONSchemaProperty>;
  required?: string[];
  additionalProperties?: boolean;
}
