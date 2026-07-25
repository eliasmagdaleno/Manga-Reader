# ADR-0002 — The catalog is a local Work store; MAL and AniList are metadata *providers*

- **Status:** Accepted (2026-07-24); **amended by ADR-0007 (2026-07-25)**
- **Related:** ADR-0001 (Work vs Listing), ADR-0004 (fulfillment routing),
  ADR-0007 (Work shape and lifecycle)

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

## Persistence: a JSON file in Application Support

(Note: "use GraphQL" describes how the app *talks to AniList* — a query protocol for a remote
API. It says nothing about on-device storage, which is this separate decision.)

The sizing question decides it. **Works are created only on user commitment** — read, saved, or
marked *Not interested* / *More like this* — so the count is bounded by *usage*, not by the size of
any source's catalog.

> **Amended by ADR-0007.** This originally read "something read, saved, **or recommended**". That
> clause contradicted the sizing argument it was supporting: candidate pools are 40 titles per rail
> refresh, so minting per recommendation grows the store with *browsing*. Minting is now tied to
> commitment only. ADR-0007 also moves the per-Listing chapter counts **out** of this store — hot,
> disposable, TTL'd data must not share a file with authoritative identity, or every count refresh
> rewrites the whole store and reproduces the very I/O pattern rejected just below.
Low thousands over years, not tens of thousands. At that scale, filtering an in-memory array of
structs takes microseconds: the store does not need a query engine, it needs sane I/O.

**Decision: Codable structs persisted to a JSON file in Application Support**, loaded lazily on
first use and written with debounced saves.

Rejected, with reasons:

- **UserDefaults + Codable** (what `HistoryStore`, `LibraryStore`, `TasteProfileStore`, and
  `EntityResolutionStore` all do). Consistent and zero-concept, but the I/O is all-or-nothing:
  every mutation re-encodes and rewrites the whole dataset, and UserDefaults is a *preferences*
  store whose plist stays resident in memory. At ~0.5–1 KB of JSON per Work, a few thousand Works
  is megabytes re-serialized on every write and resident from launch. `HistoryStore`'s 500-entry
  cap exists for exactly this reason; the Work store has no natural cap.
- **SwiftData.** Real fetches, predicates, indexes, and relationships — Work ↔ Listing genuinely
  *is* a to-many relation. But `@Model` types are classes, and this codebase is deliberately
  value-typed (`TasteProfile` is documented as "Pure value type — no I/O — so it's trivially
  testable"). Adopting it means either reference semantics in the domain layer or a mapping layer,
  plus a new concurrency model (`ModelActor`) and new test setup, in a codebase with no
  persistence framework at all.

**Trigger to revisit:** adopt SwiftData when there's a query that cannot be answered by filtering
the loaded array — e.g. "all Works with tag X above rank 80" across a store too large to hold —
or when whole-file rewrites become perceptible. Not before; until then it is cost with no benefit.
