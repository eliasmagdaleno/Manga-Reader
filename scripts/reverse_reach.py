"""Can reverse resolution reach beyond MangaDex? — measurement harness.

Runs the protocol registered in
docs/superpowers/specs/2026-08-13-reverse-resolution-beyond-mangadex-measurement-protocol.md

Replicates MALTitleMatcher (ADR-0008) + MoreLikeThis.pickMatch against live MAL,
MangaDex and WeebCentral. Reports numbers only; the verdict is applied by hand against
the pre-registered gates, which live in the spec and NOT in this file — a script that
knows its own pass mark invites tuning it.

Stages are separate subcommands, each reading and writing JSON in --out. Nothing is
recomputed and nothing is lost to a mid-run network failure:

    seeds   works.json        -> seeds.json        (no network)
    recs    seeds.json        -> recs.json         (MAL; needs MAL_CLIENT_ID)
    split   recs.json         -> split.json        (MangaDex)
    wc      split.json        -> wc.json           (WeebCentral)
    score   wc.json           -> score.json + adjudication sheet

Three scars from the previous two runs are enforced, not remembered:

1. A MAL response missing its payload key is a CONFIGURATION FAILURE, not a clean miss.
   Every MAL body is asserted before use and a failure aborts the stage.
2. WeebCentral does not degrade gracefully — a challenge page yields refusals that look
   exactly like real misses. Outcomes are decided by POSITIVE evidence only (a parsed
   article, or the site's own "No results found" alert); anything else aborts.
3. pick / refusal / search-failure are three outcomes, mirroring MALReverseResolver's
   cache-write discipline (.resolved / .unresolved / nothing-on-throw). They are never
   collapsed, and only `refusal` counts against yield.

api.mangadex.org rejects Python's urllib TLS -> shell out to curl for everything
(carried over from scripts/wc_resolve.py).
"""
import argparse
import html
import json
import os
import random
import re
import subprocess
import sys
import time
import unicodedata
import urllib.parse

# The UA pinned in WebViewService.swift:74 — cf_clearance is bound to it.
WC_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) "
         "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1")
API_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

# MALTitleMatcher's constants. Kept in sync by test_matcher_parity, below.
NOISE = {"manga", "season", "part", "cour"}
THRESHOLD = 0.90
MARGIN = 0.05

WORKS_JSON = ("~/Library/Developer/CoreSimulator/Devices/"
              "2A0D54DF-5961-4286-A2B6-F24B4F7537B4/data/Containers/Data/Application/"
              "2A20DDA1-723A-43E3-8AF9-0695A0244E93/Library/Application Support/works.json")


class Abort(Exception):
    """A condition under which recording anything would be recording a fiction."""


def curl(url, headers=(), ua=API_UA):
    cmd = ["curl", "-s", "--compressed", "-A", ua, "-w", "\n__HTTP__%{http_code}"]
    for h in headers:
        cmd += ["-H", h]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, timeout=60)
    body = out.stdout.decode("utf-8", "replace")
    code = None
    if "\n__HTTP__" in body:
        body, _, tail = body.rpartition("\n__HTTP__")
        code = tail.strip()
    return body, code


def q(text, limit=100):
    """Percent-encode a title for a query string the way the app's URLQueryItem would.

    Must encode UTF-8 BYTES. Python's str.isalnum() is true for CJK and other non-ASCII
    letters, so a naive "keep alphanumerics" pass emits raw multibyte characters and
    MangaDex answers 400 — on exactly the Japanese-titled recommendations this
    measurement most needs to see.
    """
    return urllib.parse.quote(text[:limit], safe="")


# --- MALTitleMatcher, ported (ADR-0008) -------------------------------------

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
    """candidates: [(id, [titles])] -> (id|None, top_score, runner_up|None).

    Mirrors MALTitleMatcher.bestMatch(sourceTitles:candidates:): one ranked list scored
    over the title cross-product, therefore one ambiguity guard. Deliberately NOT a
    per-title max of independent lists (ADR-0008).
    """
    norm_sources = [n for n in (normalize(t) for t in source_titles) if n]
    if not norm_sources or not candidates:
        return None, 0.0, None
    scored = []
    for cid, titles in candidates:
        norms = [normalize(t) for t in titles]
        best = max((similarity(s, c) for s in norm_sources for c in norms), default=0.0)
        scored.append((cid, best))
    scored.sort(key=lambda x: -x[1])
    top, runner = scored[0], (scored[1][1] if len(scored) > 1 else None)
    if top[1] < THRESHOLD:
        return None, top[1], runner
    if runner is not None and top[1] - runner < MARGIN:
        return None, top[1], runner          # too close to call — precision over recall
    return top[0], top[1], runner


def pick_match(target_mal_id, mal_title, candidates):
    """MoreLikeThis.pickMatch. `candidates`: [(id, title, mal_id|None)].

    The strong arm — an exact malId hit — is retained here even though WeebCentral can
    never satisfy it (no external ids). That absence is the whole reason for the
    measurement, and deleting the arm would hide it.
    """
    for cid, _title, cmal in candidates:
        if cmal is not None and cmal == target_mal_id:
            return cid, "exact-malid", 1.0, None
    mid, top, runner = best_match([mal_title], [(c[0], [c[1]]) for c in candidates])
    return mid, ("fuzzy" if mid else None), top, runner


# --- Sources ----------------------------------------------------------------

def mal_detail(mal_id, client_id):
    """MAL /manga/{id} with the app's exact field set. Asserts payload — see scar 1."""
    url = (f"https://api.myanimelist.net/v2/manga/{mal_id}?fields="
           "alternative_titles,synopsis,main_picture,genres,related_manga,recommendations")
    raw, code = curl(url, headers=[f"X-MAL-CLIENT-ID: {client_id}"])
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise Abort(f"MAL /manga/{mal_id} returned non-JSON (HTTP {code}): {raw[:200]!r}")
    if "id" not in data:
        # A request without a usable client id answers with an error body and no payload.
        # Reporting that as "no recommendations" is exactly the failure scar 1 names.
        raise Abort(f"MAL /manga/{mal_id} body has no 'id' (HTTP {code}): {raw[:200]!r}. "
                    "Check MAL_CLIENT_ID — do NOT treat this as an empty result.")
    return data


def mangadex_candidates(title):
    """MangaDex /manga?title= — the app's searchManga, plus the alt-title sets."""
    raw, code = curl(f"https://api.mangadex.org/manga?title={q(title)}&limit=20")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise Abort(f"MangaDex non-JSON (HTTP {code}): {raw[:200]!r}")
    if "data" not in data:
        raise Abort(f"MangaDex body has no 'data' (HTTP {code}): {raw[:200]!r}")
    out = []
    for m in data["data"]:
        attrs = m["attributes"]
        names = [v for v in (attrs.get("title") or {}).values() if v]
        for alt in attrs.get("altTitles") or []:
            names += [v for v in alt.values() if v]
        mal = (attrs.get("links") or {}).get("mal")
        out.append({"id": m["id"],
                    "titles": list(dict.fromkeys(names)),
                    "mal": int(mal) if mal and str(mal).isdigit() else None})
    return out


# Result items are `article.flex.gap-4`, and each CONTAINS two further <article> cover
# blocks (neither carrying both classes). So the item boundary is the next matching START
# tag, not the next </article> — matching to the closing tag truncates the item before its
# title link and silently yields zero candidates.
WC_ARTICLE_START = re.compile(r'<article[^>]*class="[^"]*\bflex\b[^"]*\bgap-4\b[^"]*"')
WC_SERIES_HREF = re.compile(r'href="[^"]*?/series/([^/"]+)')
WC_LINK_TITLE = re.compile(
    r'<a[^>]*class="[^"]*\blink\b[^"]*\blink-hover\b[^"]*"[^>]*>(.*?)</a>', re.S)
WC_SERIES_LINK_TEXT = re.compile(r'<a[^>]*href="[^"]*?/series/[^"]*"[^>]*>(.*?)</a>', re.S)
WC_TAG = re.compile(r"<[^>]+>")
WC_CHALLENGE = re.compile(
    r"just a moment|cf[-_]chl|turnstile|challenge-platform|__cf_bm|enable javascript",
    re.I)
WC_NO_RESULTS = re.compile(r"No results found", re.I)


def wc_search(title):
    """WeebCentral /search/data -> (outcome, candidates).

    outcome is 'ok' (candidates parsed) or 'empty' (the site's own no-results alert).
    Anything else raises Abort — see scar 2. Selectors mirror `seriesListScript` in
    WeebCentralSource.swift: article.flex.gap-4, a[href*="/series/"], a.link.link-hover.
    """
    url = ("https://weebcentral.com/search/data?sort=Best%20Match"
           f"&display_mode=Full%20Display&limit=20&offset=0&text={q(title)}")
    body, code = curl(url, ua=WC_UA)
    if code != "200":
        raise Abort(f"WeebCentral HTTP {code} for {title!r}")
    if WC_CHALLENGE.search(body):
        raise Abort(f"WeebCentral served a challenge for {title!r} — refusals from here "
                    "are indistinguishable from real misses. Fall back to driving it "
                    "in-app, as the ADR-0019 gate run did.")
    out = []
    starts = [m.start() for m in WC_ARTICLE_START.finditer(body)]
    for i, start in enumerate(starts):
        block = body[start:starts[i + 1] if i + 1 < len(starts) else len(body)]
        href = WC_SERIES_HREF.search(block)
        if not href:
            continue
        # `a.link.link-hover` with the series link as fallback — seriesListScript's
        # `titleEl || link`.
        m = WC_LINK_TITLE.search(block) or WC_SERIES_LINK_TEXT.search(block)
        raw_title = m.group(1) if m else ""
        text = html.unescape(WC_TAG.sub("", raw_title)).strip()
        if text:
            out.append((href.group(1), text, None))   # WeebCentral publishes no mal id
    if out:
        return "ok", out
    if WC_NO_RESULTS.search(body):
        return "empty", []
    # Neither articles nor the site's own empty-state: an unrecognized page. Recording a
    # refusal here would be inventing one.
    raise Abort(f"WeebCentral page for {title!r} matched neither results nor the "
                f"no-results alert ({len(body)} bytes) — page shape may have changed.")


# --- Stages -----------------------------------------------------------------

def load(out_dir, name):
    with open(os.path.join(out_dir, name)) as f:
        return json.load(f)


def save(out_dir, name, obj):
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, name)
    with open(path, "w") as f:
        json.dump(obj, f, indent=1, ensure_ascii=False)
    print(f"wrote {path}", file=sys.stderr)


def stage_seeds(args):
    works = json.load(open(os.path.expanduser(args.works)))["works"]
    seeds = []
    for w in works:
        mal = (w.get("externalIds") or {}).get("mal")
        if mal:
            seeds.append({"malId": mal,
                          "title": w.get("displayTitle"),
                          "sources": sorted({l["sourceId"] for l in w.get("listings", [])})})
    seeds.sort(key=lambda s: s["malId"])
    save(args.out, "seeds.json", {"works": len(works), "seeds": seeds})
    print(f"{len(seeds)} of {len(works)} library Works carry a MAL id", file=sys.stderr)


def stage_recs(args):
    client_id = os.environ.get("MAL_CLIENT_ID") or args.client_id
    if not client_id:
        sys.exit("MAL_CLIENT_ID not set (env or --client-id). Secrets.xcconfig is at the repo root.")
    seeds = load(args.out, "seeds.json")["seeds"]
    rows, seen = [], {}
    for i, seed in enumerate(seeds, 1):
        detail = mal_detail(seed["malId"], client_id)
        recs = detail.get("recommendations") or []
        # The app takes the top 8 by weight (MoreLikeThisProvider.topRecommendations).
        # Rank is recorded so the analysis can restrict to the shipped top-8 without a
        # re-run, while the full list stays available as the wider sample frame.
        ranked = sorted(recs, key=lambda r: -r.get("numRecommendations", 0))
        for rank, rec in enumerate(ranked):
            node = rec["node"]
            key = node["id"]
            if key in seen:
                seen[key]["seenFrom"].append(seed["malId"])
                continue
            row = {"malId": node["id"], "title": node["title"],
                   "weight": rec.get("numRecommendations", 0), "rank": rank,
                   "inShippedTop8": rank < 8, "seenFrom": [seed["malId"]]}
            seen[key] = row
            rows.append(row)
        print(f"[{i}/{len(seeds)}] {seed['title'][:40]}: {len(recs)} recs", file=sys.stderr)
        time.sleep(args.delay)
    save(args.out, "recs.json", {"seeds": len(seeds), "unique": len(rows), "recs": rows})


def stage_split(args):
    recs = load(args.out, "recs.json")["recs"]
    if args.only_top8:
        recs = [r for r in recs if r["inShippedTop8"]]
    rows = []
    for i, rec in enumerate(recs, 1):
        cands = mangadex_candidates(rec["title"])
        hit = next((c for c in cands if c["mal"] == rec["malId"]), None)
        row = dict(rec)
        row["population"] = "easy" if hit else "hard"
        row["mangaDexId"] = hit["id"] if hit else None
        # Labels for Easy come from MangaDex's alt-title set, which the WeebCentral
        # matcher never sees. That is what keeps the Easy grading non-circular.
        row["mangaDexTitles"] = hit["titles"] if hit else None
        rows.append(row)
        print(f"[{i}/{len(recs)}] {rec['title'][:40]}: {row['population']}", file=sys.stderr)
        time.sleep(args.delay)
    easy = sum(1 for r in rows if r["population"] == "easy")
    save(args.out, "split.json", {"easy": easy, "hard": len(rows) - easy, "rows": rows})
    print(f"easy={easy} hard={len(rows) - easy}", file=sys.stderr)


def stage_wc(args):
    rows = load(args.out, "split.json")["rows"]
    done = {}
    if args.resume and os.path.exists(os.path.join(args.out, "wc.json")):
        done = {r["malId"]: r for r in load(args.out, "wc.json")["rows"]}
        print(f"resuming: {len(done)} already recorded", file=sys.stderr)
    out = []
    try:
        for i, row in enumerate(rows, 1):
            if row["malId"] in done:
                out.append(done[row["malId"]])
                continue
            r = dict(row)
            try:
                status, cands = wc_search(row["title"])
            except Abort:
                if args.strict:
                    raise
                # A per-title failure is the third outcome: searched-and-threw. It is
                # recorded as such and excluded from yield, never as a refusal.
                r.update(outcome="search-failure", wcId=None, score=None, runnerUp=None)
                out.append(r)
                print(f"[{i}/{len(rows)}] {row['title'][:40]}: SEARCH-FAILURE", file=sys.stderr)
                time.sleep(args.delay)
                continue
            wc_id, arm, top, runner = pick_match(row["malId"], row["title"], cands)
            r.update(outcome="pick" if wc_id else "refusal",
                     wcId=wc_id, arm=arm, score=round(top, 3),
                     runnerUp=round(runner, 3) if runner is not None else None,
                     candidates=len(cands),
                     wcTitle=next((c[1] for c in cands if c[0] == wc_id), None),
                     wcEmpty=(status == "empty"))
            out.append(r)
            print(f"[{i}/{len(rows)}] {row['title'][:40]}: {r['outcome']} "
                  f"({r['score']})", file=sys.stderr)
            time.sleep(args.delay)
    finally:
        # Partial progress is still evidence; never lose a run to a late abort.
        save(args.out, "wc.json", {"rows": out})


def stage_score(args):
    rows = load(args.out, "wc.json")["rows"]
    report = {}
    for pop in ("easy", "hard"):
        p = [r for r in rows if r["population"] == pop]
        picks = [r for r in p if r["outcome"] == "pick"]
        refusals = [r for r in p if r["outcome"] == "refusal"]
        failures = [r for r in p if r["outcome"] == "search-failure"]
        block = {"n": len(p), "picks": len(picks), "refusals": len(refusals),
                 "searchFailures": len(failures),
                 # Yield is over searched-and-answered only: a search that threw is not
                 # evidence of absence, so it is excluded rather than counted a miss.
                 "yield": round(len(picks) / max(1, len(picks) + len(refusals)), 4)}
        if pop == "easy":
            # Strict normalized comparison against MangaDex's alt titles — deliberately
            # NOT the fuzzy matcher, which would be grading itself.
            correct = [r for r in picks
                       if normalize(r.get("wcTitle") or "")
                       in {normalize(t) for t in (r.get("mangaDexTitles") or [])}]
            block["correct"] = len(correct)
            block["precision"] = round(len(correct) / len(picks), 4) if picks else None
            block["wrong"] = [{"mal": r["malId"], "malTitle": r["title"],
                               "wcTitle": r.get("wcTitle"), "score": r.get("score")}
                              for r in picks if r not in correct]
        report[pop] = block

    hard_picks = [r for r in rows if r["population"] == "hard" and r["outcome"] == "pick"]
    rng = random.Random(args.seed)
    sample = rng.sample(hard_picks, min(args.sample, len(hard_picks)))
    report["adjudicationSample"] = len(sample)
    report["note"] = ("Verdict is NOT computed here. Apply the pre-registered gates from "
                      "the protocol spec by hand, including the inconclusive thresholds.")
    save(args.out, "score.json", report)

    lines = ["# Hard-population adjudication sheet",
             "",
             f"{len(sample)} picks sampled at random (seed {args.seed}) from "
             f"{len(hard_picks)} hard picks.",
             "Mark each row correct (y) or wrong (n): is the WeebCentral title the same "
             "work as the MAL title?",
             "",
             "| # | MAL title | WeebCentral title | score | y/n |",
             "|---|---|---|---|---|"]
    for i, r in enumerate(sample, 1):
        lines.append(f"| {i} | {r['title']} | {r.get('wcTitle')} | {r.get('score')} |  |")
    path = os.path.join(args.out, "adjudication.md")
    with open(path, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"wrote {path}", file=sys.stderr)
    print(json.dumps(report, indent=1, ensure_ascii=False))


def stage_selftest(args):
    """Parity checks for the ported matcher, and a live shape check on each source.

    The matcher cases mirror assertions in MangaCartaTests so a drift in the port shows
    up here rather than as a wrong measurement.
    """
    fails = []

    def check(label, got, want):
        if got != want:
            fails.append(f"{label}: got {got!r}, want {want!r}")

    check("normalize drops noise", normalize("Berserk Manga"), "berserk")
    check("normalize folds diacritics", normalize("Joséphine Impératrice"),
          "josephine imperatrice")
    check("normalize punctuation", normalize("Yotsuba to!"), "yotsuba to")
    check("similarity identical", similarity("abc", "abc"), 1.0)
    check("similarity empty", similarity("", "abc"), 0.0)
    # Ambiguity guard rejects even an exact hit when the runner-up is too close.
    got, _, _ = best_match(["one piece"], [(1, ["One Piece"]), (2, ["One Piece!"])])
    check("ambiguity guard rejects", got, None)
    got, _, _ = best_match(["one piece"], [(1, ["One Piece"]), (2, ["Naruto"])])
    check("clear winner accepted", got, 1)
    # The strong arm fires regardless of title distance; the fuzzy arm never sees it.
    got, arm, _, _ = pick_match(42, "Totally Different", [("x", "Unrelated", 42)])
    check("exact malId arm", (got, arm), ("x", "exact-malid"))
    got, arm, _, _ = pick_match(42, "Berserk", [("x", "Berserk", None)])
    check("fuzzy arm on id-less source", (got, arm), ("x", "fuzzy"))

    print("matcher parity:", "FAIL" if fails else "ok", file=sys.stderr)
    for f in fails:
        print("  " + f, file=sys.stderr)

    if not args.offline:
        status, cands = wc_search("Berserk")
        print(f"weebcentral live: {status}, {len(cands)} candidates, "
              f"first={cands[0][1] if cands else None!r}", file=sys.stderr)
        status, cands = wc_search("Yotsuba to!")
        print(f"weebcentral empty-state: {status}, {len(cands)} candidates", file=sys.stderr)
        md = mangadex_candidates("Berserk")
        print(f"mangadex live: {len(md)} candidates, "
              f"mal ids present={sum(1 for c in md if c['mal'])}", file=sys.stderr)
    if fails:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="docs/superpowers/measurements/reverse-reach")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("seeds"); s.set_defaults(fn=stage_seeds)
    s.add_argument("--works", default=WORKS_JSON)

    s = sub.add_parser("recs"); s.set_defaults(fn=stage_recs)
    s.add_argument("--client-id"); s.add_argument("--delay", type=float, default=0.5)

    s = sub.add_parser("split"); s.set_defaults(fn=stage_split)
    s.add_argument("--delay", type=float, default=0.3)
    s.add_argument("--only-top8", action="store_true",
                   help="restrict to the 8 recommendations the app actually shows")

    s = sub.add_parser("wc"); s.set_defaults(fn=stage_wc)
    s.add_argument("--delay", type=float, default=0.5)
    s.add_argument("--resume", action="store_true")
    s.add_argument("--strict", action="store_true",
                   help="abort the whole run on any WeebCentral anomaly")

    s = sub.add_parser("score"); s.set_defaults(fn=stage_score)
    s.add_argument("--sample", type=int, default=30); s.add_argument("--seed", type=int, default=1)

    s = sub.add_parser("selftest"); s.set_defaults(fn=stage_selftest)
    s.add_argument("--offline", action="store_true")

    args = ap.parse_args()
    try:
        args.fn(args)
    except Abort as e:
        sys.exit(f"ABORT: {e}")


if __name__ == "__main__":
    main()
