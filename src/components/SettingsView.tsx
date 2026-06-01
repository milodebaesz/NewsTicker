import { useEffect, useState } from "react";
import { Mail, Plus, Trash2, ShieldCheck } from "lucide-react";
import { fetchProtonMail } from "../lib/proton";
import { getSettings, saveSettings } from "../lib/settings";
import { getSources, saveSources } from "../lib/sources";
import { getProfile, saveProfile } from "../lib/profile";
import { isConnected } from "../lib/google";
import type { Settings, Source } from "../lib/types";

const input =
  "w-full rounded-lg border border-line bg-card px-3 py-2 text-ink outline-none focus:border-brand focus:ring-2 focus:ring-brand/20";
const label = "mb-1 block text-sm font-medium text-ink-soft";
const card = "rounded-xl border border-line bg-card p-5 shadow-sm";

export function SettingsView({ onClose }: { onClose: () => void }) {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [sources, setSources] = useState<Source[]>([]);
  const [desc, setDesc] = useState("");
  const [keywords, setKeywords] = useState("");
  const [mute, setMute] = useState("");
  const [newLabel, setNewLabel] = useState("");
  const [newUrl, setNewUrl] = useState("");
  const [saved, setSaved] = useState(false);
  const [googleOn, setGoogleOn] = useState(false);
  const [googleBusy, setGoogleBusy] = useState(false);
  const [protonTest, setProtonTest] = useState<string>("");

  useEffect(() => {
    void (async () => {
      setSettings(await getSettings());
      setSources(await getSources());
      const p = await getProfile();
      setDesc(p.description);
      setKeywords(p.keywords.join(", "));
      setMute(p.mute.join(", "));
      setGoogleOn(await isConnected());
    })();
  }, []);

  async function toggleGoogle() {
    setGoogleBusy(true);
    try {
      if (googleOn) {
        await chrome.runtime.sendMessage({ type: "disconnectGoogle" });
        setGoogleOn(false);
      } else {
        const res = await chrome.runtime.sendMessage({ type: "connectGoogle" });
        setGoogleOn(!!res?.ok);
        if (!res?.ok) alert("Koppelen mislukt. Controleer of je als test-gebruiker bent toegevoegd in Google Cloud.");
      }
    } finally {
      setGoogleBusy(false);
    }
  }

  async function testProton() {
    if (!settings) return;
    setProtonTest("…");
    try {
      const items = await fetchProtonMail(settings);
      setProtonTest(`✓ verbonden — ${items.length} berichten gevonden`);
    } catch (e) {
      setProtonTest(`✗ ${e instanceof Error ? e.message : String(e)}`);
    }
  }

  if (!settings) return null;

  const splitList = (s: string) => s.split(",").map((x) => x.trim()).filter(Boolean);

  async function save() {
    if (!settings) return;
    await saveSettings(settings);
    await saveSources(sources);
    await saveProfile({
      description: desc.trim(),
      keywords: splitList(keywords),
      mute: splitList(mute),
    });
    await chrome.runtime.sendMessage({ type: "setupAlarm" });
    setSaved(true);
    setTimeout(() => setSaved(false), 1500);
  }

  function addSource() {
    const url = newUrl.trim();
    if (!url) return;
    setSources([
      ...sources,
      { id: crypto.randomUUID(), url, label: newLabel.trim() || new URL(url).hostname, enabled: true },
    ]);
    setNewLabel("");
    setNewUrl("");
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6 px-6 py-8">
      <div className="flex items-center justify-between">
        <h2 className="text-xl font-semibold text-ink">Instellingen</h2>
        <button onClick={onClose} className="text-sm text-muted hover:text-brand">
          ← Terug naar overzicht
        </button>
      </div>

      {/* Google-koppeling */}
      <section className={`${card} space-y-3`}>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-muted">
          Gmail &amp; Google Agenda
        </h3>
        <div className="flex items-center gap-3">
          <div
            className={`flex h-10 w-10 items-center justify-center rounded-lg ${
              googleOn ? "bg-accent-soft text-accent-ink" : "bg-subtle text-muted"
            }`}
          >
            <Mail className="h-5 w-5" />
          </div>
          <div className="flex-1">
            <div className="font-medium text-ink">
              {googleOn ? "Verbonden" : "Niet verbonden"}
            </div>
            <div className="text-xs text-muted">
              Ongelezen mails en komende afspraken in je ticker. Read-only + als gelezen markeren.
            </div>
          </div>
          <button
            onClick={toggleGoogle}
            disabled={googleBusy}
            className={`rounded-lg px-4 py-2 text-sm font-medium shadow-sm disabled:opacity-50 ${
              googleOn
                ? "border border-line bg-card text-ink-soft hover:bg-subtle"
                : "bg-brand text-white hover:brightness-110"
            }`}
          >
            {googleBusy ? "…" : googleOn ? "Loskoppelen" : "Koppelen"}
          </button>
        </div>
      </section>

      {/* Proton Mail via Bridge */}
      <section className={`${card} space-y-3`}>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-muted">
          Proton Mail (via Bridge)
        </h3>
        <p className="text-xs text-muted">
          Vereist het lokale helper-servertje uit de map <code>proton-helper</code> én een
          draaiende Proton Bridge. Zie de README daar.
        </p>
        <label className="flex items-center gap-2 text-ink-soft">
          <input
            type="checkbox"
            className="accent-[var(--color-brand)]"
            checked={settings.protonEnabled}
            onChange={(e) => setSettings({ ...settings, protonEnabled: e.target.checked })}
          />
          Proton-mail ophalen
        </label>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <span className={label}>Helper-URL</span>
            <input
              className={input}
              value={settings.protonUrl}
              placeholder="http://127.0.0.1:8910"
              onChange={(e) => setSettings({ ...settings, protonUrl: e.target.value })}
            />
          </div>
          <div>
            <span className={label}>Token</span>
            <input
              type="password"
              className={input}
              value={settings.protonToken}
              placeholder="zelfde als HELPER_TOKEN"
              onChange={(e) => setSettings({ ...settings, protonToken: e.target.value })}
            />
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={testProton}
            className="inline-flex items-center gap-1.5 rounded-lg bg-subtle px-3 py-2 text-sm text-ink-soft hover:bg-subtle-hover"
          >
            <ShieldCheck className="h-4 w-4" /> Verbinding testen
          </button>
          {protonTest && (
            <span
              className={`text-sm ${protonTest.startsWith("✗") ? "text-red-600" : "text-brand"}`}
            >
              {protonTest}
            </span>
          )}
        </div>
      </section>

      {/* AI-scoring */}
      <section className={`${card} space-y-4`}>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-muted">Relevantie (AI)</h3>
        <label className="flex items-center gap-2 text-ink-soft">
          <input
            type="checkbox"
            className="accent-[var(--color-brand)]"
            checked={settings.scoringEnabled}
            onChange={(e) => setSettings({ ...settings, scoringEnabled: e.target.checked })}
          />
          Items scoren en sorteren met OpenAI
        </label>
        <div>
          <span className={label}>OpenAI API-key</span>
          <input
            type="password"
            className={input}
            value={settings.openaiKey}
            placeholder="sk-..."
            onChange={(e) => setSettings({ ...settings, openaiKey: e.target.value })}
          />
          <p className="mt-1 text-xs text-muted">
            Wordt lokaal in de browser opgeslagen (chrome.storage), niet gedeeld.
          </p>
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <span className={label}>Model</span>
            <input
              className={input}
              value={settings.model}
              onChange={(e) => setSettings({ ...settings, model: e.target.value })}
            />
          </div>
          <div>
            <span className={label}>Min. relevantie: {settings.minRelevance}</span>
            <input
              type="range"
              min={0}
              max={100}
              step={5}
              className="mt-2 w-full accent-[var(--color-brand)]"
              value={settings.minRelevance}
              onChange={(e) => setSettings({ ...settings, minRelevance: Number(e.target.value) })}
            />
          </div>
        </div>
        <div>
          <span className={label}>Verversen elke {settings.refreshMinutes} min</span>
          <input
            type="range"
            min={5}
            max={120}
            step={5}
            className="mt-2 w-full accent-[var(--color-brand)]"
            value={settings.refreshMinutes}
            onChange={(e) => setSettings({ ...settings, refreshMinutes: Number(e.target.value) })}
          />
        </div>
      </section>

      {/* Interesseprofiel */}
      <section className={`${card} space-y-4`}>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-muted">
          Jouw interesseprofiel
        </h3>
        <div>
          <span className={label}>Waar ben je in geïnteresseerd?</span>
          <textarea
            className={`${input} h-24 resize-none`}
            value={desc}
            onChange={(e) => setDesc(e.target.value)}
          />
        </div>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <span className={label}>Trefwoorden (komma's)</span>
            <input className={input} value={keywords} onChange={(e) => setKeywords(e.target.value)} />
          </div>
          <div>
            <span className={label}>Negeren (komma's)</span>
            <input className={input} value={mute} onChange={(e) => setMute(e.target.value)} />
          </div>
        </div>
      </section>

      {/* Bronnen */}
      <section className={`${card} space-y-3`}>
        <h3 className="text-sm font-semibold uppercase tracking-wide text-muted">RSS-bronnen</h3>
        <ul className="space-y-2">
          {sources.map((s, idx) => (
            <li
              key={s.id}
              className="flex items-center gap-3 rounded-lg border border-line bg-subtle/40 px-3 py-2"
            >
              <input
                type="checkbox"
                className="accent-[var(--color-brand)]"
                checked={s.enabled}
                onChange={(e) => {
                  const next = [...sources];
                  next[idx] = { ...s, enabled: e.target.checked };
                  setSources(next);
                }}
              />
              <div className="min-w-0 flex-1">
                <div className="truncate font-medium text-ink">{s.label}</div>
                <div className="truncate text-xs text-muted">{s.url}</div>
              </div>
              <button
                onClick={() => setSources(sources.filter((x) => x.id !== s.id))}
                className="text-muted hover:text-red-500"
              >
                <Trash2 className="h-4 w-4" />
              </button>
            </li>
          ))}
        </ul>
        <div className="flex gap-2">
          <input
            className={`${input} flex-[0_0_30%]`}
            placeholder="Naam"
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
          />
          <input
            className={input}
            placeholder="https://… (RSS/Atom-feed)"
            value={newUrl}
            onChange={(e) => setNewUrl(e.target.value)}
          />
          <button
            onClick={addSource}
            className="inline-flex items-center gap-1 rounded-lg bg-subtle px-3 text-sm text-ink-soft hover:bg-subtle-hover"
          >
            <Plus className="h-4 w-4" /> Toevoegen
          </button>
        </div>
      </section>

      <div className="flex items-center gap-3">
        <button
          onClick={save}
          className="rounded-lg bg-brand px-4 py-2 font-medium text-white shadow-sm hover:brightness-110"
        >
          Opslaan
        </button>
        {saved && <span className="text-sm text-brand">Opgeslagen ✓</span>}
      </div>
    </div>
  );
}
