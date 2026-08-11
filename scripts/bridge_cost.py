"""What does the MangaDex bridge cost per refusal, and per library?

Replicates `MALEntityResolver.bridged(sourceTitles:)` from `origin/mangadex-alt-titles`
request-for-request against the live APIs, over the 16 refusals the 2026-08-11 resolvability
measurement produced. Counts requests; does not estimate them.

The sequence, from the branch:

  Round A  min(knownTitles, 3) x MangaDexAPI.searchManga(title:)  [limit=20, includes cover_art]
           -> pool by listing id, partition on malId != nil
           -> match the id-BEARING side first, collapsing by malId (titles unioned)
           -> hit: done, cost = Round A
  Round B  only when the id-bearing side missed AND the id-LESS side matched (right series,
           no MAL link): harvest that listing's titles, keep spellings not already known,
           re-search MAL with min(newSpellings, 3) calls, match against sources + harvest.
           cost = Round A + Round B

Matcher is the same port `wc_resolve.py` validated against four in-app ADR-0017 results.
api.mangadex.org rejects Python's urllib TLS -> shell out to curl.

Usage:  python3 scripts/bridge_cost.py <MAL_CLIENT_ID>
"""
import json
import re
import subprocess
import sys
import time
import unicodedata

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
      "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

NOISE = {"manga", "season", "part", "cour"}
THRESHOLD = 0.90
MARGIN = 0.05
NOVEL_TYPES = {"novel", "light_novel"}
TITLE_SEARCH_LIMIT = 3          # MALEntityResolver.titleSearchLimit

# The 16 refusals from docs/superpowers/specs/2026-08-11-weebcentral-resolvability-measurement.md.
# `Lilith's Cord` is excluded there (MAL search returned no usable response) and stays excluded
# here, so both measurements share a denominator.
REFUSALS = [
    "Xia Ke Xing",
    "Yoruhime-sama",
    "The Vigilante of the Kingcraft Paradise",
    "Junjou Romantica",
    "Sweet HR",
    "Vairocana",
    "Beyond Virtual",
    "Kin no Tamago (Katsuwo)",
    "Koi Inu",
    "Sozo no Eterunite",
    "Together with Zun-chan!",
    "Brothers (NARUSE Yoshiki)",
    "The Grandmaster of Demonic Cultivation",
    "Miquiztli",
    # Full title, deliberately. The resolvability doc's table truncates this one with an
    # ellipsis; copying the truncation cost a recovery on the first run of this harness —
    # the short form scores far below threshold against MangaDex's full title, while the
    # real one ties it at 1.000. A source title is the input, so it must not be abridged.
    "Level 1 kara Hajimaru Shoukan Musou ~Ore dake Tsukaeru Ura Dungeon de, "
    "Subete no Tenseisha wo Bucchigiru~",
    "Ling Bao Zhi",
]

# The library the per-library figure is expressed over: the resolvability measurement's own
# sample. 64 titles, 47 resolved, 16 refused, 1 uncounted.
LIBRARY_SIZE = 64

REQUESTS = {"mangadex": 0, "mal": 0}


def curl(url, headers=(), kind=None):
    if kind:
        REQUESTS[kind] += 1
    cmd = ["curl", "-s", "--compressed", "-A", UA]
    for h in headers:
        cmd += ["-H", h]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, timeout=60)
    return out.stdout.decode("utf-8", "replace")


# --- MALTitleMatcher, ported (identical to wc_resolve.py) --------------------

def normalize(title):
    folded = unicodedata.normalize("NFKD", title)
    folded = "".join(c for c in folded if not unicodedata.combining(c)).lower()
    spaced = "".join(c if c.isalnum() else " " for c in folded)
    return " ".join(t for t in spaced.split() if t not in NOISE)


def levenshtein(a, b):
    prev = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        cur = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        prev = cur
    return prev[len(b)]


def similarity(a, b):
    if a == b:
        return 1.0
    if not a or not b:
        return 0.0
    return 1.0 - levenshtein(a, b) / max(len(a), len(b))


def best_match(source_titles, candidates):
    """candidates: [(id, [titles])]. Returns (id|None, top, runner)."""
    norm_sources = [n for n in (normalize(t) for t in source_titles) if n]
    if not norm_sources or not candidates:
        return None, 0.0, None
    scored = []
    for cid, titles in candidates:
        norms = [normalize(t) for t in titles]
        best = max((similarity(s, c) for s in norm_sources for c in norms), default=0.0)
        scored.append((cid, best))
    scored.sort(key=lambda x: -x[1])
    top = scored[0]
    runner = scored[1][1] if len(scored) > 1 else None
    if top[1] < THRESHOLD:
        return None, top[1], runner
    if runner is not None and top[1] - runner < MARGIN:
        return None, top[1], runner
    return top[0], top[1], runner


# --- The two searches the bridge makes --------------------------------------

def mangadex_search(title):
    """MangaDexAPI.searchManga(title:) — limit 20. Returns [(id, display, [alts], mal|None)]."""
    q = re.sub(r"[^A-Za-z0-9]", "%20", title)[:100]
    raw = curl(f"https://api.mangadex.org/manga?title={q}&includes[]=cover_art&limit=20&offset=0",
               kind="mangadex")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if "data" not in data:
        return None
    out = []
    for m in data["data"]:
        attrs = m["attributes"]
        titles = list((attrs.get("title") or {}).values())
        display = titles[0] if titles else ""
        # MangaAttributes.toManga: flatten alt locale maps, drop blanks/dupes/display title.
        seen = {display}
        alts = []
        for alt in attrs.get("altTitles") or []:
            for v in alt.values():
                v = v.strip()
                if v and v not in seen:
                    seen.add(v)
                    alts.append(v)
        mal = (attrs.get("links") or {}).get("mal")
        out.append((m["id"], display, alts, int(mal) if mal and str(mal).isdigit() else None))
    return out


def mal_search(title, client_id):
    url = ("https://api.myanimelist.net/v2/manga?q="
           + re.sub(r"[^A-Za-z0-9]", "%20", title)[:64]
           + "&limit=10&fields=alternative_titles,media_type")
    raw = curl(url, headers=[f"X-MAL-CLIENT-ID: {client_id}"], kind="mal")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if "data" not in data:
        return None
    out = []
    for node in (n["node"] for n in data["data"]):
        if node.get("media_type") in NOVEL_TYPES:      # ADR-0017
            continue
        alt = node.get("alternative_titles") or {}
        titles = [node["title"]] + [t for t in (alt.get("en"), alt.get("ja")) if t]
        titles += alt.get("synonyms") or []
        out.append((node["id"], titles))
    return out


# --- bridged(sourceTitles:) --------------------------------------------------

def bridged(source_titles, client_id):
    """Returns a row describing what the bridge did and what it cost."""
    before_md, before_mal = REQUESTS["mangadex"], REQUESTS["mal"]
    pool = {}
    for title in source_titles[:TITLE_SEARCH_LIMIT]:
        listings = mangadex_search(title)
        time.sleep(0.3)
        for listing in (listings or []):
            pool.setdefault(listing[0], listing)
    round_a = REQUESTS["mangadex"] - before_md

    if not pool:
        return {"outcome": "no-pool", "malId": None, "roundA": round_a, "roundB": 0,
                "pool": 0, "idBearing": 0}

    ordered = sorted(pool.values(), key=lambda x: x[0])
    id_bearing = [x for x in ordered if x[3] is not None]
    id_less = [x for x in ordered if x[3] is None]

    by_mal = {}
    for lid, display, alts, mal in id_bearing:
        by_mal.setdefault(mal, []).extend([display] + alts)
    id_candidates = [(k, by_mal[k]) for k in sorted(by_mal)]

    matched, top, runner = best_match(source_titles, id_candidates)
    if matched is not None:
        return {"outcome": "recovered-round-a", "malId": matched, "roundA": round_a,
                "roundB": 0, "pool": len(pool), "idBearing": len(id_bearing),
                "top": round(top, 3), "runner": round(runner, 3) if runner is not None else None}

    # The id-less side: "right series, no MAL link".
    idless_cands = [(x[0], [x[1]] + x[2]) for x in id_less]
    identified, itop, irunner = best_match(source_titles, idless_cands)
    if identified is None:
        return {"outcome": "no-match", "malId": None, "roundA": round_a, "roundB": 0,
                "pool": len(pool), "idBearing": len(id_bearing),
                "top": round(top, 3), "idlessTop": round(itop, 3)}

    listing = pool[identified]
    harvested = [listing[1]] + listing[2]
    lowered = {t.lower() for t in source_titles}
    new_spellings = [s for s in harvested if s.lower() not in lowered]
    if not new_spellings:
        return {"outcome": "identified-no-new-titles", "malId": None, "roundA": round_a,
                "roundB": 0, "pool": len(pool), "idBearing": len(id_bearing),
                "harvested": len(harvested)}

    before_mal_b = REQUESTS["mal"]
    retry = {}
    for spelling in new_spellings[:TITLE_SEARCH_LIMIT]:
        cands = mal_search(spelling, client_id)
        time.sleep(0.4)
        for cid, titles in (cands or []):
            retry.setdefault(cid, titles)
    round_b = REQUESTS["mal"] - before_mal_b

    retry_cands = [(k, retry[k]) for k in sorted(retry)]
    matched2, top2, runner2 = best_match(source_titles + harvested, retry_cands)
    return {"outcome": "recovered-round-b" if matched2 else "round-b-missed",
            "malId": matched2, "roundA": round_a, "roundB": round_b,
            "pool": len(pool), "idBearing": len(id_bearing),
            "harvested": len(harvested), "newSpellings": len(new_spellings),
            "top": round(top2, 3) if matched2 else round(top2, 3)}


def main():
    client_id = sys.argv[1]
    rows = []
    for title in REFUSALS:
        row = bridged([title], client_id)
        row["title"] = title
        row["extra"] = row["roundA"] + row["roundB"]
        rows.append(row)
        print(f"  {title[:44]:46} {row['outcome']:26} "
              f"A={row['roundA']} B={row['roundB']} mal={row['malId']}", file=sys.stderr)

    recovered = [r for r in rows if r["malId"] is not None]
    total_extra = sum(r["extra"] for r in rows)
    summary = {
        "refusals": len(rows),
        "recovered": len(recovered),
        "totalExtraRequests": total_extra,
        "extraPerRefusal": round(total_extra / len(rows), 2),
        "extraPerRecoveredId": round(total_extra / len(recovered), 2) if recovered else None,
        "librarySize": LIBRARY_SIZE,
        "extraPerLibraryTitle": round(total_extra / LIBRARY_SIZE, 3),
        "requestsByAPI": dict(REQUESTS),
    }
    print(json.dumps({"rows": rows, "summary": summary}, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
