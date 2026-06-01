import type { FeedItem } from "./types";

const KEY = "nt_items";
const MAX_ITEMS = 500;
const MAX_AGE_DAYS = 7;

export async function getItems(): Promise<FeedItem[]> {
  const stored = await chrome.storage.local.get(KEY);
  return (stored[KEY] as FeedItem[]) ?? [];
}

async function setItems(items: FeedItem[]): Promise<void> {
  await chrome.storage.local.set({ [KEY]: items });
}

// Voegt nieuwe items toe en behoudt de lees-/verberg-/score-status van
// items die we al kenden (gematcht op id).
export async function upsertItems(incoming: FeedItem[]): Promise<void> {
  const existing = await getItems();
  const byId = new Map(existing.map((i) => [i.id, i]));
  for (const it of incoming) {
    const prev = byId.get(it.id);
    if (prev) {
      byId.set(it.id, {
        ...it,
        read: prev.read,
        dismissed: prev.dismissed,
        relevance: prev.relevance,
        reason: prev.reason,
        // bewaar het AI-onderwerp als dat er al is, anders de feed-categorie
        topic: prev.relevance !== null ? prev.topic : it.topic,
      });
    } else {
      byId.set(it.id, it);
    }
  }
  await setItems([...byId.values()]);
}

export async function updateItem(id: string, patch: Partial<FeedItem>): Promise<void> {
  const items = await getItems();
  await setItems(items.map((i) => (i.id === id ? { ...i, ...patch } : i)));
}

// Markeert lokaal als gelezen én laat de background een mail in Gmail
// als gelezen markeren (verwijdert daar het UNREAD-label).
export async function markRead(id: string): Promise<void> {
  await updateItem(id, { read: true });
  try {
    await chrome.runtime.sendMessage({ type: "markRead", id });
  } catch {
    /* background niet bereikbaar — lokaal is al bijgewerkt */
  }
}

// Past dezelfde patch toe op meerdere items in één schrijfactie.
export async function patchItems(patches: Map<string, Partial<FeedItem>>): Promise<void> {
  if (patches.size === 0) return;
  const items = await getItems();
  await setItems(items.map((i) => (patches.has(i.id) ? { ...i, ...patches.get(i.id) } : i)));
}

export async function pruneOld(): Promise<void> {
  const items = await getItems();
  const cutoff = Date.now() - MAX_AGE_DAYS * 86_400_000;
  let kept = items.filter(
    (i) => !i.dismissed && new Date(i.publishedAt).getTime() > cutoff
  );
  kept.sort((a, b) => new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime());
  if (kept.length > MAX_ITEMS) kept = kept.slice(0, MAX_ITEMS);
  await setItems(kept);
}
