# Newsticker — Proton-helper

Een Chrome-extensie kan geen rauwe IMAP-verbinding maken, alleen HTTP. Proton
Bridge spreekt enkel IMAP/SMTP op `localhost`. Dit servertje is de brug ertussen:
het leest je inbox via Bridge en biedt die aan op een lokale HTTP-poort die de
extensie pollt.

Alles draait op je eigen machine. Je Bridge-wachtwoord staat in `.env` en gaat
nergens anders heen dan naar de lokale Bridge-poort.

## Eenmalige setup

1. Zorg dat **Proton Bridge** draait en ingelogd is.
2. In deze map:
   ```bash
   npm install
   cp .env.example .env
   ```
3. Open `.env` en vul in:
   - `PROTON_EMAIL` — je Proton-adres
   - `PROTON_BRIDGE_PASSWORD` — het **Bridge**-wachtwoord (Bridge → account →
     IMAP-wachtwoord), niet je accountwachtwoord
   - `HELPER_TOKEN` — een zelfverzonnen sleutel (`openssl rand -hex 16`)
   - controleer `PROTON_IMAP_PORT` (standaard `1143`, staat in Bridge)

## Starten

```bash
npm start
```

Laat dit venster open zolang je Proton-mail in Newsticker wilt zien. Automatisch
op de achtergrond starten kan met het meegeleverde launchd-bestand
`com.newsticker.proton-helper.plist` — zie `../HANDLEIDING.md` (stap 2).

## Koppelen in de extensie

Instellingen → **Proton Mail (via Bridge)**:
- Inschakelen aanvinken
- URL: `http://127.0.0.1:8910` (of je eigen `HELPER_PORT`)
- Token: dezelfde `HELPER_TOKEN` als in `.env`
- Test de verbinding en sla op.
