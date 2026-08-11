"""Seed a WeebCentral cohort into a simulator's works.json for the ADR-0019 Amendment 1 run.

Cohort rule is fixed by docs/superpowers/specs/2026-08-11-adr-0019-amendment-1-run-protocol.md:
Popularity, offset 0, limit 80, every title seeded, none inspected first.

Plants the shape LibraryStore.toggle -> WorkStore.mint(from:) produces for a WeebCentral
listing. The protocol requires this shape to be diffed against a UI-minted control before
pass 1 -- this script does not do that check, it only writes.

usage: adr0019_seed.py <works.json> [limit]
"""
import html
import json
import re
import subprocess
import sys
import uuid

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")


PAGE = 32  # the endpoint caps a page at 32 and ignores a larger `limit` -- see Amendment A.


def page_of(offset):
    url = (f"https://weebcentral.com/search/data?sort=Popularity"
           f"&display_mode=Full%20Display&limit={PAGE}&offset={offset}")
    page = subprocess.run(["curl", "-s", "--compressed", "-A", UA, url],
                          capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
    # One <article> per series; take the href's ULID and the cover's alt text together so a
    # title is never paired with another series' id.
    out = []
    for m in re.finditer(
            r'href="https://weebcentral\.com/series/([0-9A-Z]{26})/[^"]*"'
            r'(?:(?!href=).)*?alt="(.*?) cover"', page, re.S):
        out.append((m.group(1), html.unescape(m.group(2))))
    return out


def cohort(total):
    out, seen = [], set()
    for offset in range(0, total, PAGE):
        got = page_of(offset)
        print(f"  offset {offset}: {len(got)} series")
        for wid, title in got:
            if wid not in seen:
                seen.add(wid)
                out.append((wid, title))
    return out


def main():
    path, limit = sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 80
    entries = cohort(limit)
    print(f"fetched {len(entries)} series")

    doc = json.load(open(path))
    existing = {(l["sourceId"], l["mangaId"])
                for w in doc["works"] for l in w["listings"]}

    added = 0
    for wid, title in entries:
        if ("weebcentral", wid) in existing:
            continue
        doc["works"].append({
            "id": {"raw": str(uuid.uuid4()).upper()},
            "listings": [{"sourceId": "weebcentral", "mangaId": wid}],
            "externalIds": {},
            "displayTitle": title,
            "knownTitles": [title],
        })
        added += 1

    json.dump(doc, open(path, "w"))
    print(f"seeded {added}; works.json now holds {len(doc['works'])}")
    for wid, title in entries:
        print(f"  {wid}\t{title}")


if __name__ == "__main__":
    main()
