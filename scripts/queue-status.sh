#!/bin/bash
# Show what the metadata upgrade queue has actually done.
#
# The queue's persistent output is two files: works.json (what it learned) and
# upgrade-attempts.json (what it decided not to retry). Read together they explain
# "0 eligible" — a quiet queue with answers looks identical to a stalled one without.
#
# Usage: ./queue-status.sh                  report every simulator store
#        ./queue-status.sh <works.json>     report one specific store

set -uo pipefail

report() {
  local store="$1"
  local memory="$(dirname "$store")/upgrade-attempts.json"
  echo "store:        $store"
  echo "last written: $(stat -f '%Sm' "$store")"
  echo
  python3 - "$store" "$memory" <<'PY'
import json, sys, datetime, os
EPOCH = datetime.datetime(2001, 1, 1)          # Apple reference date

works = json.load(open(sys.argv[1]))["works"]
resolved = 0
for w in works:
    s   = w.get("snapshot") or {}
    ids = w.get("externalIds") or {}
    ranked = len(s.get("tags", []))
    if ids.get("anilist"):
        resolved += 1
    when = ""
    if s.get("fetchedAt"):
        when = (EPOCH + datetime.timedelta(seconds=s["fetchedAt"])).strftime("%m-%d %H:%M UTC")
    # Ranked tags are the tell that AniList actually answered: MangaDex has no rank
    # concept, and provisional snapshots write an empty tags array.
    state = "UPGRADED" if ranked else ("provisional" if s else "never fetched")
    title = w["displayTitle"][:32]
    print(f'{title:<34} {state:<14} anilist={ids.get("anilist","-"):<8} '
          f'genres={len(s.get("genres",[])):<3} ranked={ranked:<3} {when}')

print()
print(f"{len(works)} works, {resolved} resolved to AniList")
# ADR-0011 gates the AniList candidate pool at 3 resolved Works, and failing that gate
# is silent — the For You rail renders normally, just without the pool.
print("AniList pool gate (needs 3):",
      "PASS" if resolved >= 3 else f"FAIL - {3-resolved} short")

# Attempt memory. Without this, a queue that has answered everything and a queue that
# is stuck both just say "0 eligible".
mem = sys.argv[2]
if os.path.exists(mem):
    entries = json.load(open(mem))["entries"]
    kinds = {}
    for e in entries:
        kinds[list(e["outcome"])[0]] = kinds.get(list(e["outcome"])[0], 0) + 1
    print(f"suppressed by attempt memory: {len(entries)} "
          f"({', '.join(f'{v} {k}' for k, v in sorted(kinds.items()))})")
else:
    print("suppressed by attempt memory: 0 (no upgrade-attempts.json yet)")
PY
  echo
}

if [ $# -gt 0 ]; then
  [ -f "$1" ] || { echo "no such works.json: $1"; exit 1; }
  report "$1"
  exit 0
fi

# Report EVERY store, never guess. A reinstall mints a fresh container and each
# simulator has its own, so "the newest works.json" is routinely the wrong one — and
# picking it silently reports a stale install as though it were the live one.
# -exec stat rather than `xargs ls -t`: "Application Support" contains a space.
found=0
while IFS= read -r store; do
  [ -n "$store" ] || continue
  found=$((found + 1))
  report "$store"
done < <(find ~/Library/Developer/CoreSimulator/Devices -name works.json \
           -path '*Application Support*' -exec stat -f '%m %N' {} + 2>/dev/null \
         | sort -rn | cut -d' ' -f2-)

[ "$found" -gt 0 ] || echo "no works.json found — has the app run on a simulator yet?"
[ "$found" -gt 1 ] && echo "$found stores above, newest first — the live one is whichever your last run installed to"
exit 0
