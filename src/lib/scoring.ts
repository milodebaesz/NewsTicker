import { getSettings } from "./settings";
import { getProfile } from "./profile";
import type { FeedItem } from "./types";

export interface Score {
  relevance: number;
  reason: string;
  topic: string;
}

// Vaste, nette onderwerpen zodat de filterchips consistent blijven.
const TOPICS = [
  "Tech & AI",
  "Politiek",
  "Economie",
  "Wetenschap",
  "Gezondheid",
  "Sport",
  "Cultuur",
  "Wereld",
  "Overig",
];

// Scoort één batch items (max ~25) in één OpenAI-call.
export async function scoreBatch(items: FeedItem[]): Promise<Map<string, Score>> {
  const result = new Map<string, Score>();
  const settings = await getSettings();
  if (!settings.openaiKey || items.length === 0) return result;

  const profile = await getProfile();
  const batch = items.slice(0, 25);
  const payload = batch.map((it, i) => ({
    i,
    bron: it.sourceLabel,
    titel: it.title,
    samenvatting: it.summary.slice(0, 200),
  }));

  const system = `Je bent een persoonlijke nieuws-curator. Beoordeel hoe relevant elk item is voor deze gebruiker (0-100) en deel het in bij één onderwerp.

Profiel: ${profile.description}
Interesses: ${profile.keywords.join(", ")}
Niet interessant: ${profile.mute.join(", ")}

Kies "topic" uit precies deze lijst: ${TOPICS.join(", ")}.

Geef ALLEEN JSON terug in dit formaat:
{"scores":[{"i":0,"relevance":85,"reason":"korte reden, max 8 woorden","topic":"Tech & AI"}]}`;

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${settings.openaiKey}`,
    },
    body: JSON.stringify({
      model: settings.model || "gpt-4o-mini",
      temperature: 0.2,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: JSON.stringify(payload) },
      ],
    }),
  });

  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`OpenAI-fout (${res.status}): ${txt.slice(0, 200)}`);
  }

  const data = await res.json();
  const content = data.choices?.[0]?.message?.content ?? "{}";
  const parsed = JSON.parse(content) as {
    scores?: Array<{ i: number; relevance: number; reason: string; topic?: string }>;
  };

  for (const sc of parsed.scores ?? []) {
    const it = batch[sc.i];
    if (!it) continue;
    const topic = TOPICS.includes(sc.topic ?? "") ? (sc.topic as string) : it.topic || "Overig";
    result.set(it.id, {
      relevance: Math.max(0, Math.min(100, Math.round(sc.relevance ?? 0))),
      reason: String(sc.reason ?? "").slice(0, 80),
      topic,
    });
  }
  return result;
}
