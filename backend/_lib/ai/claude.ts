import Anthropic from "@anthropic-ai/sdk";
import { getEnv } from "../env.js";
import type {
  AIProvider,
  ChatChunk,
  ChatRequest,
  JSONSchema,
} from "./types.js";

const MODELS = {
  flash: "claude-sonnet-4-20250514",
  pro: "claude-opus-4-20250514",
} as const;

export class ClaudeProvider implements AIProvider {
  readonly name = "claude";
  private client: Anthropic;

  constructor() {
    const env = getEnv();
    if (!env.ANTHROPIC_API_KEY) {
      throw new Error("ANTHROPIC_API_KEY is required for ClaudeProvider");
    }
    this.client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });
  }

  async *chat(req: ChatRequest): AsyncIterable<ChatChunk> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;

    const systemMessages = req.messages
      .filter((m) => m.role === "system")
      .map((m) => m.content);
    const systemPrompt = systemMessages.length > 0
      ? systemMessages.join("\n\n")
      : undefined;

    const nonSystem = req.messages.filter((m) => m.role !== "system");
    const lastUser = nonSystem.at(-1);
    if (!lastUser || lastUser.role !== "user") {
      throw new Error("chat() requires at least one user message");
    }

    const apiMessages = nonSystem.slice(0, -1).map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    }));

    const stream = await this.client.messages.create({
      model: modelId,
      system: systemPrompt,
      messages: [...apiMessages, { role: "user", content: lastUser.content }],
      max_tokens: req.maxOutputTokens ?? 1024,
      temperature: req.temperature ?? 0.7,
      stream: true,
    });

    for await (const event of stream) {
      switch (event.type) {
        case "content_block_delta":
          if (event.delta.type === "text_delta" && event.delta.text) {
            yield { text: event.delta.text, done: false };
          }
          break;
        case "message_delta": {
          const u = event.usage;
          if (u) {
            const pt = u.input_tokens;
            const ct = u.output_tokens;
            if (pt != null && ct != null) {
              yield {
                text: "",
                done: false,
                usage: {
                  promptTokens: pt,
                  completionTokens: ct,
                  totalTokens: pt + ct,
                },
              };
            }
          }
          break;
        }
        case "message_stop":
          // The stream is ending; usage is not available here in Claude's
          // streaming API — it was sent in message_delta.
          break;
      }
    }

    yield { text: "", done: true };
  }

  async chatJSON<T>(req: ChatRequest & { schema: JSONSchema }): Promise<T> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;

    const systemMessages = req.messages
      .filter((m) => m.role === "system")
      .map((m) => m.content);
    const systemPrompt = [
      ...systemMessages,
      "You MUST respond with valid JSON matching the provided schema. No prose, no markdown.",
    ].join("\n\n");

    const nonSystem = req.messages.filter((m) => m.role !== "system");
    const lastUser = nonSystem.at(-1);
    if (!lastUser || lastUser.role !== "user") {
      throw new Error("chatJSON() requires at least one user message");
    }

    const apiMessages = nonSystem.slice(0, -1).map((m) => ({
      role: m.role as "user" | "assistant",
      content: m.content,
    }));

    const response = await this.client.messages.create({
      model: modelId,
      system: systemPrompt,
      messages: [...apiMessages, { role: "user", content: lastUser.content }],
      max_tokens: req.maxOutputTokens ?? 1024,
      temperature: req.temperature ?? 0.2,
    });

    const text = response.content
      .filter((b) => b.type === "text")
      .map((b) => (b as Anthropic.TextBlock).text)
      .join("");

    return JSON.parse(text) as T;
  }
}
