# ADR-0002 — The catalog is a local Work store; MAL and AniList are metadata *providers*

- **Status:** Accepted (2026-07-24)
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing)

## Context

ADR-0001 established that the recommender must reason over Works. This ADR decides **who owns
the Work's identity and metadata.**

The cheap option is to make `malId` the Work key — the code half-does this already
(`EntityResolutionStore` is keyed by `String(malId)` in both directions). Two things rule it out:

1. **Coverage.** MyAnimeList is strong on Japanese manga and thinner on manhwa/manhua/webtoons,
   which are a large share of what the aggregator sources we want to support actually carry.
2. **A second provider is wanted.** AniList is desirable for exactly that coverage gap. If
   `malId` is the identity, adding AniList is a re-keying migration rather than an addition.

Verified live against `https://graphql.anilist.co` on 2026-07-24:

- **`Media.idMal` exists and is populated.** `Solo Leveling` → `id: 105398, idMal: 121496`.
  AniList therefore *bridges* to MAL rather than competing with it — one AniList query yields
  both external ids, and everything already built on `malId` keeps working.
- **AniList covers the gap.** `Solo Leveling`, a manhwa, is fully populated.
- **AniList tags carry a `rank` (0–100).** `Solo Leveling` → `Dungeon: 95`, `Male Protagonist:
  93`, … `Marriage: 20`. This is *per-title tag relevance*, which MangaDex's flat tag list does
  not provide.

## Decision

**A local Work store owns the catalog.** The app generates its own stable Work id. External ids
are attributes of a Work, not its identity:

```
Work #17
  title:       "Shingeki no Kyojin"
  externalIds: { mal: 23390, anilist: 53390 }
  tags:        [ (Action, 95), (Military, 88), (Tragedy, 74) ]
  listings:    [ (mangadex, "abc-123"), (weebcentral, "xyz-789") ]
```

Three consequences of that shape, decided here:

1. **Tags live on the Work**, sourced from whichever metadata provider knows it — not from the
   source the user happened to read on. *This is the fix for the cross-source invisibility bug
   documented in ADR-0001*: a manga read on WeebCentral inherits its Work's tags, so it gains an
   engagement weight, contributes tag signal, and becomes eligible as a recommendation seed.
   A source that publishes no tag vocabulary of its own is no longer second-class.
2. **Tags carry a weight.** AniList's `rank` is stored alongside the tag name. `TasteProfile`
   currently approximates relevance with a coarse `groupWeight` heuristic (genre 1.0 / theme 0.7
   / format 0.3, in `TasteProfile.swift:33`); a real per-title rank is strictly better evidence
   and should eventually replace or multiply it. MangaDex-sourced tags have no rank and default
   to the existing group heuristic.
3. **MAL and AniList are both metadata providers** behind one seam. AniList is preferred where
   both know a Work (better coverage, ranked tags, and it hands over `idMal` for free).

## Consequences

- `EntityResolutionStore` migrates off its `malId` key to the Work key; `malId` becomes one
  entry in `externalIds`.
- The `manga.sourceId == "mangadex"` guard in `MangaDetailView.swift:56` and the mangadex-only
  filter in `RecommendationEngine.scheduleBackfill` both go away — tag backfill becomes a
  Work-level concern.
- A Work known to no provider can still exist (local-only, no tags, no recommendations).
- One more network dependency, and AniList's rate limits now matter.

## Not decided here

**Local persistence technology.** "Use GraphQL" describes how the app *talks to AniList* — it is
a query protocol for a remote API, not a storage engine. How the Work store persists on device
is a separate, still-open choice: a UserDefaults-backed JSON store (matching `HistoryStore`,
`LibraryStore`, `TasteProfileStore`, and `EntityResolutionStore` — consistent, zero new
dependencies, but the app's largest store by far), or SwiftData/Core Data (real queries and
relations, iOS 17.5-compatible, but a new persistence paradigm in a codebase that has none).
Decide before implementation; the Work store is the first thing here big enough that
UserDefaults is genuinely questionable.
