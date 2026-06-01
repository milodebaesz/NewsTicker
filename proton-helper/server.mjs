// Lokale brug tussen Proton Bridge (IMAP) en de Newsticker-extensie (HTTP).
// De extensie kan zelf geen IMAP spreken; dit servertje vertaalt het.
//
// Draait volledig op je eigen machine. Je Bridge-wachtwoord blijft in .env
// en gaat nergens anders heen dan naar de lokale Bridge-poort.
import "dotenv/config";
import http from "node:http";
import { ImapFlow } from "imapflow";
import { simpleParser } from "mailparser";

const HOST = process.env.PROTON_IMAP_HOST || "127.0.0.1";
const PORT = Number(process.env.PROTON_IMAP_PORT || 1143);
const EMAIL = process.env.PROTON_EMAIL || "";
const PASSWORD = process.env.PROTON_BRIDGE_PASSWORD || "";
const HELPER_PORT = Number(process.env.HELPER_PORT || 8910);
const TOKEN = process.env.HELPER_TOKEN || "";

if (!EMAIL || !PASSWORD || !TOKEN) {
  console.error("Vul PROTON_EMAIL, PROTON_BRIDGE_PASSWORD en HELPER_TOKEN in (.env). Zie .env.example.");
  process.exit(1);
}

function imapClient() {
  return new ImapFlow({
    host: HOST,
    port: PORT,
    secure: false, // Bridge gebruikt STARTTLS op 1143
    auth: { user: EMAIL, pass: PASSWORD },
    tls: { rejectUnauthorized: false }, // Bridge gebruikt een zelfondertekend certificaat
    logger: false,
  });
}

// Eerste 20 niet-lege regels van de mailtekst.
function preview(text) {
  if (!text) return "";
  const lines = text
    .replace(/\r/g, "")
    .replace(/ /g, " ")
    .split("\n")
    .map((l) => l.replace(/[ \t]+$/g, ""));
  while (lines.length && !lines[0].trim()) lines.shift();
  const out = [];
  let blank = 0;
  for (const l of lines) {
    const isBlank = l.trim() === "";
    if (isBlank) {
      blank++;
      if (blank > 1) continue;
    } else {
      blank = 0;
    }
    out.push(isBlank ? "" : l.trim());
    if (out.length >= 20) break;
  }
  return out.join("\n").trim();
}

async function listMail(max) {
  const client = imapClient();
  await client.connect();
  const items = [];
  const lock = await client.getMailboxLock("INBOX");
  try {
    let uids = await client.search({ seen: false }, { uid: true });
    if (!uids || uids.length === 0) {
      // alles gelezen → toon de recentste inbox-mail zodat het vak niet leeg blijft
      uids = await client.search({ all: true }, { uid: true });
    }
    uids = uids.slice(-max).reverse(); // nieuwste eerst
    if (uids.length === 0) return items;

    for await (const msg of client.fetch(uids, { uid: true, envelope: true, source: true, flags: true }, { uid: true })) {
      const parsed = await simpleParser(msg.source);
      const fromAddr = msg.envelope?.from?.[0];
      const from = (fromAddr?.name || fromAddr?.address || "Onbekend").trim();
      items.push({
        uid: msg.uid,
        from,
        subject: msg.envelope?.subject || "(geen onderwerp)",
        date: (msg.envelope?.date || new Date()).toISOString(),
        unread: !msg.flags?.has("\\Seen"),
        preview: preview(parsed.text || parsed.html?.replace(/<[^>]+>/g, " ") || ""),
      });
    }
  } finally {
    lock.release();
  }
  await client.logout();
  return items;
}

async function markRead(uid) {
  const client = imapClient();
  await client.connect();
  const lock = await client.getMailboxLock("INBOX");
  try {
    await client.messageFlagsAdd({ uid: String(uid) }, ["\\Seen"], { uid: true });
  } finally {
    lock.release();
  }
  await client.logout();
}

function send(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  // Alleen verzoeken met het juiste token; weert willekeurige localhost-pagina's.
  if (req.headers["x-nt-token"] !== TOKEN) {
    return send(res, 401, { error: "ongeldig token" });
  }
  const url = new URL(req.url, `http://localhost:${HELPER_PORT}`);

  try {
    if (req.method === "GET" && url.pathname === "/mail") {
      const max = Math.min(50, Number(url.searchParams.get("max")) || 20);
      const items = await listMail(max);
      return send(res, 200, { items });
    }
    if (req.method === "POST" && url.pathname === "/mark-read") {
      let raw = "";
      for await (const c of req) raw += c;
      const { uid } = JSON.parse(raw || "{}");
      if (!uid) return send(res, 400, { error: "uid ontbreekt" });
      await markRead(uid);
      return send(res, 200, { ok: true });
    }
    if (req.method === "GET" && url.pathname === "/health") {
      return send(res, 200, { ok: true });
    }
    return send(res, 404, { error: "onbekend pad" });
  } catch (e) {
    console.error(e);
    return send(res, 500, { error: String(e?.message || e) });
  }
});

server.listen(HELPER_PORT, "127.0.0.1", () => {
  console.log(`Newsticker Proton-helper luistert op http://127.0.0.1:${HELPER_PORT}`);
  console.log(`IMAP: ${EMAIL} @ ${HOST}:${PORT}`);
});
