#!/bin/bash
# Controleert of alle feeds in de bronnenlijst (FeedSearch.swift) nog werken.
# Gebruik: ios/scripts/check-feeds.sh   (alleen ophalen, er wordt niets verstuurd)
cd "$(dirname "$0")/../Newsticker" || exit 1

ok=0; bad=0
while IFS='|' read -r name url; do
  out=$(curl -sL -m 15 -A "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) Newsticker/0.1" -w $'\n%{http_code}' "$url" 2>/dev/null)
  code=$(tail -n1 <<<"$out")
  items=$(grep -oiE '<(item|entry)[ >]' <<<"$out" | wc -l | tr -d ' ')
  if grep -qiE '<(rss|feed|rdf:rdf)[ >]' <<<"$out" && [ "$items" -gt 0 ]; then
    ok=$((ok + 1))
  else
    bad=$((bad + 1))
    printf 'KAPOT  HTTP %-3s %3s items  %-28s %s\n' "$code" "$items" "$name" "$url"
  fi
done < <(grep -oE 'f\("[^"]+", "https://[^"]+"' Services/FeedSearch.swift \
          | sed -E 's/f\("([^"]+)", "([^"]+)"/\1|\2/' | sort -u -t'|' -k2)

echo "Klaar: $ok werken, $bad kapot."
