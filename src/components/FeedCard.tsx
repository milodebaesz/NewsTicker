import { useState } from "react";
import { Check, X } from "lucide-react";
import { markRead, updateItem } from "../lib/feed";
import { timeAgo } from "../lib/format";
import type { FeedItem } from "../lib/types";

export function FeedCard({ item, span = "" }: { item: FeedItem; span?: string }) {
  const [imgFail, setImgFail] = useState(false);
  const hasImg = !!item.image && !imgFail;
  const big = span.includes("row-span-2"); // grote tegel → ruimere typografie
  const wide = span.includes("col-span-2");

  return (
    <article
      className={`group relative flex break-inside-avoid flex-col overflow-hidden rounded-2xl border border-line shadow-sm transition hover:shadow-md ${span} ${
        hasImg ? "bg-ink text-white" : "bg-card"
      }`}
    >
      {hasImg && (
        <>
          <img
            src={item.image}
            alt=""
            loading="lazy"
            referrerPolicy="no-referrer"
            onError={() => setImgFail(true)}
            className="absolute inset-0 h-full w-full object-cover transition duration-500 group-hover:scale-[1.03]"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/40 to-black/5" />
        </>
      )}

      {/* hover-acties */}
      <div className="absolute right-2 top-2 z-10 flex gap-1 opacity-0 transition group-hover:opacity-100">
        <button
          title="Gelezen"
          onClick={() => void markRead(item.id)}
          className={`rounded-md p-1.5 ${
            hasImg ? "bg-black/40 text-white hover:bg-black/60" : "bg-subtle text-ink-soft hover:bg-subtle-hover"
          }`}
        >
          <Check className="h-3.5 w-3.5" />
        </button>
        <button
          title="Verbergen"
          onClick={() => void updateItem(item.id, { dismissed: true })}
          className={`rounded-md p-1.5 ${
            hasImg ? "bg-black/40 text-white hover:bg-black/60" : "bg-subtle text-muted hover:bg-subtle-hover"
          }`}
        >
          <X className="h-3.5 w-3.5" />
        </button>
      </div>

      <div className={`relative flex h-full min-h-0 flex-col p-4 ${hasImg ? "justify-end" : ""}`}>
        {/* meta */}
        <div
          className={`mb-1.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs ${
            hasImg ? "text-white/80" : "text-muted"
          }`}
        >
          <span className={`font-semibold ${hasImg ? "text-white" : "text-brand"}`}>
            {item.sourceLabel}
          </span>
          <span>·</span>
          <span>{timeAgo(item.publishedAt)}</span>
          {item.topic && (
            <span
              className={`rounded-full px-2 py-0.5 ${
                hasImg ? "bg-white/15 text-white" : "border border-line text-muted"
              }`}
            >
              {item.topic}
            </span>
          )}
          {item.relevance !== null && (
            <span
              className={`ml-auto rounded-full px-2 py-0.5 font-medium ${
                item.relevance >= 70
                  ? "bg-accent text-black"
                  : hasImg
                    ? "bg-white/20 text-white"
                    : "bg-subtle text-ink-soft"
              }`}
            >
              {item.relevance}
            </span>
          )}
        </div>

        <a
          href={item.url}
          target="_blank"
          rel="noreferrer"
          onClick={() => void markRead(item.id)}
          className={`block font-semibold leading-snug hover:underline ${
            hasImg ? "text-white" : "text-ink"
          } ${big ? "text-lg" : "text-[15px]"} ${big ? "line-clamp-4" : "line-clamp-3"}`}
        >
          {item.title}
        </a>

        {/* samenvatting: op grote/brede tegels of op kaarten zonder beeld */}
        {item.summary && (big || wide || !hasImg) && (
          <p
            className={`mt-1.5 text-sm ${big ? "line-clamp-3" : "line-clamp-2"} ${
              hasImg ? "text-white/80" : "text-muted"
            }`}
          >
            {item.summary}
          </p>
        )}
        {item.reason && !hasImg && (
          <p className="mt-1.5 text-xs italic text-muted/80">{item.reason}</p>
        )}
      </div>
    </article>
  );
}
