# Glossary

Shared vocabulary for the reader + recommender. Terms here are meant to be used *exactly* —
if a type, variable, or doc comment means one of these, it should say this word.

## Identity

**Work** — a manga as a thing in the world, independent of where you read it. Owns identity,
external ids, and the metadata the recommender ranks on. *No Swift type for this yet* — see
[ADR-0001](adr/0001-work-vs-listing-identity.md).

**Work id** — the app's own opaque, locally-minted identifier for a Work. **Immutable for the
life of the Work**, and never derived from an external id: a provider id may arrive long after
the Work exists, or not at all.
_Avoid_: canonical id, manga id.

**Listing** — one source's copy of a Work: a source id, that source's manga id, its chapters,
its cover. The existing `Manga` struct is a Listing, despite the name.

**Display title** — the title a Work shows the user: the Listing title it was **minted from**, set
once and **never overwritten by a provider**. Sticky on purpose — a provider's canonical title is
often the romaji one, so letting the snapshot win would rename *Attack on Titan* to *Shingeki no
Kyojin* as a delayed side effect of a background fetch. On merge the surviving Work keeps its own.

**Known titles** — every title a Work has ever been known by: the mint-time title of each linked
Listing plus the provider's romaji / english / native / synonyms. Accumulates like external ids
and never shrinks. This is matcher fuel — it raises recall without loosening
`MALTitleMatcher`'s precision-biased threshold — and it is what the manual-link UI shows the user
when nothing matched.

**Listing key** — the `(sourceId, mangaId)` pair identifying a Listing. This, *not* the Work id,
is what history, library, and taste feedback persist — Works are resolved from it at the seam
where the recommender reads them.
_Avoid_: manga key, composite id.

**External id** — an id assigned by a metadata provider: `malId` (MyAnimeList), potentially
`anilistId`. A Work may have several, or none.

**External-id index** — the lookup from an external id to a Work id. Because the Work id is
opaque, this index — not the id's spelling — is what makes arriving at the same Work twice
resolve to one Work.

**Mint** — to create a Work. Happens **only on user commitment** — read, save, *Not interested*,
*More like this*, manual link — never on browsing, searching, or appearing in a candidate pool.
Always **synchronous, local, and network-free**: a Work is minted from the Listing alone with a
provisional snapshot, because minting sits on the path where the user just opened a chapter.
Browsing must not grow the store, or the Work count stops being bounded by usage.

**Resolution** — establishing the Work ↔ Listing link. Free when the source publishes an
external id (MangaDex exposes `attributes.links.mal`); otherwise fuzzy title matching via
`MALTitleMatcher`. **Precision-biased**: no confident match yields `nil` rather than a guess,
so failures are silent omissions, never wrong links. Runs at the **Work** level — MyAnimeList is
searched **once per known title** (capped, display title first) and the results are unioned into
**one** candidate pool, which the matcher scores over the title cross-product. N searches, one
ranked list, one ambiguity guard — never N matches and a maximum, which would have no runner-up to
guard against ([ADR-0008](adr/0008-upgrade-queue-resolution-and-drain.md),
[ADR-0009](adr/0009-upgrade-queue-construction.md)). Always goes through MyAnimeList; AniList is a
lookup-by-id provider and is never asked to search. A confident id is written to the Work
**immediately**, before the metadata fetch — otherwise a transient provider failure rewinds the
Work to an unresolved one and re-searches forever.

**Reverse resolution** — the other direction: external id → a Listing you can actually open.
Currently MangaDex-only.

**Manual link override** — a user-established Work ↔ Listing link, used where automatic
resolution declined to guess. Authoritative and never cache-evicted — see
[ADR-0005](adr/0005-manual-link-override.md).

**Metadata provider** — a catalog the app reads Work metadata from: MyAnimeList, AniList. Not a
Source: a provider tells you *about* a manga, a Source *serves its pages*. AniList is preferred
where both know a Work — better manhwa/manhua coverage, ranked tags, and its `Media.idMal` hands
over the MAL id for free.

**Metadata snapshot** — a Work's genres, ranked tags, status and chapter total, all taken from
**one** authoritative provider, stamped with which one and when. Never merged field-by-field
across providers, so "where did this tag come from?" always has a single answer. **External ids
are the exception**: they accumulate and are never replaced.

**Provisional snapshot** — a metadata snapshot built from the Listing's own tags rather than a
provider — in practice MangaDex's, which arrive free with the detail fetch the UI already makes.
Costs no request, carries no tag rank, and is replaced wholesale once a provider is queried.

**Upgrade queue** — the single serial queue that turns provisional snapshots into provider ones,
resolving a Work to an external id first when it has none. It owns the whole AniList request
budget (**30/min, measured — not the 90 the docs claim**), so provider access goes through it and
never straight from a view model. Ordered by **engagement weight** descending, which the
recommender **pushes** to it on each rail build — the queue never reaches back for it, because
assembling that input mints Works as a side effect. Works with **no reading history** sort after
every weighted one; a negligible tail may stay provisional indefinitely. **Drains while the app is
foregrounded and idles when nothing is stale** — not batched on rail build, which fires once a
session and so never runs during a long read. It **polls** (a scan, then a 60s sleep when the scan
is empty) rather than waiting on a signal: the only honest signal site is `mint`, which runs on
every page turn, and a missed poll self-heals where a missed poke wedges forever. Its own service,
not the recommender's: the recommender is one consumer of Work metadata, not its owner. **Its
output is not visible until the next rail build** (pull-to-refresh or relaunch), deliberately: a
rail that rearranges itself while being looked at is worse than one that is a session stale
([ADR-0008](adr/0008-upgrade-queue-resolution-and-drain.md),
[ADR-0009](adr/0009-upgrade-queue-construction.md),
[ADR-0010](adr/0010-upgrade-queue-drain-loop-and-wiring.md)).

**Drain pass** — the queue's unit of work between idles: it re-scans before **every** request, so a
pass is a sequence of single upgrades rather than a batch under one frozen ordering. Re-scanning
each time is what lets a Work minted mid-read, or a freshly pushed engagement weight, take effect at
the next request instead of the next pass — and it costs nothing against a 2-second request floor. A
pass ends when nothing is left eligible, or when three requests fail in a row. Works that failed
*transiently* are skipped for the remainder of the pass and reconsidered in the next one, which is
how the queue makes forward progress without recording a network blip as if it were an answer about
a Work ([ADR-0010](adr/0010-upgrade-queue-drain-loop-and-wiring.md)).

**Attempt memory** — the queue's per-Work record of what already failed, in a file it owns. Not in
the Work store: it passes the delete test (losing it costs one redundant pass), and data with
different answers to that test must not share a file. Records an **outcome**, not just a timestamp,
because the two stages fail differently: `.unmatched(knownTitlesCount)` (MAL had candidates, none
cleared the threshold) is reopened as soon as the title count grows — sound because `knownTitles` is
**monotonic**, it only ever appends — while `.absentFromProvider(malId)` (resolution worked, AniList
has **nothing usable** for that id: either no entry at all, or an entry carrying neither genres nor
tags) can only be reopened by its 14-day TTL, since re-matching yields the same id forever. Both
shapes belong to one outcome because the enum's cases distinguish *what evidence reopens them*, not
what caused them, and these reopen identically. Without that second outcome the fetch stage would
have no memory at all and would re-request every empty-handed Work on every drain. Transient failures
are never recorded, so an outage cannot poison it for the TTL.

**Snapshot TTL** — how long a provider snapshot is trusted, derived from the Work's own
publication status rather than a guessed constant: a `FINISHED` Work is **terminal** (its chapter
total will never change again), while a `RELEASING` Work is **known-incomplete** — its
`chapters` is `null` by definition — and re-checked on a ~14-day cycle.

**Work store** — the local, app-owned catalog of Works. Its persistence technology is still
undecided (see ADR-0002); "GraphQL" describes how the app *talks to AniList*, not how the store
saves to disk.

**Work merge** — collapsing two Works discovered to be the same manga, which happens whenever an
external id or a manual link arrives after both already exist. The losing Work id is **aliased,
never erased**: it stays resolvable to the winner forever, so a stale id redirects instead of
resolving to nothing. Identity and metadata are decided by different rules: the **incumbent**
external-id owner survives as the Work (the id that arrived first is the one already on screen),
but the survivor keeps whichever **snapshot** ranks higher — `nil` < provisional < provider — so a
merge can never discard the tags reading actually produced
([ADR-0009](adr/0009-upgrade-queue-construction.md)).
_Avoid_: dedupe, collapse.

**Queryable tag** (`QueryableTag`) — a coarse tag name a Source can actually browse by
(`mangaByTag` takes a *display name*). AniList's 19 `genres` and the searchable half of MangaDex's
77 tags live here. This axis drives candidate **generation**. Carries MangaDex's **group**
(genre / theme / format / content) when known, `nil` for AniList genres — dropping it would
flatten `TasteProfile.groupWeight`.

**Ranked tag** — a fine-grained tag carrying a **tag rank**, from AniList's 425-tag vocabulary
(`Dungeon: 95`, `Male Protagonist: 93`). Only 32 of MangaDex's 77 tag names exist in that
vocabulary at all, so this axis is **not searchable on a Source** — `mangaByTag` takes a MangaDex
display name. It **is** searchable on AniList, which queries its own vocabulary and filters by rank
while doing it, and that is where the axis is spent: it drives **generation of the AniList pool**
([ADR-0011](adr/0011-ranked-axis-generation.md)), and scores the candidates it generates.

**Tag rank** — AniList's 0–100 per-title tag relevance (`Solo Leveling` → `Dungeon: 95`,
`Marriage: 20`). Real evidence of how much a tag characterizes a title, as opposed to
`TasteProfile.groupWeight`'s coarse genre/theme/format heuristic. MangaDex tags have no rank.

## Sources

**Source** — something that can serve chapters: MangaDex, WeebCentral. Conforms to
`MangaSource`, registered in `SourceRegistry`.

**Extension** — a Source that is *not* compiled into the app; loaded at runtime, authored
against a host API. None exist yet — see ADR-0003.

**Substrate** — the engine an Extension's code runs inside: JavaScriptCore, a `WKWebView`, or a
WebAssembly VM. Not the extension, and not the API — just what executes it.

**Host API** — the functions the app exposes *to* an Extension (fetch, fetch-via-WebView, log,
storage). A forever-contract: once extensions exist in the wild, breaking it breaks them all.

**Fulfillment** — choosing *which* Listing to actually read a Work from, when several sources
have it. Ranked by English chapter completeness, MangaDex breaking ties — see
[ADR-0004](adr/0004-fulfillment-routing.md).

**Count cache** — the evictable `(sourceId, mangaId) → (English chapter count, fetchedAt)` cache
that fulfillment ranks on. **Disposable by design**: deleting it costs one default route until the
background refresh repopulates, so it lives apart from the Work store — hot, TTL'd, losable data
must not share a file with authoritative identity. A missing entry means *unknown*, never zero.

**Chapter frontier** — the most chapters any installed source has for a Work. The fallback
reference for completeness when the metadata providers don't know the true total, which is the
normal case for ongoing series (AniList reports `chapters: null` while `status: RELEASING` —
One Piece included).

## Recommender

**Taste profile** (`TasteProfile`) — a normalized tag-weight vector plus **seeds**, built from
reading history. Pure value type, no I/O.

**Seed** (`SeedManga`) — a highly-engaged manga used to ask an external catalog "what's like
this?" Top 5 by engagement weight.

**Engagement weight** — per-**Work** signal strength: recency (30-day half-life) × (chapters read
+ finished bonus + saved bonus), doubled by *More like this*. Computed in `TasteProfile.build` and
exposed as `workWeights`, which is **pushed to the upgrade queue** on every rail build — one
definition of engagement, never a second one computed by whoever needs it
([ADR-0009](adr/0009-upgrade-queue-construction.md)). Computed for **every Work with reading
history**, tagged or not: an untagged read Work is the highest-value thing the queue can upgrade,
so it must be orderable. Two things stay tag-gated — a Work's *contribution* to the tag vector
(nothing to contribute) and **seed** selection (seeds are catalog queries, and an untagged Work is
a worse question to ask).

**Candidate pool** — one provider's ranked output (`[ScoredManga]`). Three exist: the *tag pool*
(`TagCandidateProvider`), the *MAL pool* (`MALCandidateProvider`), and the *AniList pool*.

**AniList pool** — candidates generated by querying AniList's ranked vocabulary with **tag pairs**
drawn from the user's own Works. The only pool whose candidates arrive carrying their own metadata,
so it is the only one that does not score by provenance.

**Tag pair** — two ranked tags that **co-occur in one Work** the user read, both at rank ≥ 60. The
seeding unit for the AniList pool: `AND` semantics make a pair expressive where a single tag is just
a popularity list, and drawing both legs from the same Work is what makes the conjunction a claim
someone actually made. Weighted by `Σ engagement(w) × min(rank_a, rank_b)/100` over the Works
carrying both, so pairs that *recur* beat pairs that happened once. Top 5 seed the query.

**Minimum tag rank** — AniList's per-tag floor on a query. Applies to **every** tag in a
conjunction, so it thins a pair fast: `Dungeon ∧ Iyashikei` is empty at 80. Set to 60 — the floor
excludes noise, it does not rank.

**Tag vocabulary** — AniList's 425 tags with their `category`, `isAdult` and `isGeneralSpoiler`
flags, cached whole in `Caches/`. Category is a property of a *tag name*, never of a Work, which is
why it is not persisted on `RankedTag`. `Technical` and `Cast-Main Cast` are excluded from seeding
(format facts and near-universal traits); the 8 `isGeneralSpoiler` tags are excluded from **reason
strings** but not from seeding.

**Provenance scoring** — the scoring shape the tag and MAL pools share: `weight × 1/(1 + position)`,
summed over every query that surfaced the title. Multi-query overlap falls out for free. Used
because a `Manga` carries no tags, so list position is the only candidate-side datum available.

**Normalization** — dividing a pool by its own maximum so both pools land in `[0,1]` and can be
added. Buys comparability, **destroys confidence**: a pool's top item is always exactly `1.0`
whether the pool was strong or garbage.

**Agreement bonus** — the extra credit a title gets for appearing in more than one pool:
`agreementBonus · (∏ contributing normalized scores)^(1/n)`, the geometric mean across the pools
that scored it. Tracks the **weakest** contributing signal, so topping every pool earns the full
bonus while incidental co-occurrence deep in each earns almost nothing. Replaced a flat `+0.25`,
under which a title at ~40% of top strength in two pools outranked the best recommendation either
signal had on its own. Generalized from the two-pool form when the AniList pool landed; summing
pairwise terms instead would have let one title collect the bonus three times, which is the same
failure the flat bonus had ([ADR-0011](adr/0011-ranked-axis-generation.md)).

**Exploration** — the seeded reshuffle in `RecommendationEngine.compose` that mixes lower-ranked
tail candidates into the rail so it moves between sessions. Deliberately non-deterministic
across sessions, which is why golden-file testing targets the *pool*, not the rail.

**Golden file** — a committed, deterministic snapshot of ranked output used to make ranking
changes reviewable as a diff. The project has no labeled relevance data, so this is the only
available evidence that a tuning change did what was intended.

## Library & Collections

**Collection** (`LibraryCollection`) — a named group for organizing saved manga. May be a system default collection or user-created custom collection.

**System Collection** — built-in default collection (`Reading`, `On Hold`, `Planned`, `Dropped`). Cannot be deleted or renamed; can be enabled/disabled and reordered.

**Custom Collection** — user-created collection. Can be created, renamed, reordered, enabled/disabled, and deleted.

**Collection Multi-assignment** — ability for a single saved manga item (`LibraryItem`) to belong to multiple collections simultaneously (e.g. `Reading` and `Favorites`).

## Reader

**Chrome** — the reader's floating top bar and page indicator. The **only** dismiss control lives
here, so "is chrome visible" and "can the user leave" are the same question — which is why
visibility is *derived* (`showChrome || pageCount == 0`) and never assigned in a `catch`. See
[ADR-0012](adr/0012-reader-failure-states-and-chapter-advance-commit.md).

**Commit** — the instant a fetched chapter *replaces* the one being read: `currentChapter`, `pages`
and the pager target are assigned together, and nothing is assigned before the pages are in hand.
Because commit is the only thing that changes `currentChapter`, that property changing is a
trustworthy "we really moved" signal.
_Avoid_: load, switch, advance — an **advance** is the attempt, a commit is the outcome.

**Reading position** (`ReadingPosition`) — a place inside a chapter: a page index plus a `fraction`
of the way down that page. The fraction is only meaningful against the page it was captured on, and
is only ever non-zero in the vertical mode, where a page is a **strip**. Persisted flat on
`ReadingEntry` (`page`, `fraction`), which is why that type hand-writes `init(from:)` — a default value
does not make a non-optional key optional to Swift's decoder. Carried as one value everywhere else. **Persisted positions only move forward** — same page keeps the larger fraction, a higher page
takes the new pair — because `page` doubles as the completion signal for Continue Reading, the
in-progress badge and taste signals.
_Avoid_: resume pointer, last position — a *last* position would move backwards, which is a
[deliberately rejected design](adr/0014-resuming-a-webtoon-where-the-reader-stopped.md), not a
synonym.

**Strip** — a webtoon page: one tall image, routinely several screens long. The reason a page index
alone cannot say where a reader stopped, and the unit the anchor grid subdivides.

**Pager target** (`pagerTarget`) — where the pager belongs once a load completes, **whether or not
it committed**. On success it is the position the chapter opens at; on a failed advance it is the page
the pager retreats to inside the chapter that survived. It is a **reading position** but, unlike a
persisted one, it is transient and **not monotonic** — retreating is its whole purpose.
_Avoid_: landing page — nothing lands when an advance fails.

**Anchor grid** — the N invisible, equally spaced, individually identified slices overlaid on each
strip so `scrollTo` can address a point *inside* it. A rendering constant, never persisted, so its
resolution can be raised without touching saved data.

**Settle loop** — restore scrolling to a fraction, re-measuring where it actually landed, and
scrolling again until the target strip sits where it should or the attempt budget runs out. It exists
because no strip has its real height while its image is still decoding, so the first scroll is aiming
at a placeholder. Its stopping rule is pure and unit-tested; the loop around it is not.

**Advance trigger** — the sentinel pager index one step past an interstitial, whose appearance
*requests* the adjacent chapter. It is not a page and holds no content of its own; it reports on the
load it asked for. See [ADR-0013](adr/0013-reader-view-layer-after-load-then-commit.md).

**Transient / permanent failure** — whether retrying could plausibly succeed. Transient keeps Retry
as the primary action; permanent offers a way out instead of a button that cannot work.
**Anything unrecognised is transient**: wrongly offering Retry costs a tap, wrongly withholding it
strands a user. The same split governs the upgrade queue
([ADR-0008](adr/0008-upgrade-queue-resolution-and-drain.md)).

**Banner** — a failure surfaced *over* readable content, as opposed to instead of it. Reachable only
when a chapter is already on screen, which is exactly the case a failed advance leaves behind;
blanking out a chapter being read to report that a *different* one is missing is what the commit
ordering exists to prevent.

