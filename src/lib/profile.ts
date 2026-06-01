import type { InterestProfile } from "./types";

const KEY = "nt_profile";

const DEFAULT: InterestProfile = {
  description:
    "Ik ben softwareontwikkelaar en bouw web-apps met React, Next.js, Supabase en AI/OpenAI. Ik volg tech, startups, AI-ontwikkelingen en de aandelenmarkt. Nederlandse en internationale actualiteit interesseert me ook.",
  keywords: ["AI", "OpenAI", "React", "Next.js", "Supabase", "startups", "beurs", "tech"],
  mute: ["sport", "showbizz"],
};

export async function getProfile(): Promise<InterestProfile> {
  const stored = await chrome.storage.local.get(KEY);
  return { ...DEFAULT, ...(stored[KEY] ?? {}) };
}

export async function saveProfile(profile: InterestProfile): Promise<void> {
  await chrome.storage.local.set({ [KEY]: profile });
}
