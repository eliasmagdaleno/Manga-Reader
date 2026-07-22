# "More Like This" (Cross-Source Recommendations, subsystem 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Netflix-style "More Like This" rail on the manga detail page, sourced from MyAnimeList per-title recommendations and reverse-resolved to openable MangaDex titles.

**Architecture:** A per-title, non-personalized feature kept fully separate from the home `RecommendationEngine` (they share only the reusable `MangaRail` UI). A new `@MainActor` `MoreLikeThisProvider` orchestrates: forward-resolve the current `Manga` → MAL id (reusing subsystem 2's `MALEntityResolver`), fetch MAL detail, take the top-N recommendations by weight, then reverse-resolve each MAL recommendation back to a MangaDex `Manga` (precise `malId` match first, fuzzy title fallback, omit on no confident match). Decision logic lives in pure, unit-tested helpers; the network glue is thin and live-verified (the codebase has no network-mock harness for `MangaDexAPI`/`MyAnimeListAPI`). A reverse cache added to `EntityResolutionStore` (keyed by `String(malId)`, same 14-day miss TTL, app-wide `.shared` instance) persists resolutions across detail-page opens.

**Tech Stack:** SwiftUI, Swift Concurrency (`async`/`await`, `withTaskGroup`), Foundation, UserDefaults+Codable persistence. Pure SwiftUI + Foundation — no third-party dependencies. XCTest for unit + UI tests.

## Global Constraints

- **Deployment target iOS 17.5.** No API newer than 17.5 without an `#available(iOS 18.0, *)` branch.
- **No third-party dependencies / package managers.** Pure SwiftUI + Foundation only.
- **Nothing outside source adapters calls `MangaDexAPI` directly** — except this subsystem's `MoreLikeThisProvider`, which (like `LibraryStore` and `MALEntityResolver` before it) is an app-level service that legitimately calls `MangaDexAPI`/`MyAnimeListAPI` static methods. ViewModels/Views still go through the provider, never the APIs.
- **Precision over recall, end to end.** Any recommendation that cannot be reverse-resolved with confidence is omitted. Better 6 solid cards than 10 with 4 wrong ones.
- **`EntityResolutionStore.missTTL` stays `nonisolated static let`.** Any new freshness helper that references it off-actor (e.g. `ReverseResolution.isFresh`) must also be reachable without `@MainActor`.
- **`[Int: X]` JSON-encodes oddly in Swift** — key the reverse cache by `String(malId)`, matching the forward map's string keying.
- **New files in `Services/` and `Models/` are auto-compiled** (Xcode synchronized root groups) — no `project.pbxproj` edits. `MangaDetailView.swift` and `MyAnimeListDebugView.swift` already exist, so editing them needs no `pbxproj` change either. (Only a brand-new file under `Views/` would.)
- **Tests run on the iPhone 17 simulator with `-parallel-testing-enabled NO`** (no iPhone 16 sim on this machine; parallel test clones are unwanted). Expect SourceKit/LSP "Cannot find X in scope" / "No such module 'XCTest'" false alarms from the standalone indexer — judge correctness by the `xcodebuild test` run, not the indexer.
- **Frequent commits** — one per task, after its tests pass.

Reference paths (all relative to repo root `/Users/eliasmagdaleno/xcode/Manga-Reader`):
- Source root: `Manga-Reader/` (note: the app sources live under `Manga-Reader/Manga-Reader/…`)
- Unit tests: `Manga-ReaderTests/Manga_ReaderTests.swift` (single class `Manga_ReaderTests: XCTestCase`)
- UI tests: `Manga-ReaderUITests/Manga_ReaderUITests.swift` (single class `Manga_ReaderUITests: XCTestCase`)

---

## File Structure

**New files:**
- `Manga-Reader/Services/MoreLikeThis.swift` — the pure, network-free reverse-match helper (`enum MoreLikeThis` with `pickMatch(...)`).
- `Manga-Reader/Services/MoreLikeThisProvider.swift` — `@MainActor` orchestration service + a pure `topRecommendations(_:limit:)` static.
- `Manga-Reader/Models/MoreLikeThisViewModel.swift` — `@MainActor ObservableObject` the detail rail binds to.

**Modified files:**
- `Manga-Reader/Services/MALTitleMatcher.swift` — add generic `bestMatch<ID>(...)`; `decide(...)` delegates to it.
- `Manga-Reader/Services/EntityResolutionStore.swift` — add `ReverseResolution` enum, `reverseCache` map + accessors, and `static let shared`.
- `Manga-Reader/Models/MangaDexAPI.swift` — change `fetchMangaByIdsWithCovers(ids:)` from `private static` to `static` (internal).
- `Manga-Reader/Views/MangaDetailView.swift` — add the `moreLikeThis` view model, the bottom rail section, and a `.task` to load it.
- `Manga-Reader/Views/MyAnimeListDebugView.swift` — add a "More Like This" probe field (throwaway; retired with the debug screen later).
- `Manga-ReaderTests/Manga_ReaderTests.swift` — append unit tests.
- `Manga-ReaderUITests/Manga_ReaderUITests.swift` — append two live UI tests.

---

## Task 1: Generalize `MALTitleMatcher` scoring (`bestMatch<ID>`)

Extract the normalize+score+threshold+ambiguity-guard core of `decide` into a generic static over the id type, so both the forward (→ MAL id) and reverse (→ MangaDex id) paths share one implementation. `decide` delegates to it. The existing 7 matcher tests are the refactor's safety net; one new test proves genericity over a non-`Int` id.

**Files:**
- Modify: `Manga-Reader/Services/MALTitleMatcher.swift:76-95` (replace the `decide` body; add `bestMatch`)
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append near the existing `// MARK: - MALTitleMatcher` block, ~line 1846)

**Interfaces:**
- Consumes: existing `MALTitleMatcher.normalize`, `MALTitleMatcher.similarity`, `acceptanceThreshold`, `ambiguityMargin`, `MALCandidate`, `MALMatchDecision`.
- Produces: `func bestMatch<ID>(sourceTitle: String, candidates: [(id: ID, titles: [String])]) -> ID?` on `MALTitleMatcher` — returns the id of the confident best match, or `nil`. Reused by Task 2 (`MoreLikeThis.pickMatch`) and internally by `decide`.

- [ ] **Step 1: Write the failing test**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift` (inside `final class Manga_ReaderTests`, after the last matcher test near line 1846):

```swift
    func testMALBestMatchIsGenericOverStringId() {
        let matcher = MALTitleMatcher()
        let candidates: [(id: String, titles: [String])] = [
            (id: "md-1", titles: ["Shingeki no Kyojin", "Attack on Titan"]),
            (id: "md-2", titles: ["Some Unrelated Manga"]),
        ]
        XCTAssertEqual(matcher.bestMatch(sourceTitle: "Attack on Titan", candidates: candidates), "md-1")
    }

    func testMALBestMatchRejectsAmbiguousAndBelowThreshold() {
        let matcher = MALTitleMatcher()
        // Two identical titles → ambiguity guard → nil.
        XCTAssertNil(matcher.bestMatch(sourceTitle: "Hero", candidates: [
            (id: 1, titles: ["Hero"]),
            (id: 2, titles: ["Hero"]),
        ]))
        // Nothing clears the acceptance threshold → nil.
        XCTAssertNil(matcher.bestMatch(sourceTitle: "Berserk", candidates: [
            (id: 1, titles: ["Completely Different Story"]),
        ]))
        // Empty candidates / empty source → nil.
        XCTAssertNil(matcher.bestMatch(sourceTitle: "Berserk", candidates: [(id: Int, titles: [String])]()))
        XCTAssertNil(matcher.bestMatch(sourceTitle: "", candidates: [(id: 1, titles: ["Berserk"])]))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALBestMatchIsGenericOverStringId
```
Expected: FAIL to compile — "value of type 'MALTitleMatcher' has no member 'bestMatch'".

- [ ] **Step 3: Write the minimal implementation**

In `Manga-Reader/Services/MALTitleMatcher.swift`, replace the current `decide(sourceTitle:candidates:)` method (lines 76-95) with the generic core plus a thin delegating `decide`:

```swift
    /// The id of the best-matching candidate for `sourceTitle`, or nil if no candidate
    /// clears the acceptance threshold and the ambiguity guard. Generic over the id type
    /// so it serves both MAL-id matching (forward) and MangaDex-id matching (reverse).
    /// Precision-biased: any doubt resolves to nil rather than a wrong id.
    func bestMatch<ID>(sourceTitle: String,
                       candidates: [(id: ID, titles: [String])]) -> ID? {
        let normSource = Self.normalize(sourceTitle)
        guard !normSource.isEmpty, !candidates.isEmpty else { return nil }

        let scored = candidates
            .map { candidate -> (id: ID, score: Double) in
                let best = candidate.titles
                    .map { Self.similarity(normSource, Self.normalize($0)) }
                    .max() ?? 0
                return (candidate.id, best)
            }
            .sorted { $0.score > $1.score }

        guard let best = scored.first, best.score >= acceptanceThreshold else { return nil }
        // Ambiguity guard rejects even exact matches (1.0) if the runner-up is too close.
        if scored.count >= 2, best.score - scored[1].score < ambiguityMargin {
            return nil   // too close to call — precision over recall
        }
        return best.id
    }

    /// Best MAL match for `sourceTitle` among `candidates`, or `.noMatch`. Delegates to
    /// the generic `bestMatch`; kept for callers that speak the `MALCandidate`/decision API.
    func decide(sourceTitle: String, candidates: [MALCandidate]) -> MALMatchDecision {
        let match = bestMatch(sourceTitle: sourceTitle,
                              candidates: candidates.map { (id: $0.malId, titles: $0.titles) })
        return match.map { .matched(malId: $0) } ?? .noMatch
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run (the two new tests plus the whole existing matcher suite as the refactor's safety net):
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALBestMatchIsGenericOverStringId \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALBestMatchRejectsAmbiguousAndBelowThreshold \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideMatchesViaAlternativeTitle \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testMALDecideEmptyInputsAreNoMatch
```
Expected: PASS — all four. (The delegation keeps `decide`'s behavior identical; the existing `testMALDecide*` tests must stay green.)

- [ ] **Step 5: Commit**

```sh
git add Manga-Reader/Services/MALTitleMatcher.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Refactor MALTitleMatcher: extract generic bestMatch<ID>, decide delegates

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Pure reverse-match helper (`MoreLikeThis.pickMatch`)

The testable core of reverse resolution: given a MAL recommendation (its id + title) and the MangaDex search results for that title, pick the confident MangaDex `Manga` — or `nil`. Precise first (a candidate whose `malId == target` is a confirmed match), fuzzy title fallback via `bestMatch`, `nil` when neither is confident.

**Files:**
- Create: `Manga-Reader/Services/MoreLikeThis.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append)

**Interfaces:**
- Consumes: `Manga` (fields `id: String`, `malId: Int?`, `title: String`), `MALTitleMatcher.bestMatch` (Task 1).
- Produces: `enum MoreLikeThis` with `static func pickMatch(targetMalId: Int, malTitle: String, candidates: [Manga], matcher: MALTitleMatcher = .init()) -> Manga?`. Consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift` (inside `final class Manga_ReaderTests`; a small `Manga`-builder keeps the cases readable):

```swift
    // MARK: - MoreLikeThis.pickMatch

    /// Minimal `Manga` for pure MoreLikeThis tests. `Manga`'s memberwise init is internal,
    /// reachable here via `@testable import Manga_Reader`.
    private func mlManga(id: String, title: String, malId: Int?) -> Manga {
        Manga(id: id, sourceId: "mangadex", title: title, description: "",
              status: "unknown", year: nil, coverURL: nil, malId: malId)
    }

    func testPickMatchPrefersExactMalIdOverCloserTitle() {
        // A candidate carrying the target malId wins even though a DIFFERENT candidate
        // has an identical title (which fuzzy matching would otherwise prefer).
        let candidates = [
            mlManga(id: "md-decoy", title: "Berserk", malId: 999),
            mlManga(id: "md-real", title: "Beruseruku", malId: 42),
        ]
        let match = MoreLikeThis.pickMatch(targetMalId: 42, malTitle: "Berserk", candidates: candidates)
        XCTAssertEqual(match?.id, "md-real")
    }

    func testPickMatchFallsBackToFuzzyTitleWhenNoCandidateCarriesId() {
        let candidates = [
            mlManga(id: "md-1", title: "Vinland Saga", malId: nil),
            mlManga(id: "md-2", title: "Totally Other Thing", malId: nil),
        ]
        let match = MoreLikeThis.pickMatch(targetMalId: 777, malTitle: "Vinland Saga", candidates: candidates)
        XCTAssertEqual(match?.id, "md-1")
    }

    func testPickMatchReturnsNilWhenAmbiguousOrBelowThreshold() {
        // Ambiguous: two identical titles, neither carries the id.
        let ambiguous = [
            mlManga(id: "md-1", title: "Hero", malId: nil),
            mlManga(id: "md-2", title: "Hero", malId: nil),
        ]
        XCTAssertNil(MoreLikeThis.pickMatch(targetMalId: 5, malTitle: "Hero", candidates: ambiguous))
        // Below threshold: nothing close enough.
        let unrelated = [mlManga(id: "md-1", title: "Completely Different Story", malId: nil)]
        XCTAssertNil(MoreLikeThis.pickMatch(targetMalId: 5, malTitle: "Berserk", candidates: unrelated))
    }

    func testPickMatchReturnsNilForEmptyCandidates() {
        XCTAssertNil(MoreLikeThis.pickMatch(targetMalId: 5, malTitle: "Berserk", candidates: []))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testPickMatchPrefersExactMalIdOverCloserTitle
```
Expected: FAIL to compile — "cannot find 'MoreLikeThis' in scope".

- [ ] **Step 3: Write the minimal implementation**

Create `Manga-Reader/Services/MoreLikeThis.swift`:

```swift
//
//  MoreLikeThis.swift
//  Manga-Reader
//
//  Pure, network-free core of "More Like This" reverse resolution: turn one MAL
//  recommendation (its id + title) plus the MangaDex search results for that title into
//  the confident MangaDex `Manga` — or nil. Precision-biased, fully unit-tested. The
//  networking that produces `candidates` and consumes the result lives in
//  MoreLikeThisProvider.
//

import Foundation

enum MoreLikeThis {
    /// Reverse-resolve one MAL recommendation to a MangaDex `Manga` among `candidates`
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

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testPickMatchPrefersExactMalIdOverCloserTitle \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testPickMatchFallsBackToFuzzyTitleWhenNoCandidateCarriesId \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testPickMatchReturnsNilWhenAmbiguousOrBelowThreshold \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testPickMatchReturnsNilForEmptyCandidates
```
Expected: PASS — all four.

- [ ] **Step 5: Commit**

```sh
git add Manga-Reader/Services/MoreLikeThis.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add MoreLikeThis.pickMatch: pure reverse-resolution core

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Reverse cache in `EntityResolutionStore`

Add a second, parallel map for the reverse direction (MAL id → MangaDex manga id), keyed by `String(malId)`, persisted under its own UserDefaults key with the same 14-day miss TTL. Add an app-wide `static let shared` so the cache persists across detail-page opens.

**Files:**
- Modify: `Manga-Reader/Services/EntityResolutionStore.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append near the existing `// MARK: - EntityResolutionStore` block, ~line 1847)

**Interfaces:**
- Consumes: existing `EntityResolutionStore` shape (`init(defaults:)`, `missTTL`, `save`/`load` pattern), `MALResolution.isFresh` (as the shape to mirror).
- Produces:
  - `enum ReverseResolution: Codable, Equatable` with cases `.resolved(mangaDexId: String)` / `.unresolved(checkedAt: Date)` and `func isFresh(now: Date = Date()) -> Bool`.
  - `func reverseResolution(malId: Int) -> ReverseResolution?`
  - `func recordReverse(malId: Int, _ resolution: ReverseResolution)`
  - `static let shared = EntityResolutionStore()`
  All consumed by Task 4.

- [ ] **Step 1: Write the failing test**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift`:

```swift
    // MARK: - EntityResolutionStore reverse cache

    @MainActor func testReverseCacheRoundTripsAndKeysByMalId() {
        let defaults = UserDefaults(suiteName: "test.reverse.\(UUID().uuidString)")!
        let store = EntityResolutionStore(defaults: defaults)
        store.recordReverse(malId: 42, .resolved(mangaDexId: "md-abc"))
        XCTAssertEqual(store.reverseResolution(malId: 42), .resolved(mangaDexId: "md-abc"))
        XCTAssertNil(store.reverseResolution(malId: 99))
    }

    @MainActor func testReverseCacheDoesNotCollideWithForwardCache() {
        let defaults = UserDefaults(suiteName: "test.reverse.\(UUID().uuidString)")!
        let store = EntityResolutionStore(defaults: defaults)
        // Forward map keyed "{sourceId}:{mangaId}"; reverse keyed String(malId). Same
        // numeric value must not bleed across the two maps.
        store.record(sourceId: "mangadex", mangaId: "7", .resolved(malId: 7))
        store.recordReverse(malId: 7, .resolved(mangaDexId: "md-7"))
        XCTAssertEqual(store.resolution(sourceId: "mangadex", mangaId: "7"), .resolved(malId: 7))
        XCTAssertEqual(store.reverseResolution(malId: 7), .resolved(mangaDexId: "md-7"))
    }

    func testReverseResolutionIsFreshHonorsMissTTL() {
        let now = Date()
        let fresh = ReverseResolution.unresolved(checkedAt: now.addingTimeInterval(-EntityResolutionStore.missTTL + 1))
        let stale = ReverseResolution.unresolved(checkedAt: now.addingTimeInterval(-EntityResolutionStore.missTTL - 1))
        XCTAssertTrue(fresh.isFresh(now: now))
        XCTAssertFalse(stale.isFresh(now: now))
        XCTAssertTrue(ReverseResolution.resolved(mangaDexId: "x").isFresh(now: now))
    }

    @MainActor func testReverseCachePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: "test.reverse.\(UUID().uuidString)")!
        EntityResolutionStore(defaults: defaults).recordReverse(malId: 11, .resolved(mangaDexId: "md-11"))
        let reloaded = EntityResolutionStore(defaults: defaults)
        XCTAssertEqual(reloaded.reverseResolution(malId: 11), .resolved(mangaDexId: "md-11"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testReverseCacheRoundTripsAndKeysByMalId
```
Expected: FAIL to compile — "cannot find 'ReverseResolution' in scope" / no member `recordReverse`.

- [ ] **Step 3: Write the minimal implementation**

In `Manga-Reader/Services/EntityResolutionStore.swift`:

(a) Add the `ReverseResolution` enum after the existing `MALResolution` enum (after line 29):

```swift
/// The cached outcome of reverse-resolving a MAL id to a MangaDex manga id.
enum ReverseResolution: Codable, Equatable {
    case resolved(mangaDexId: String)   // Cached indefinitely.
    case unresolved(checkedAt: Date)    // A miss; re-attempt once older than `missTTL`.

    /// Whether this entry should still be trusted (vs. re-attempted). Hits are always
    /// fresh; a miss is fresh until it passes the TTL. Mirrors `MALResolution.isFresh`.
    func isFresh(now: Date = Date()) -> Bool {
        switch self {
        case .resolved:
            return true
        case .unresolved(let checkedAt):
            return now.timeIntervalSince(checkedAt) < EntityResolutionStore.missTTL
        }
    }
}
```

(b) Inside `final class EntityResolutionStore`, add the reverse map, a shared instance, and accessors. Add the `@Published` reverse map right after the existing `cache` property (line 34):

```swift
    /// MAL id (as `String(malId)`) → reverse-resolution outcome.
    @Published private(set) var reverseCache: [String: ReverseResolution] = [:]

    /// App-wide instance so the forward and reverse caches persist across detail-page
    /// opens. Tests still construct isolated instances via `init(defaults:)`.
    static let shared = EntityResolutionStore()
```

Add a second UserDefaults key next to `cacheKey` (line 39):

```swift
    private let reverseCacheKey = "entityResolution.reverseCache"
```

Add the accessors after the existing `record(...)` method (after line 54):

```swift
    func reverseResolution(malId: Int) -> ReverseResolution? {
        reverseCache[String(malId)]
    }

    func recordReverse(malId: Int, _ resolution: ReverseResolution) {
        reverseCache[String(malId)] = resolution
        save()
    }
```

Extend `save()` and `load()` (lines 60-69) to persist/restore the reverse map alongside the forward one:

```swift
    private func save() {
        if let data = try? JSONEncoder().encode(cache) { defaults.set(data, forKey: cacheKey) }
        if let data = try? JSONEncoder().encode(reverseCache) { defaults.set(data, forKey: reverseCacheKey) }
    }

    private func load() {
        if let data = defaults.data(forKey: cacheKey),
           let value = try? JSONDecoder().decode([String: MALResolution].self, from: data) {
            cache = value
        }
        if let data = defaults.data(forKey: reverseCacheKey),
           let value = try? JSONDecoder().decode([String: ReverseResolution].self, from: data) {
            reverseCache = value
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testReverseCacheRoundTripsAndKeysByMalId \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testReverseCacheDoesNotCollideWithForwardCache \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testReverseResolutionIsFreshHonorsMissTTL \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testReverseCachePersistsAcrossInstances
```
Expected: PASS — all four.

- [ ] **Step 5: Commit**

```sh
git add Manga-Reader/Services/EntityResolutionStore.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add reverse cache (MAL id -> MangaDex id) + shared store to EntityResolutionStore

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: `MoreLikeThisProvider` orchestration

The `@MainActor` service that turns a `Manga` into openable MangaDex recommendations. Also exposes `MangaDexAPI.fetchMangaByIdsWithCovers` (internal) and adds a pure `topRecommendations` static (unit-tested). The network orchestration is thin and live-verified in Task 6 (no network-mock harness in this codebase).

**Files:**
- Modify: `Manga-Reader/Models/MangaDexAPI.swift:527` (`private static` → `static`)
- Create: `Manga-Reader/Services/MoreLikeThisProvider.swift`
- Test: `Manga-ReaderTests/Manga_ReaderTests.swift` (append — pure `topRecommendations` only)

**Interfaces:**
- Consumes: `MALEntityResolver.malId(for:)`, `MyAnimeListAPI.mangaDetail(id:)` → `MyAnimeListMangaDetail` (`.recommendations: [Recommendation]?`, `Recommendation { let node: MyAnimeListManga; let numRecommendations: Int }`, `MyAnimeListManga { let id: Int; let title: String }`), `MangaDexAPI.searchManga(title:)` → `[Manga]`, `MangaDexAPI.fetchMangaByIdsWithCovers(ids:)` → `[Manga]`, `MoreLikeThis.pickMatch` (Task 2), `EntityResolutionStore.shared`/`reverseResolution`/`recordReverse`/`ReverseResolution` (Task 3), `MALTitleMatcher` (Task 1).
- Produces:
  - `MoreLikeThisProvider` (`@MainActor final class`) with `init(store:resolver:matcher:)` and `func recommendations(for manga: Manga, limit: Int = 8) async -> [Manga]`.
  - `static func topRecommendations(_ recs: [MyAnimeListMangaDetail.Recommendation], limit: Int) -> [MyAnimeListMangaDetail.Recommendation]`.
  Consumed by Task 5 (view model) and Task 6 (debug probe).

- [ ] **Step 1: Write the failing test (pure `topRecommendations`)**

Append to `Manga-ReaderTests/Manga_ReaderTests.swift`:

```swift
    // MARK: - MoreLikeThisProvider.topRecommendations (pure)

    /// Minimal `Recommendation` builder — the MAL DTO memberwise inits are internal,
    /// reachable via `@testable import Manga_Reader`.
    private func mlRec(malId: Int, weight: Int) -> MyAnimeListMangaDetail.Recommendation {
        MyAnimeListMangaDetail.Recommendation(
            node: MyAnimeListManga(id: malId, title: "T\(malId)",
                                   mainPicture: nil, alternativeTitles: nil),
            numRecommendations: weight)
    }

    func testTopRecommendationsSortsByWeightDescendingAndCaps() {
        let recs = [mlRec(malId: 1, weight: 3), mlRec(malId: 2, weight: 10), mlRec(malId: 3, weight: 7)]
        let top = MoreLikeThisProvider.topRecommendations(recs, limit: 2)
        XCTAssertEqual(top.map { $0.node.id }, [2, 3])   // 10, 7 — highest weight first, capped at 2
    }

    func testTopRecommendationsHandlesEmptyAndUndercount() {
        XCTAssertTrue(MoreLikeThisProvider.topRecommendations([], limit: 8).isEmpty)
        let recs = [mlRec(malId: 1, weight: 5)]
        XCTAssertEqual(MoreLikeThisProvider.topRecommendations(recs, limit: 8).map { $0.node.id }, [1])
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests/Manga_ReaderTests/testTopRecommendationsSortsByWeightDescendingAndCaps
```
Expected: FAIL to compile — "cannot find 'MoreLikeThisProvider' in scope".

- [ ] **Step 3a: Expose the batch fetch**

In `Manga-Reader/Models/MangaDexAPI.swift`, line 527, change the access level (no behavior change):

```swift
    static func fetchMangaByIdsWithCovers(ids: [String]) async throws -> [Manga] {
```

- [ ] **Step 3b: Write the provider**

Create `Manga-Reader/Services/MoreLikeThisProvider.swift`:

```swift
//
//  MoreLikeThisProvider.swift
//  Manga-Reader
//
//  Turns a Manga into a list of openable MangaDex "More Like This" titles, sourced from
//  MyAnimeList's per-title recommendations. Orchestration only: forward-resolve → MAL
//  detail → top-N recommendations → reverse-resolve each back to a MangaDex Manga, in
//  recommendation-weight order. The decision logic lives in pure helpers (MoreLikeThis,
//  MALTitleMatcher); this is the thin, live-verified network glue (the codebase has no
//  network-mock harness). Non-throwing: any failure degrades to fewer/zero cards.
//

import Foundation

@MainActor
final class MoreLikeThisProvider {
    private let store: EntityResolutionStore
    private let resolver: MALEntityResolver
    private let matcher: MALTitleMatcher

    init(store: EntityResolutionStore = .shared,
         resolver: MALEntityResolver? = nil,
         matcher: MALTitleMatcher = .init()) {
        self.store = store
        self.resolver = resolver ?? MALEntityResolver(store: store)
        self.matcher = matcher
    }

    /// The top `limit` recommendations by weight (descending). Pure — no network.
    static func topRecommendations(_ recs: [MyAnimeListMangaDetail.Recommendation],
                                   limit: Int) -> [MyAnimeListMangaDetail.Recommendation] {
        Array(recs.sorted { $0.numRecommendations > $1.numRecommendations }.prefix(limit))
    }

    /// Up to `limit` openable MangaDex titles similar to `manga`, in MAL-recommendation
    /// order. Empty when `manga` has no MAL match, MAL returns no recommendations, or none
    /// reverse-resolve. Never throws — network failures degrade to fewer/zero cards.
    func recommendations(for manga: Manga, limit: Int = 8) async -> [Manga] {
        guard let malId = await resolver.malId(for: manga) else { return [] }
        guard let detail = try? await MyAnimeListAPI.mangaDetail(id: malId) else { return [] }
        let recs = Self.topRecommendations(detail.recommendations ?? [], limit: limit)
        guard !recs.isEmpty else { return [] }

        // Partition into fresh cache hits (batch-fetch later) and misses (live search).
        var resolvedIds: [Int: String] = [:]     // malId -> MangaDex id, from fresh cache hits
        var toSearch: [MyAnimeListManga] = []     // recs needing a live search
        for rec in recs {
            if let cached = store.reverseResolution(malId: rec.node.id), cached.isFresh() {
                if case .resolved(let mdId) = cached { resolvedIds[rec.node.id] = mdId }
                // A fresh .unresolved miss: skip entirely (don't re-search yet).
            } else {
                toSearch.append(rec.node)
            }
        }

        // Live search + reverse-resolve the misses; records the cache outcomes.
        let freshlyResolved = await reverseResolveViaSearch(toSearch)   // [malId: Manga]
        for (recMalId, m) in freshlyResolved { resolvedIds[recMalId] = m.id }

        // Full `Manga` values we already have (from the live searches), keyed by id.
        let searchedById = Dictionary(freshlyResolved.values.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })

        // Batch-fetch the MangaDex ids we know but don't yet have a full Manga for
        // (cache-hit ids). One request, covers included.
        let idsNeedingFetch = Array(Set(resolvedIds.values.filter { searchedById[$0] == nil }))
        var fetchedById: [String: Manga] = [:]
        if !idsNeedingFetch.isEmpty,
           let fetched = try? await MangaDexAPI.fetchMangaByIdsWithCovers(ids: idsNeedingFetch) {
            fetchedById = Dictionary(fetched.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }

        // Reassemble in recommendation (weight) order; drop self; de-dupe by id.
        var out: [Manga] = []
        var seen = Set<String>()
        for rec in recs {
            guard let mdId = resolvedIds[rec.node.id],
                  let resolved = searchedById[mdId] ?? fetchedById[mdId],
                  resolved.id != manga.id,
                  seen.insert(resolved.id).inserted else { continue }
            out.append(resolved)
        }
        return out
    }

    /// Search MangaDex for each rec's title and reverse-resolve to a confident Manga
    /// (bounded concurrency, cap 4 — the pattern established for LibraryStore.refresh).
    /// Records `.resolved`/`.unresolved` in the reverse cache; a THROWN search records
    /// nothing (transient — don't poison the cache), mirroring MALEntityResolver.
    private func reverseResolveViaSearch(_ nodes: [MyAnimeListManga]) async -> [Int: Manga] {
        guard !nodes.isEmpty else { return [:] }
        let matcher = self.matcher
        let maxConcurrent = 4

        // (malId, resolved Manga?, didSearch) — didSearch == false means the search threw.
        let results: [(Int, Manga?, Bool)] = await withTaskGroup(
            of: (Int, Manga?, Bool).self
        ) { group in
            var iterator = nodes.makeIterator()

            func addNext() {
                guard let node = iterator.next() else { return }
                group.addTask {
                    do {
                        let candidates = try await MangaDexAPI.searchManga(title: node.title)
                        let match = MoreLikeThis.pickMatch(targetMalId: node.id,
                                                           malTitle: node.title,
                                                           candidates: candidates,
                                                           matcher: matcher)
                        return (node.id, match, true)
                    } catch {
                        return (node.id, nil, false)   // transient — cache nothing
                    }
                }
            }

            for _ in 0..<maxConcurrent { addNext() }

            var out: [(Int, Manga?, Bool)] = []
            while let result = await group.next() {
                out.append(result)
                addNext()
            }
            return out
        }

        var resolved: [Int: Manga] = [:]
        for (recMalId, manga, didSearch) in results {
            if let manga {
                store.recordReverse(malId: recMalId, .resolved(mangaDexId: manga.id))
                resolved[recMalId] = manga
            } else if didSearch {
                store.recordReverse(malId: recMalId, .unresolved(checkedAt: Date()))
            }   // !didSearch → record nothing
        }
        return resolved
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass, and confirm the app builds**

Run the pure tests:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testTopRecommendationsSortsByWeightDescendingAndCaps \
  -only-testing:Manga-ReaderTests/Manga_ReaderTests/testTopRecommendationsHandlesEmptyAndUndercount
```
Expected: PASS — both. (This also proves the whole provider + `withTaskGroup` orchestration compiles, since the test target links it. Watch specifically for Sendable/actor-isolation warnings on the `withTaskGroup` closures — `Manga`, `MyAnimeListManga`, and `MALTitleMatcher` are all value types with Sendable stored properties, so the off-actor tasks are legal; the `store.recordReverse` calls happen after the group completes, back on the MainActor.)

- [ ] **Step 5: Commit**

```sh
git add Manga-Reader/Models/MangaDexAPI.swift Manga-Reader/Services/MoreLikeThisProvider.swift Manga-ReaderTests/Manga_ReaderTests.swift
git commit -m "Add MoreLikeThisProvider: MAL recs -> MangaDex reverse resolution

Expose MangaDexAPI.fetchMangaByIdsWithCovers (internal) for cache-hit batch render.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `MoreLikeThisViewModel` + detail-page rail

The view model the rail binds to, plus the bottom-of-page rail section in `MangaDetailView` (reuses `MangaRail`, loads async via `.task`, hidden when empty). Verified by building the app and, at the branch's end, by the live UI test in Task 6.

**Files:**
- Create: `Manga-Reader/Models/MoreLikeThisViewModel.swift`
- Modify: `Manga-Reader/Views/MangaDetailView.swift` (add `@StateObject`, rail section, `.task`, the `moreLikeThisRail` view)

**Interfaces:**
- Consumes: `MoreLikeThisProvider` (Task 4), `Manga`, `MangaRail(items:)`, `InkSectionHeader(_:eyebrow:)`.
- Produces: `MoreLikeThisViewModel` (`@MainActor final class ObservableObject`) with `@Published private(set) var items: [Manga]`, `@Published private(set) var isLoading: Bool`, `func load(for manga: Manga) async` (idempotent per manga id).

- [ ] **Step 1: Create the view model**

Create `Manga-Reader/Models/MoreLikeThisViewModel.swift`:

```swift
//
//  MoreLikeThisViewModel.swift
//  Manga-Reader
//
//  Backs the detail-page "More Like This" rail. Loads once per manga via
//  MoreLikeThisProvider; publishes the resolved MangaDex titles for MangaRail. Empty
//  `items` means "no rail" — the view hides the section (graceful, like the For You rail).
//

import SwiftUI

@MainActor
final class MoreLikeThisViewModel: ObservableObject {
    @Published private(set) var items: [Manga] = []
    @Published private(set) var isLoading = false

    private let provider: MoreLikeThisProvider
    private var loadedFor: String?

    init(provider: MoreLikeThisProvider = MoreLikeThisProvider()) {
        self.provider = provider
    }

    /// Idempotent per manga id: loads recommendations once for a given manga. Safe to
    /// call from `.task` on every appear — a repeat call for the same manga is a no-op.
    func load(for manga: Manga) async {
        guard loadedFor != manga.id else { return }
        loadedFor = manga.id
        isLoading = true
        defer { isLoading = false }
        items = await provider.recommendations(for: manga)
    }
}
```

- [ ] **Step 2: Wire the rail into `MangaDetailView`**

In `Manga-Reader/Views/MangaDetailView.swift`:

(a) Add the state object next to the other `@StateObject`/state (after line 13, `@EnvironmentObject private var tasteProfile`):

```swift
    @StateObject private var moreLikeThis = MoreLikeThisViewModel()
```

(b) In `body`, append the rail as the LAST section in the main `VStack` — change lines 44-49 from:

```swift
                hero
                actionRow
                if !vm.tags.isEmpty { tags }
                if !vm.description.isEmpty || vm.isLoading { description }
                chapters
```
to:
```swift
                hero
                actionRow
                if !vm.tags.isEmpty { tags }
                if !vm.description.isEmpty || vm.isLoading { description }
                chapters
                if !moreLikeThis.items.isEmpty { moreLikeThisRail }
```

(c) Add the load trigger next to the existing `.onAppear { vm.load() }` (line 54). Add on the following line:

```swift
        .task { await moreLikeThis.load(for: manga) }
```

(d) Add the `moreLikeThisRail` computed view. Insert it immediately after the `description` computed property's closing brace (line 339) and before the `// MARK: Chapters` comment (line 341):

```swift
    // MARK: More Like This — MAL-sourced cross-source recommendations, bottom of page.

    private var moreLikeThisRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            InkSectionHeader("More Like This", eyebrow: "Similar titles")
            MangaRail(items: moreLikeThis.items)
        }
        .accessibilityIdentifier("moreLikeThisSection")
    }
```

(Both `InkSectionHeader` and `MangaRail` apply their own `.padding(.horizontal, Gutter.page)`, matching the `description`/`chapters` sections — no extra padding needed.)

- [ ] **Step 3: Build to verify it compiles**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`. (Ignore any standalone SourceKit/LSP "Cannot find X in scope" noise — trust the `xcodebuild` result.)

- [ ] **Step 4: Commit**

```sh
git add Manga-Reader/Models/MoreLikeThisViewModel.swift Manga-Reader/Views/MangaDetailView.swift
git commit -m "Add More Like This rail to detail page + MoreLikeThisViewModel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Debug-screen probe + live UI verification

Extend the throwaway `MyAnimeListDebugView` with a "More Like This" probe (types a title → runs the provider → lists resolved MangaDex titles), then add two live UI tests against the real MAL + MangaDex APIs: the probe, and the real detail-page rail. This is the codebase's established technique for verifying network code with no mocking harness. The probe field + its UI test are throwaway (deleted when the debug screen is retired in a later cleanup); the detail-page rail test is permanent.

**Files:**
- Modify: `Manga-Reader/Views/MyAnimeListDebugView.swift` (add the probe field + action)
- Modify: `Manga-ReaderUITests/Manga_ReaderUITests.swift` (append two live tests)

**Interfaces:**
- Consumes: `MoreLikeThisProvider().recommendations(for:)` (Task 4), the detail-page rail (Task 5, `accessibilityIdentifier("moreLikeThisSection")` + `MangaRail`'s `"mangaCoverCard"` cards), existing debug-screen nav (`malClientRow` → `malSearchField`), existing Home→Detail nav (`mangaCoverCard`).
- Produces: no code consumed downstream — this is verification.

- [ ] **Step 1: Add the probe to `MyAnimeListDebugView`**

In `Manga-Reader/Views/MyAnimeListDebugView.swift`:

(a) Add state next to the existing `@State` (after line 18, `@State private var resolvedText`):

```swift
    @State private var mltQuery = ""
    @State private var mltResults: [Manga] = []
```

(b) Add a new `Section` after the "Resolve source title" section (after line 42, its closing `}`):

```swift
            Section("More Like This") {
                TextField("Title", text: $mltQuery)
                    .accessibilityIdentifier("mltField")
                    .onSubmit { moreLikeThis() }
                Button("Find similar") { moreLikeThis() }
                    .accessibilityIdentifier("mltButton")
                    .disabled(mltQuery.isEmpty || isLoading)
                ForEach(mltResults, id: \.id) { manga in
                    Text(manga.title)
                        .accessibilityIdentifier("mltResultRow_\(manga.id)")
                }
            }
```

(c) Add the action after the existing `resolve()` method (after line 133, its closing `}`):

```swift
    /// Runs a synthetic MangaDex manga (no malId) through the full More Like This pipeline
    /// — forward-resolve the typed title → MAL id, MAL recommendations, reverse-resolve
    /// each back to MangaDex — so the end-to-end path can be verified against the live APIs.
    private func moreLikeThis() {
        mltResults = []
        isLoading = true
        let manga = Manga(id: "mlt-\(UUID().uuidString)", sourceId: "mangadex",
                          title: mltQuery, description: "", status: "unknown",
                          year: nil, coverURL: nil, malId: nil)
        Task {
            defer { isLoading = false }
            mltResults = await MoreLikeThisProvider().recommendations(for: manga)
        }
    }
```

- [ ] **Step 2: Add the two live UI tests**

Append to `Manga-ReaderUITests/Manga_ReaderUITests.swift` (inside `final class Manga_ReaderUITests`):

```swift
    /// Throwaway live-verification for the More Like This provider via the debug screen:
    /// Settings → "MyAnimeList Client" → type a well-known title → "Find similar" → assert
    /// at least one resolved MangaDex recommendation row appears (proves forward resolution
    /// + MAL recommendations + reverse resolution against the real APIs). Retired with the
    /// debug screen once the real detail-page rail is proven (see the rail test below).
    func testMoreLikeThisDebugProbeLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        // Settings tab (retry — a busy Home can swallow the first tap).
        let settingsNavTitle = app.navigationBars["Settings"]
        var reachedSettings = false
        for _ in 0..<3 {
            app.tabBars.buttons["Settings"].tap()
            if settingsNavTitle.waitForExistence(timeout: 8) { reachedSettings = true; break }
        }
        XCTAssertTrue(reachedSettings, "should have navigated to the Settings tab")

        let malRow = app.buttons["malClientRow"]
        XCTAssertTrue(malRow.waitForExistence(timeout: 10),
                      "the DEBUG 'MyAnimeList Client' row should be on Settings")

        let mltField = app.textFields["mltField"]
        var reachedDebugScreen = false
        for _ in 0..<3 {
            malRow.tap()
            if mltField.waitForExistence(timeout: 8) { reachedDebugScreen = true; break }
        }
        XCTAssertTrue(reachedDebugScreen, "the More Like This probe field should be present")

        // Focus + type (retry — typeText fails if the tap didn't land while busy).
        var focused = false
        for _ in 0..<3 {
            mltField.tap()
            if app.keyboards.element.waitForExistence(timeout: 5) { focused = true; break }
        }
        XCTAssertTrue(focused, "the probe field should have keyboard focus before typing")
        mltField.typeText("Berserk")

        let button = app.buttons["mltButton"]
        XCTAssertTrue(button.exists)
        button.tap()

        // Ground truth: at least one resolved MangaDex recommendation row. Poll generously
        // — this hits MAL search + detail + several MangaDex searches serially/concurrently.
        let firstResult = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'mltResultRow_'")
        ).firstMatch
        var appeared = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if firstResult.exists { appeared = true; break }
            usleep(500_000)
        }
        XCTAssertTrue(appeared, "at least one More Like This recommendation should resolve from the live APIs")
    }

    /// Permanent live-verification of the real detail-page rail: open a popular Home title,
    /// scroll to the bottom, and assert the "More Like This" header plus at least one card
    /// appear — end-to-end against the real MAL + MangaDex APIs.
    func testMoreLikeThisDetailRailLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        // Home: wait for the first cover card, then open it (retry once — a LazyVStack
        // re-layout while covers stream in can swallow the first tap).
        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        // The rail loads async (MAL + MangaDex round-trips) and sits at the very bottom.
        // Poll: swipe up, check for the header, repeat until it appears or we give up.
        let header = app.staticTexts["More Like This"]
        var railAppeared = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if header.exists { railAppeared = true; break }
            app.swipeUp(velocity: .fast)
            usleep(700_000)
        }
        XCTAssertTrue(railAppeared,
                      "the 'More Like This' header should appear at the bottom of the detail page")

        // And at least one recommendation card under it.
        let section = app.otherElements["moreLikeThisSection"]
        let card = section.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "at least one More Like This card should render")
    }
```

- [ ] **Step 3: Run the live UI tests**

Run:
```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test \
  -only-testing:Manga-ReaderUITests/Manga_ReaderUITests/testMoreLikeThisDebugProbeLiveVerification \
  -only-testing:Manga-ReaderUITests/Manga_ReaderUITests/testMoreLikeThisDetailRailLiveVerification
```
Expected: PASS — both, against the live APIs. Notes:
- These are network-dependent and slow; MAL soft-rate-limits (HTTP 429 with `Retry-After`), which the app retries once. If a run flakes on rate-limiting, re-run after a pause — a flake here is an API-availability issue, not a logic failure.
- The detail-rail test depends on the first Home title actually having MAL recommendations that reverse-resolve. Popular MangaDex titles reliably do; if the very first card happens to resolve to nothing, the header is legitimately absent — open a known-popular title instead (the debug-probe test with "Berserk" is the deterministic backstop).

- [ ] **Step 4: Commit**

```sh
git add Manga-Reader/Views/MyAnimeListDebugView.swift Manga-ReaderUITests/Manga_ReaderUITests.swift
git commit -m "Add More Like This debug probe + live UI verification (probe + detail rail)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (before finishing the branch)

- [ ] **Run the full unit-test suite** (all pure tests must pass together, proving no regressions in the matcher/store refactors):

```sh
xcodebuild -scheme Manga-Reader \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  test -only-testing:Manga-ReaderTests
```
Expected: PASS — the full unit suite (144 pre-existing + the new pure tests).

- [ ] **Finish the branch** via `superpowers:finishing-a-development-branch` (merge to `main`, then push — subsystem 2 was merged AND pushed to origin, so match that).

---

## Notes for the executor

- **Branch:** do this work on a feature branch off `main` (e.g. `feature/more-like-this`), not on `main` directly.
- **Cleanup owed (deferred, NOT this branch):** the throwaway `MyAnimeListDebugView` + its live UI tests (`testMyAnimeListDebugScreenLiveVerification`, `testMALEntityResolutionLiveVerification`, and the new `testMoreLikeThisDebugProbeLiveVerification`) are verification stepping-stones. Per the spec's YAGNI list, retiring the debug screen is a later cleanup once the real rail is proven — leave them in place at the end of this branch. The permanent feature is the detail-page rail + its `testMoreLikeThisDetailRailLiveVerification`.
- **Why the provider may call `MangaDexAPI` directly:** the "nothing outside source adapters calls `MangaDexAPI`" convention is about browse/detail data flow through `MangaSource`. Cross-source resolution is inherently MangaDex-specific plumbing (subsystem 2's `MALEntityResolver` already searches MAL directly); the provider follows that precedent, not the source-abstraction path.
```
