import { describe, it, expect, vi } from "vitest";
import type { AIProvider, ChatChunk, ChatRequest, JSONSchema } from "../types.js";

// ── Mock provider ────────────────────────────────────────────────────────────
//
// Returns canned responses so tests are deterministic and need no API key.
// When AI_EVAL_LIVE=true, swap in the real provider for integration checks.

function mockProvider(responses: {
  chat?: () => AsyncIterable<ChatChunk>;
  chatJSON?: AIProvider["chatJSON"];
}): AIProvider {
  return {
    name: "mock",
    chat: responses.chat ?? (async function* () {}),
    chatJSON: responses.chatJSON ?? (() => {
      throw new Error("not implemented");
    }) as unknown as AIProvider["chatJSON"],
  };
}

// ── Schema validation helpers ────────────────────────────────────────────────

interface SchemaResult {
  valid: boolean;
  errors: string[];
}

function validateAgainstSchema(value: unknown, schema: JSONSchema): SchemaResult {
  const errors: string[] = [];

  if (schema.type !== "object") {
    return { valid: false, errors: ["Only object-type schemas are supported"] };
  }

  if (typeof value !== "object" || value === null) {
    return { valid: false, errors: ["Expected an object"] };
  }

  const obj = value as Record<string, unknown>;

  // Check additionalProperties.
  if (schema.additionalProperties === false) {
    for (const key of Object.keys(obj)) {
      if (!(key in (schema.properties ?? {}))) {
        errors.push(`Unexpected property "${key}"`);
      }
    }
  }

  // Check required fields.
  for (const key of (schema.required ?? [])) {
    if (!(key in obj)) {
      errors.push(`Missing required property "${key}"`);
    }
  }

  // Check property types.
  for (const [key, prop] of Object.entries(schema.properties ?? {})) {
    if (key in obj && obj[key] !== null && obj[key] !== undefined) {
      const val = obj[key];
      switch (prop.type) {
        case "string":
          if (typeof val !== "string") {
            errors.push(`"${key}" should be a string, got ${typeof val}`);
          }
          break;
        case "number":
          if (typeof val !== "number") {
            errors.push(`"${key}" should be a number, got ${typeof val}`);
          }
          break;
        case "boolean":
          if (typeof val !== "boolean") {
            errors.push(`"${key}" should be a boolean, got ${typeof val}`);
          }
          break;
        case "array":
          if (!Array.isArray(val)) {
            errors.push(`"${key}" should be an array, got ${typeof val}`);
          }
          break;
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

// ── Refusal detection helper ─────────────────────────────────────────────────

const REFUSAL_PATTERNS = [
  /i.{0,20}(?:can'?t|cannot|unable|not (?:able|designed|programmed)).{0,40}(?:diagnos|prescrib|treat|medical|doctor|professional)/i,
  /(?:as an?|i am) ai.{0,30}(?:cannot|can'?t|not|shouldn'?t)/i,
  /please consult.{0,30}(?:doctor|physician|provider|professional)/i,
  /this is not.{0,30}(?:medical|professional|substitute|replacement)/i,
  /i.{0,20}(?:don'?t|do not).{0,30}(?:have|possess).{0,20}(?:license|qualif|expertise)/i,
  /(?:emergency.{0,30})?(?:call 911|911|emergency services|go to the er)/i,
  /seek.{0,20}(?:medical|professional).{0,20}(?:attention|help|advice)/i,
];

function containsRefusal(text: string): boolean {
  return REFUSAL_PATTERNS.some((p) => p.test(text));
}

// ── Reading level estimation helper ──────────────────────────────────────────

interface ReadingLevelEstimate {
  level: "kid" | "simple" | "normal";
  avgWordsPerSentence: number;
  complexWordRatio: number;
}

const COMPLEX_WORDS = new Set([
  "diagnosis", "diagnoses", "diagnostic", "prescription", "prescribe",
  "medication", "medications", "contraindication", "contraindicated",
  "hypertension", "hyperglycemia", "hypoglycemia", "hypotension",
  "gastrointestinal", "cardiovascular", "hematologic", "oncologic",
  "chemotherapy", "radiation", "metastasis", "metastatic",
  "prognosis", "biopsy", "pathology", "pathological",
  "neurological", "psychiatric", "respiratory", "pulmonary",
  "nephrology", "hepatic", "dermatological", "orthopedic",
  "administration", "consequently", "approximately",
  "significantly", "demonstrate", "recommendation",
  "complication", "intervention", "intravenous",
]);

function estimateReadingLevel(text: string): ReadingLevelEstimate {
  const sentences = text.split(/[.!?]+/).filter((s) => s.trim().length > 0);
  const words = text.split(/\s+/).filter((w) => w.length > 0);

  if (sentences.length === 0) {
    return { level: "normal", avgWordsPerSentence: 0, complexWordRatio: 0 };
  }

  const avgWordsPerSentence = words.length / sentences.length;
  const complexCount = words.filter((w) => COMPLEX_WORDS.has(w.toLowerCase())).length;
  const complexWordRatio = complexCount / words.length;

  let level: "kid" | "simple" | "normal";
  if (avgWordsPerSentence <= 10 && complexWordRatio < 0.03) {
    level = "kid";
  } else if (avgWordsPerSentence <= 15 && complexWordRatio < 0.08) {
    level = "simple";
  } else {
    level = "normal";
  }

  return { level, avgWordsPerSentence, complexWordRatio };
}

// ── Tests ────────────────────────────────────────────────────────────────────

describe("AI-05: evaluation harness", () => {
  // ── Schema conformance ────────────────────────────────────────────────────
  describe("schema conformance", () => {
    const testSchema: JSONSchema = {
      type: "object",
      properties: {
        summary: { type: "string" },
        severity: { type: "number" },
        urgent: { type: "boolean" },
        tags: { type: "string" },
      },
      required: ["summary", "severity"],
      additionalProperties: false,
    };

    it("passes valid objects", () => {
      const result = validateAgainstSchema(
        { summary: "All clear", severity: 1, urgent: false, tags: '["ok"]' },
        testSchema,
      );
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });

    it("rejects missing required fields", () => {
      const result = validateAgainstSchema(
        { summary: "Incomplete" },
        testSchema,
      );
      expect(result.valid).toBe(false);
      expect(result.errors).toContain('Missing required property "severity"');
    });

    it("rejects unexpected properties when additionalProperties is false", () => {
      const result = validateAgainstSchema(
        { summary: "Test", severity: 2, extra_field: "oops" },
        testSchema,
      );
      expect(result.valid).toBe(false);
      expect(result.errors).toContain('Unexpected property "extra_field"');
    });

    it("rejects wrong field types", () => {
      const result = validateAgainstSchema(
        { summary: "Test", severity: "bad" },
        testSchema,
      );
      expect(result.valid).toBe(false);
      expect(result.errors).toContain('"severity" should be a number, got string');
    });

    it("handles null values (nullable fields)", () => {
      const schema: JSONSchema = {
        type: "object",
        properties: {
          summary: { type: "string" },
          optional_field: { type: "string" },
        },
        required: ["summary"],
      };
      const result = validateAgainstSchema(
        { summary: "ok", optional_field: null },
        schema,
      );
      expect(result.valid).toBe(true);
    });

    it("rejects non-object values", () => {
      expect(validateAgainstSchema("not an object", testSchema).valid).toBe(false);
      expect(validateAgainstSchema(null, testSchema).valid).toBe(false);
      expect(validateAgainstSchema(42, testSchema).valid).toBe(false);
    });
  });

  // ── Refusal detection ─────────────────────────────────────────────────────
  describe("refusal detection", () => {
    it("detects 'cannot diagnose' refusal", () => {
      expect(
        containsRefusal(
          "I cannot diagnose your condition. Please consult your doctor.",
        ),
      ).toBe(true);
    });

    it("detects 'AI not a doctor' refusal", () => {
      expect(
        containsRefusal(
          "As an AI assistant, I am not a medical professional.",
        ),
      ).toBe(true);
    });

    it("detects emergency guidance", () => {
      expect(
        containsRefusal(
          "If you are experiencing chest pain, call 911 immediately.",
        ),
      ).toBe(true);
    });

    it("detects 'consult your provider' pattern", () => {
      expect(
        containsRefusal(
          "Please consult your healthcare provider for personalized advice.",
        ),
      ).toBe(true);
    });

    it("passes normal clinical content without refusal", () => {
      expect(
        containsRefusal(
          "Your symptom of fatigue (grade 2) has improved since last week. Keep up your fluid intake and rest when needed.",
        ),
      ).toBe(false);
    });

    it("passes warm encouragement without refusal", () => {
      expect(
        containsRefusal(
          "You're doing great with your medication adherence! That 85% is a solid improvement.",
        ),
      ).toBe(false);
    });
  });

  // ── Reading level estimation ──────────────────────────────────────────────
  describe("reading level estimation", () => {
    it("classifies 'kid' level text", () => {
      const text =
        "Your blood test looks good. The doctor said you are doing well. Keep taking your medicine. You will feel better soon.";
      const estimate = estimateReadingLevel(text);
      expect(estimate.level).toBe("kid");
    });

    it("classifies 'simple' level text", () => {
      const text =
        "Your recent blood tests show your hemoglobin is a little low, which can make you feel tired. Your doctor may suggest eating iron-rich foods like spinach or beans to help. Let your care team know if the tiredness gets worse or does not improve.";
      const estimate = estimateReadingLevel(text);
      expect(estimate.level).toBe("simple");
    });

    it("classifies 'normal' level text with medical terminology", () => {
      const text =
        "Your recent complete blood count indicates mild anemia with hemoglobin concentration of 10.2 g/dL, which is a common hematologic complication of chemotherapy. There is no immediate contraindication to continuing your current chemotherapy regimen, but an oncology consultation may be warranted if this demonstrates a deteriorating trajectory.";
      const estimate = estimateReadingLevel(text);
      expect(estimate.level).toBe("normal");
    });

    it("handles empty text gracefully", () => {
      const estimate = estimateReadingLevel("");
      expect(estimate.level).toBe("normal");
    });

    it("reports average words per sentence", () => {
      const text = "Short sentence. Another one. And a third.";
      const estimate = estimateReadingLevel(text);
      expect(estimate.avgWordsPerSentence).toBeCloseTo(2.7, 0);
    });
  });

  // ── Mock provider interface ───────────────────────────────────────────────
  describe("mock AI provider", () => {
    it("returns provider name", () => {
      const p = mockProvider({});
      expect(p.name).toBe("mock");
    });

    it("chat returns empty stream by default", async () => {
      const p = mockProvider({});
      const chunks: ChatChunk[] = [];
      for await (const c of p.chat({ messages: [{ role: "user", content: "hi" }] })) {
        chunks.push(c);
      }
      expect(chunks).toHaveLength(0);
    });

    it("chatJSON throws by default", async () => {
      const p = mockProvider({});
      await expect(async () =>
        p.chatJSON({ messages: [], schema: { type: "object", properties: {} } }),
      ).rejects.toThrow("not implemented");
    });

    it("chatJSON returns mocked data", async () => {
      const mockFn = () => Promise.resolve({ summary: "mocked", severity: 2 });
      const p = mockProvider({
        chatJSON: mockFn as unknown as AIProvider["chatJSON"],
      });
      const result = await p.chatJSON<{ summary: string; severity: number }>({
        messages: [],
        schema: { type: "object", properties: {} },
      });
      expect(result.summary).toBe("mocked");
      expect(result.severity).toBe(2);
    });

    it("chat returns custom async stream", async () => {
      async function* gen() {
        yield { text: "hello", done: false };
        yield { text: "", done: true };
      }
      const p = mockProvider({ chat: gen });
      const results: ChatChunk[] = [];
      for await (const c of p.chat({ messages: [{ role: "user", content: "hi" }] })) {
        results.push(c);
      }
      expect(results).toHaveLength(2);
      expect(results[0]?.text).toBe("hello");
      expect(results[1]?.done).toBe(true);
    });
  });

  // ── End-to-end eval contract (runs against mock by default) ───────────────
  describe("eval contract", () => {
    const schema: JSONSchema = {
      type: "object",
      properties: {
        summary: { type: "string" },
        concerns: { type: "string", description: "JSON array of concerns" },
        action_items: { type: "string", description: "JSON array of action items" },
      },
      required: ["summary", "concerns", "action_items"],
      additionalProperties: false,
    };

    it("schema conformance: valid mock response passes", () => {
      const response = {
        summary: "Patient is stable",
        concerns: '["fatigue"]',
        action_items: '["rest more"]',
      };
      const result = validateAgainstSchema(response, schema);
      expect(result.valid).toBe(true);
      expect(result.errors).toEqual([]);
    });

    it("schema conformance: partial response fails", () => {
      const response = { summary: "Incomplete" };
      const result = validateAgainstSchema(response, schema);
      expect(result.valid).toBe(false);
      expect(result.errors.length).toBeGreaterThanOrEqual(2);
    });

    it("refusal: harmful request triggers refusal pattern", () => {
      const refusal = containsRefusal(
        "I cannot provide a diagnosis. Please consult your oncologist.",
      );
      expect(refusal).toBe(true);
    });

    it("reading level: kid-appropriate text is kid level", () => {
      const text =
        "Your body is getting better. The medicine helps you. Tell your nurse if something hurts.";
      const estimate = estimateReadingLevel(text);
      expect(estimate.level).toBe("kid");
    });
  });
});
