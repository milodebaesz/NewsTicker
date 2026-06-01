// OAuth-helper rond chrome.identity. De token blijft op het device; we sturen
// 'm nooit ergens anders heen dan rechtstreeks naar Google's API's.

const CONNECTED_KEY = "nt_google_connected";

// Vraagt een token. interactive=true toont de Google-inlog/consent-popup.
// Chrome heeft de callback-vorm gewijzigd van string → { token } object;
// we vangen beide vormen af zodat het op elke versie werkt.
export function getToken(interactive: boolean): Promise<string | null> {
  return new Promise((resolve) => {
    chrome.identity.getAuthToken({ interactive }, (result: unknown) => {
      if (chrome.runtime.lastError) {
        if (interactive) console.warn("getAuthToken:", chrome.runtime.lastError.message);
        resolve(null);
        return;
      }
      const token =
        typeof result === "string"
          ? result
          : ((result as { token?: string } | null)?.token ?? null);
      resolve(token);
    });
  });
}

export async function connect(): Promise<boolean> {
  const token = await getToken(true);
  await chrome.storage.local.set({ [CONNECTED_KEY]: !!token });
  return !!token;
}

export async function isConnected(): Promise<boolean> {
  const stored = await chrome.storage.local.get(CONNECTED_KEY);
  return !!stored[CONNECTED_KEY];
}

export async function disconnect(): Promise<void> {
  const token = await getToken(false);
  if (token) {
    // lokaal uit de cache halen én bij Google intrekken
    await new Promise<void>((r) => chrome.identity.removeCachedAuthToken({ token }, () => r()));
    try {
      await fetch(`https://oauth2.googleapis.com/revoke?token=${token}`, { method: "POST" });
    } catch {
      /* netwerk faalt → token is lokaal al weg */
    }
  }
  await chrome.storage.local.set({ [CONNECTED_KEY]: false });
}

// Doet een Google API-call met automatische token-refresh bij 401.
export async function apiFetch(url: string, init: RequestInit = {}): Promise<Response> {
  let token = await getToken(false);
  if (!token) throw new Error("Niet verbonden met Google.");

  const doFetch = (t: string) =>
    fetch(url, { ...init, headers: { ...(init.headers ?? {}), Authorization: `Bearer ${t}` } });

  let res = await doFetch(token);
  if (res.status === 401) {
    // token verlopen → uit cache gooien en één keer opnieuw proberen
    await new Promise<void>((r) => chrome.identity.removeCachedAuthToken({ token: token! }, () => r()));
    token = await getToken(false);
    if (token) res = await doFetch(token);
  }
  return res;
}
