"""Harvest the simulator seed fixture from live MangaDex + AniList.

The fixture the simulator is seeded with has to be *real* data: real MangaDex ids so
every seeded row opens in the app, real cover filenames so the Library and History look
like a user's, and real AniList tag ranks because the >= 60 floor in TagPairSeeding is
what decides whether a Work contributes a seed pair at all. Invented ranks clear or miss
that gate for reasons unrelated to the app, which makes every recommendation run measured
against the fixture meaningless.

Run once, deliberately. The output is committed twice over:

    scripts/seed-harvest.json                   the raw harvest (provenance, re-emit)
    MangaCartaTests/SimulatorSeedFixture.swift the generated rows the seed installs

    ./harvest_seed_fixture.py probe [titles...]   availability check, no writes
    ./harvest_seed_fixture.py fetch    live pull -> seed-harvest.json
    ./harvest_seed_fixture.py emit     seed-harvest.json -> the Swift file (no network)

Two stages so a network failure costs one stage, and so the Swift can be regenerated
offline after a shape change.

api.mangadex.org rejects Python's urllib TLS -> shell out to curl for everything
(carried over from scripts/reverse_reach.py and scripts/wc_resolve.py).
"""
import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
HARVEST = os.path.join(HERE, "seed-harvest.json")
SWIFT = os.path.join(HERE, "..", "MangaCartaTests", "SimulatorSeedFixture.swift")
UA = "MangaCarta-seed-harvest/1.0"

# The fixture's *behaviour* half is authored here, not harvested: which titles the seeded
# user read, how far they got, and what they saved. It is a portrait of a plausible user
# — action/drama-heavy seinen with a romance-comedy streak — because that is what the
# taste profile has to have a shape for. `read` is the number of leading English chapters
# to mark, and `stop` is where they stopped in the last one: "end" finished it, a float
# parks them that fraction of the way in. A fixture with every entry parked mid-chapter
# would show a home screen the app can never actually reach.
TITLES = [
    # Read, and therefore drawn only from titles with **readable** English chapters on
    # MangaDex. Licensed series are removed or reduced to external links to an official
    # reader, so a title can resolve perfectly and still offer nothing the app can open —
    # `probe` reports the readable count, and these were chosen from it.
    {"title": "Berserk",                     "read": 3, "stop": 0.3,   "saved": True},
    {"title": "Vagabond",                    "read": 2, "stop": "end", "saved": True},
    {"title": "Chainsaw Man",                "read": 3, "stop": "end", "saved": True},
    {"title": "Dorohedoro",                  "read": 2, "stop": "end", "saved": True},
    {"title": "Hunter x Hunter",             "read": 2, "stop": 0.4,   "saved": True},
    {"title": "Made in Abyss",               "read": 2, "stop": "end", "saved": True},
    {"title": "Horimiya",                    "read": 1, "stop": "end", "saved": False},
    {"title": "Kaguya-sama: Love Is War",    "read": 2, "stop": 0.2,   "saved": False},
    {"title": "Kingdom",                     "read": 1, "stop": 0.6,   "saved": False},
    # Saved or merely browsed. No reading, so MangaDex availability does not constrain
    # them — a real library is mostly titles you have not started.
    {"title": "Vinland Saga",                "read": 0, "saved": True},
    {"title": "Oyasumi Punpun",              "read": 0, "saved": True},
    {"title": "20th Century Boys",           "read": 0, "saved": True},
    {"title": "Jujutsu Kaisen",              "read": 0, "saved": False},
    {"title": "Sousou no Frieren",           "read": 0, "saved": True},
    {"title": "Tokyo Ghoul",                 "read": 0, "saved": True},
    {"title": "Death Note",                  "read": 0, "saved": False},
    {"title": "One-Punch Man",               "read": 0, "saved": False},
    {"title": "Spy x Family",                "read": 0, "saved": False},
    {"title": "Solo Leveling",               "read": 0, "saved": False},
    {"title": "Blue Lock",                   "read": 0, "saved": False},
    # The two refusals. They are Works the upgrade queue answered and will not re-ask
    # about, which is the state the ADR-0018 guard exists to release — a fixture of
    # nothing but successes cannot exercise it. Harvested like any other row so they are
    # navigable in the app; only the outcome is authored.
    #
    # `drop_mal` forces `.unmatched` to actually suppress: the guard releases any Work
    # carrying an authoritative id, so a refusal row with a MAL id would be recorded and
    # then immediately ignored.
    {"title": "Ousama Ranking",  "read": 0, "saved": True,
     "refusal": "unmatched", "drop_mal": True},
    {"title": "Kagurabachi",     "read": 0, "saved": False, "refusal": "absent"},
]

ANILIST_QUERY = """
query ($mal: Int, $search: String) {
  Media(idMal: $mal, search: $search, type: MANGA) {
    id
    idMal
    title { romaji english }
    genres
    status
    chapters
    tags { name rank isGeneralSpoiler isMediaSpoiler }
  }
}
"""


class Abort(Exception):
    """A condition under which recording anything would be recording a fiction."""


def curl(url, headers=(), data=None):
    # -g: curl treats [] as a glob range otherwise, and every MangaDex array parameter
    # (`includes[]`, `translatedLanguage[]`) fails before a request is even made.
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


def q(text, limit=100):
    """Percent-encode a title the way the app's URLQueryItem would — UTF-8 bytes, so a
    Japanese title does not become a 400."""
    return urllib.parse.quote(text[:limit], safe="")


def normalize(title):
    folded = unicodedata.normalize("NFKD", title)
    folded = "".join(c for c in folded if not unicodedata.combining(c)).lower()
    return " ".join("".join(c if c.isalnum() else " " for c in folded).split())


def get_json(url, what, headers=(), data=None):
    body, code = curl(url, headers=headers, data=data)
    if code != "200":
        raise Abort(f"{what}: HTTP {code}")
    try:
        # strict=False: MangaDex descriptions carry raw control characters, and the
        # strict parser rejects the whole response over one of them.
        return json.loads(body, strict=False)
    except json.JSONDecodeError:
        raise Abort(f"{what}: response was not JSON ({body[:200]!r})")


# --- MangaDex ---------------------------------------------------------------

def mangadex_lookup(title):
    """The Listing half: id, cover filename, the MAL id MangaDex publishes, status."""
    url = ("https://api.mangadex.org/manga?limit=10&includes[]=cover_art"
           f"&title={q(title)}")
    payload = get_json(url, f"mangadex search {title!r}")
    wanted = normalize(title)
    best = None
    for entry in payload.get("data", []):
        attrs = entry["attributes"]
        names = [v for v in attrs.get("title", {}).values()]
        names += [v for alt in attrs.get("altTitles", []) for v in alt.values()]
        if any(normalize(n) == wanted for n in names):
            best = entry
            break
    # **An exact normalized match or nothing.** MangaDex's relevance ranking answers a
    # search for a title it does not carry with whatever it does carry — "Monster"
    # returns "Futsuu to Bakemono", "Blame!" returns "Black Jack Alive". Taking the
    # first result silently seeds the wrong manga under the right name, and every
    # number measured against the fixture afterwards is fiction.
    if best is None:
        found = ", ".join(
            "%s (%s)" % (e["attributes"]["title"].get("en")
                         or next(iter(e["attributes"]["title"].values()), "?"),
                         e["id"][:8])
            for e in payload.get("data", [])[:5]) or "nothing"
        raise Abort(f"mangadex search {title!r}: no exact title match. Got: {found}. "
                    f"Either the title is not on MangaDex, or the spec needs the "
                    f"exact name MangaDex uses.")

    attrs = best["attributes"]
    cover = next((r["attributes"]["fileName"] for r in best.get("relationships", [])
                  if r["type"] == "cover_art" and r.get("attributes")), None)
    mal = attrs.get("links", {}).get("mal")
    return {
        "mangaId": best["id"],
        "mangaDexTitle": (attrs.get("title", {}).get("en")
                          or next(iter(attrs.get("title", {}).values()), title)),
        "coverFileName": cover,
        "malId": int(mal) if mal and str(mal).isdigit() else None,
        "status": attrs.get("status"),
    }


def mangadex_chapters(manga_id, count):
    """The first `count` English chapters, with their real page counts.

    Page count comes from /at-home/server, the same endpoint the reader uses, because
    "finished" is `page == pageCount - 1` everywhere in the app rather than a flag — a
    guessed page count produces entries that read as finished when they are not.
    """
    if count <= 0:
        return []
    url = ("https://api.mangadex.org/chapter?limit=%d&translatedLanguage[]=en"
           "&order[chapter]=asc&includeExternalUrl=0&manga=%s" % (count, manga_id))
    payload = get_json(url, f"mangadex chapters for {manga_id}")
    out = []
    for entry in payload.get("data", []):
        attrs = entry["attributes"]
        time.sleep(0.25)
        at_home = get_json(f"https://api.mangadex.org/at-home/server/{entry['id']}",
                           f"at-home for {entry['id']}")
        pages = len(at_home.get("chapter", {}).get("data", []))
        if pages == 0:
            raise Abort(f"chapter {entry['id']} reports no pages")
        out.append({"chapterId": entry["id"],
                    "chapterNumber": attrs.get("chapter") or "1",
                    "pageCount": pages})
    return out


# --- AniList ----------------------------------------------------------------

def anilist_lookup(title, mal_id):
    """The ranked axis. By MAL id where MangaDex published one — that is an
    authoritative link and cannot mismatch — and by title search otherwise."""
    variables = {"mal": mal_id} if mal_id else {"search": title}
    body = json.dumps({"query": ANILIST_QUERY, "variables": variables})
    payload = get_json("https://graphql.anilist.co", f"anilist {title!r}",
                       headers=["Content-Type: application/json",
                                "Accept: application/json"],
                       data=body)
    if payload.get("errors"):
        raise Abort(f"anilist {title!r}: {payload['errors']}")
    media = (payload.get("data") or {}).get("Media")
    if not media:
        raise Abort(f"anilist {title!r}: no Media")
    # Spoiler tags are dropped, matching what the app's own AniList adapter does: a
    # fixture that carries them would seed pairs the app would never generate.
    tags = [{"name": t["name"], "rank": t["rank"] or 0}
            for t in media.get("tags", [])
            if not t.get("isGeneralSpoiler") and not t.get("isMediaSpoiler")
            and (t["rank"] or 0) > 0]
    tags.sort(key=lambda t: -t["rank"])
    return {
        "anilistId": media["id"],
        "anilistTitle": media["title"].get("english") or media["title"]["romaji"],
        "genres": media.get("genres", []),
        "tags": tags[:12],
        "status": media.get("status"),
        "chapterTotal": media.get("chapters"),
    }


# --- Stages -----------------------------------------------------------------

def probe(titles):
    """Is this title on MangaDex, and does it have English chapters to read?

    Availability is the constraint the fixture's reading half lives under: MangaDex
    removes licensed series, so a title can resolve perfectly and still offer nothing to
    have read. Probe before authoring `read` counts rather than discovering it in a
    harvest.
    """
    for title in titles:
        try:
            md = mangadex_lookup(title)
        except Abort as exc:
            print(f"  {title}: {exc}")
            continue
        # `includeExternalUrl=0`, matching the harvest: a licensed title's chapters are
        # often external links to an official reader, which the app cannot open. Counting
        # them says a title is readable when nothing in it is.
        payload = get_json("https://api.mangadex.org/chapter?limit=1&includeExternalUrl=0"
                           "&translatedLanguage[]=en&manga=%s" % md["mangaId"],
                           f"chapter count for {title!r}")
        print("  %-28s %4s en-chapters  mal=%-7s %s" % (
            title, payload.get("total", 0), md["malId"], md["mangaId"][:8]))
        time.sleep(0.3)


def fetch():
    rows = []
    shortfalls = []
    for spec in TITLES:
        title = spec["title"]
        print(f"  {title} ...", flush=True)
        md = mangadex_lookup(title)
        time.sleep(0.3)
        mal_id = None if spec.get("drop_mal") else md["malId"]
        al = anilist_lookup(title, mal_id)
        time.sleep(0.3)
        # A refusal row is a Work the queue could not upgrade, so it carries no ranked
        # axis — seeding one would describe a state no drain could have produced.
        chapters = mangadex_chapters(md["mangaId"], spec.get("read", 0))
        row = {
            "title": md["mangaDexTitle"],
            "sourceId": "mangadex",
            "mangaId": md["mangaId"],
            "coverFileName": md["coverFileName"],
            "malId": mal_id,
            "anilistId": al["anilistId"],
            "anilistTitle": al["anilistTitle"],
            "genres": al["genres"],
            "tags": [] if spec.get("refusal") else al["tags"],
            "status": al["status"],
            "chapterTotal": al["chapterTotal"],
            "chapters": chapters,
            "stop": spec.get("stop", "end"),
            "isSaved": spec.get("saved", False),
            "refusal": spec.get("refusal"),
        }
        if spec.get("read", 0) and len(chapters) < spec["read"]:
            # Not fatal — but the fixture's reading half is the taste profile's input, so
            # silently seeding fewer chapters than authored would quietly change what
            # every recommendation run measures.
            shortfalls.append("%s: asked %d chapters, got %d"
                              % (title, spec["read"], len(chapters)))
        rows.append(row)
        print(f"    md={md['mangaId'][:8]} mal={mal_id} al={al['anilistId']} "
              f"tags={len(row['tags'])} chapters={len(chapters)} "
              f"(anilist called it {al['anilistTitle']!r})", flush=True)

    with open(HARVEST, "w") as f:
        json.dump({"harvestedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                   "rows": rows}, f, indent=2, ensure_ascii=False)
    print(f"\nwrote {len(rows)} rows to {HARVEST}")
    for line in shortfalls:
        print(f"  SHORTFALL  {line}")


STATUS = {"FINISHED": ".finished", "RELEASING": ".releasing",
          "NOT_YET_RELEASED": ".notYetReleased", "CANCELLED": ".cancelled",
          "HIATUS": ".hiatus"}


def swift_string(text):
    return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')


def emit():
    with open(HARVEST) as f:
        harvest = json.load(f)

    out = ['//',
           '//  SimulatorSeedFixture.swift',
           '//  MangaCartaTests',
           '//',
           '//  GENERATED by scripts/harvest_seed_fixture.py — do not edit by hand.',
           '//  Harvested %s from live MangaDex + AniList.' % harvest["harvestedAt"],
           '//',
           '//  Swift rather than a JSON resource on purpose: the rows are typed, so the',
           '//  day `SimulatorSeed.Row` changes shape this file fails to compile instead of',
           '//  decoding into something quietly wrong. Regenerate with `emit`, which needs',
           '//  no network — scripts/seed-harvest.json is the committed raw harvest.',
           '//',
           '',
           'import Foundation',
           '@testable import MangaCarta',
           '',
           'extension SimulatorSeed {',
           '',
           '    /// The seeded user: %d Works, %d read, %d saved, %d refused.' % (
               len(harvest["rows"]),
               sum(1 for r in harvest["rows"] if r["chapters"]),
               sum(1 for r in harvest["rows"] if r["isSaved"]),
               sum(1 for r in harvest["rows"] if r["refusal"])),
           '    static let harvestedRows: [Row] = [']

    for row in harvest["rows"]:
        reads = []
        for i, ch in enumerate(row["chapters"]):
            last = i == len(row["chapters"]) - 1
            stop = row["stop"]
            if last and stop != "end":
                page = max(0, min(ch["pageCount"] - 2, int(ch["pageCount"] * stop)))
            else:
                page = ch["pageCount"] - 1
            reads.append((ch, page))

        refusal = {"unmatched": ".unmatched(knownTitlesCount: 1)",
                   "absent": ".absentFromProvider(malId: %s)" % row["malId"],
                   None: "nil"}[row["refusal"]]
        cover = ('nil' if not row["coverFileName"]
                 else 'mangaCoverURL(mangaId: %s, fileName: %s)' % (
                     swift_string(row["mangaId"]), swift_string(row["coverFileName"])))

        out.append('        Row(title: %s,' % swift_string(row["title"]))
        out.append('            sourceId: %s, mangaId: %s,' % (
            swift_string(row["sourceId"]), swift_string(row["mangaId"])))
        out.append('            coverURL: %s,' % cover)
        out.append('            malId: %s, anilistId: %d,' % (
            row["malId"] if row["malId"] else "nil", row["anilistId"]))
        out.append('            genres: [%s],' % ", ".join(
            swift_string(g) for g in row["genres"]))
        if row["tags"]:
            out.append('            tags: [')
            for tag in row["tags"]:
                out.append('                RankedTag(name: %s, rank: %d),' % (
                    swift_string(tag["name"]), tag["rank"]))
            out.append('            ],')
        else:
            out.append('            tags: [],')
        out.append('            status: %s, chapterTotal: %s,' % (
            STATUS.get(row["status"], ".unknown"),
            row["chapterTotal"] if row["chapterTotal"] else "nil"))
        if reads:
            out.append('            reading: [')
            for ch, page in reads:
                out.append('                Row.Read(chapterId: %s, chapterNumber: %s,'
                           % (swift_string(ch["chapterId"]),
                              swift_string(ch["chapterNumber"])))
                out.append('                         page: %d, pageCount: %d),' % (
                    page, ch["pageCount"]))
            out.append('            ],')
        else:
            out.append('            reading: [],')
        out.append('            isSaved: %s, refusal: %s),' % (
            "true" if row["isSaved"] else "false", refusal))

    out += ['    ]', '}', '']
    with open(SWIFT, "w") as f:
        f.write("\n".join(out))
    print(f"wrote {len(harvest['rows'])} rows to {os.path.normpath(SWIFT)}")


if __name__ == "__main__":
    stage = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if stage == "fetch":
            fetch()
        elif stage == "probe":
            probe(sys.argv[2:] or [t["title"] for t in TITLES])
        elif stage == "emit":
            emit()
        else:
            print(__doc__)
            sys.exit(2)
    except Abort as exc:
        print(f"\nABORT: {exc}", file=sys.stderr)
        sys.exit(1)
