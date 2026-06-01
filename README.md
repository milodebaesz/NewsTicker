# Newsticker

Chrome-extensie (new tab) die nieuws via RSS verzamelt en met AI filtert op wat
voor jóu relevant is. Bovenin een doorlopende headline-band, daaronder kaarten
gesorteerd op relevantie.

## Stack

Vite + React 19 + Tailwind v4 + TypeScript. Manifest v3. Optioneel OpenAI voor
relevantie-scoring.

## Bouwen

```bash
npm install
npm run build      # → dist/
npm run dev        # watch-modus tijdens ontwikkelen
```

## Installeren in Chrome

1. `chrome://extensions` → "Ontwikkelaarsmodus" aan.
2. "Uitgepakte extensie laden" → kies de map `dist/`.
3. Open een nieuw tabblad. De achtergrond-worker haalt direct de bronnen op.

## Hoe het werkt

- **`src/background.ts`** — service worker. Draait op `chrome.alarms` (interval
  instelbaar), haalt elke RSS-bron op, ontdubbelt op URL-hash, scoort nieuwe
  items met OpenAI en bewaart alles in `chrome.storage.local`.
- **New tab UI** — leest uit `chrome.storage.local` en luistert live op
  wijzigingen (`chrome.storage.onChanged`).
- **Relevantie** — je interesseprofiel (vrije tekst + trefwoorden + negeerlijst)
  in de instellingen bepaalt de score 0–100 per item.

RSS wordt rechtstreeks vanuit de service worker opgehaald; dankzij
`host_permissions: <all_urls>` gelden er geen CORS-restricties.

## Privacy / keys

De OpenAI-key staat lokaal in `chrome.storage.local` (device-only), net als bij
PromptPad. Voor een gepubliceerde versie of multi-device sync is de nette
upgrade: het ophalen + scoren naar een **Supabase Edge Function** verplaatsen en
de extensie alleen laten lezen — dan verlaat de key nooit de server.

## Roadmap

- [x] RSS-pijplijn + AI-scoring + new tab dashboard + ticker
- [ ] Mail (Gmail via `chrome.identity`, scopes read-only)
- [ ] Agenda (Google Calendar)
- [ ] Beurs (Finnhub/Twelve Data watchlist)
- [ ] Optionele Supabase-sync tussen apparaten
