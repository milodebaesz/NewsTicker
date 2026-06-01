import type { FeedItem, Settings } from "./types";

interface ProtonMail {
  uid: number;
  from: string;
  subject: string;
  date: string;
  unread: boolean;
  preview: string;
}

export function protonConfigured(s: Settings): boolean {
  return s.protonEnabled && !!s.protonUrl && !!s.protonToken;
}

function base(s: Settings): string {
  return s.protonUrl.replace(/\/+$/, "");
}

// Haalt mail op uit het lokale helper-servertje (dat met Proton Bridge praat).
export async function fetchProtonMail(s: Settings, max = 20): Promise<FeedItem[]> {
  const res = await fetch(`${base(s)}/mail?max=${max}`, {
    headers: { "x-nt-token": s.protonToken },
  });
  if (!res.ok) throw new Error(`Proton-helper: HTTP ${res.status}`);
  const data = (await res.json()) as { items?: ProtonMail[] };
  const now = new Date().toISOString();

  return (data.items ?? []).map((m) => ({
    id: `proton_${m.uid}`,
    sourceType: "mail",
    sourceLabel: m.from || "Proton Mail",
    title: m.subject || "(geen onderwerp)",
    summary: m.preview || "",
    image: "",
    topic: "Mail",
    url: "https://mail.proton.me/u/0/inbox",
    publishedAt: m.date || now,
    relevance: null,
    reason: "",
    read: false,
    dismissed: false,
    fetchedAt: now,
  }));
}

// Markeert een Proton-mail als gelezen (zet \Seen via de helper).
export async function markProtonRead(s: Settings, itemId: string): Promise<void> {
  const uid = Number(itemId.replace(/^proton_/, ""));
  await fetch(`${base(s)}/mark-read`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-nt-token": s.protonToken },
    body: JSON.stringify({ uid }),
  });
}
