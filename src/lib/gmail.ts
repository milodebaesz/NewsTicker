import { apiFetch } from "./google";
import type { FeedItem } from "./types";

const BASE = "https://gmail.googleapis.com/gmail/v1/users/me";

interface GmailListResp {
  messages?: { id: string; threadId: string }[];
}
interface GmailPart {
  mimeType?: string;
  body?: { data?: string; size?: number };
  parts?: GmailPart[];
}
interface GmailMsg {
  id: string;
  internalDate?: string;
  snippet?: string;
  payload?: GmailPart & { headers?: { name: string; value: string }[] };
}

function header(msg: GmailMsg, name: string): string {
  return msg.payload?.headers?.find((h) => h.name.toLowerCase() === name.toLowerCase())?.value ?? "";
}

// Gmail levert de body base64url-gecodeerd aan.
function decodeBody(data: string): string {
  try {
    const bin = atob(data.replace(/-/g, "+").replace(/_/g, "/"));
    const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
    return new TextDecoder("utf-8").decode(bytes);
  } catch {
    return "";
  }
}

// Eerste deel met dit mime-type, ook in geneste multipart-structuren.
function findPart(part: GmailPart, mime: string): GmailPart | null {
  if (part.mimeType === mime && part.body?.data) return part;
  for (const p of part.parts ?? []) {
    const found = findPart(p, mime);
    if (found) return found;
  }
  return null;
}

function stripHtml(html: string): string {
  return html
    .replace(/<style[\s\S]*?<\/style>/gi, "")
    .replace(/<script[\s\S]*?<\/script>/gi, "")
    .replace(/<\/(p|div|tr|h[1-6]|li)>/gi, "\n")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#39;/g, "'")
    .replace(/&quot;/gi, '"');
}

// De eerste 20 niet-lege regels van de mailtekst (text/plain bij voorkeur,
// anders HTML ontdaan van opmaak, anders de snippet als laatste redmiddel).
function bodyPreview(msg: GmailMsg): string {
  let text = "";
  const payload = msg.payload;
  if (payload) {
    const plain = findPart(payload, "text/plain");
    if (plain?.body?.data) text = decodeBody(plain.body.data);
    if (!text) {
      const html = findPart(payload, "text/html");
      if (html?.body?.data) text = stripHtml(decodeBody(html.body.data));
    }
  }
  if (!text) text = msg.snippet ?? "";

  const lines = text
    .replace(/\r/g, "")
    .replace(/ /g, " ")
    .split("\n")
    .map((l) => l.replace(/[ \t]+$/g, ""));

  // verwijder lege regels aan het begin
  while (lines.length && !lines[0].trim()) lines.shift();

  // pak de eerste 20 regels en plet reeksen lege regels tot één
  const out: string[] = [];
  let blank = 0;
  for (const l of lines) {
    const isBlank = l.trim() === "";
    if (isBlank) {
      blank++;
      if (blank > 1) continue;
    } else {
      blank = 0;
    }
    out.push(isBlank ? "" : l.trim());
    if (out.length >= 20) break;
  }
  return out.join("\n").trim();
}

async function listMessages(query: string, max: number): Promise<{ id: string }[]> {
  const res = await apiFetch(`${BASE}/messages?maxResults=${max}&q=${encodeURIComponent(query)}`);
  if (!res.ok) throw new Error(`Gmail: HTTP ${res.status}`);
  const data = (await res.json()) as GmailListResp;
  return data.messages ?? [];
}

// Haalt mail uit de inbox als FeedItems. Eerst ongelezen; is alles gelezen,
// dan de recentste inbox-mail zodat het vak niet onterecht leeg blijft.
// (Geen `category:primary` — dat matcht niets als Gmail-tabbladen uit staan.)
export async function fetchMail(max = 20): Promise<FeedItem[]> {
  let ids = await listMessages("is:unread in:inbox", max);
  if (ids.length === 0) ids = await listMessages("in:inbox", max);
  const now = new Date().toISOString();

  const items = await Promise.all(
    ids.map(async ({ id }): Promise<FeedItem | null> => {
      const r = await apiFetch(`${BASE}/messages/${id}?format=full`);
      if (!r.ok) return null;
      const msg = (await r.json()) as GmailMsg;
      const fromRaw = header(msg, "From");
      const from = fromRaw.replace(/<[^>]+>/, "").replace(/"/g, "").trim() || fromRaw;
      const subject = header(msg, "Subject") || "(geen onderwerp)";
      const published = msg.internalDate
        ? new Date(Number(msg.internalDate)).toISOString()
        : now;
      return {
        id: `mail_${id}`,
        sourceType: "mail",
        sourceLabel: from,
        title: subject,
        summary: bodyPreview(msg),
        image: "",
        topic: "Mail",
        url: `https://mail.google.com/mail/u/0/#inbox/${id}`,
        publishedAt: published,
        relevance: null,
        reason: "",
        read: false,
        dismissed: false,
        fetchedAt: now,
      };
    })
  );

  return items.filter((i): i is FeedItem => i !== null);
}

// Markeert een mail als gelezen in Gmail zelf (verwijdert het UNREAD-label).
export async function markMailRead(itemId: string): Promise<void> {
  const id = itemId.replace(/^mail_/, "");
  await apiFetch(`${BASE}/messages/${id}/modify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ removeLabelIds: ["UNREAD"] }),
  });
}
