import type { Source } from "./types";

const KEY = "nt_sources";

// Nederlandse + tech-bronnen als startpunt; pas ze aan in de instellingen.
const DEFAULTS: Source[] = [
  { id: "nos", url: "https://feeds.nos.nl/nosnieuwsalgemeen", label: "NOS", enabled: true },
  { id: "nu", url: "https://www.nu.nl/rss/Algemeen", label: "NU.nl", enabled: true },
  { id: "tweakers", url: "https://feeds.feedburner.com/tweakers/mixed", label: "Tweakers", enabled: true },
  { id: "verge", url: "https://www.theverge.com/rss/index.xml", label: "The Verge", enabled: true },
  { id: "hn", url: "https://hnrss.org/frontpage", label: "Hacker News", enabled: true },
];

export async function getSources(): Promise<Source[]> {
  const stored = await chrome.storage.local.get(KEY);
  if (stored[KEY]) return stored[KEY] as Source[];
  await chrome.storage.local.set({ [KEY]: DEFAULTS });
  return DEFAULTS;
}

export async function saveSources(sources: Source[]): Promise<void> {
  await chrome.storage.local.set({ [KEY]: sources });
}
