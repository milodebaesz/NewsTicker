import { XMLParser } from "fast-xml-parser";
import type { FeedItem, Source } from "./types";

// fast-xml-parser werkt zonder DOM, dus bruikbaar in de service worker
// (waar DOMParser niet bestaat).
const parser = new XMLParser({ ignoreAttributes: false, attributeNamePrefix: "@_" });

function hashId(s: string): string {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return "i" + (h >>> 0).toString(36);
}

// fast-xml-parser geeft tekst soms als string, soms als { "#text": ... }.
function text(x: unknown): string {
  if (x == null) return "";
  if (typeof x === "string") return x;
  if (typeof x === "number") return String(x);
  if (typeof x === "object" && "#text" in (x as Record<string, unknown>)) {
    return String((x as Record<string, unknown>)["#text"] ?? "");
  }
  return "";
}

function stripHtml(s: string): string {
  return s
    .replace(/<[^>]*>/g, " ")
    .replace(/&[a-z#0-9]+;/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function asArray<T>(x: T | T[] | undefined): T[] {
  if (x === undefined || x === null) return [];
  return Array.isArray(x) ? x : [x];
}

function toIso(raw: unknown): string {
  const s = text(raw) || String(raw ?? "");
  const d = new Date(s);
  return isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

// Eerste categorie uit het item (RSS <category>tekst</category> of
// Atom <category term="..."/>), opgeschoond tot een leesbaar onderwerp.
function firstTopic(node: Record<string, unknown>): string {
  for (const c of asArray<Record<string, unknown> | string>(node.category as never)) {
    const raw =
      typeof c === "string"
        ? c
        : text(c) || text(c?.["@_term"]) || text(c?.["@_label"]);
    if (raw) {
      const first = raw.split("/")[0].replace(/[-_]+/g, " ").trim();
      if (first) return first.charAt(0).toUpperCase() + first.slice(1);
    }
  }
  return "";
}

const IMG_EXT = /\.(jpe?g|png|webp|gif|avif)(\?|$)/i;

// Probeert een afbeelding te vinden via de gangbare RSS/Atom-velden,
// anders de eerste <img> uit de HTML-inhoud.
function pickImage(node: Record<string, unknown>, html: string): string {
  // <enclosure url=... type="image/...">
  for (const e of asArray<Record<string, unknown>>(node.enclosure as never)) {
    const url = text(e?.["@_url"]);
    const type = text(e?.["@_type"]);
    if (url && (type.startsWith("image") || IMG_EXT.test(url))) return url;
  }
  // <media:content> / <media:thumbnail>
  for (const key of ["media:content", "media:thumbnail", "media:group"]) {
    for (const m of asArray<Record<string, unknown>>(node[key] as never)) {
      const url = text(m?.["@_url"]);
      const medium = text(m?.["@_medium"]);
      const type = text(m?.["@_type"]);
      if (url && (medium === "image" || type.startsWith("image") || IMG_EXT.test(url) || !medium)) {
        return url;
      }
      // media:group bevat soms geneste media:content
      const nested = asArray<Record<string, unknown>>(m?.["media:content"] as never);
      for (const n of nested) {
        const nu = text(n?.["@_url"]);
        if (nu) return nu;
      }
    }
  }
  // eerste <img src="..."> in de beschrijving/inhoud
  const m = html.match(/<img[^>]+src=["']([^"']+)["']/i);
  if (m) return m[1];
  return "";
}

export async function fetchRss(source: Source): Promise<FeedItem[]> {
  const res = await fetch(source.url, { cache: "no-store" });
  if (!res.ok) throw new Error(`${source.label}: HTTP ${res.status}`);
  const xml = await res.text();
  const doc = parser.parse(xml);
  const now = new Date().toISOString();
  const out: FeedItem[] = [];

  // RSS 2.0 / RDF
  const rssItems = [
    ...asArray<Record<string, unknown>>(doc?.rss?.channel?.item),
    ...asArray<Record<string, unknown>>(doc?.["rdf:RDF"]?.item),
  ];
  for (const it of rssItems) {
    const linkRaw = it.link as unknown;
    const link =
      typeof linkRaw === "string"
        ? linkRaw
        : text((linkRaw as Record<string, unknown>)?.["@_href"]) || text(linkRaw);
    const title = stripHtml(text(it.title));
    if (!link || !title) continue;
    const rawHtml = text(it["content:encoded"]) || text(it.description);
    out.push({
      id: hashId(link),
      sourceType: "rss",
      sourceLabel: source.label,
      title,
      summary: stripHtml(text(it.description) || rawHtml).slice(0, 400),
      image: pickImage(it, rawHtml),
      topic: firstTopic(it),
      url: link,
      publishedAt: it.pubDate || it["dc:date"] ? toIso(it.pubDate ?? it["dc:date"]) : now,
      relevance: null,
      reason: "",
      read: false,
      dismissed: false,
      fetchedAt: now,
    });
  }

  // Atom
  for (const e of asArray<Record<string, unknown>>(doc?.feed?.entry)) {
    const links = asArray<Record<string, unknown> | string>(e.link as never);
    const alt =
      links.find((l) => typeof l === "object" && (l as Record<string, unknown>)["@_rel"] === "alternate") ??
      links[0];
    const href = typeof alt === "string" ? alt : text((alt as Record<string, unknown>)?.["@_href"]);
    const title = stripHtml(text(e.title));
    if (!href || !title) continue;
    const rawHtml = text(e.content) || text(e.summary);
    out.push({
      id: hashId(href),
      sourceType: "rss",
      sourceLabel: source.label,
      title,
      summary: stripHtml(text(e.summary) || rawHtml).slice(0, 400),
      image: pickImage(e, rawHtml),
      topic: firstTopic(e),
      url: href,
      publishedAt: toIso(e.published ?? e.updated ?? now),
      relevance: null,
      reason: "",
      read: false,
      dismissed: false,
      fetchedAt: now,
    });
  }

  return out;
}
