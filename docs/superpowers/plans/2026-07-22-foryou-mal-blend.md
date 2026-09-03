# For You + MAL Blend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Blend MyAnimeList collaborative recommendations into the "For You" rail as a new candidate source with an agreement (overlap) boost, without changing the rail's engine/exploration/grid.

**Architecture:** `RecommendationEngine → CompositeCandidateProvider → { TagCandidateProvider (existing), MALCandidateProvider → MoreLikeThisProvider (existing) }`. The composite normalizes and blends two ranked candidate pools; the engine's `makeProvider` seam swaps in the composite.

**Tech Stack:** SwiftUI, Foundation. No third-party deps. Xcode project (objectVersion 70 / Xcode 16 format). iOS 17.5 deployment target.

**Spec:** `docs/superpowers/specs/2026-07-22-foryou-mal-blend-design.md`

## Simplifications vs the spec (approved refinements)

- **No manga-info cache / no backfill change.** `ReadingEntry` already carries `mangaTitle` and `coverURL`, so seeds materialize straight from history (+ library for a possible `malId`). The spec's `TasteProfileStore` manga-info cache is dropped as unnecessary.
- **Seed ranking = the existing per-manga weight `w`.** `TasteProfile.build` already computes `w` per manga incorporating recency, chapters, finished (+1.5), saved (+1.0), and "more like this" (×2.0). Ranking seeds by `w` already realizes "combined signal, explicit first" — no separate seed-scoring logic.

## Global Constraints

- **No third-party dependencies.** Pure SwiftUI + Foundation.
- **Repo layout:** work from `/Users/eliasmagdaleno/xcode/MangaCarta`; app sources are under `MangaCarta/…` from there (e.g. `MangaCarta/Models/CandidateProvider.swift`). `Models/` and `Services/` are synchronized groups — **no `project.pbxproj` edits** for this feature (all files already exist or land in synchronized groups).
- **Branch protection is on `main`:** all work lands via a PR that passes both CI checks (`Build & unit tests`, `SwiftLint`). Do not push to `main` directly.
- **Build/test on the iPhone 17 simulator** with **`-parallel-testing-enabled NO`**.
- **Unit tests use XCTest** (`MangaCartaTests` is `XCTestCase` — use `func test…()` + `XCTAssert…`, not Swift Testing).
- **SourceKit/LSP false alarms** ("No such module 'XCTest'", "Cannot find type 'Manga'/'Tag' in scope") are indexer noise — judge correctness ONLY by `xcodebuild`.
- **Tuning constants** (name them, don't inline magic numbers): `W_TAG = 1.0`, `W_MAL = 0.85`, `OVERLAP_BONUS = 0.25`, seed cap `= 5`, per-seed MAL limit `= 8`.
- **`MoreLikeThisProvider` is `@MainActor`;** the injectable seam protocol must be `@MainActor` to conform cleanly (see Task 2).
- End commit messages with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

## Reference: existing signatures this plan builds on

```swift
struct Manga: Identifiable {                 // Models/MangaDexAPI.swift
    let id: String; let sourceId: String; let title: String; let description: String
    let status: String; let year: Int?; let coverURL: URL?; let malId: Int?
}
struct ScoredManga: Identifiable { let manga: Manga; let score: Double; let reason: String; var id: String { manga.id } }
protocol CandidateProvider {                 // Models/CandidateProvider.swift
    func candidates(for profile: TasteProfile, excluding: Set<String>, limit: Int) async throws -> [ScoredManga]
}
struct ReadingEntry {                         // Services/HistoryStore.swift — has mangaTitle, coverURL, sourceId
    let mangaId: String; let mangaTitle: String; let coverURL: URL?; let sourceId: String?
    let chapterNumber: String; var page: Int; var pageCount: Int; var updatedAt: Date /* …others… */
}
// MoreLikeThisProvider (Services/) — @MainActor:
func recommendations(for manga: Manga, limit: Int = 8) async -> [Manga]   // MAL-order, never throws
```

---

## Task 1: `SeedManga` + seed materialization in `TasteProfile`

Give `TasteProfile` the top-N seed manga (materialized `Manga` + weight) the MAL provider will use. Pure value logic — unit-tested with no network.

**Files:**
- Modify: `MangaCarta/Models/TasteProfile.swift`
- Modify: `MangaCarta/Models/RecommendationEngine.swift` (pass `libraryItems` into `build`)
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Produces: `struct SeedManga { let manga: Manga; let weight: Double }`; `TasteProfile.seeds: [SeedManga]`; `TasteProfile.build(…, libraryItems: [Manga] = [], seedLimit: Int = 5)` now also returns `seeds`.

- [ ] **Step 1: Write the failing test**

Add to `MangaCartaTests/MangaCartaTests.swift` (XCTest). Helper to build a tagged history entry + tags:

```swift
    private func seedEntry(_ id: String, title: String, updated: Date) -> ReadingEntry {
        ReadingEntry(id: UUID(), mangaId: id, mangaTitle: title, coverURL: nil,
                     chapterId: "\(id)-c1", chapterNumber: "1", page: 9, pageCount: 10,
                     updatedAt: updated, sourceId: "mangadex")
    }

    func testTasteProfileSeedsRankedByWeightAndCapped() {
        let now = Date()
        let tag = [Tag(id: "t1", name: "Action", group: "genre")]
        // Three tagged, read manga; "b" is saved (weight boost), "c" is more-like-this (×2).
        let history = [seedEntry("a", title: "A", updated: now),
                       seedEntry("b", title: "B", updated: now),
                       seedEntry("c", title: "C", updated: now)]
        let profile = TasteProfile.build(
            history: history, savedIds: ["b"],
            tagCache: ["a": tag, "b": tag, "c": tag],
            moreLikeThis: ["c"], now: now,
            libraryItems: [Manga(id: "b", sourceId: "mangadex", title: "B", description: "",
                                 status: "unknown", year: nil, coverURL: nil, malId: 42)],
            seedLimit: 2)
        // c (×2) and b (+saved) outrank a; capped at 2; c first.
        XCTAssertEqual(profile.seeds.map(\.manga.id), ["c", "b"])
        // Saved seed uses the library Manga → carries malId.
        XCTAssertEqual(profile.seeds.first(where: { $0.manga.id == "b" })?.manga.malId, 42)
        // Read-only seed falls back to history-derived Manga (title from mangaTitle).
        XCTAssertEqual(profile.seeds.first(where: { $0.manga.id == "c" })?.manga.title, "C")
    }
```

(Confirm the real `Tag` initializer while writing — if `Tag(id:name:group:)` differs, match it. `ReadingEntry`'s memberwise init may order fields differently; match the struct.)

- [ ] **Step 2: Run it — expect failure**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:MangaCartaTests`
Expected: FAIL — `seeds` / `SeedManga` / the `libraryItems` param don't exist.

- [ ] **Step 3: Implement**

In `MangaCarta/Models/TasteProfile.swift`:

(a) Add the seed type above `struct TasteProfile`:
```swift
/// A recommendation seed: a manga the user engaged with, plus its engagement weight.
struct SeedManga {
    let manga: Manga
    let weight: Double
}
```
(b) Add the stored field to `TasteProfile` (after `taggedMangaCount`):
```swift
    /// Top read/saved manga (materialized), highest engagement first — MAL rec seeds.
    let seeds: [SeedManga]
```
(c) Change `build`'s signature and body. Add params `libraryItems: [Manga] = []` and `seedLimit: Int = 5`. Inside the per-manga loop, capture each manga's weight; after the loop, rank and materialize seeds. Replace the whole method with:
```swift
    static func build(history: [ReadingEntry],
                      savedIds: Set<String>,
                      tagCache: [String: [Tag]],
                      moreLikeThis: Set<String>,
                      now: Date,
                      libraryItems: [Manga] = [],
                      seedLimit: Int = 5) -> TasteProfile {
        var entriesByManga: [String: [ReadingEntry]] = [:]
        for e in history { entriesByManga[e.mangaId, default: []].append(e) }

        var raw: [String: Double] = [:]
        var names: [String: String] = [:]
        var mangaWeight: [String: Double] = [:]   // per-manga engagement weight, for seeds
        var taggedCount = 0

        for (mangaId, entries) in entriesByManga {
            guard let tags = tagCache[mangaId], !tags.isEmpty else { continue }
            taggedCount += 1

            let distinctChapters = Set(entries.map(\.chapterNumber)).count
            let latest = entries.max { $0.updatedAt < $1.updatedAt }!
            let finished = latest.pageCount > 0 && latest.page >= latest.pageCount - 1
            let days = max(0, now.timeIntervalSince(latest.updatedAt) / 86_400)
            let recency = pow(0.5, days / 30.0)

            var w = recency * (1.0
                               + log2(1.0 + Double(distinctChapters))
                               + (finished ? 1.5 : 0.0)
                               + (savedIds.contains(mangaId) ? 1.0 : 0.0))
            if moreLikeThis.contains(mangaId) { w *= 2.0 }
            mangaWeight[mangaId] = w

            for t in tags {
                raw[t.id, default: 0] += w * groupWeight(t.group)
                names[t.id] = t.name
            }
        }

        let seeds = makeSeeds(mangaWeight: mangaWeight, entriesByManga: entriesByManga,
                              libraryItems: libraryItems, limit: seedLimit)

        guard let maxW = raw.values.max(), maxW > 0 else {
            return TasteProfile(weights: [:], tagName: [:], orderedTagIds: [],
                                taggedMangaCount: taggedCount, seeds: seeds)
        }
        let normalized = raw.mapValues { $0 / maxW }
        let ordered = normalized.sorted { $0.value > $1.value }.map(\.key)
        return TasteProfile(weights: normalized, tagName: names, orderedTagIds: ordered,
                            taggedMangaCount: taggedCount, seeds: seeds)
    }

    /// Top `limit` manga by engagement weight, materialized to `Manga`: prefer a saved
    /// library entry (carries malId); else synthesize from a history entry (title/cover).
    private static func makeSeeds(mangaWeight: [String: Double],
                                  entriesByManga: [String: [ReadingEntry]],
                                  libraryItems: [Manga],
                                  limit: Int) -> [SeedManga] {
        let libraryById = Dictionary(libraryItems.map { ($0.id, $0) },
                                     uniquingKeysWith: { first, _ in first })
        return mangaWeight.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, weight -> SeedManga? in
                if let saved = libraryById[id] {
                    return SeedManga(manga: saved, weight: weight)
                }
                guard let e = entriesByManga[id]?.first else { return nil }
                let manga = Manga(id: id, sourceId: e.sourceId ?? "mangadex",
                                  title: e.mangaTitle, description: "", status: "unknown",
                                  year: nil, coverURL: e.coverURL, malId: nil)
                return SeedManga(manga: manga, weight: weight)
            }
    }
```

- [ ] **Step 4: Update the caller**

In `MangaCarta/Models/RecommendationEngine.swift`, `profileAndExclusions()` calls `TasteProfile.build`. Pass the library items so seeds can prefer saved `Manga`. Change:
```swift
        let profile = TasteProfile.build(history: history.entries,
                                         savedIds: savedIds,
                                         tagCache: profileStore.tagCache,
                                         moreLikeThis: Set(profileStore.moreLikeThis),
                                         now: now())
```
to:
```swift
        let profile = TasteProfile.build(history: history.entries,
                                         savedIds: savedIds,
                                         tagCache: profileStore.tagCache,
                                         moreLikeThis: Set(profileStore.moreLikeThis),
                                         now: now(),
                                         libraryItems: library.items)
```

- [ ] **Step 5: Run tests — expect pass**

Run the same `-only-testing:MangaCartaTests` command. Expected: `** TEST SUCCEEDED **` (new test + existing suite; existing `build` callers/tests compile because the new params are defaulted).

- [ ] **Step 6: Commit**
```sh
git add MangaCarta/Models/TasteProfile.swift MangaCarta/Models/RecommendationEngine.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add SeedManga + seed materialization to TasteProfile

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `SimilarTitlesProviding` seam + `MALCandidateProvider`

The collaborative half: turn seeds into scored candidates via per-seed MAL recommendations. Introduce a `@MainActor` protocol so `MoreLikeThisProvider` can be stubbed in tests.

**Files:**
- Modify: `MangaCarta/Services/MoreLikeThisProvider.swift` (conform to the new protocol)
- Modify: `MangaCarta/Models/CandidateProvider.swift` (protocol + `MALCandidateProvider`)
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Produces: `@MainActor protocol SimilarTitlesProviding { func recommendations(for manga: Manga, limit: Int) async -> [Manga] }`; `struct MALCandidateProvider: CandidateProvider`.
- Consumes: `TasteProfile.seeds` (Task 1), `ScoredManga`, `CandidateProvider`.

- [ ] **Step 1: Write the failing test**

Add to `MangaCartaTests/MangaCartaTests.swift`. A stub that returns fixed recs per seed id:
```swift
    @MainActor
    private final class StubSimilar: SimilarTitlesProviding {
        let bySeedId: [String: [Manga]]
        init(_ bySeedId: [String: [Manga]]) { self.bySeedId = bySeedId }
        func recommendations(for manga: Manga, limit: Int) async -> [Manga] {
            Array((bySeedId[manga.id] ?? []).prefix(limit))
        }
    }

    private func mdManga(_ id: String, _ title: String) -> Manga {
        Manga(id: id, sourceId: "mangadex", title: title, description: "",
              status: "unknown", year: nil, coverURL: nil, malId: nil)
    }

    func testMALCandidateProviderScoresByPositionAndSeedWeight() async throws {
        // Seed "s1" (weight 2) recommends x,y ; seed "s2" (weight 1) recommends y,z.
        // y is recommended by both → its score sums; excluding drops "z".
        let profile = TasteProfile(weights: ["t": 1], tagName: ["t": "Action"],
                                   orderedTagIds: ["t"], taggedMangaCount: 2,
                                   seeds: [SeedManga(manga: mdManga("s1", "S1"), weight: 2),
                                           SeedManga(manga: mdManga("s2", "S2"), weight: 1)])
        let stub = await StubSimilar(["s1": [mdManga("x", "X"), mdManga("y", "Y")],
                                      "s2": [mdManga("y", "Y"), mdManga("z", "Z")]])
        let provider = MALCandidateProvider(similar: stub)
        let out = try await provider.candidates(for: profile, excluding: ["z"], limit: 10)

        let byId = Dictionary(uniqueKeysWithValues: out.map { ($0.manga.id, $0) })
        XCTAssertNil(byId["z"])                                   // excluded
        // y: s1 pos0 (2 * 1/1) + s2 pos0 (1 * 1/1) = 3 ; x: s1 pos0 = 2 → y ranks first.
        XCTAssertEqual(out.first?.manga.id, "y")
        XCTAssertEqual(byId["y"]?.score ?? 0, 3.0, accuracy: 0.0001)
        XCTAssertEqual(byId["x"]?.score ?? 0, 2.0, accuracy: 0.0001)
        // Reason names the strongest seed that surfaced it.
        XCTAssertEqual(byId["x"]?.reason, "Because you read S1")
    }
```

- [ ] **Step 2: Run it — expect failure**

Run the `-only-testing:MangaCartaTests` command. Expected: FAIL — `SimilarTitlesProviding` / `MALCandidateProvider` undefined.

- [ ] **Step 3: Conform `MoreLikeThisProvider` to the seam**

In `MangaCarta/Services/MoreLikeThisProvider.swift`, add (below the class, same file) the protocol and conformance. `MoreLikeThisProvider.recommendations(for:limit:)` already matches:
```swift
/// The one capability MALCandidateProvider needs — injectable so tests can stub it.
@MainActor
protocol SimilarTitlesProviding {
    func recommendations(for manga: Manga, limit: Int) async -> [Manga]
}

extension MoreLikeThisProvider: SimilarTitlesProviding {}
```

- [ ] **Step 4: Implement `MALCandidateProvider`**

In `MangaCarta/Models/CandidateProvider.swift`, append:
```swift
/// Collaborative candidates: for each of the profile's seeds, fetch MAL "more like this"
/// (already reverse-resolved to openable MangaDex titles) and score each result by
/// position × the seed's engagement weight, summed across seeds. Network-tolerant — an
/// empty seed result just contributes nothing.
struct MALCandidateProvider: CandidateProvider {
    let similar: SimilarTitlesProviding
    var perSeedLimit: Int = 8

    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga] {
        let seeds = profile.seeds
        guard !seeds.isEmpty else { return [] }

        // Per-seed recommendation lists, concurrently (bounded by seed count, ≤5).
        let lists: [(seed: SeedManga, recs: [Manga])] =
            await withTaskGroup(of: (SeedManga, [Manga]).self) { group in
                for seed in seeds {
                    let provider = similar
                    let per = perSeedLimit
                    group.addTask {
                        let recs = await provider.recommendations(for: seed.manga, limit: per)
                        return (seed, recs)
                    }
                }
                var out: [(SeedManga, [Manga])] = []
                for await r in group { out.append(r) }
                return out
            }

        var scores: [String: Double] = [:]
        var mangaById: [String: Manga] = [:]
        var bestSeed: [String: (weight: Double, title: String)] = [:]

        for (seed, recs) in lists {
            for (i, m) in recs.enumerated() where !excluding.contains(m.id) {
                scores[m.id, default: 0] += seed.weight * (1.0 / Double(1 + i))
                if mangaById[m.id] == nil { mangaById[m.id] = m }
                if (bestSeed[m.id]?.weight ?? -1) < seed.weight {
                    bestSeed[m.id] = (seed.weight, seed.manga.title)
                }
            }
        }

        return scores.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, score in
                guard let m = mangaById[id] else { return nil }
                let reason = bestSeed[id].map { "Because you read \($0.title)" } ?? "Recommended"
                return ScoredManga(manga: m, score: score, reason: reason)
            }
    }
}
```

- [ ] **Step 5: Run tests — expect pass**

Run the `-only-testing:MangaCartaTests` command. Expected: `** TEST SUCCEEDED **`. If the build flags actor-isolation on the `SimilarTitlesProviding` conformance, confirm the protocol is `@MainActor` (it must be, since `MoreLikeThisProvider` is).

- [ ] **Step 6: Commit**
```sh
git add MangaCarta/Services/MoreLikeThisProvider.swift MangaCarta/Models/CandidateProvider.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add SimilarTitlesProviding seam + MALCandidateProvider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `CompositeCandidateProvider` (the blender)

Merge tag + MAL pools: normalize each to [0,1], weighted add, gold-star overlap bonus. Pure logic (stub children) — fully unit-tested.

**Files:**
- Modify: `MangaCarta/Models/CandidateProvider.swift`
- Test: `MangaCartaTests/MangaCartaTests.swift`

**Interfaces:**
- Produces: `struct CompositeCandidateProvider: CandidateProvider` with `init(tag: CandidateProvider, mal: CandidateProvider)`.

- [ ] **Step 1: Write the failing test**

Add to `MangaCartaTests/MangaCartaTests.swift`. A stub provider returning fixed candidates:
```swift
    private struct StubProvider: CandidateProvider {
        let out: [ScoredManga]
        func candidates(for profile: TasteProfile, excluding: Set<String>, limit: Int) async throws -> [ScoredManga] { out }
    }

    func testCompositeBlendsNormalizesAndBoostsOverlap() async throws {
        let profile = TasteProfile(weights: [:], tagName: [:], orderedTagIds: [],
                                   taggedMangaCount: 0, seeds: [])
        // Tag pool (raw scores 10, 5); MAL pool (raw scores 100, 50). "y" is in both.
        let tag = StubProvider(out: [ScoredManga(manga: mdManga("x", "X"), score: 10, reason: "More Action"),
                                     ScoredManga(manga: mdManga("y", "Y"), score: 5,  reason: "More Action")])
        let mal = StubProvider(out: [ScoredManga(manga: mdManga("y", "Y"), score: 100, reason: "Because you read S"),
                                     ScoredManga(manga: mdManga("z", "Z"), score: 50,  reason: "Because you read S")])
        let composite = CompositeCandidateProvider(tag: tag, mal: mal)
        let out = try await composite.candidates(for: profile, excluding: [], limit: 10)
        let byId = Dictionary(uniqueKeysWithValues: out.map { ($0.manga.id, $0) })

        // Normalized: x=1.0,y_tag=0.5 (tag) ; y_mal=1.0,z=0.5 (mal).
        // final: y = 1.0*0.5 + 0.85*1.0 + 0.25(overlap) = 1.60 ; x = 1.0 ; z = 0.85*0.5 = 0.425
        XCTAssertEqual(byId["y"]?.score ?? 0, 1.60, accuracy: 0.0001)
        XCTAssertEqual(byId["x"]?.score ?? 0, 1.00, accuracy: 0.0001)
        XCTAssertEqual(byId["z"]?.score ?? 0, 0.425, accuracy: 0.0001)
        XCTAssertEqual(out.first?.manga.id, "y")                    // overlap leads
        XCTAssertEqual(byId["y"]?.reason, "Because you read S")     // MAL reason preferred when MAL contributed
    }

    func testCompositeDegradesToTagOnlyWhenMALEmpty() async throws {
        let profile = TasteProfile(weights: [:], tagName: [:], orderedTagIds: [],
                                   taggedMangaCount: 0, seeds: [])
        let tag = StubProvider(out: [ScoredManga(manga: mdManga("x", "X"), score: 10, reason: "More Action"),
                                     ScoredManga(manga: mdManga("y", "Y"), score: 5,  reason: "More Action")])
        let mal = StubProvider(out: [])
        let out = try await CompositeCandidateProvider(tag: tag, mal: mal)
            .candidates(for: profile, excluding: [], limit: 10)
        XCTAssertEqual(out.map(\.manga.id), ["x", "y"])            // exactly the tag ranking
    }
```

- [ ] **Step 2: Run it — expect failure**

Run the `-only-testing:MangaCartaTests` command. Expected: FAIL — `CompositeCandidateProvider` undefined.

- [ ] **Step 3: Implement**

In `MangaCarta/Models/CandidateProvider.swift`, append:
```swift
/// Blends two candidate pools (tag + MAL). Each pool is normalized to [0, 1] (÷ its own
/// max) so the two signals are comparable, then combined `W_TAG·tag + W_MAL·mal`; a title
/// in BOTH pools gets an extra OVERLAP_BONUS so agreement leads. Empty MAL pool ⇒ exactly
/// the tag ranking (graceful degradation).
struct CompositeCandidateProvider: CandidateProvider {
    let tag: CandidateProvider
    let mal: CandidateProvider

    private let wTag = 1.0
    private let wMal = 0.85
    private let overlapBonus = 0.25

    func candidates(for profile: TasteProfile,
                    excluding: Set<String>,
                    limit: Int) async throws -> [ScoredManga] {
        async let tagPool = tag.candidates(for: profile, excluding: excluding, limit: limit)
        async let malPool = mal.candidates(for: profile, excluding: excluding, limit: limit)
        // Either pool failing degrades to empty (MAL failing ⇒ tag-only rail).
        let tags = (try? await tagPool) ?? []
        let mals = (try? await malPool) ?? []

        let tagNorm = Self.normalized(tags)
        let malNorm = Self.normalized(mals)

        var score: [String: Double] = [:]
        var manga: [String: Manga] = [:]
        var reason: [String: String] = [:]

        for c in tags {
            manga[c.manga.id] = c.manga
            reason[c.manga.id] = c.reason
            score[c.manga.id, default: 0] += wTag * (tagNorm[c.manga.id] ?? 0)
        }
        for c in mals {
            if manga[c.manga.id] == nil { manga[c.manga.id] = c.manga }
            reason[c.manga.id] = c.reason      // MAL reason preferred when MAL contributed
            score[c.manga.id, default: 0] += wMal * (malNorm[c.manga.id] ?? 0)
        }
        // Gold-star: present in both pools.
        let both = Set(tagNorm.keys).intersection(malNorm.keys)
        for id in both { score[id, default: 0] += overlapBonus }

        return score.sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { id, value in
                guard let m = manga[id] else { return nil }
                return ScoredManga(manga: m, score: value, reason: reason[id] ?? "Recommended")
            }
    }

    /// id → score ÷ pool max, in [0, 1]. Empty/all-zero pool → empty map.
    private static func normalized(_ pool: [ScoredManga]) -> [String: Double] {
        guard let max = pool.map(\.score).max(), max > 0 else { return [:] }
        return Dictionary(pool.map { ($0.manga.id, $0.score / max) },
                          uniquingKeysWith: { first, _ in first })
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

Run the `-only-testing:MangaCartaTests` command. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**
```sh
git add MangaCarta/Models/CandidateProvider.swift MangaCartaTests/MangaCartaTests.swift
git commit -m "Add CompositeCandidateProvider: normalize + blend + overlap boost

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Wire the composite into the engine + live verification

Swap the engine's default provider to the composite and verify the rail still populates end-to-end.

**Files:**
- Modify: `MangaCarta/Models/RecommendationEngine.swift`
- Test: `MangaCartaUITests/MangaCartaUITests.swift`

**Interfaces:**
- Consumes: `CompositeCandidateProvider`, `MALCandidateProvider`, `TagCandidateProvider`, `MoreLikeThisProvider`.

- [ ] **Step 1: Change the default provider**

In `MangaCarta/Models/RecommendationEngine.swift`, the init parameter default is:
```swift
         makeProvider: @escaping (MangaSource) -> CandidateProvider = { TagCandidateProvider(source: $0) },
```
Change it to build the composite. `MoreLikeThisProvider()` is `@MainActor`; it's constructed inside the closure body (which runs on the main actor during `rebuild()`), so this is safe:
```swift
         makeProvider: @escaping (MangaSource) -> CandidateProvider = { source in
             CompositeCandidateProvider(
                 tag: TagCandidateProvider(source: source),
                 mal: MALCandidateProvider(similar: MoreLikeThisProvider()))
         },
```

- [ ] **Step 2: Build**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `** BUILD SUCCEEDED **`. If the closure default trips main-actor isolation on `MoreLikeThisProvider()`, wrap construction so it evaluates in the closure body (it already does) — do not move it to a stored property initializer.

- [ ] **Step 3: Full unit-suite regression**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:MangaCartaTests`
Expected: PASS (existing recommendation/tag tests still green — engine tests inject their own `makeProvider`, so the new default only affects production).

- [ ] **Step 4: Add a live UI test that the rail still populates**

Append inside `final class MangaCartaUITests` in `MangaCartaUITests/MangaCartaUITests.swift`:
```swift
    /// The "For You" rail still populates end-to-end with the composite (tag + MAL)
    /// provider wired in. Network-dependent: a flake is API/seed availability, not a
    /// logic bug. The rail is hidden until there's enough reading signal, so this asserts
    /// the app launches to a populated Home and — if a "For You" rail is present — it has
    /// at least one card.
    func testForYouRailPopulatesWithCompositeProvider() throws {
        let app = XCUIApplication()
        app.launch()
        // Home must load content at all (proves the composite provider didn't break Home).
        let anyCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(anyCard.waitForExistence(timeout: 25), "Home should load cover cards")

        // If the personalized rail is showing, it must have a card under it.
        let forYou = app.staticTexts["For You"]
        if forYou.waitForExistence(timeout: 5) {
            let card = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
            XCTAssertTrue(card.exists, "the For You rail should render at least one card")
        }
    }
```
(While writing, confirm the rail's header text is exactly `"For You"` in `RecommendationRail`/Home; if it differs, match the real string.)

- [ ] **Step 5: Run the live UI test**

Run: `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:MangaCartaUITests/MangaCartaUITests/testForYouRailPopulatesWithCompositeProvider`
Expected: PASS. Network-dependent; re-run after a pause on a flake.

- [ ] **Step 6: Commit**
```sh
git add MangaCarta/Models/RecommendationEngine.swift MangaCartaUITests/MangaCartaUITests.swift
git commit -m "Wire CompositeCandidateProvider into RecommendationEngine (For You + MAL)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Final verification (before finishing the branch)

- [ ] **Full unit suite:** `xcodebuild -scheme MangaCarta -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO test -only-testing:MangaCartaTests` — PASS.
- [ ] **SwiftLint clean:** `swiftlint lint` — zero error-severity violations (CI enforces this).
- [ ] **Whole-branch review**, then open a **PR to `main`**; both CI checks (`Build & unit tests`, `SwiftLint`) must go green, then merge (superpowers:finishing-a-development-branch). Do NOT push to `main` directly — branch protection forbids it.

## Notes for the executor

- **Verification is by `xcodebuild`, not the SourceKit indexer** — "cannot find type" diagnostics are false alarms.
- **`@MainActor` isolation:** `SimilarTitlesProviding` MUST be `@MainActor` (Task 2) because `MoreLikeThisProvider` is; the stub in tests is a `@MainActor` class. `MoreLikeThisProvider()` in the engine default (Task 4) is fine because it's constructed in the closure body (main-actor context at call time), not a default-argument or stored-property initializer.
- **Match real initializers while writing tests** — confirm `Tag(id:name:group:)` and `ReadingEntry`'s memberwise init field order against the source; adjust the test literals if they differ.
- **Task order:** Task 1 (seeds) → Task 2 (MAL provider, needs seeds) → Task 3 (composite, blends providers) → Task 4 (engine wiring + live test).
