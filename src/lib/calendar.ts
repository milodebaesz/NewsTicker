import { apiFetch } from "./google";
import type { FeedItem } from "./types";

const BASE = "https://www.googleapis.com/calendar/v3/calendars/primary/events";

interface CalEvent {
  id: string;
  summary?: string;
  htmlLink?: string;
  location?: string;
  description?: string;
  start?: { dateTime?: string; date?: string };
}
interface CalResp {
  items?: CalEvent[];
}

function fmtWhen(ev: CalEvent): { iso: string; label: string } {
  const dt = ev.start?.dateTime ?? ev.start?.date ?? "";
  const d = new Date(dt);
  if (isNaN(d.getTime())) return { iso: new Date().toISOString(), label: "" };
  if (ev.start?.date) {
    // hele dag
    return { iso: d.toISOString(), label: d.toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "long" }) };
  }
  return {
    iso: d.toISOString(),
    label: d.toLocaleString("nl-NL", { weekday: "short", day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }),
  };
}

// Haalt komende afspraken (vanaf nu, komende 7 dagen) als FeedItems.
export async function fetchCalendar(max = 15): Promise<FeedItem[]> {
  const now = new Date();
  const week = new Date(now.getTime() + 7 * 86_400_000);
  const params = new URLSearchParams({
    timeMin: now.toISOString(),
    timeMax: week.toISOString(),
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: String(max),
  });
  const res = await apiFetch(`${BASE}?${params.toString()}`);
  if (!res.ok) throw new Error(`Agenda: HTTP ${res.status}`);
  const data = (await res.json()) as CalResp;
  const nowIso = now.toISOString();

  return (data.items ?? []).map((ev): FeedItem => {
    const when = fmtWhen(ev);
    const extra = [ev.location, ev.description].filter(Boolean).join(" · ");
    return {
      id: `cal_${ev.id}`,
      sourceType: "calendar",
      sourceLabel: when.label || "Agenda",
      title: ev.summary || "(geen titel)",
      summary: extra.slice(0, 200),
      image: "",
      topic: "Agenda",
      url: ev.htmlLink || "https://calendar.google.com",
      publishedAt: when.iso, // = starttijd; agenda sorteren we apart
      relevance: null,
      reason: "",
      read: false,
      dismissed: false,
      fetchedAt: nowIso,
    };
  });
}
