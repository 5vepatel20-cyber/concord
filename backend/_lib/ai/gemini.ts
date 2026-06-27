// Gemini implementation of the AIProvider interface.
// Build phase (free tier, no BAA). Swap to Claude via Vertex / Bedrock
// pre-Phase-2 by adding a sibling provider and switching the factory in
// provider.ts — no consumer code changes.

import { GoogleGenerativeAI, type Schema } from "@google/generative-ai";
import { getEnv } from "../env.js";
import type {
  AIProvider,
  ChatChunk,
  ChatRequest,
  JSONSchema,
} from "./types.js";

const MODELS = {
  flash: "gemini-2.5-flash",
  pro: "gemini-2.5-pro",
} as const;

export class GeminiProvider implements AIProvider {
  readonly name = "gemini";
  private client: GoogleGenerativeAI;

  constructor() {
    const env = getEnv();
    this.client = new GoogleGenerativeAI(env.GEMINI_API_KEY);
  }

  async *chat(req: ChatRequest): AsyncIterable<ChatChunk> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;
    const model = this.client.getGenerativeModel({
      model: modelId,
      systemInstruction: req.messages
        .filter((m) => m.role === "system")
        .map((m) => m.content)
        .join("\n\n"),
    });

    // Gemini uses a different message shape: alternating user/model turns,
    // no system role in the chat (system goes via systemInstruction).
    const history = req.messages
      .filter((m) => m.role !== "system")
      .slice(0, -1)
      .map((m) => ({
        role: m.role === "assistant" ? ("model" as const) : ("user" as const),
        parts: [{ text: m.content }],
      }));
    const lastUser = req.messages.filter((m) => m.role !== "system").at(-1);
    if (!lastUser || lastUser.role !== "user") {
      throw new Error("chat() requires at least one user message");
    }

    const chat = model.startChat({
      history,
      generationConfig: {
        maxOutputTokens: req.maxOutputTokens ?? 1024,
        temperature: req.temperature ?? 0.7,
      },
    });

    const result = await chat.sendMessageStream(lastUser.content);
    for await (const item of result.stream) {
      const text = item.text();
      if (text) yield { text, done: false };
    }

    // Extract citation metadata + token usage from the aggregated response.
    try {
      const aggregated = await result.response;
      const extra: Partial<ChatChunk> = {};

      // ATLAS-06: Citations.
      const sources = aggregated.candidates?.[0]?.citationMetadata?.citationSources;
      if (sources && sources.length > 0) {
        const citations: Array<{ uri: string }> = [];
        for (const s of sources) {
          if (s.uri) citations.push({ uri: s.uri });
        }
        if (citations.length > 0) extra.citations = citations;
      }

      // AI-08: Token usage.
      const usageMeta = aggregated.usageMetadata;
      if (usageMeta) {
        extra.usage = {
          promptTokens: usageMeta.promptTokenCount ?? 0,
          completionTokens: usageMeta.candidatesTokenCount ?? 0,
          totalTokens: usageMeta.totalTokenCount ?? 0,
        };
      }

      if (extra.citations || extra.usage) {
        yield { text: "", done: false, ...extra };
      }
    } catch {
      // Aggregated response extras are best-effort; never crash the stream.
    }

    yield { text: "", done: true };
  }

  async chatJSON<T>(req: ChatRequest & { schema: JSONSchema }): Promise<T> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;
    const model = this.client.getGenerativeModel({
      model: modelId,
      systemInstruction: [
        ...req.messages.filter((m) => m.role === "system").map((m) => m.content),
        "You MUST respond with valid JSON matching the provided schema. No prose, no markdown.",
      ].join("\n\n"),
      generationConfig: {
        maxOutputTokens: req.maxOutputTokens ?? 1024,
        temperature: req.temperature ?? 0.2,
        // Gemini supports a constrained-decode via responseMimeType + schema.
        // Our JSONSchema is a minimal subset of JSON Schema Draft 7; we cast
        // through unknown to Gemini's richer Schema union (which adds
        // description, enum, items, format, etc. — Gemini infers these from
        // our object structure).
        responseMimeType: "application/json",
        responseSchema: req.schema as unknown as Schema,
      },
    });

    const lastUser = req.messages.filter((m) => m.role !== "system").at(-1);
    if (!lastUser || lastUser.role !== "user") {
      throw new Error("chatJSON() requires at least one user message");
    }
    const result = await model.generateContent(lastUser.content);
    const text = result.response.text();
    return JSON.parse(text) as T;
  }
}
