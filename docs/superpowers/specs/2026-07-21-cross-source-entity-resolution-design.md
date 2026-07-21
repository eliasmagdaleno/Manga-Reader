# Cross-Source Entity Resolution — Design

Date: 2026-07-21

## Context

This is **subsystem 2** of the three-part cross-source recommendations effort (see
`docs/superpowers/specs/2026-07-20-mal-client-design.md` and the
`recommender-roadmap` memory). Subsystem 1 — a read-only MyAnimeList (MAL) client —
is done and merged to `main` (`Models/MyAnimeListAPI.swift`). Subsystem 3 — a
"More Like This" tab on the manga detail page plus extending the recommendation engine
past MangaDex — is not started and depends on this one.

**The problem this subsystem solves:** given a `Manga` from *any* registered source
(MangaDex, WeebCentral, …), determine the canonical MyAnimeList id for it, if one can be
found with confidence. MAL is the source-independent identity backbone; "More Like This"
consumes a title's `related_manga`/`recommendations` (all MAL ids) and, later, resolves
those back to whichever sources carry them. None of that is possible without a reliable
`Manga → MAL id` step, and that step is exactly what the recommender roadmap flagged as
its known weak point.

**Scope of this spec:** the resolver, its cache, the MangaDex fast path, and the fuzzy
title-matching path, plus unit tests and a debug-screen live-verification hook. No
production "More Like This" UI, no feeding MAL data into the recommendation engine, and
no reverse direction (MAL id → source manga) — all subsystem 3.

## Decisions

- **`Manga` carries an optional `malId`.** `Manga` is the app's source-agnostic,
  bridge-friendly value type. A `malId: Int?` fits that contract (Int-typed, optional)
  and is legitimately a property of the manga, not of the resolver. MangaDex populates it
  for free from `attributes.links.mal` at decode time; scraped sources leave it `nil`.
  This makes the common case (MangaDex) a zero-network fast path. AniList (`links.al`)
  and other external ids are ignored for now — YAGNI; add them only when something needs
  them.

- **A dedicated `EntityResolutionStore`, not an extension of an existing store.**
  `LibraryStore`/`TasteProfileStore` key off MangaDex manga ids; resolution spans sources,
  so it needs a source-qualified key and its own store. It mirrors `TasteProfileStore`'s
  shape exactly (`@MainActor ObservableObject`, UserDefaults + Codable, injectable init).

- **Precision over recall.** A wrong match pollutes "More Like This" worse than a missing
  one. The matcher biases toward *not* matching: a high acceptance threshold plus an
  ambiguity guard, and on any doubt it returns `nil` and the title is simply omitted
  downstream. The resolver never guesses.

- **Only the expensive path is cached.** MangaDex manga already carry `malId`, so those
  short-circuit before any store lookup. The store persists only fuzzy-search outcomes —
  both hits and misses.

- **Testing follows the established convention.** There is no network-mocking harness for
  `MangaDexAPI`/`MyAnimeListAPI` in this codebase. The pure decision logic is factored
  into a free-standing, thoroughly unit-tested `MALTitleMatcher`; the live network path is
  verified through the throwaway `MyAnimeListDebugView` (extended here), exactly as
  subsystem 1 was verified.

## Design

### 1. `Manga.malId` + MangaDex `links` decode

- Add `let malId: Int?` to `Manga` (`Models/MangaDexAPI.swift`, the domain struct).
- Add a `links` field to `MangaAttributes` and `MangaDetailAttributes`. MangaDex returns
  `attributes.links` as an object of external-site keys → id/slug strings, e.g.
  `{"mal": "25", "al": "30002", ...}`. Decode it as `[String: String]?` (values are not
  all ints — AniList/others may be slugs — so a permissive string map is safest; we only
  read `"mal"`).
- In `toManga(...)`, set `malId = links?["mal"].flatMap(Int.init)`. A non-numeric or
  missing `mal` link yields `nil`.
- All existing `Manga(...)` construction sites must pass the new field. `WeebCentralSource`
  (and any other non-MangaDex source that builds a `Manga`) passes `malId: nil`.

Rationale for capturing links at decode rather than re-fetching detail: the id is already
in every `/manga` payload we receive, so this is free; a resolver-side re-fetch would cost
a network round-trip for the case that should cost nothing.

### 2. `MALTitleMatcher` — pure decision core (`Services/MALTitleMatcher.swift`, new)

The only piece with non-trivial logic, and the piece that carries the unit tests. It has
no dependency on the network or the store — it takes a source title and the candidate DTOs
and returns a decision.

```swift
enum MALMatchDecision: Equatable {
    case matched(malId: Int)
    case noMatch
}

struct MALTitleMatcher {
    // Tunable knobs, named so they're easy to adjust later.
    var acceptanceThreshold: Double = 0.90   // min normalized similarity to accept a fuzzy match
    var ambiguityMargin: Double = 0.05       // reject if best and runner-up are within this

    /// Normalize a title for comparison: lowercase, strip diacritics, drop punctuation,
    /// collapse whitespace, remove common noise tokens (season/part markers, "(manga)").
    static func normalize(_ title: String) -> String

    /// Normalized Levenshtein similarity in [0, 1] (1 == identical after normalization).
    static func similarity(_ a: String, _ b: String) -> Double

    /// Decide the best MAL match for `sourceTitle` among `candidates`.
    /// Each candidate contributes its full title set (main + alternative titles).
    func decide(sourceTitle: String, candidates: [MALCandidate]) -> MALMatchDecision
}

/// A MAL candidate reduced to what matching needs: its id and every title it goes by.
struct MALCandidate: Equatable {
    let malId: Int
    let titles: [String]   // main title + alternative titles (en / ja / synonyms)
}
```

`decide` algorithm:
1. `normSource = normalize(sourceTitle)`.
2. For each candidate, its score = max over its normalized titles of
   `similarity(normSource, normTitle)`. An exact normalized equality is score `1.0`
   (exact-match-wins falls out of the metric — no special case needed beyond the metric
   returning 1.0 for equal strings).
3. Take the best-scoring candidate and the runner-up.
4. Accept the best **iff** `bestScore >= acceptanceThreshold` **and**
   `bestScore - runnerUpScore >= ambiguityMargin` (or there is only one candidate). The
   ambiguity guard rejects generic titles that match several MAL entries near-equally.
5. Otherwise `.noMatch`.

Empty candidate list, or an empty/whitespace-only source title, → `.noMatch`.

### 3. `alternative_titles` decode on the MAL client

`MyAnimeListManga` currently decodes `id`, `title`, `mainPicture` only, even though
`searchManga` already requests `fields=alternative_titles,main_picture`. Widen it:

```swift
struct MyAnimeListManga: Decodable {
    let id: Int
    let title: String
    let mainPicture: MainPicture?
    let alternativeTitles: AlternativeTitles?    // NEW

    struct MainPicture: Decodable { let medium: String?; let large: String? }

    struct AlternativeTitles: Decodable {
        let synonyms: [String]?
        let en: String?
        let ja: String?
    }

    /// Every title this manga goes by, for matching. Deduped, empties dropped.
    var allTitles: [String] { /* title + en + ja + synonyms, non-empty, deduped */ }
}
```

`allTitles` is what builds a `MALCandidate` (`MALCandidate(malId: m.id, titles: m.allTitles)`).
This is additive — existing decode tests and the debug screen keep working
(`alternativeTitles` is optional).

### 4. `EntityResolutionStore` (`Services/EntityResolutionStore.swift`, new)

Mirrors `TasteProfileStore`: `@MainActor final class ... : ObservableObject`, UserDefaults
+ Codable, injectable `init(defaults:)`.

```swift
enum MALResolution: Codable, Equatable {
    case resolved(malId: Int)          // cached indefinitely — a manga's MAL id is stable
    case unresolved(checkedAt: Date)   // a miss; re-attempt once older than the TTL
}

@MainActor
final class EntityResolutionStore: ObservableObject {
    @Published private(set) var cache: [String: MALResolution] = [:]

    /// Miss re-attempt window. A miss older than this is treated as absent so a new MAL
    /// entry (or an improved matcher) gets another chance.
    static let missTTL: TimeInterval = 14 * 24 * 60 * 60   // 14 days

    func resolution(sourceId: String, mangaId: String) -> MALResolution?   // nil if absent
    func record(sourceId: String, mangaId: String, _ resolution: MALResolution)
}

/// Whether an `.unresolved` miss is still inside its re-attempt window. A pure static
/// helper (not an instance method) so it's unit-testable with an explicit `now` and has
/// no hidden clock dependency; `.resolved` is always "fresh" (never re-attempted).
extension MALResolution {
    func isFresh(now: Date = Date()) -> Bool
}
```

Key format: `"{sourceId}:{mangaId}"`, built internally. The resolver reads a cached entry
with `resolution(...)` and decides via `isFresh`: a `.resolved` returns its id; a fresh
`.unresolved` returns nil (skip network); an absent or stale entry falls through to the
fuzzy path.

### 5. `MALEntityResolver` (`Services/MALEntityResolver.swift`, new)

`@MainActor`, holds an `EntityResolutionStore`. One public method:

```swift
@MainActor
final class MALEntityResolver {
    init(store: EntityResolutionStore, matcher: MALTitleMatcher = .init())

    /// The canonical MAL id for `manga`, or nil if none can be found with confidence.
    /// Never throws for an ordinary no-match; network errors are swallowed to nil so a
    /// transient MAL outage degrades to "omit" rather than surfacing an error.
    func malId(for manga: Manga) async -> Int?
}
```

Flow:
1. **Fast path:** `if let id = manga.malId { return id }`. (No store write — it's free
   every time.)
2. **Cache:** `store.resolution(sourceId: manga.sourceId, mangaId: manga.id)`:
   - `.resolved(id)` → return `id`.
   - `.unresolved` still fresh (within TTL) → return `nil` (skip network).
   - absent, or `.unresolved` stale → fall through to fuzzy.
3. **Fuzzy:** `try? await MyAnimeListAPI.searchManga(title: manga.title)`. On thrown/empty
   → treat as no candidates. Build `[MALCandidate]` from `allTitles`. Run
   `matcher.decide(sourceTitle: manga.title, candidates:)`.
   - `.matched(id)` → `store.record(..., .resolved(id))`, return `id`.
   - `.noMatch` → `store.record(..., .unresolved(checkedAt: Date()))`, return `nil`.

A network error is caught and produces `.noMatch` behavior **without** writing an
`.unresolved` record — a transient outage should not poison the cache for 14 days. (Only a
genuine "MAL returned candidates but none matched" writes the miss.)

### 6. Debug-screen verification hook

Extend `Views/MyAnimeListDebugView.swift` (already the throwaway MAL verification screen)
with a second field: "resolve a source title." It takes a title string, builds a synthetic
scraped-source `Manga` (`sourceId: "weebcentral"`, `malId: nil`, a throwaway id), runs it
through a `MALEntityResolver`, and displays the resolved MAL id (or "no confident match")
plus, on a hit, the resolved title fetched via `mangaDetail` — enough to eyeball that the
fuzzy path picks the right entry against the real API. No production wiring; deleted with
the rest of the debug screen when subsystem 3 ships.

## Data flow

```
Manga (any source)
   │
   ▼
MALEntityResolver.malId(for:)
   ├─ manga.malId present? ──────────────► return it            (MangaDex fast path)
   ├─ store: .resolved? ─────────────────► return cached id
   ├─ store: fresh .unresolved? ─────────► return nil
   └─ else:
        MyAnimeListAPI.searchManga(title) ─► [MyAnimeListManga]
             │ .allTitles
             ▼
        [MALCandidate] ─► MALTitleMatcher.decide ─► .matched(id) → store .resolved → id
                                                    .noMatch      → store .unresolved → nil
```

## Testing

Unit (no network):

- **`MALTitleMatcher`:** `normalize` cases (diacritics, punctuation, case, whitespace,
  season/"(manga)" noise); exact normalized match → `1.0`/accept; a near-miss just below
  vs just above `acceptanceThreshold`; the ambiguity guard (two near-equal candidates →
  `.noMatch`; a clear winner → accept); an alt-title hit where the *main* title does not
  match; empty candidates and empty source title → `.noMatch`.
- **`EntityResolutionStore`:** record/read round-trip; source-qualified keys don't collide
  across sources; `.resolved` always returned; `.unresolved` fresh vs stale relative to
  `missTTL`; UserDefaults persistence (encode → new instance → decode).
- **Resolver fast path:** a `Manga` with `malId` set returns it without any store or
  network interaction (verifiable because no store record is written).
- **Decode:** `MangaAttributes`/`MangaDetailAttributes` `links.mal` → `Manga.malId`
  (present, missing, non-numeric); `MyAnimeListManga.alternativeTitles` + `allTitles`
  (present, absent, dedupe) from fixture JSON.

Live verification (per convention — iPhone 17 sim, `-parallel-testing-enabled NO`):

- Through the extended `MyAnimeListDebugView`: resolve a known scraped-source-style title
  (e.g. "Attack on Titan") and confirm it lands on the correct MAL entry
  (Shingeki no Kyojin) via the English alternative title; resolve a deliberately
  garbage/unknown title and confirm "no confident match."

## Explicitly deferred (YAGNI / subsystem 3)

- The "More Like This" UI and any production wiring of the resolver.
- Feeding MAL identity/recommendations into `RecommendationEngine`/`TasteProfile`
  (a real design fork — folding into the MangaDex-only engine vs a parallel MAL-driven
  feature — to be discussed with the user when subsystem 3 is designed).
- The reverse direction: resolving a MAL id back to source manga.
- Non-MAL external ids (AniList `links.al`, etc.).
- Token-set / word-order-tolerant similarity metrics — start with normalized Levenshtein;
  revisit only if precision-biased Levenshtein misses too many real matches in practice.
- Any batch/prefetch resolution — resolution is on-demand, one manga at a time.
```
