"""Can WeebCentral titles be resolved to MyAnimeList at all?

Replicates MALTitleMatcher (ADR-0008) + excludingNovels (ADR-0017) against the live MAL
API, on real WeebCentral titles. Ground truth comes from MangaDex's links.mal for the
same title, so a "resolved" count is never reported without a correctness check.

api.mangadex.org rejects Python's urllib TLS -> shell out to curl for everything.
"""
import html
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


def curl(url, headers=()):
    cmd = ["curl", "-s", "--compressed", "-A", UA]
    for h in headers:
        cmd += ["-H", h]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, timeout=60)
    return out.stdout.decode("utf-8", "replace")


# --- MALTitleMatcher, ported ------------------------------------------------

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
    """candidates: [(id, [titles])]. Returns (id, best, runner_up) or (None, best, runner)."""
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


# --- Sources ----------------------------------------------------------------

def weebcentral_titles(sort, offset, limit):
    url = (f"https://weebcentral.com/search/data?sort={sort}"
           f"&display_mode=Full%20Display&limit={limit}&offset={offset}")
    page = curl(url)
    seen, out = set(), []
    for m in re.finditer(r'alt="([^"]*?) cover"', page):
        t = html.unescape(m.group(1))
        if t not in seen:
            seen.add(t)
            out.append(t)
    return out


def mal_search(title, client_id):
    url = ("https://api.myanimelist.net/v2/manga?q="
           + re.sub(r"[^A-Za-z0-9]", "%20", title)[:64]
           + "&limit=10&fields=alternative_titles,media_type")
    raw = curl(url, headers=[f"X-MAL-CLIENT-ID: {client_id}"])
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


def mangadex_mal_id(title):
    """Independent ground truth: MangaDex's own links.mal for the same title."""
    q = re.sub(r"[^A-Za-z0-9]", "%20", title)[:100]
    raw = curl(f"https://api.mangadex.org/manga?title={q}&limit=5")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None, None
    best, best_score = None, 0.0
    for m in data.get("data", []):
        attrs = m["attributes"]
        names = [v for v in (attrs.get("title") or {}).values()]
        for alt in attrs.get("altTitles") or []:
            names += list(alt.values())
        score = max((similarity(normalize(title), normalize(n)) for n in names), default=0.0)
        if score > best_score:
            best_score, best = score, attrs
    if best is None or best_score < 0.90:
        return None, best_score
    mal = ((best.get("links") or {}).get("mal"))
    return (int(mal) if mal and mal.isdigit() else None), best_score


def main():
    client_id = sys.argv[1]
    cohorts = [("popularity-top", "Popularity", 0, 25),
               ("popularity-deep", "Popularity", 400, 25)]
    report = {}
    for name, sort, offset, limit in cohorts:
        titles = weebcentral_titles(sort, offset, limit)
        rows = []
        for t in titles:
            cands = mal_search(t, client_id)
            time.sleep(0.4)
            if cands is None:
                rows.append({"title": t, "outcome": "search-failed"})
                continue
            mid, top, runner = best_match([t], cands)
            truth, truth_score = mangadex_mal_id(t)
            time.sleep(0.3)
            rows.append({"title": t, "resolved": mid, "top": round(top, 3),
                         "runner": round(runner, 3) if runner is not None else None,
                         "candidates": len(cands),
                         "mangadex_mal": truth,
                         "mangadex_title_score": round(truth_score or 0, 3)})
        report[name] = rows
        print(f"--- {name}: {len(titles)} titles", file=sys.stderr)
    print(json.dumps(report, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    main()
