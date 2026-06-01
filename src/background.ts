import { getSources } from "./lib/sources";
import { fetchRss } from "./lib/rss";
import { getItems, upsertItems, patchItems, pruneOld } from "./lib/feed";
import { scoreBatch } from "./lib/scoring";
import { getSettings } from "./lib/settings";
import { isConnected, connect, disconnect } from "./lib/google";
import { fetchMail, markMailRead } from "./lib/gmail";
import { fetchProtonMail, markProtonRead, protonConfigured } from "./lib/proton";
import { fetchCalendar } from "./lib/calendar";
import type { FeedItem } from "./lib/types";

const ALARM = "nt_refresh";

async function refresh(): Promise<void> {
  const sources = (await getSources()).filter((s) => s.enabled);
  const collected: FeedItem[] = [];
  const errors: string[] = [];

  for (const src of sources) {
    try {
      collected.push(...(await fetchRss(src)));
    } catch (e) {
      console.warn("RSS-fout", src.label, e);
      errors.push(`${src.label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  // Gmail + Agenda, alleen als de gebruiker Google heeft gekoppeld.
  if (await isConnected()) {
    try {
      collected.push(...(await fetchMail()));
    } catch (e) {
      console.warn("Gmail-fout", e);
      errors.push(`Gmail: ${e instanceof Error ? e.message : String(e)}`);
    }
    try {
      collected.push(...(await fetchCalendar()));
    } catch (e) {
      console.warn("Agenda-fout", e);
      errors.push(`Agenda: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  // Proton Mail via het lokale helper-servertje (onafhankelijk van Google).
  const settings = await getSettings();
  if (protonConfigured(settings)) {
    try {
      collected.push(...(await fetchProtonMail(settings)));
    } catch (e) {
      console.warn("Proton-fout", e);
      errors.push(`Proton: ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  await upsertItems(collected);
  await backfillImages();
  await rescore();
  await pruneOld();
  await chrome.storage.local.set({
    nt_lastRefresh: Date.now(),
    nt_lastError: errors.join(" · "),
  });
}

// Haalt de og:image van de artikelpagina op voor items zonder feed-afbeelding.
async function fetchOgImage(url: string): Promise<string> {
  try {
    const res = await fetch(url, { cache: "no-store" });
    if (!res.ok) return "";
    const html = (await res.text()).slice(0, 250_000); // <head> ruim genoeg
    const patterns = [
      /<meta[^>]+property=["']og:image(?::secure_url)?["'][^>]+content=["']([^"']+)["']/i,
      /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i,
      /<meta[^>]+name=["']twitter:image["'][^>]+content=["']([^"']+)["']/i,
    ];
    for (const re of patterns) {
      const m = html.match(re);
      if (m?.[1]) return m[1].replace(/&amp;/g, "&");
    }
  } catch {
    /* stil falen — gewoon geen afbeelding */
  }
  return "";
}

// Vult ontbrekende afbeeldingen aan (max 14 per ronde om het licht te houden).
async function backfillImages(): Promise<void> {
  const missing = (await getItems())
    .filter((i) => i.sourceType === "rss" && !i.image && !i.dismissed)
    .slice(0, 14);
  const patches = new Map<string, Partial<FeedItem>>();
  for (const it of missing) {
    const img = await fetchOgImage(it.url);
    if (img) patches.set(it.id, { image: img });
  }
  await patchItems(patches);
}

// Scoort items die nog geen relevantie hebben (max 3 batches per ronde).
async function rescore(): Promise<void> {
  const settings = await getSettings();
  if (!settings.scoringEnabled || !settings.openaiKey) return;

  // Alleen nieuws scoren; mail/agenda blijven lokaal — niet naar OpenAI.
  const unscored = (await getItems()).filter(
    (i) => i.sourceType === "rss" && i.relevance === null && !i.dismissed
  );
  for (let n = 0; n < 3 && unscored.length > 0; n++) {
    const batch = unscored.splice(0, 25);
    try {
      const scores = await scoreBatch(batch);
      const patches = new Map(
        [...scores].map(([id, s]) => [id, { relevance: s.relevance, reason: s.reason, topic: s.topic }])
      );
      await patchItems(patches);
    } catch (e) {
      console.warn("Scoring-fout", e);
      await chrome.storage.local.set({
        nt_lastError: e instanceof Error ? e.message : String(e),
      });
      break;
    }
  }
}

async function setupAlarm(): Promise<void> {
  const { refreshMinutes } = await getSettings();
  await chrome.alarms.create(ALARM, { periodInMinutes: Math.max(5, refreshMinutes) });
}

chrome.runtime.onInstalled.addListener(async () => {
  await setupAlarm();
  await refresh();
});

chrome.runtime.onStartup.addListener(async () => {
  await setupAlarm();
  await refresh();
});

chrome.alarms.onAlarm.addListener((a) => {
  if (a.name === ALARM) void refresh();
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "refresh") {
    refresh()
      .then(() => sendResponse({ ok: true }))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }
  if (msg?.type === "setupAlarm") {
    setupAlarm().then(() => sendResponse({ ok: true }));
    return true;
  }
  if (msg?.type === "connectGoogle") {
    connect()
      .then((ok) => refresh().then(() => sendResponse({ ok })))
      .catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }
  if (msg?.type === "disconnectGoogle") {
    disconnect().then(() => sendResponse({ ok: true }));
    return true;
  }
  if (msg?.type === "markRead" && typeof msg.id === "string") {
    const id = msg.id as string;
    // mail ook bij de bron als gelezen markeren (Gmail of Proton)
    const done = id.startsWith("mail_")
      ? markMailRead(id)
      : id.startsWith("proton_")
        ? getSettings().then((s) => markProtonRead(s, id))
        : Promise.resolve();
    done.catch((e) => console.warn("markRead:", e)).finally(() => sendResponse({ ok: true }));
    return true;
  }
  return false;
});
