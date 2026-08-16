"""Does a wider search input recover reverse-resolution misses? — measurement harness.

Runs the protocol registered in
docs/superpowers/specs/2026-08-15-search-input-width-measurement-protocol.md

Replicates MoreLikeThis.pickMatch + MALTitleMatcher (ADR-0008) against live MAL,
AniList and MangaDex. Reports numbers only; the verdict is applied by hand against the
pre-registered gates, which live in the spec and NOT in this file — a script that knows
its own pass mark invites tuning it.

The lever under test is REACH, not matching. Baseline searches MangaDex with one
spelling; treatment searches with the first N spellings and unions the candidates into
ONE pool before matching (MALEntityResolver's shipped fan-out shape — a per-spelling max
would route around the ambiguity guard, ADR-0008).

Stages are separate subcommands, each reading and writing JSON in --out:

    seeds     works.json   -> seeds.json      (no network)
    mal-rows  seeds.json   -> mal_rows.json   (MAL; needs MAL_CLIENT_ID)
    al-rows   seeds.json   -> al_rows.json    (AniList GraphQL)
    measure   *_rows.json  -> measure_<arm>.json  (MangaDex; the run)
    score     measure_*    -> score.json

Scars carried over from the previous three runs, enforced rather than remembered:

1. A MAL body missing its payload key is a CONFIGURATION FAILURE, not a clean miss.
2. Percent-encode UTF-8 BYTES — str.isalnum() is true for CJK, and raw multibyte on the
   wire makes MangaDex answer 400 on exactly the rows this needs.
3. MAL answers 307 on some merged ids and following the redirect hangs. Abort loudly.
4. pick / refusal / search-failure are three outcomes, never collapsed.

api.mangadex.org rejects Python's urllib TLS -> shell out to curl for everything.
"""
import argparse
import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.parse

API_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/17.0 Safari/605.1.15")

# MALTitleMatcher's constants (ADR-0008).
NOISE = {"manga", "season", "part", "cour"}
THRESHOLD = 0.90
MARGIN = 0.05

WORKS_JSON = ("~/Library/Developer/CoreSimulator/Devices/"
              "2A0D54DF-5961-4286-A2B6-F24B4F7537B4/data/Containers/Data/Application/"
              "2A20DDA1-723A-43E3-8AF9-0695A0244E93/Library/Application Support/works.json")


# TagPairSeeding.swift's `seedExcludedTagCategories`, flattened to the tag names those
# categories cover in this library — the vocabulary call that resolves categories is an
# in-app cache this harness has no access to.
EXCLUDED_TAGS = {"Full Color", "Four-koma", "Male Protagonist", "Female Protagonist",
                 "Primarily Adult Cast", "Primarily Female Cast", "Primarily Male Cast",
                 "Shounen", "Seinen", "Shoujo", "Josei", "Kodomo"}


class Abort(Exception):
    """A condition under which recording anything would be recording a fiction."""


def curl(url, headers=(), ua=API_UA, post=None):
    cmd = ["curl", "-s", "--compressed", "-A", ua, "-w", "\n__HTTP__%{http_code}"]
    for h in headers:
        cmd += ["-H", h]
    if post is not None:
        cmd += ["-X", "POST", "--data-binary", post]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, timeout=60)
    body = out.stdout.decode("utf-8", "replace")
    code = None
    if "\n__HTTP__" in body:
        body, _, tail = body.rpartition("\n__HTTP__")
        code = tail.strip()
    return body, code


def q(text, limit=100):
    """Percent-encode a title the way the app's URLQueryItem would — UTF-8 bytes (scar 2)."""
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
    """Mirrors MALTitleMatcher.bestMatch: ONE ranked list over the title cross-product,
    therefore one ambiguity guard. Returns (id|None, top, runner_up|None)."""
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
        return None, top[1], runner
    return top[0], top[1], runner


def pick_match(target_mal_id, mal_title, candidates):
    """MoreLikeThis.pickMatch. `candidates`: [{id, titles, mal}].

    Returns (id|None, arm, score, runner, wrong_id_hit). The strong arm is an exact malId
    hit; the fuzzy arm sees ONE candidate title, exactly as the shipped code does
    (`candidates.map { (id: $0.id, titles: [$0.title]) }`).
    """
    for c in candidates:
        if c["mal"] is not None and c["mal"] == target_mal_id:
            return c["id"], "exact-malid", 1.0, None
    mid, top, runner = best_match([mal_title], [(c["id"], [c["titles"][0]]) for c in candidates])
    return mid, ("fuzzy" if mid else None), top, runner


# --- Sources ----------------------------------------------------------------

def mal_get(path, client_id, what):
    raw, code = curl(f"https://api.myanimelist.net/v2/{path}",
                     headers=[f"X-MAL-CLIENT-ID: {client_id}"])
    if code in ("301", "302", "307", "308"):
        # Scar 3: merged ids redirect and following it hangs.
        raise Abort(f"MAL answered {code} for {what} — merged id. Skip it, do not follow.")
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise Abort(f"MAL {what} returned non-JSON (HTTP {code}): {raw[:200]!r}")
    return data, code


def mal_detail(mal_id, client_id, fields):
    data, code = mal_get(f"manga/{mal_id}?fields={fields}", client_id, f"/manga/{mal_id}")
    if "id" not in data:
        # Scar 1: a request without a usable client id answers with an error body and no
        # payload. Reporting that as "no data" is how a run invents clean misses.
        raise Abort(f"MAL /manga/{mal_id} body has no 'id' (HTTP {code}): {raw_preview(data)}. "
                    "Check MAL_CLIENT_ID — do NOT treat this as an empty result.")
    return data


def raw_preview(data):
    return json.dumps(data, ensure_ascii=False)[:200]


def mal_all_titles(node):
    """MyAnimeListManga.allTitles: primary, then en/ja alternates, then synonyms.
    Blank entries dropped, order preserved, deduped — the Swift property's contract."""
    alt = node.get("alternative_titles") or {}
    ordered = [node.get("title"), alt.get("en"), alt.get("ja")] + list(alt.get("synonyms") or [])
    out = []
    for t in ordered:
        t = (t or "").strip()
        if t and t not in out:
            out.append(t)
    return out


def mangadex_candidates(title):
    """MangaDex /manga?title= — searchManga's shipped shape: limit 20, covers included."""
    raw, code = curl(f"https://api.mangadex.org/manga?title={q(title)}"
                     "&limit=20&includes[]=cover_art")
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
        for a in attrs.get("altTitles") or []:
            names += [v for v in a.values() if v]
        mal = (attrs.get("links") or {}).get("mal")
        out.append({"id": m["id"],
                    "titles": list(dict.fromkeys(names)),
                    "mal": int(mal) if mal and str(mal).isdigit() else None})
    return out


ANILIST_POOL_QUERY = """
query ($tags: [String], $rank: Int, $perPage: Int) {
  Page(page: 1, perPage: $perPage) {
    media(type: MANGA, tag_in: $tags, minimumTagRank: $rank,
          isAdult: false, sort: POPULARITY_DESC) {
      id idMal
      title { romaji english native }
      synonyms
    }
  }
}
"""


def anilist_pool(tags, rank, per_page):
    """One pair's page, mirroring AniListAPI.mediaByTagsQuery. `tag_in` is a CONJUNCTION."""
    payload = json.dumps({"query": ANILIST_POOL_QUERY,
                          "variables": {"tags": tags, "rank": rank, "perPage": per_page}})
    raw, code = curl("https://graphql.anilist.co",
                     headers=["Content-Type: application/json",
                              "Accept: application/json"],
                     post=payload)
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise Abort(f"AniList non-JSON (HTTP {code}): {raw[:200]!r}")
    if data.get("errors"):
        raise Abort(f"AniList errors (HTTP {code}): {raw_preview(data['errors'])}")
    if "data" not in data:
        raise Abort(f"AniList body has no 'data' (HTTP {code}): {raw[:200]!r}")
    page = (data["data"] or {}).get("Page") or {}
    return page.get("media") or []


def anilist_titles(node):
    """AniListWork.knownTitles: romaji, english, native, then synonyms."""
    t = node.get("title") or {}
    ordered = [t.get("romaji"), t.get("english"), t.get("native")] + list(node.get("synonyms") or [])
    out = []
    for s in ordered:
        s = (s or "").strip()
        if s and s not in out:
            out.append(s)
    return out


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
    """Library Works -> MAL seeds, and the seeded tag PAIRS the AniList pool queries.

    Pairs mirror `seedPairs` (TagPairSeeding.swift): both legs at rank >= 60 on the same
    Work, weighted by min(rank)/100 summed over carrying Works. Two documented departures,
    both because this runs outside the app: engagement weights come from `TasteProfile`,
    which is not in works.json, so every Work votes 1.0; and the category/adult exclusions
    need AniList's tag vocabulary, so `seedExcludedTagCategories` is applied by name only.
    """
    works = json.load(open(os.path.expanduser(args.works)))["works"]
    seeds, pair_weight, pair_works = [], {}, {}
    for w in works:
        mal = (w.get("externalIds") or {}).get("mal")
        if mal:
            seeds.append({"malId": mal, "title": w.get("displayTitle")})
        ranked = sorted({t["name"]: t.get("rank") or 0
                         for t in ((w.get("snapshot") or {}).get("tags") or [])
                         if (t.get("rank") or 0) >= 60 and t["name"] not in EXCLUDED_TAGS}.items())
        for i in range(len(ranked)):
            for j in range(i + 1, len(ranked)):
                (a, ra), (b, rb) = ranked[i], ranked[j]
                key = f"{a}|{b}"
                pair_weight[key] = pair_weight.get(key, 0.0) + min(ra, rb) / 100.0
                pair_works.setdefault(key, set()).add(w["id"]["raw"])
    seeds.sort(key=lambda s: s["malId"])
    pairs = [{"pair": k.split("|"), "weight": round(v, 3), "works": len(pair_works[k])}
             for k, v in sorted(pair_weight.items(), key=lambda kv: (-kv[1], kv[0]))]
    save(args.out, "seeds.json", {"works": len(works), "seeds": seeds, "pairs": pairs})
    print(f"{len(seeds)} of {len(works)} Works carry a MAL id; {len(pairs)} seeded tag pairs",
          file=sys.stderr)


def stage_mal_rows(args):
    """Seeds -> their MAL recommendations -> each row's full title set.

    --hops 2 expands the frame by treating hop-1 recommendations as seeds. The library's
    own recommendation slots are a bounded frame (86 seeds -> 107 unique rows on
    2026-08-15), which cannot reach the registered n on its own; the expansion is declared
    in the protocol's amendment, not invented here.
    """
    client_id = os.environ.get("MAL_CLIENT_ID") or args.client_id
    if not client_id:
        sys.exit("MAL_CLIENT_ID not set (env or --client-id). Secrets.xcconfig is at the repo root.")
    seeds = load(args.out, "seeds.json")["seeds"]
    frontier = [s["malId"] for s in seeds]
    seen_seeds, rows, by_id, skipped = set(), [], {}, []
    for hop in range(1, args.hops + 1):
        nxt = []
        for i, mal_id in enumerate(frontier, 1):
            if mal_id in seen_seeds:
                continue
            seen_seeds.add(mal_id)
            try:
                detail = mal_detail(mal_id, client_id, "alternative_titles,recommendations")
            except Abort as e:
                if "merged id" in str(e):
                    skipped.append({"malId": mal_id, "why": "redirect"})
                    continue
                raise
            for rank, rec in enumerate(sorted(detail.get("recommendations") or [],
                                              key=lambda r: -r.get("numRecommendations", 0))):
                node = rec["node"]
                if node["id"] in by_id:
                    by_id[node["id"]]["seenFrom"].append(mal_id)
                    continue
                row = {"malId": node["id"], "title": node["title"], "hop": hop,
                       "rank": rank, "inShippedTop8": rank < 8, "seenFrom": [mal_id],
                       "titles": None}
                by_id[node["id"]] = row
                rows.append(row)
                nxt.append(node["id"])
            print(f"[hop {hop}] [{i}/{len(frontier)}] {mal_id}: {len(rows)} rows",
                  file=sys.stderr)
            time.sleep(args.delay)
        frontier = nxt
        if len(rows) >= args.max_rows:
            break

    # The treatment's title set. One detail call per row — the recommendation node carries
    # only id+title, and `allTitles` is what the wider search spends its queries on.
    for i, row in enumerate(rows, 1):
        if len(rows) > args.max_rows and i > args.max_rows:
            break
        try:
            detail = mal_detail(row["malId"], client_id, "alternative_titles")
        except Abort as e:
            if "merged id" in str(e):
                skipped.append({"malId": row["malId"], "why": "redirect"})
                row["titles"] = [row["title"]]
                continue
            raise
        row["titles"] = mal_all_titles(detail)
        print(f"[titles {i}/{len(rows)}] {row['title'][:38]}: {len(row['titles'])}",
              file=sys.stderr)
        time.sleep(args.delay)
    rows = [r for r in rows if r["titles"]][:args.max_rows]
    save(args.out, "mal_rows.json", {"rows": rows, "skipped": skipped, "hops": args.hops})


def stage_al_rows(args):
    """The ADR-0011 ranked pool's candidates: tag PAIRS, conjunctive, popularity-sorted."""
    pairs = [p["pair"] for p in load(args.out, "seeds.json")["pairs"][:args.pairs]]
    rows, by_id, used = [], {}, []
    for pair in pairs:
        if len(rows) >= args.max_rows:
            break
        media = anilist_pool(pair, args.rank, args.per_page)
        used.append({"pair": pair, "returned": len(media)})
        for node in media:
            if not node.get("idMal") or node["idMal"] in by_id:
                continue
            titles = anilist_titles(node)
            if not titles:
                continue
            row = {"malId": node["idMal"], "title": titles[0], "titles": titles,
                   "anilistId": node["id"], "fromPair": pair}
            by_id[node["idMal"]] = row
            rows.append(row)
        print(f"[{len(used)}/{len(pairs)}] {' + '.join(pair)}: {len(media)} -> {len(rows)} rows",
              file=sys.stderr)
        time.sleep(args.delay)
    save(args.out, "al_rows.json", {"rows": rows[:args.max_rows], "pairs": used})


def stage_measure(args):
    """The run. Baseline = one query on the primary title. Treatment = queries 2..K
    unioned into ONE pool, re-picked after each, so N falls out of the data.

    Stopping rule (registered): draw until `--target-unresolved` baseline-unresolved rows
    accumulate, capped at `--query-cap` BASELINE queries. Whichever binds first.
    """
    rows = load(args.out, f"{args.arm}_rows.json")["rows"]
    out, baseline_queries, unresolved = [], 0, 0
    stop = None
    for i, row in enumerate(rows, 1):
        if unresolved >= args.target_unresolved:
            stop = "target-unresolved"
            break
        if baseline_queries >= args.query_cap:
            stop = "query-cap"
            break
        titles = row["titles"][:args.max_spellings]
        rec = {"malId": row["malId"], "title": row["title"], "titles": titles,
               "spellings": len(titles)}
        try:
            pool = mangadex_candidates(titles[0])
        except Abort as e:
            # Searched-and-threw is its own outcome (scar 4): it is not a miss, and the
            # row cannot be counted either way.
            rec["outcome"] = "search-failure"
            rec["error"] = str(e)[:200]
            out.append(rec)
            print(f"[{i}] {row['title'][:38]}: SEARCH-FAILURE", file=sys.stderr)
            continue
        baseline_queries += 1
        by_id = {c["id"]: c for c in pool}
        mid, arm, score, runner = pick_match(row["malId"], row["title"], pool)
        rec["baseline"] = {"picked": mid, "arm": arm, "score": round(score or 0, 4),
                           "runnerUp": runner, "candidates": len(pool),
                           "wrongMalIds": sorted({c["mal"] for c in pool
                                                  if c["mal"] and c["mal"] != row["malId"]})[:5]}
        if mid:
            rec["outcome"] = "baseline-resolved"
            out.append(rec)
            print(f"[{i}] {row['title'][:38]}: resolved ({arm})", file=sys.stderr)
            time.sleep(args.delay)
            continue

        unresolved += 1
        rec["outcome"] = "baseline-unresolved"
        rec["treatment"] = []
        for k, spelling in enumerate(titles[1:], start=2):
            try:
                more = mangadex_candidates(spelling)
            except Abort as e:
                rec["treatment"].append({"query": k, "spelling": spelling,
                                         "error": str(e)[:200]})
                continue
            added = [c for c in more if c["id"] not in by_id]
            for c in added:
                by_id[c["id"]] = c
            union = list(by_id.values())
            tmid, tarm, tscore, trunner = pick_match(row["malId"], row["title"], union)
            rec["treatment"].append({"query": k, "spelling": spelling,
                                     "added": len(added), "poolSize": len(union),
                                     "picked": tmid, "arm": tarm,
                                     "score": round(tscore or 0, 4), "runnerUp": trunner})
            time.sleep(args.delay)
            if tmid:
                rec["recoveredAtQuery"] = k
                rec["recoveredArm"] = tarm
                rec["recoveredId"] = tmid
                rec["recoveredMalOnEntry"] = by_id[tmid]["mal"]
                break
        out.append(rec)
        flag = f"RECOVERED@{rec.get('recoveredAtQuery')}" if rec.get("recoveredAtQuery") else "still unresolved"
        print(f"[{i}] {row['title'][:38]}: {flag} ({unresolved} unresolved so far)",
              file=sys.stderr)
    save(args.out, f"measure_{args.arm}.json",
         {"arm": args.arm, "rows": len(out), "baselineQueries": baseline_queries,
          "unresolved": unresolved, "stoppedBy": stop or "frame-exhausted",
          "maxSpellings": args.max_spellings, "results": out})


def stage_score(args):
    """Aggregate per arm. Reports numbers; the gates live in the spec, not here."""
    report = {}
    for arm in args.arms:
        try:
            m = load(args.out, f"measure_{arm}.json")
        except FileNotFoundError:
            continue
        rows = m["results"]
        unresolved = [r for r in rows if r["outcome"] == "baseline-unresolved"]
        recovered = [r for r in unresolved if r.get("recoveredAtQuery")]
        # Fuzzy-arm regressions: a baseline fuzzy pick that a wider pool would refuse.
        # Only computable where the baseline picked fuzzily AND treatment ran, which by
        # construction it does not — treatment only runs on unresolved rows. Recorded as
        # the count of baseline fuzzy picks, the population such a regression could come
        # from, so the write-up can say what was and was not observable.
        fuzzy_baseline = [r for r in rows
                          if r.get("baseline", {}).get("arm") == "fuzzy"]
        wrong = [r for r in recovered
                 if r.get("recoveredArm") == "exact-malid"
                 and r.get("recoveredMalOnEntry") != r["malId"]]
        extra = sum(len(r.get("treatment", [])) for r in unresolved)
        by_query = {}
        for r in recovered:
            k = r["recoveredAtQuery"]
            by_query[k] = by_query.get(k, 0) + 1
        report[arm] = {
            "rows": len(rows),
            "searchFailures": sum(1 for r in rows if r["outcome"] == "search-failure"),
            "baselineResolved": sum(1 for r in rows if r["outcome"] == "baseline-resolved"),
            "baselineUnresolved": len(unresolved),
            "recovered": len(recovered),
            "recoveryRate": round(len(recovered) / len(unresolved), 4) if unresolved else None,
            "recoveredByQueryIndex": dict(sorted(by_query.items())),
            "extraQueries": extra,
            "extraQueriesPerRecovered": round(extra / len(recovered), 2) if recovered else None,
            "wrongStrongArmPicks": len(wrong),
            "wrongDetail": [{"malId": r["malId"], "title": r["title"],
                             "gotMal": r.get("recoveredMalOnEntry"),
                             "mangaDexId": r.get("recoveredId")} for r in wrong],
            "baselineFuzzyPicks": len(fuzzy_baseline),
            "stoppedBy": m["stoppedBy"],
            "recoveredArms": {a: sum(1 for r in recovered if r.get("recoveredArm") == a)
                              for a in {r.get("recoveredArm") for r in recovered}},
        }
    report["note"] = ("Numbers only. Gates are in "
                      "docs/superpowers/specs/2026-08-15-search-input-width-measurement-protocol.md")
    save(args.out, "score.json", report)
    print(json.dumps(report, indent=1, ensure_ascii=False))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", default="docs/superpowers/measurements/search-width")
    p.add_argument("--delay", type=float, default=0.3)
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("seeds"); s.add_argument("--works", default=WORKS_JSON)
    s.set_defaults(fn=stage_seeds)

    s = sub.add_parser("mal-rows")
    s.add_argument("--client-id"); s.add_argument("--hops", type=int, default=1)
    s.add_argument("--max-rows", type=int, default=800)
    s.set_defaults(fn=stage_mal_rows)

    s = sub.add_parser("al-rows")
    s.add_argument("--rank", type=int, default=60); s.add_argument("--per-page", type=int, default=50)
    s.add_argument("--pairs", type=int, default=20)
    s.add_argument("--max-rows", type=int, default=800)
    s.set_defaults(fn=stage_al_rows)

    s = sub.add_parser("measure")
    s.add_argument("--arm", choices=["mal", "al"], required=True)
    s.add_argument("--target-unresolved", type=int, default=60)
    s.add_argument("--query-cap", type=int, default=1500)
    s.add_argument("--max-spellings", type=int, default=5)
    s.set_defaults(fn=stage_measure)

    s = sub.add_parser("score"); s.add_argument("--arms", nargs="+", default=["mal", "al"])
    s.set_defaults(fn=stage_score)

    args = p.parse_args()
    try:
        args.fn(args)
    except Abort as e:
        sys.exit(f"ABORT: {e}")


if __name__ == "__main__":
    main()
