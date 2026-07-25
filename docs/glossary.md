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
so failures are silent omissions, never wrong links.

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

**Upgrade queue** — the single serial queue that turns provisional snapshots into provider ones.
It owns the whole AniList request budget (**30/min, measured — not the 90 the docs claim**), so
provider access goes through it and never straight from a view model. Ordered by **engagement
weight**, so the Works that move the profile are upgraded first and a negligible tail may stay
provisional indefinitely.

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
resolving to nothing.
_Avoid_: dedupe, collapse.

**Queryable tag** (`QueryableTag`) — a coarse tag name a Source can actually browse by
(`mangaByTag` takes a *display name*). AniList's 19 `genres` and the searchable half of MangaDex's
77 tags live here. This axis drives candidate **generation**. Carries MangaDex's **group**
(genre / theme / format / content) when known, `nil` for AniList genres — dropping it would
flatten `TasteProfile.groupWeight`.

**Ranked tag** — a fine-grained tag carrying a **tag rank**, from AniList's 425-tag vocabulary
(`Dungeon: 95`, `Male Protagonist: 93`). Only 32 of MangaDex's 77 tag names exist in that
vocabulary at all, so this axis is **not searchable** and is used for **scoring and re-ranking**
candidates already retrieved — never as a search key.

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

**Engagement weight** — per-manga signal strength: recency (30-day half-life) × (chapters read
+ finished bonus + saved bonus), doubled by *More like this*. Computed in `TasteProfile.build`.
**Only computed for manga that have cached tags** — the root of the cross-source invisibility
described in ADR-0001.

**Candidate pool** — one provider's ranked output (`[ScoredManga]`). Two exist: the *tag pool*
(`TagCandidateProvider`) and the *MAL pool* (`MALCandidateProvider`).

**Provenance scoring** — the scoring shape both pools share: `weight × 1/(1 + position)`,
summed over every query that surfaced the title. Multi-query overlap falls out for free.

**Normalization** — dividing a pool by its own maximum so both pools land in `[0,1]` and can be
added. Buys comparability, **destroys confidence**: a pool's top item is always exactly `1.0`
whether the pool was strong or garbage.

**Agreement bonus** — the extra credit a title gets for appearing in both pools:
`agreementBonus · √(tag · mal)`, the geometric mean of the two normalized scores. Tracks the
**weaker** signal, so topping both pools earns the full bonus while incidental co-occurrence deep
in both earns almost nothing; it is zero when either pool omits the title, so non-overlap needs no
special case. Replaced a flat `+0.25`, under which a title at ~40% of top strength in both pools
outranked the best recommendation either signal had on its own.

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

