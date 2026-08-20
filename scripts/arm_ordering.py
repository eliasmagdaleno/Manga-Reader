"""Does it matter which arm reverse-resolves a shared target first?

Both reverse-resolution consumers — the MAL More-Like-This provider and the ADR-0011
AniList pool — hold one `MALReverseResolver` and answer into one cache, and the ADR-0020
AniList-arm run found them asking about the same titles: 10 of 12 pool targets were already
resolved by the MAL arm when the pool got there.

Whoever asks first fixes **which spelling is tried as the baseline search**, because the two
arms build their targets from different sources:

    MAL arm      target.titles = MAL's primary title      (nested recommendation nodes
                                                           carry exactly one)
    AniList arm  target.titles = romaji, english, native, synonyms

That matters because the arms pay differently when the baseline misses. `searchWidening`
fetches more spellings only when it holds fewer than two — so the MAL arm spends an extra
`mangaDetail` on every widened row and the AniList arm never does.

So the question is not "who wins the race" but: **for shared targets, does the first
spelling differ, and does the difference change whether the baseline hits?**

    ./arm_ordering.py          the shared targets — the population the question is about
    ./arm_ordering.py --all    every target the MAL arm resolved, to test whether the
                               answer is a property of these ten or of the two providers

No MAL key needed: the MAL arm's own first spelling is recorded in the log.
`curl -g` and `strict=False` for the reasons scripts/harvest_seed_fixture.py documents.
"""
import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "docs", "superpowers", "measurements", "adr0020-anilist-arm")
UA = "Manga-Reader-arm-ordering/1.0"

ANILIST_QUERY = """
query ($ids: [Int]) {
  Page(perPage: 50) {
    media(idMal_in: $ids, type: MANGA) {
      idMal
      title { romaji english native }
      synonyms
    }
  }
}
"""


class Abort(Exception):
    """A condition under which recording anything would be recording a fiction."""


def curl(url, headers=(), data=None):
    cmd = ["curl", "-sg", "--compressed", "-A", UA, "-w", "\n__HTTP__%{http_code}"]
    for h in headers:
        cmd += ["-H", h]
    if data is not None:
        cmd += ["-X", "POST", "--data-binary", data]
    cmd.append(url)
    out = subprocess.run(cmd, capture_output=True, timeout=60)
    body = out.stdout.decode("utf-8", "replace")
    code = None
    if "\n__HTTP__" in body:
        body, _, tail = body.rpartition("\n__HTTP__")
        code = tail.strip()
    return body, code


def get_json(url, what, headers=(), data=None):
    body, code = curl(url, headers=headers, data=data)
    if code != "200":
        raise Abort(f"{what}: HTTP {code}")
    try:
        return json.loads(body, strict=False)
    except json.JSONDecodeError:
        raise Abort(f"{what}: not JSON ({body[:200]!r})")


def q(text, limit=100):
    return urllib.parse.quote(text[:limit], safe="")


def norm(t):
    f = unicodedata.normalize("NFKD", t)
    f = "".join(c for c in f if not unicodedata.combining(c)).lower()
    return " ".join("".join(c if c.isalnum() else " " for c in f).split())


def baseline_hits(spelling, mal_id):
    """Does MangaDex's answer to this one spelling contain the entry publishing `mal_id`?

    This is the *strong arm only* — an exact `links.mal` hit, which is what ADR-0020
    Decision 4 restricts widened candidates to and what every recovery in the in-app run
    came back through. Deliberately not the fuzzy matcher: re-implementing that here would
    be a second definition of shipped matching behaviour, and the question does not need it.
    """
    payload = get_json(f"https://api.mangadex.org/manga?limit=20&title={q(spelling)}",
                       f"mangadex search {spelling!r}")
    for entry in payload.get("data", []):
        link = entry["attributes"].get("links", {}).get("mal")
        if link and str(link).isdigit() and int(link) == mal_id:
            return True, entry["id"]
    return False, None


def main():
    rows = [json.loads(l) for l in open(os.path.join(DATA, "reverse.log")) if l.strip()]
    pool = json.load(open(os.path.join(DATA, "anilist-pool.json")))
    pool_mal = {c["manga"]["malId"] for c in pool["candidates"]
                if c.get("manga") and c["manga"].get("malId")}

    # The MAL arm's rows are the single-spelling ones: MAL's nested recommendation nodes
    # publish one title, so anything holding several came from the AniList pool.
    mal_first = {}
    for r in rows:
        if len(r["spellings"]) == 1:
            mal_first.setdefault(r["malId"], (r["spellings"][0], r["outcome"]))

    # `--all` widens the comparison from the targets the two arms actually shared in one
    # session to every target the MAL arm resolved. The shared set is the population the
    # question is about; the wider one says whether the answer is a property of these ten
    # or of the two providers' title fields in general.
    everything = "--all" in sys.argv
    shared = sorted(set(mal_first) if everything else (pool_mal & set(mal_first)))
    print(f"pool targets: {len(pool_mal)}   "
          f"{'all MAL-arm targets' if everything else 'shared with the MAL arm'}: "
          f"{len(shared)}\n")
    if not shared:
        raise Abort("no shared targets in the committed run; nothing to compare")

    payload = get_json("https://graphql.anilist.co", "anilist titles",
                       headers=["Content-Type: application/json"],
                       data=json.dumps({"query": ANILIST_QUERY,
                                        "variables": {"ids": shared}}))
    if payload.get("errors"):
        raise Abort(f"anilist: {payload['errors']}")
    ani = {}
    for m in payload["data"]["Page"]["media"]:
        titles = [m["title"].get("romaji"), m["title"].get("english"),
                  m["title"].get("native")] + (m.get("synonyms") or [])
        seen, ordered = set(), []
        for t in titles:
            t = (t or "").strip()
            if t and t not in seen:
                seen.add(t)
                ordered.append(t)
        ani[m["idMal"]] = ordered

    same_spelling = differ = 0
    both_hit = mal_only = ani_only = neither = 0
    print("%-8s %-34s %-34s %s" % ("mal", "MAL arm's first spelling",
                                   "AniList arm's first spelling", "baseline"))
    for mal_id in shared:
        mal_spelling, mal_outcome = mal_first[mal_id]
        titles = ani.get(mal_id)
        if not titles:
            print("%-8s %-34s %-34s %s" % (mal_id, mal_spelling[:33], "(AniList had none)", "-"))
            continue
        ani_spelling = titles[0]

        if norm(mal_spelling) == norm(ani_spelling):
            same_spelling += 1
            verdict = "same spelling — ordering cannot matter"
            print("%-8s %-34s %-34s %s" % (mal_id, mal_spelling[:33], ani_spelling[:33], verdict))
            continue

        differ += 1
        mal_hit = mal_outcome == "baseline-resolved"
        time.sleep(0.3)
        ani_hit, _ = baseline_hits(ani_spelling, mal_id)
        if mal_hit and ani_hit:
            both_hit += 1
            verdict = "both hit"
        elif mal_hit:
            mal_only += 1
            verdict = "MAL's hits, AniList's MISSES  <- pool-first would cost more"
        elif ani_hit:
            ani_only += 1
            verdict = "AniList's hits, MAL's MISSES  <- MAL-first costs a mangaDetail"
        else:
            neither += 1
            verdict = "neither hits"
        print("%-8s %-34s %-34s %s" % (mal_id, mal_spelling[:33], ani_spelling[:33], verdict))

    print(f"\nshared targets:            {len(shared)}")
    print(f"  same first spelling:     {same_spelling}   (ordering is a no-op)")
    print(f"  different first spelling:{differ}")
    print(f"    both baselines hit:    {both_hit}   (ordering is a no-op)")
    print(f"    only MAL's hits:       {mal_only}   (current order is the cheaper one)")
    print(f"    only AniList's hits:   {ani_only}   (current order costs a mangaDetail)")
    print(f"    neither hits:          {neither}   (both widen; MAL also pays mangaDetail)")


if __name__ == "__main__":
    try:
        main()
    except Abort as exc:
        print(f"\nABORT: {exc}", file=sys.stderr)
        sys.exit(1)
