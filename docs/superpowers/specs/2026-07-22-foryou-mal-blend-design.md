# Fold MAL signal into "For You" — hybrid tag + collaborative recommendations

**Date:** 2026-07-22
**Status:** Design approved, pending spec review

## Problem

The app has two disconnected recommendation systems:

- **"For You" home rail** — on-device, MangaDex-tag-based (`RecommendationEngine` +
  `TagCandidateProvider`), built from reading history. It can only surface titles that
  share a genre-tag with what you've read — a tag echo chamber.
- **"More Like This" detail rail** — per-title, MyAnimeList-recommendation-based
  (`MoreLikeThisProvider`), reverse-resolved to openable MangaDex titles.

The collaborative signal MAL carries ("readers who liked X also liked Y") routinely
crosses tag boundaries and finds titles the tag feed structurally cannot. This feature
blends that MAL signal into the "For You" rail — the surface seen every launch.

## Approach (chosen)

**MAL as a new candidate source, blended with the tag source, with an explicit
agreement (overlap) boost.** Rejected: MAL as a pure re-ranker of the tag pool (can't
surface MAL-only discoveries); strict interleaving (ignores agreement).

The `RecommendationEngine`'s compose/exploration/"See all" logic is **unchanged** — it
still receives a ranked `[ScoredManga]`. Only the `CandidateProvider` behind it gets
smarter, via the existing `makeProvider` injection seam.

## Design

### The pipeline

```
RecommendationEngine
  └─ CompositeCandidateProvider            (new — the blender)
       ├─ TagCandidateProvider             (existing, unchanged)
       └─ MALCandidateProvider             (new — the collaborative half)
            └─ MoreLikeThisProvider        (existing, reused as-is)
```

### 1. `MALCandidateProvider` (new, `Models/CandidateProvider.swift` or a sibling file)

Conforms to the existing `CandidateProvider` protocol
(`candidates(for:excluding:limit:) async throws -> [ScoredManga]`).

- Reads the top **seed manga** off the profile (see §3), each with an engagement weight.
- For each seed, concurrently calls the existing
  `MoreLikeThisProvider.recommendations(for: seed)` → `[Manga]` in MAL-recommendation
  order (bounded concurrency, matching the cap-4 pattern already used elsewhere).
- Scores each returned title with the **same positional formula the tag provider uses**:
  a title at position `i` (0-based) in seed `s`'s list contributes
  `seedWeight(s) · 1 / (1 + i)`. Contributions **sum across seeds**, so a title several
  of your seeds point to ranks higher.
- Skips anything in `excluding` (read ∪ saved ∪ not-interested).
- Reason string: `"Because you read <seedTitle>"`, where `seedTitle` is the
  highest-weight seed that surfaced the title.
- Returns ranked `[ScoredManga]`, capped at `limit`.

Never throws in practice — `MoreLikeThisProvider.recommendations` already degrades network
failures to empty, so a dead/slow MAL yields an empty MAL pool, not an error.

### 2. `CompositeCandidateProvider` (new)

Conforms to `CandidateProvider`. Wraps two child providers (tag + MAL).

- Runs both children **concurrently** (`async let` / task group).
- **Normalizes each child's scores to [0, 1]** independently: divide every score by that
  child's max score. (Empty or all-zero pool → contributes nothing.) This is what makes
  the two differently-scaled signals comparable.
- **Weighted additive combine**, keyed by manga id:
  `final(id) = W_TAG · tagNorm(id) + W_MAL · malNorm(id)`, with
  `W_TAG = 1.0`, `W_MAL = 0.85` (tag-leaning: tags are the always-available base).
  A title in only one pool gets only that term; a title in both collects both — the
  natural overlap lift.
- **Agreement bonus (gold star):** any id present in **both** normalized pools gets an
  extra `+ OVERLAP_BONUS` (start `0.25`) so both-endorsed titles decisively lead.
- **Reason for a merged title:** prefer the MAL reason (`"Because you read X"`) when MAL
  contributed; else the tag reason (`"More <Tag>"`).
- Sort by `final` descending, cap at `limit`, return `[ScoredManga]`.

All four constants (`W_TAG`, `W_MAL`, `OVERLAP_BONUS`, seed cap) are named constants,
tunable after seeing real output. No tuning UI (YAGNI).

### 3. Seed selection & materialization

The MAL provider needs actual `Manga` (title, ideally `malId`) for your top titles — not
just IDs. `Manga.malId` is often already populated for MangaDex reads (from `links.mal`),
giving free MAL identity.

- **Ranking:** the top ~**5** manga by a combined signal — explicit signals first
  (library saves + `TasteProfileStore.moreLikeThis` marks), then highest-engagement
  implicit reads. `TasteProfile.build` already computes a per-manga engagement weight
  (recency half-life × completion × chapters) internally before aggregating to tags;
  that same per-manga weight ranks the seeds.
- **Materialization:** full `Manga` for seeds come from (a) `LibraryStore.items` (saved
  titles are already `Manga`), and (b) a new lightweight **manga-info cache** on
  `TasteProfileStore` (`[mangaId: MangaInfo]` where `MangaInfo` = title + optional
  `malId`), populated by the **existing tag backfill** — which already fetches MangaDex
  detail for read manga to cache tags, so it can stash title + `malId` at the same time
  with no new network calls. Seeds whose full `Manga` can't be materialized are skipped.
- **Single construction point:** `TasteProfile.build` gains two parameters —
  `libraryItems: [Manga]` and `mangaInfo: [String: MangaInfo]` — and produces the ranked,
  materialized `seeds: [SeedManga]` (`SeedManga = (manga: Manga, weight: Double)`) as a new
  field on the profile it already returns. The engine passes those in from `LibraryStore`
  and `TasteProfileStore`. The `CandidateProvider` protocol is unchanged — the MAL child
  reads `profile.seeds`.

### 4. Engine wiring (`Models/RecommendationEngine.swift`)

- `makeProvider` default changes from `TagCandidateProvider(source:)` to a
  `CompositeCandidateProvider(tag: TagCandidateProvider(source:), mal: MALCandidateProvider(...))`.
- `TasteProfile.build` is extended (per §3) to populate `profile.seeds` from the library
  items + manga-info cache the engine passes in.
- The background `rebuild()` task already backs the rail; the MAL work happens there, so
  the UI never blocks. The rail paints from whatever the composite returns.

## Behavior

- **Graceful degradation:** tag candidates are the floor. If the MAL pool is empty (no
  internet, MAL rate-limited/down, no seed resolves), the composite result equals the
  tag-only rail — today's behavior. MAL can only add or reorder, never break or empty.
- **Cold-start:** unchanged `minTaggedManga >= 3` gate hides the rail until there's
  signal. The MAL layer needs ≥1 resolvable seed; until then it contributes nothing.
- **Cost/speed:** the `EntityResolutionStore` reverse cache already memoizes
  MAL→MangaDex, so repeat builds mostly skip the network; seed cap (~5) bounds fan-out.

## Data flow

`RecommendationEngine.rebuild()` → builds `TasteProfile` (now incl. `seeds`) →
`CompositeCandidateProvider.candidates(for:excluding:limit:)` runs `TagCandidateProvider`
(MangaDex tag feeds) and `MALCandidateProvider` (per-seed `MoreLikeThisProvider`,
reverse-resolved + cached) concurrently → normalize, weight, gold-star, sort →
`[ScoredManga]` → existing `compose()` exploration → `@Published recommendations`.

## Testing

Consistent with the codebase (pure logic → unit tests; end-to-end → one live UI test):

1. **`CompositeCandidateProvider` blending (unit, no network):** stub two child providers
   returning fixed `[ScoredManga]`. Assert: per-pool normalization; the weighted add; that
   a both-pools title gets the overlap bonus and outranks either single-pool title; that an
   empty MAL pool yields exactly the tag ranking (degradation); reason-string precedence.
2. **`MALCandidateProvider` scoring (unit, no network):** inject a stub `MoreLikeThisProvider`
   returning fixed per-seed `[Manga]`. Assert positional scoring, summation across seeds,
   `excluding` filtering, and `"Because you read X"` reasons.
3. **Seed selection (unit):** assert the combined-signal ranking (explicit before implicit),
   the ~5 cap, and that unmaterializable seeds are dropped.
4. **Live UI test:** the "For You" rail still populates end-to-end with the composite
   provider wired in (network-dependent; a flake is API availability).
5. **Regression:** existing recommendation + tag-provider unit tests stay green.

## Out of scope (YAGNI)

- No tuning UI and no per-user learned weights — the four constants are code, tunable later.
- No change to the exploration shuffle, the "See all" grid, or the "More Like This" detail
  rail.
- No new persisted feedback signals beyond the existing not-interested / more-like-this.
- Extending seeds beyond the top ~5, or to non-MangaDex-sourced reads, is a later step.

## Files (anticipated)

- Modify: `Models/CandidateProvider.swift` — add `MALCandidateProvider`,
  `CompositeCandidateProvider` (or a new co-located file).
- Modify: `Models/TasteProfile.swift` — add `seeds: [SeedManga]` and `SeedManga`.
- Modify: `Services/TasteProfileStore.swift` — add the manga-info cache (title + malId),
  populated by backfill.
- Modify: `Models/RecommendationEngine.swift` — assemble seeds, default `makeProvider` to
  the composite, extend backfill to cache manga-info.
- Tests: `Manga-ReaderTests/…` (blend, MAL scoring, seed selection);
  `Manga-ReaderUITests/…` (rail still populates).
- All touched code lives in synchronized groups (`Models/`, `Services/`) — no
  `project.pbxproj` edit.
