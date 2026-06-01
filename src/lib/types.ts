export type SourceType = "rss" | "mail" | "calendar";

export interface Settings {
  openaiKey: string;
  model: string;
  refreshMinutes: number;
  minRelevance: number; // 0-100, items hieronder worden verborgen (alleen als scoring aan staat)
  scoringEnabled: boolean;
  protonEnabled: boolean; // Proton Mail via lokaal helper-servertje (Bridge)
  protonUrl: string; // bv. http://127.0.0.1:8910
  protonToken: string; // gedeelde sleutel met de helper
}

export interface Source {
  id: string;
  url: string;
  label: string;
  enabled: boolean;
}

export interface InterestProfile {
  description: string; // vrije tekst: waar ben ik in geïnteresseerd
  keywords: string[];
  mute: string[];
}

export interface FeedItem {
  id: string; // stabiele hash van de url
  sourceType: SourceType;
  sourceLabel: string;
  title: string;
  summary: string;
  image: string; // thumbnail-URL uit de feed, "" als geen
  topic: string; // onderwerp — uit feed-categorie, verfijnd door AI
  url: string;
  publishedAt: string; // ISO
  relevance: number | null; // 0-100, null = nog niet gescoord
  reason: string;
  read: boolean;
  dismissed: boolean;
  fetchedAt: string; // ISO
}
