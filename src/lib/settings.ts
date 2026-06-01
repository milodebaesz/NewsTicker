import type { Settings } from "./types";

const KEY = "nt_settings";

const DEFAULTS: Settings = {
  openaiKey: "",
  model: "gpt-4o-mini",
  refreshMinutes: 15,
  minRelevance: 40,
  scoringEnabled: true,
  protonEnabled: false,
  protonUrl: "http://127.0.0.1:8910",
  protonToken: "",
};

export async function getSettings(): Promise<Settings> {
  const stored = await chrome.storage.local.get(KEY);
  return { ...DEFAULTS, ...(stored[KEY] ?? {}) };
}

export async function saveSettings(patch: Partial<Settings>): Promise<Settings> {
  const next = { ...(await getSettings()), ...patch };
  await chrome.storage.local.set({ [KEY]: next });
  return next;
}
