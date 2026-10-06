# App Store Connect – Newsticker

Alles wat je in App Store Connect moet invullen. Tekenlimieten tussen haakjes.

## Algemeen

| Veld | Waarde |
|---|---|
| Naam (30) | Newsticker |
| Bundle ID | com.mkdebie.newsticker |
| SKU | newsticker-ios |
| Primaire categorie | Nieuws |
| Secundaire categorie | Productiviteit |
| Leeftijdsclassificatie | 12+ (nieuwsinhoud: "Onregelmatige/milde realistische geweld"; de app toont nieuws van derden) |
| Privacybeleid-URL | https://milodebaesz.github.io/NewsTicker/privacy.html |
| Ondersteunings-URL | https://milodebaesz.github.io/NewsTicker/ |
| Copyright | 2026 Mihaly de Bie |
| Versleuteling | Geen (ITSAppUsesNonExemptEncryption = NO staat al in de app) |

## Nederlands (primaire taal)

**Ondertitel (30)**
Jouw nieuws, privé en slim

**Promotietekst (170)**
Al je nieuwsbronnen op één plek. Zelfde verhaal bij meerdere bronnen? Dan zie je het één keer. Met een ochtendbriefing en AI op je iPhone, zonder account.

**Beschrijving (4000)**
Newsticker brengt het nieuws van jouw favoriete bronnen samen op één rustige plek. Geen account, geen advertenties, geen tracking: wat je leest en wat de app van je leert, blijft op je iPhone.

ZELFDE NIEUWS, ÉÉN KAART
Brengen NOS, NU.nl en de Volkskrant hetzelfde verhaal? Newsticker voegt ze samen tot één kaart. Tik erop en wissel tussen de bronnen.

SLIM GESORTEERD, OP JE IPHONE
Met Apple Intelligence beoordeelt Newsticker welk nieuws bij jouw interesses past en vat het verhalen samen in drie zinnen. Dat gebeurt op je iPhone zelf: er gaat niets naar een server. Liever gewoon op tijd? Kies "Nieuwste".

JOUW EIGEN ALGORITME
De app leert van wat je leest, en van "Meer hiervan" en "Minder hiervan". Bij "Jouw algoritme" zie je precies wat hij geleerd heeft, en stuur je het bij of wis je het.

OCHTENDBRIEFING
Elke ochtend op het tijdstip dat jij kiest een melding met de vijf verhalen die er voor jou toe doen, elk met één zin uitleg.

JOUW BRONNEN
Kies uit zo'n 70 Nederlandse, Vlaamse, Engelse en Duitse bronnen, of voeg elke website met een RSS-feed toe. Met een doorlopende nieuwsband bovenin.

PRIVACY
• Geen account, geen login
• Geen advertenties, geen tracking, geen analytics
• AI draait op je eigen iPhone
• Je gegevens blijven op je toestel

Samenvattingen en relevantiescores vragen Apple Intelligence (iPhone 15 Pro of nieuwer). Op andere iPhones werkt alles behalve die AI-functies.

**Trefwoorden (100, komma's zonder spaties)**
nieuws,rss,feed,nos,nieuwslezer,briefing,privacy,samenvatting,ai,krant,actueel,tech,lezen

**Wat is er nieuw (1.0)**
De eerste versie van Newsticker.

## English

**Subtitle (30)**
Your news, private and smart

**Promotional text (170)**
All your news sources in one place. Same story from several sources? You see it once. With a morning briefing and on-device AI, no account needed.

**Description**
Newsticker brings news from your favorite sources together in one calm place. No account, no ads, no tracking: what you read and what the app learns about you stays on your iPhone.

SAME STORY, ONE CARD
When several sources cover the same story, Newsticker merges them into one card. Tap it and switch between sources.

SMART, ON YOUR IPHONE
With Apple Intelligence, Newsticker rates which news matches your interests and summarizes stories in three sentences — on your iPhone itself, nothing goes to a server. Prefer plain chronological? Choose "Newest".

YOUR OWN ALGORITHM
The app learns from what you read, and from "More like this" and "Less like this". "Your algorithm" shows exactly what it learned, so you can adjust or clear it.

MORNING BRIEFING
Every morning, at a time you choose, a notification with the five stories that matter to you, each with a one-line explanation.

YOUR SOURCES
Choose from about 70 Dutch, Flemish, English and German sources, or add any website with an RSS feed.

PRIVACY
• No account, no login
• No ads, no tracking, no analytics
• AI runs on your own iPhone
• Your data stays on your device

Summaries and relevance ratings require Apple Intelligence (iPhone 15 Pro or later). On other iPhones everything except those AI features works.

Note: the app's interface is currently in Dutch.

**Keywords**
news,rss,feed,reader,briefing,privacy,summary,ai,headlines,newspaper,tech,offline

## App-privacy (vragenlijst in App Store Connect)

- "Verzamelt u of uw externe partners gegevens van deze app?" → **Nee, we verzamelen geen gegevens.**
  Toelichting: alle gegevens blijven op het toestel; de app heeft geen eigen server. Verbindingen met nieuwssites zijn gewone verzoeken aan sites die de gebruiker zelf kiest; de optionele OpenAI-koppeling gebruikt de eigen sleutel van de gebruiker en is standaard uit.
- Tracking: **Nee.**

## TestFlight

**Beta-app-beschrijving**
Newsticker verzamelt nieuws uit je favoriete bronnen, voegt hetzelfde verhaal van meerdere bronnen samen en sorteert met Apple Intelligence op je iPhone. Geen account nodig.

**Wat te testen**
1. Doorloop de introductie en kies je bronnen en interesses.
2. Gebruik de app een paar dagen: klopt "Voor jou", en voelt "Nieuwste" goed?
3. Zet de ochtendbriefing aan: komt hij op tijd en kloppen de verhalen?
4. Open artikelen: is duidelijk van welke bron ze zijn en hoe je het artikel leest?
5. Voeg een eigen bron toe via zoeken of een website-adres.
6. Laat weten als iets traag is, vastloopt of onduidelijk is (schermafbeelding via TestFlight).

**Feedback-e-mail**
CONTACT_EMAIL

**Inloggegevens voor de review**
Niet nodig: de app heeft geen account.

## Screenshots

In `ios/AppStore/screenshots/` (6,9 inch, 1320 × 2868). Volgorde: feed, leesweergave met samenvatting, briefing, "Jouw algoritme", introductie.
