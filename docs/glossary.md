# Glossary

Shared vocabulary for the reader + recommender. Terms here are meant to be used *exactly* —
if a type, variable, or doc comment means one of these, it should say this word.

## Identity

**Work** — a manga as a thing in the world, independent of where you read it. Owns identity,
external ids, and the metadata the recommender ranks on. *No Swift type for this yet* — see
[ADR-0001](adr/0001-work-vs-listing-identity.md).

**Listing** — one source's copy of a Work: a source id, that source's manga id, its chapters,
its cover. The existing `Manga` struct is a Listing, despite the name.

**External id** — an id assigned by a metadata provider: `malId` (MyAnimeList), potentially
`anilistId`. A Work may have several, or none.

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

**Work store** — the local, app-owned catalog of Works. Its persistence technology is still
undecided (see ADR-0002); "GraphQL" describes how the app *talks to AniList*, not how the store
saves to disk.

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

