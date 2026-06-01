import type { FeedItem } from "../lib/types";

// Doorlopende headline-band bovenaan. Items worden verdubbeld zodat de
// CSS-animatie naadloos kan loopen (-50% = exact één set verschoven).
export function Ticker({ items }: { items: FeedItem[] }) {
  if (items.length === 0) return null;
  const row = [...items, ...items];
  // Snelheid schaalt mee met het aantal items zodat de leessnelheid prettig
  // blijft (langer = trager); ~10s per item, minimaal 90s.
  const duration = Math.max(90, items.length * 10);

  return (
    <div className="relative overflow-hidden border-y border-line bg-card">
      <div
        className="nt-ticker flex w-max gap-10 py-2.5 whitespace-nowrap will-change-transform"
        style={{ animationDuration: `${duration}s` }}
      >
        {row.map((it, i) => (
          <a
            key={`${it.id}-${i}`}
            href={it.url}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-2 text-sm text-ink-soft hover:text-brand"
          >
            <span className="text-accent">▸</span>
            <span className="font-semibold text-brand">{it.sourceLabel}</span>
            <span>{it.title}</span>
          </a>
        ))}
      </div>
      {/* fades aan de randen */}
      <div className="pointer-events-none absolute inset-y-0 left-0 w-16 bg-gradient-to-r from-card to-transparent" />
      <div className="pointer-events-none absolute inset-y-0 right-0 w-16 bg-gradient-to-l from-card to-transparent" />
    </div>
  );
}
