# "More Like This" (Cross-Source Recommendations, subsystem 3) — Design

Date: 2026-07-21

## Context

Subsystem 3 (final piece) of the cross-source recommendations effort. Subsystems 1
(read-only MAL client) and 2 (cross-source entity resolution — `Manga → MAL id`) are done
and merged to `main`. This ships the user-facing payoff: a **Netflix-style "More Like
This" rail on each manga detail page**, sourced from MyAnimeList's per-title
`recommendations` and resolved to openable MangaDex titles.

Prior specs/plans:
- `docs/superpowers/specs/2026-07-20-mal-client-design.md` (subsystem 1)
- `docs/superpowers/specs/2026-07-21-cross-source-entity-resolution-design.md` (subsystem 2)

**Scope of this spec:** a per-title "More Like This" feature — a provider that turns the
current `Manga` into a list of openable MangaDex `Manga`, a view model, the detail-page
rail, the reverse-resolution cache, and verification. **Out of scope** (YAGNI, listed at
the end): `related_manga`, multi-source reverse resolution, feeding MAL into the home
`RecommendationEngine`, MAL-detail caching, and any tab/segmented-control treatment.

## Decisions

- **Separate feature, not folded into `RecommendationEngine`.** The home "For You" engine is
  personalized, tag-based, MangaDex-only, and home-level. "More Like This" is per-title,
  non-personalized, MAL-collaborative, and cross-source-aware. They share only the reusable
  rail UI. Folding them would tangle two disjoint data flows and lifecycles; keeping them
  separate keeps each a deep, simple module. The existing `TasteProfile` "More like this"
  feedback (which boosts home-engine tags) is unrelated and stays untouched.
- **Recommendations only for v1.** MAL's `recommendations` (collaborative "readers also
  liked", weighted by `numRecommendations`) is the genuine "more like this" discovery
  signal. `related_manga` (prequels/sequels/side-stories) is a different UX ("continue the
  series") and is deferred — it comes from the same MAL fetch, so adding it later is cheap.
- **MangaDex-only reverse resolution.** MAL hands back `(malId, title)` pairs; each must
  become an openable source `Manga`. MangaDex is the only source whose search results carry
  `malId` (from `links.mal`, subsystem 2), so reverse resolution there is **precise** (accept
  the search result whose `malId == target`), with a fuzzy title fallback. It also has the
  biggest catalog and behaves identically regardless of which source the user is viewing.
  Multi-source reverse resolution is deferred.
- **Precision over recall, end to end.** Any recommendation that can't be reverse-resolved
  with confidence is omitted — better to show 6 solid cards than 10 with 4 wrong ones. Same
  stance as subsystem 2.
- **Reuse subsystem 2's machinery.** Forward resolution uses `MALEntityResolver`; the fuzzy
  half of reverse resolution reuses `MALTitleMatcher`'s scoring (refactored into a shared
  generic); the cache extends `EntityResolutionStore`.

## Design

### 1. Expose MangaDex batch-fetch-by-ids

`MangaDexAPI.fetchMangaByIdsWithCovers(ids:)` exists but is `private static`. Make it
`static` (internal) so the provider can render cache-hit recommendations (whose MangaDex
ids are known) in one batched call instead of re-searching. No behavior change.

### 2. Generalize `MALTitleMatcher` scoring (DRY across both directions)

Extract the normalize+score+threshold+ambiguity-guard core into a generic static so both
the forward (→ MAL id) and reverse (→ MangaDex id) paths share one implementation. The
existing `MALCandidate`/`MALMatchDecision`/`decide` API and its 7 tests stay — `decide`
delegates to the generic (the tests are the refactor's safety net).

```swift
extension MALTitleMatcher {
    /// The id of the best-matching candidate for `sourceTitle`, or nil if no candidate
    /// clears the acceptance threshold and the ambiguity guard. Generic over the id type
    /// so it serves both MAL-id matching (forward) and MangaDex-id matching (reverse).
    func bestMatch<ID>(sourceTitle: String,
                       candidates: [(id: ID, titles: [String])]) -> ID? {
        // (normalize source; score each candidate = max similarity over its normalized
        //  titles; sort desc; require best >= acceptanceThreshold AND, when >=2 candidates,
        //  best - runnerUp >= ambiguityMargin; else nil.)  ← the current `decide` body.
    }
}
```

`decide(sourceTitle:candidates:)` becomes:
```swift
func decide(sourceTitle: String, candidates: [MALCandidate]) -> MALMatchDecision {
    let match = bestMatch(sourceTitle: sourceTitle,
                          candidates: candidates.map { (id: $0.malId, titles: $0.titles) })
    return match.map { .matched(malId: $0) } ?? .noMatch
}
```

### 3. Pure reverse-match helper (the testable core of reverse resolution)

Given a MAL recommendation (its id + title) and the MangaDex search results for that title,
pick the confident MangaDex `Manga` — or nil. Pure, no network, fully unit-tested.

```swift
enum MoreLikeThis {
    /// Reverse-resolve one MAL recommendation to a MangaDex Manga among `candidates`
    /// (the MangaDex search results for `malTitle`). Precise first: a candidate whose
    /// `malId` equals `targetMalId` is a confirmed match. Otherwise fall back to fuzzy
    /// title matching via `matcher`. nil = no confident match (omit downstream).
    static func pickMatch(targetMalId: Int,
                          malTitle: String,
                          candidates: [Manga],
                          matcher: MALTitleMatcher = .init()) -> Manga? {
        if let exact = candidates.first(where: { $0.malId == targetMalId }) { return exact }
        let byTitle = matcher.bestMatch(
            sourceTitle: malTitle,
            candidates: candidates.map { (id: $0.id, titles: [$0.title]) })
        return byTitle.flatMap { id in candidates.first { $0.id == id } }
    }
}
```

### 4. Reverse cache — extend `EntityResolutionStore`

Add a second, parallel map for the reverse direction (MAL id → MangaDex manga id), keyed by
`String(malId)`, with the same 14-day miss TTL. Also add a shared instance so the cache
persists across detail-page opens (the forward cache and this reverse cache live in one
store).

```swift
/// Reverse resolution outcome: a MAL id → a MangaDex manga id (or a cached miss).
enum ReverseResolution: Codable, Equatable {
    case resolved(mangaDexId: String)   // cached indefinitely
    case unresolved(checkedAt: Date)    // re-attempt after missTTL

    func isFresh(now: Date = Date()) -> Bool {   // mirrors MALResolution.isFresh
        switch self {
        case .resolved: return true
        case .unresolved(let at): return now.timeIntervalSince(at) < EntityResolutionStore.missTTL
        }
    }
}

extension EntityResolutionStore {
    // New @Published private(set) var reverseCache: [String: ReverseResolution] = [:]
    // persisted under its own UserDefaults key, loaded/saved alongside `cache`.
    func reverseResolution(malId: Int) -> ReverseResolution?          // keyed by String(malId)
    func recordReverse(malId: Int, _ resolution: ReverseResolution)

    static let shared = EntityResolutionStore()   // app-wide instance; injectable init kept for tests
}
```

`isFresh(now:)` on `MALResolution` and `ReverseResolution` are the same shape;
`EntityResolutionStore.missTTL` is already `nonisolated`, so both are callable off-actor.

### 5. `MoreLikeThisProvider` — `Services/MoreLikeThisProvider.swift` (new)

`@MainActor`. Orchestrates: forward-resolve → MAL detail → top-N recommendations →
reverse-resolve each → openable MangaDex `Manga`, in recommendation-weight order. The
network glue is the thin untestable part (matching the codebase's no-mock convention); the
decision logic lives in the pure helpers above.

```swift
@MainActor
final class MoreLikeThisProvider {
    init(store: EntityResolutionStore = .shared,
         resolver: MALEntityResolver? = nil,          // defaults to MALEntityResolver(store:)
         matcher: MALTitleMatcher = .init())

    /// Up to `limit` openable MangaDex titles similar to `manga`, in MAL-recommendation
    /// order. Empty when `manga` has no MAL match, MAL returns no recommendations, or none
    /// reverse-resolve. Never throws — network failures degrade to fewer/zero cards.
    func recommendations(for manga: Manga, limit: Int = 8) async -> [Manga]
}
```

Flow:
1. `guard let malId = await resolver.malId(for: manga) else { return [] }` (subsystem 2,
   cached).
2. `guard let detail = try? await MyAnimeListAPI.mangaDetail(id: malId) else { return [] }`.
3. `let recs = (detail.recommendations ?? []).sorted { $0.numRecommendations > $1.numRecommendations }.prefix(limit)`.
   Empty → `[]`.
4. For each rec `(node.id, node.title)`, produce a MangaDex `Manga`, preserving order:
   - **Cache hit** `reverseResolution(malId: rec.id)` fresh: `.resolved(id)` → collect `id`
     for a single batched `fetchMangaByIdsWithCovers`; fresh `.unresolved` → skip.
   - **Miss/stale:** `searchManga(title: rec.title)` (bounded concurrency, cap 4) →
     `MoreLikeThis.pickMatch(targetMalId: rec.id, malTitle: rec.title, candidates:, matcher:)`.
     Match → `recordReverse(.resolved(mangaDexId:))`, keep the `Manga`; no match →
     `recordReverse(.unresolved(checkedAt: Date()))`, omit. A thrown search returns nil for
     that entry **without** recording a miss (transient — don't poison the cache), same rule
     as subsystem 2.
5. Merge the batch-fetched cache-hit manga with the freshly-searched ones, drop the current
   `manga` itself if it appears, de-dupe by manga id, and return in the recommendation order
   from step 3.

Bounded concurrency uses the sliding-window `TaskGroup` pattern already established for
`LibraryStore.refresh` (cap 4).

### 6. `MoreLikeThisViewModel` + detail-page rail

**`MoreLikeThisViewModel`** (`Models/MoreLikeThisViewModel.swift`, new) — `@MainActor final
class ... : ObservableObject`, mirroring the other detail view models:
```swift
@Published private(set) var items: [Manga] = []
@Published private(set) var isLoading = false
func load(for manga: Manga) async   // idempotent; sets isLoading, calls provider, publishes items
```

**`MangaDetailView`** — add a `@StateObject private var moreLikeThis = MoreLikeThisViewModel()`,
a new `moreLikeThis` rail section appended **last** in the body `VStack` (after `chapters`),
shown only when `!moreLikeThis.items.isEmpty`, and a `.task { await moreLikeThis.load(for: manga) }`
to load async on appear (non-blocking; the rest of the page renders immediately). The
section reuses `MangaRail` (horizontal cover cards) with each card a
`NavigationLink(destination: MangaDetailView(manga:))`, under an `InkSectionHeader("More
Like This", eyebrow: "Similar titles")` matching the page's existing section styling. When
empty (no MAL match / no resolved recs) the section is absent — graceful, like the home
"For You" rail.

## Data flow

```
MangaDetailView (.task)
        │
        ▼
MoreLikeThisViewModel.load(for:) ──► MoreLikeThisProvider.recommendations(for:)
        │
        ├─ MALEntityResolver.malId(for:)  ─ nil ─► []          (subsystem 2, cached)
        ├─ MyAnimeListAPI.mangaDetail(malId).recommendations (top N by weight)
        └─ per rec (malId, title), order-preserving:
              reverseCache fresh? ─ resolved ─► collect MangaDex id ─┐
                                   ─ miss ─────► skip                 │ batch
              else searchManga(title) ─► MoreLikeThis.pickMatch ──────┤ fetch
                     match ─► cache .resolved + keep Manga            │ by ids
                     no match ─► cache .unresolved + omit             │
        ▼                                                            ▼
   [Manga] (recommendation order, deduped, self excluded) ──► MangaRail on detail page
```

## Testing

Unit (pure/deterministic, no network):
- **`MoreLikeThis.pickMatch`:** precise `malId` match wins even when a different candidate
  has a closer title; fuzzy fallback when no candidate carries the id; ambiguity guard /
  below-threshold → nil (omit); empty candidates → nil.
- **`MALTitleMatcher.bestMatch` generic + `decide` delegation:** the existing 7 matcher
  tests stay green (proving the refactor is behavior-preserving); one added test exercises
  `bestMatch` with a non-`Int` id type (e.g. `String`) to prove genericity.
- **`EntityResolutionStore` reverse map:** `recordReverse`/`reverseResolution` round-trip;
  keys don't collide with the forward map; `ReverseResolution.isFresh` fresh vs stale at
  `missTTL`; persistence across instances.
- **Recommendation ordering/selection** (pure): a helper that sorts by `numRecommendations`
  desc and takes top-N — verify order and cap. (If this lives inline in the provider,
  factor the sort/take into a pure static so it's testable without network.)

Live verification (per convention — iPhone 17 sim, `-parallel-testing-enabled NO`):
- **Debug-screen probe:** extend `MyAnimeListDebugView` with a "More Like This" field that
  builds a synthetic `Manga(sourceId: "mangadex", malId: nil, title: <typed>, …)` and runs
  `MoreLikeThisProvider.recommendations(for:)` on it (forward resolution fuzzy-matches the
  typed title → a MAL id, then the pipeline proceeds), listing the resolved MangaDex titles.
  A live UI test types a known title (e.g. "Berserk") and asserts ≥1 resolved recommendation
  renders.
- **Real detail-page rail:** a live UI test opens a popular title from Home, scrolls to the
  bottom, and asserts the "More Like This" section header plus ≥1 card appear — proving the
  end-to-end rail against the real MAL + MangaDex APIs.

Both live tests are throwaway-leaning (network-dependent, slow); the debug-screen probe and
its test are deleted when the debug screen is retired (the rail on the real detail page is
the permanent feature).

## Explicitly deferred (YAGNI)

- `related_manga` (prequels/sequels/side-stories) as a separate "Related" section.
- Multi-source reverse resolution (resolving into the active/other sources).
- Feeding MAL's collaborative signal into the home `RecommendationEngine`
  (the `CandidateProvider` seam exists for this — a future "For You" enhancement).
- Caching the MAL detail/recommendations payload (one MAL call per detail-page open is
  acceptable for v1).
- A tab / segmented-control treatment of the detail page (v1 is a bottom section).
- Removing the throwaway MAL debug screen — retired in a later cleanup once the rail is
  proven in the real app.
```
