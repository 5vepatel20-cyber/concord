// Vertex AI provider — calls Gemini models through GCP Vertex AI.
// Vertex AI supports BAA coverage, making it suitable for PHI workloads.
// Uses @google-cloud/vertexai SDK with application-default credentials
// or a service account configured via GOOGLE_APPLICATION_CREDENTIALS.

import { VertexAI } from "@google-cloud/vertexai";
import { getEnv } from "../env.js";
import type {
  AIProvider,
  ChatChunk,
  ChatRequest,
  JSONSchema,
} from "./types.js";

const MODELS = {
  flash: "gemini-2.5-flash-001",
  pro: "gemini-2.5-pro-001",
} as const;

export class VertexAIProvider implements AIProvider {
  readonly name = "vertex";
  private client: VertexAI;

  constructor() {
    const env = getEnv();
    this.client = new VertexAI({
      project: env.VERTEX_PROJECT_ID,
      location: env.VERTEX_LOCATION,
    });
  }

  async *chat(req: ChatRequest): AsyncIterable<ChatChunk> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;
    const model = this.client.preview.getGenerativeModel({
      model: modelId,
      systemInstruction: {
        role: "system",
        parts: req.messages
          .filter((m) => m.role === "system")
          .map((m) => ({ text: m.content })),
      },
    });

    const history = req.messages
      .filter((m) => m.role !== "system")
      .slice(0, -1)
      .map((m) => ({
        role: m.role === "assistant" ? "model" as const : "user" as const,
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

    try {
      const aggregated = await result.response;
      const usageMeta = aggregated.usageMetadata;
      if (usageMeta) {
        yield {
          text: "",
          done: false,
          usage: {
            promptTokens: usageMeta.promptTokenCount ?? 0,
            completionTokens: usageMeta.candidatesTokenCount ?? 0,
            totalTokens: usageMeta.totalTokenCount ?? 0,
          },
        };
      }
    } catch {
      // Best-effort.
    }

    yield { text: "", done: true };
  }

  async chatJSON<T>(req: ChatRequest & { schema: JSONSchema }): Promise<T> {
    const modelId = req.model === "pro" ? MODELS.pro : MODELS.flash;
    const model = this.client.preview.getGenerativeModel({
      model: modelId,
      systemInstruction: {
        role: "system",
        parts: [
          ...req.messages
            .filter((m) => m.role === "system")
            .map((m) => ({ text: m.content })),
          { text: "You MUST respond with valid JSON matching the provided schema. No prose, no markdown." },
        ],
      },
      generationConfig: {
        maxOutputTokens: req.maxOutputTokens ?? 1024,
        temperature: req.temperature ?? 0.2,
        responseMimeType: "application/json",
        responseSchema: req.schema as unknown as Record<string, unknown>,
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
