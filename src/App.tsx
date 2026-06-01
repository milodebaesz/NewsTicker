import { useEffect, useMemo, useState } from "react";
import { Newspaper, RefreshCw, Search, Settings as Cog, X } from "lucide-react";
import { getItems } from "./lib/feed";
import { getSettings } from "./lib/settings";
import { timeAgo } from "./lib/format";
import type { FeedItem, Settings, SourceType } from "./lib/types";
import { Ticker } from "./components/Ticker";
import { FeedCard } from "./components/FeedCard";
import { MailPanel } from "./components/MailPanel";
import { SettingsView } from "./components/SettingsView";

type Filter = "all" | SourceType;

const FILTERS: { key: Filter; label: string }[] = [
  { key: "all", label: "Alles" },
  { key: "rss", label: "Nieuws" },
  { key: "mail", label: "Mail" },
  { key: "calendar", label: "Agenda" },
];

// Herhalend bento-ritme: groot vierkant, breed, hoog, en gewone tegels.
const BENTO_PATTERN = [
  "col-span-2 row-span-2",
  "col-span-1 row-span-1",
  "col-span-1 row-span-1",
  "col-span-2 row-span-1",
  "col-span-1 row-span-2",
  "col-span-1 row-span-1",
  "col-span-1 row-span-1",
  "col-span-2 row-span-1",
];
const bentoSpan = (i: number) => BENTO_PATTERN[i % BENTO_PATTERN.length];

export function App() {
  const [items, setItems] = useState<FeedItem[]>([]);
  const [settings, setSettings] = useState<Settings | null>(null);
  const [lastRefresh, setLastRefresh] = useState<number | null>(null);
  const [lastError, setLastError] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [topic, setTopic] = useState<string>("");
  const [query, setQuery] = useState("");
  const [showSettings, setShowSettings] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  async function load() {
    setItems(await getItems());
    setSettings(await getSettings());
    const meta = await chrome.storage.local.get(["nt_lastRefresh", "nt_lastError"]);
    setLastRefresh(meta.nt_lastRefresh ?? null);
    setLastError(meta.nt_lastError ?? "");
  }

  useEffect(() => {
    void load();
    const listener = (changes: Record<string, chrome.storage.StorageChange>, area: string) => {
      if (area === "local" && (changes.nt_items || changes.nt_lastRefresh)) void load();
    };
    chrome.storage.onChanged.addListener(listener);
    return () => chrome.storage.onChanged.removeListener(listener);
  }, []);

  async function refresh() {
    setRefreshing(true);
    try {
      await chrome.runtime.sendMessage({ type: "refresh" });
    } finally {
      setRefreshing(false);
      await load();
    }
  }

  const scoring = settings?.scoringEnabled ?? false;
  const minRel = settings?.minRelevance ?? 0;

  // Items die door bron-filter, zoekterm en relevantiedrempel komen
  // (nog vóór het onderwerp-filter, zodat de chips de juiste opties tonen).
  const preTopic = useMemo(() => {
    const q = query.trim().toLowerCase();
    return items.filter((i) => {
      if (i.dismissed || i.read) return false;
      if (filter !== "all" && i.sourceType !== filter) return false;
      if (scoring && i.relevance !== null && i.relevance < minRel) return false;
      if (q) {
        const hay = `${i.title} ${i.summary} ${i.sourceLabel} ${i.topic}`.toLowerCase();
        if (!hay.includes(q)) return false;
      }
      return true;
    });
  }, [items, filter, scoring, minRel, query]);

  const topics = useMemo(() => {
    const counts = new Map<string, number>();
    for (const i of preTopic) {
      if (i.topic) counts.set(i.topic, (counts.get(i.topic) ?? 0) + 1);
    }
    return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12);
  }, [preTopic]);

  const visible = useMemo(() => {
    const v = preTopic.filter((i) => !topic || i.topic === topic);
    // Volgorde per bron zodat mail/agenda nooit onder gescoorde nieuwsitems
    // verdwijnen: agenda eerst (komt eraan), dan mail, dan nieuws.
    const rank = (t: string) => (t === "calendar" ? 0 : t === "mail" ? 1 : 2);
    v.sort((a, b) => {
      const dr = rank(a.sourceType) - rank(b.sourceType);
      if (dr !== 0) return dr;
      // agenda: op starttijd oplopend (eerstvolgende boven)
      if (a.sourceType === "calendar") {
        return new Date(a.publishedAt).getTime() - new Date(b.publishedAt).getTime();
      }
      // nieuws: op relevantie als scoring aan staat
      const ra = a.relevance ?? -1;
      const rb = b.relevance ?? -1;
      if (scoring && a.sourceType === "rss" && ra !== rb) return rb - ra;
      return new Date(b.publishedAt).getTime() - new Date(a.publishedAt).getTime();
    });
    return v;
  }, [preTopic, topic, scoring]);

  // Mail krijgt een eigen inklapbaar vak; de overige items vullen de bento-grid.
  const mailItems = useMemo(() => visible.filter((i) => i.sourceType === "mail"), [visible]);
  const gridItems = useMemo(
    () => visible.filter((i) => i.sourceType !== "mail"),
    [visible]
  );

  const tickerItems = useMemo(
    () =>
      [...items]
        .filter((i) => !i.dismissed && !i.read)
        .sort((a, b) => (b.relevance ?? 0) - (a.relevance ?? 0))
        .slice(0, 20),
    [items]
  );

  if (showSettings) {
    return (
      <div className="min-h-full">
        <SettingsView onClose={() => void (setShowSettings(false), load())} />
      </div>
    );
  }

  return (
    <div className="mx-auto min-h-full max-w-6xl">
      <header className="flex items-center gap-3 px-6 pt-8 pb-4">
        <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-brand text-white">
          <Newspaper className="h-5 w-5" />
        </div>
        <h1 className="text-2xl font-semibold tracking-tight text-ink">Newsticker</h1>
        <span className="text-sm text-muted">
          {lastRefresh
            ? `bijgewerkt ${timeAgo(new Date(lastRefresh).toISOString())} geleden`
            : "nog niet bijgewerkt"}
        </span>
        <div className="ml-auto flex items-center gap-2">
          <button
            onClick={refresh}
            disabled={refreshing}
            className="inline-flex items-center gap-2 rounded-lg border border-line bg-card px-3 py-2 text-sm text-ink-soft shadow-sm hover:bg-subtle disabled:opacity-50"
          >
            <RefreshCw className={`h-4 w-4 ${refreshing ? "animate-spin" : ""}`} />
            Verversen
          </button>
          <button
            onClick={() => setShowSettings(true)}
            className="inline-flex items-center justify-center rounded-lg border border-line bg-card p-2 text-ink-soft shadow-sm hover:bg-subtle"
            title="Instellingen"
          >
            <Cog className="h-4 w-4" />
          </button>
        </div>
      </header>

      <Ticker items={tickerItems} />

      {/* Bron-filters + zoekbalk */}
      <div className="flex flex-wrap items-center gap-2 px-6 pt-5">
        <nav className="flex gap-1">
          {FILTERS.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`rounded-lg px-3 py-1.5 text-sm font-medium transition ${
                filter === f.key
                  ? "bg-brand text-white shadow-sm"
                  : "text-muted hover:bg-subtle hover:text-ink-soft"
              }`}
            >
              {f.label}
            </button>
          ))}
        </nav>
        <div className="relative ml-auto">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Zoeken…"
            className="w-56 rounded-lg border border-line bg-card py-2 pl-9 pr-8 text-sm text-ink shadow-sm outline-none focus:border-brand focus:ring-2 focus:ring-brand/20"
          />
          {query && (
            <button
              onClick={() => setQuery("")}
              className="absolute right-2 top-1/2 -translate-y-1/2 text-muted hover:text-ink-soft"
            >
              <X className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>

      {/* Onderwerp-chips */}
      {topics.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-6 pt-3">
          <button
            onClick={() => setTopic("")}
            className={`rounded-full px-3 py-1 text-xs font-medium transition ${
              topic === ""
                ? "bg-ink text-white"
                : "border border-line text-muted hover:bg-subtle hover:text-ink-soft"
            }`}
          >
            Alle onderwerpen
          </button>
          {topics.map(([t, n]) => (
            <button
              key={t}
              onClick={() => setTopic(topic === t ? "" : t)}
              className={`rounded-full px-3 py-1 text-xs font-medium transition ${
                topic === t
                  ? "bg-ink text-white"
                  : "border border-line text-muted hover:bg-subtle hover:text-ink-soft"
              }`}
            >
              {t} <span className="opacity-60">{n}</span>
            </button>
          ))}
        </div>
      )}

      {lastError && (
        <p className="mx-6 mt-4 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-600">
          {lastError}
        </p>
      )}

      {/* Mail — alleen telling op het overzicht, uitklappen toont de berichten */}
      {mailItems.length > 0 && (
        <MailPanel key={filter} items={mailItems} defaultOpen={filter === "mail"} />
      )}

      {/* Bento-grid — tegels van wisselende formaten */}
      {gridItems.length > 0 && (
        <div className="grid auto-rows-[185px] grid-flow-row-dense grid-cols-2 gap-4 px-6 py-5 md:grid-cols-3 lg:grid-cols-4">
          {gridItems.map((item, i) => (
            <FeedCard key={item.id} item={item} span={bentoSpan(i)} />
          ))}
        </div>
      )}

      {gridItems.length === 0 && mailItems.length === 0 && (
        <div className="px-6 py-20 text-center text-muted">
          <p>Geen items.</p>
          <p className="mt-1 text-sm">
            {query || topic ? (
              <button
                onClick={() => {
                  setQuery("");
                  setTopic("");
                }}
                className="text-brand underline"
              >
                Filters wissen
              </button>
            ) : (
              <>
                Klik op <span className="text-ink-soft">Verversen</span> of voeg bronnen toe via{" "}
                <button onClick={() => setShowSettings(true)} className="text-brand underline">
                  instellingen
                </button>
                .
              </>
            )}
          </p>
        </div>
      )}
    </div>
  );
}
