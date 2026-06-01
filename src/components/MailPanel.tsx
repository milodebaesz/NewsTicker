import { useState } from "react";
import { Mail, ChevronDown, Check, X, ExternalLink } from "lucide-react";
import { markRead, updateItem } from "../lib/feed";
import { timeAgo } from "../lib/format";
import type { FeedItem } from "../lib/types";

// Inklapbaar mailvak: op het overzicht zie je standaard alleen het aantal,
// pas na uitklappen verschijnen de mails zelf.
export function MailPanel({ items, defaultOpen = false }: { items: FeedItem[]; defaultOpen?: boolean }) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <section className="px-6 pt-5">
      <button
        onClick={() => setOpen((o) => !o)}
        className="flex w-full items-center gap-3 rounded-2xl border border-line bg-card px-5 py-4 text-left shadow-sm transition hover:bg-subtle/50"
      >
        <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-brand text-white">
          <Mail className="h-5 w-5" />
        </span>
        <span className="flex-1">
          <span className="block font-semibold text-ink">Mail</span>
          <span className="block text-sm text-muted">
            {items.length} {items.length === 1 ? "nieuw bericht" : "nieuwe berichten"}
          </span>
        </span>
        <span className="rounded-full bg-brand-soft px-2.5 py-0.5 text-sm font-semibold text-brand">
          {items.length}
        </span>
        <ChevronDown
          className={`h-5 w-5 text-muted transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>

      {open && (
        <div className="mt-3 space-y-2.5">
          {items.map((item) => (
            <MailItem key={item.id} item={item} />
          ))}
        </div>
      )}
    </section>
  );
}

function MailItem({ item }: { item: FeedItem }) {
  const [expanded, setExpanded] = useState(false);
  const initial = (item.sourceLabel.trim()[0] || "?").toUpperCase();

  return (
    <article className="group rounded-2xl border border-line bg-card p-4 shadow-sm transition hover:shadow-md">
      <div className="flex items-start gap-3">
        <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-brand-soft text-sm font-semibold text-brand">
          {initial}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-baseline gap-2">
            <span className="truncate font-semibold text-ink">{item.sourceLabel}</span>
            <span className="ml-auto shrink-0 text-xs text-muted">{timeAgo(item.publishedAt)}</span>
          </div>
          <div className="mt-0.5 truncate font-medium text-ink-soft">{item.title}</div>

          {item.summary && (
            <p
              className={`mt-2 whitespace-pre-line text-sm leading-relaxed text-muted ${
                expanded ? "" : "line-clamp-3"
              }`}
            >
              {item.summary}
            </p>
          )}

          <div className="mt-3 flex items-center gap-2">
            <a
              href={item.url}
              target="_blank"
              rel="noreferrer"
              onClick={() => void markRead(item.id)}
              className="inline-flex items-center gap-1.5 rounded-lg bg-brand px-3 py-1.5 text-xs font-medium text-white shadow-sm hover:brightness-110"
            >
              <ExternalLink className="h-3.5 w-3.5" /> Openen in Gmail
            </a>
            {item.summary && (
              <button
                onClick={() => setExpanded((e) => !e)}
                className="rounded-lg px-2.5 py-1.5 text-xs font-medium text-brand hover:bg-subtle"
              >
                {expanded ? "Minder" : "Meer"}
              </button>
            )}
            <div className="ml-auto flex gap-1 opacity-0 transition group-hover:opacity-100">
              <button
                title="Gelezen"
                onClick={() => void markRead(item.id)}
                className="rounded-md bg-subtle p-1.5 text-ink-soft hover:bg-subtle-hover"
              >
                <Check className="h-3.5 w-3.5" />
              </button>
              <button
                title="Verbergen"
                onClick={() => void updateItem(item.id, { dismissed: true })}
                className="rounded-md bg-subtle p-1.5 text-muted hover:bg-subtle-hover"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>
    </article>
  );
}
