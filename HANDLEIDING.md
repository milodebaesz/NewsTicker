# Newsticker — handleiding

Praktische naslag voor: Proton Mail koppelen, de helper automatisch laten
draaien, en de extensie naar een andere computer overzetten.

---

## 1. Proton Mail koppelen (eenmalig)

De extensie kan zelf geen IMAP. Het servertje in `proton-helper/` vertaalt
Proton Bridge (IMAP) naar HTTP. Alles blijft lokaal; je Bridge-wachtwoord staat
in `proton-helper/.env` en gaat alleen naar de lokale Bridge-poort.

1. Zorg dat **Proton Bridge** draait en ingelogd is.
2. In de map `proton-helper/`:
   ```bash
   npm install
   cp .env.example .env
   ```
3. Vul `proton-helper/.env` in:
   - `PROTON_EMAIL` — je Proton-adres
   - `PROTON_BRIDGE_PASSWORD` — het **Bridge**-wachtwoord (Bridge → je account →
     IMAP-wachtwoord), **niet** je accountwachtwoord
   - `HELPER_TOKEN` — zelfverzonnen sleutel, genereer met `openssl rand -hex 16`
   - controleer `PROTON_IMAP_PORT` (standaard `1143`, staat in Bridge)
4. Start de helper:
   ```bash
   npm start
   ```
   Laat dit venster open zolang je Proton-mail wilt zien (of zie stap 2 voor
   automatisch starten).
5. In de extensie: **Instellingen → Proton Mail (via Bridge)**:
   - inschakelen aanvinken
   - URL: `http://127.0.0.1:8910` (of je eigen `HELPER_PORT`)
   - Token: dezelfde `HELPER_TOKEN` als in `.env`
   - **Verbinding testen** → **Opslaan**

---

## 2. Helper automatisch laten draaien (macOS, launchd)

Zo start de helper vanzelf bij het inloggen, zonder open terminalvenster.

1. Er staat een kant-en-klaar bestand in
   `proton-helper/com.newsticker.proton-helper.plist`. Controleer daarin het
   node-pad (nu `/Users/mkb/.nvm/versions/node/v22.18.0/bin/node`) — dat
   verandert als je Node bijwerkt. Huidig pad opvragen: `which node`.
2. Kopieer het naar je LaunchAgents-map en laad het:
   ```bash
   cp proton-helper/com.newsticker.proton-helper.plist ~/Library/LaunchAgents/
   launchctl load ~/Library/LaunchAgents/com.newsticker.proton-helper.plist
   ```
3. Controleren of het draait:
   ```bash
   curl -s -H "x-nt-token: JOUW_TOKEN" http://127.0.0.1:8910/health
   ```
   Logs staan in `proton-helper/helper.log` en `helper.err.log`.

Stoppen / uitschakelen:
```bash
launchctl unload ~/Library/LaunchAgents/com.newsticker.proton-helper.plist
```

Na een Node-update: pas het node-pad in de plist aan en doe `unload` + `load`.

---

## 3. Extensie overzetten naar een andere computer

Kort: **redelijk makkelijk voor de extensie zelf, met één belangrijk
aandachtspunt voor de Gmail/Agenda-koppeling.**

### a. De extensie installeren
1. Kopieer de hele projectmap (of in elk geval de gebouwde map `dist/`) naar de
   andere computer. Met de broncode erbij kun je daar opnieuw bouwen:
   ```bash
   npm install && npm run build
   ```
2. Ga naar `chrome://extensions`, zet **Ontwikkelaarsmodus** aan, klik
   **Uitgepakte extensie laden** en kies de `dist/`-map.

### b. Extensie-ID is nu vastgezet (gedaan)
- In `public/manifest.json` staat nu een `"key"`-veld, zodat de extensie op
  **elke** computer dezelfde vaste ID krijgt:
  **`kjjbjcmkfkdamcfajhglidokhinmkilf`**
- De privésleutel staat in `key.pem` (rechten 600). **Bewaar dit goed en deel het
  niet** — wie de key heeft, kan onder dezelfde ID publiceren. Niet nodig op de
  andere computers (de publieke `"key"` in het manifest is voldoende voor een
  vaste ID); je hebt `key.pem` alleen nodig als je ooit een officiële `.crx` wilt
  ondertekenen.
- **Eenmalig in Google Cloud Console** (omdat de ID veranderd is t.o.v. de oude
  `gmllg…`): open de OAuth-client van deze extensie → veld **Application ID** →
  zet daar de nieuwe ID `kjjbjcmkfkdamcfajhglidokhinmkilf`. De `client_id` in het
  manifest blijft hetzelfde. Zie "Nu eenmalig te doen" onderaan.
- Op elke computer geef je daarna nog wél éénmalig de Google-toestemming, en je
  account moet test-gebruiker zijn in Google Cloud.

### c. Instellingen en data zijn per computer
`chrome.storage.local` synchroniseert niet tussen computers. Op elke nieuwe
machine opnieuw invullen:
- OpenAI API-key
- RSS-bronnen + interesseprofiel
- Proton-instellingen (URL + token)

### d. Proton per computer apart
Proton Bridge en de helper draaien lokaal. Op elke computer dus:
- Proton Bridge installeren + inloggen
- `proton-helper/` opzetten met een eigen `.env` (stap 1)

### Samengevat
| Onderdeel        | Moeite | Opmerking                                            |
|------------------|--------|------------------------------------------------------|
| Extensie laden   | Laag   | `dist/` kopiëren of opnieuw bouwen                   |
| Gmail/Agenda     | Middel | eerst vaste `key` in manifest pinnen, dan opnieuw koppelen |
| Instellingen     | Laag   | handmatig opnieuw invullen                           |
| Proton           | Middel | Bridge + helper per computer apart opzetten          |

### Nu eenmalig te doen (na het vastzetten van de ID)

1. **Herlaad de extensie op deze computer.** `chrome://extensions` → bij
   Newsticker op het ↻-icoon (of verwijder + opnieuw `dist/` laden). De ID is nu
   `kjjbjcmkfkdamcfajhglidokhinmkilf`.
2. **Werk Google Cloud Console bij.** Ga naar
   <https://console.cloud.google.com/apis/credentials> → open de OAuth-client van
   Newsticker (type *Chrome-extensie*) → vul bij **Application ID / Item ID** de
   nieuwe ID in en bewaar. (Bestaat er nog geen extensie-OAuth-client met de
   nieuwe ID, maak er dan één aan; de scopes blijven `gmail.modify` +
   `calendar.readonly`.)
3. **Koppel Gmail/Agenda opnieuw** in de extensie-instellingen (Loskoppelen →
   Koppelen), zodat een nieuwe token onder de nieuwe ID wordt opgehaald.
4. Op **andere computers**: gewoon `dist/` laden (of opnieuw bouwen) — de ID is
   daar automatisch dezelfde. Daarna stap 3 herhalen en je instellingen + Proton
   opnieuw invullen.

> Tip: omdat de ID veranderd is, kun je de oude ID `gmllgidfhohobmibmkienaeegdlijcjg`
> later opruimen in Google Cloud als je wilt.
