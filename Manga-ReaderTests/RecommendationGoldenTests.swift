//
//  RecommendationGoldenTests.swift
//  Manga-ReaderTests
//
//  A golden-file harness for the "For You" blend.
//
//  WHY THIS EXISTS
//  The blend has tuning constants (wTag, wMal, overlapBonus in CompositeCandidateProvider;
//  seed cap; perSeedLimit) that were chosen a priori and have never been validated. There is
//  no labeled relevance data for this app — one user, no ground truth — so we cannot *prove*
//  a ranking change is an improvement. What we can do is make every ranking change show up as
//  a readable diff in a pull request. That is what this file buys: change a constant or swap
//  the agreement formula, re-run, and the golden diff shows exactly which titles moved, by how
//  much, and why.
//
//  WHAT IS GOLDENED
//  `CompositeCandidateProvider.candidates(...)` — the deterministic ranked pool.
//  Deliberately NOT `RecommendationEngine.compose()`, which mixes in a seeded exploration
//  reshuffle (`SeededRNG`) that is designed to differ between sessions and can never be
//  goldened.
//
//  WHY THE FIXTURE IS SYNTHETIC
//  Hand-written titles with hand-chosen feed positions, so every number in the golden file is
//  derivable with a calculator. This proves the *mechanics* of the blend, not the *quality* of
//  real recommendations — a recorded-from-real-API fixture would be a separate, larger case,
//  and would bake personal reading history into a public repo.
//
//  FIXTURE INVARIANT — NO TIED SCORES
//  `TagCandidateProvider` and `MALCandidateProvider` both finish with
//  `scores.sorted { $0.value > $1.value }.prefix(limit)` and no secondary tie-break. Swift's
//  sort is not guaranteed stable, so exactly-tied scores could reorder run to run, and a tie
//  straddling `limit` could change pool membership. (`CompositeCandidateProvider` does have an
//  explicit id tie-break; the two sub-providers do not.) The tag weights and seed weights below
//  are therefore chosen so that no two candidates ever tie. If you edit the fixture, preserve
//  that property or the golden will flake.
//
//  REGENERATING
//      TEST_RUNNER_REGENERATE_GOLDENS=1 xcodebuild -scheme Manga-Reader \
//        -destination 'platform=iOS Simulator,name=iPhone 17' -parallel-testing-enabled NO \
//        test -only-testing:Manga-ReaderTests/RecommendationGoldenTests
//
//  The `TEST_RUNNER_` prefix is required and is not decoration: tests run in a separate process
//  inside the simulator, and xcodebuild forwards only variables carrying that prefix, stripping
//  it before handing them to the runner. A bare `REGENERATE_GOLDENS=1` is silently ignored.
//
//  Read the diff before committing it. A golden regenerated without being read is worth nothing.
//

import XCTest
@testable import Manga_Reader

final class RecommendationGoldenTests: XCTestCase {

    // MARK: - Synthetic fixture

    // The fixture literals are column-aligned so they can be read as the tables they represent;
    // that is the whole point of a hand-traceable fixture. Alignment padding trips `colon` and
    // `comma`, so those two rules are off for this block only.
    // swiftlint:disable colon comma

    /// Tag feeds keyed by tag *name* (what `TagCandidateProvider` queries with), in rank order.
    /// Position matters: provenance scoring weights by `1 / (1 + position)`.
    private static let tagFeeds: [String: [String]] = [
        "Action":  ["A", "B", "C", "D", "Z"],
        "Romance": ["C", "E", "F"],
        "Isekai":  ["B", "G"],
    ]

    /// Per-seed MAL recommendation lists, in rank order.
    private static let malRecs: [String: [String]] = [
        "seed-berserk": ["C", "H", "A"],
        "seed-vinland": ["I", "C"],
    ]

    /// Display titles, so the golden reads like a rail and not like a hash dump.
    private static let titles: [String: String] = [
        "A": "Alpha Blade",       "B": "Blue Sentinel",   "C": "Crimson Vow",
        "D": "Dawnbreaker",       "E": "Everlight",       "F": "Fallow Season",
        "G": "Gilded Cage",       "H": "Hollow Court",    "I": "Ivory Requiem",
        "Z": "Zenith (excluded)",
    ]

    // swiftlint:enable colon comma

    /// Titles the user has already read/saved/dismissed — must never appear in the output.
    private static let excluded: Set<String> = ["Z"]

    /// Built directly rather than via `TasteProfile.build` so every weight in the golden is a
    /// stated input rather than a derived one. Profile *construction* (recency half-life,
    /// engagement weighting, seed materialization) is covered by its own unit tests; this
    /// harness isolates the *ranking*.
    private static func makeProfile() -> TasteProfile {
        let weights = ["t-action": 1.0, "t-romance": 0.7, "t-isekai": 0.4]
        let names = ["t-action": "Action", "t-romance": "Romance", "t-isekai": "Isekai"]
        return TasteProfile(
            weights: weights,
            tagName: names,
            orderedTagIds: weights.sorted { $0.value > $1.value }.map(\.key),
            taggedMangaCount: 6,
            seeds: [
                SeedManga(manga: manga("seed-berserk", title: "Berserk"), weight: 3.0),
                SeedManga(manga: manga("seed-vinland", title: "Vinland Saga"), weight: 1.2),
            ]
        )
    }

    private static func manga(_ id: String, title: String? = nil) -> Manga {
        Manga(id: id, sourceId: "mangadex", title: title ?? titles[id] ?? id,
              description: "", status: "ongoing", year: nil, coverURL: nil, malId: nil)
    }

    /// Serves the canned tag feeds. Only `mangaByTag` is exercised.
    private struct FixtureSource: MangaSource {
        let id = "fixture"
        let name = "Fixture"
        var supportsTagBrowse: Bool { true }

        func mangaByTag(tag: String, limit: Int, offset: Int) async throws -> [Manga] {
            (RecommendationGoldenTests.tagFeeds[tag] ?? []).prefix(limit).map { manga($0) }
        }
        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    /// Serves the canned MAL recommendation lists, keyed by seed id.
    private struct FixtureSimilar: SimilarTitlesProviding {
        func recommendations(for manga: Manga, limit: Int) async -> [Manga] {
            (RecommendationGoldenTests.malRecs[manga.id] ?? [])
                .prefix(limit)
                .map { RecommendationGoldenTests.manga($0) }
        }
    }

    // MARK: - The golden test

    // `SimilarTitlesProviding` is @MainActor, so anything that constructs `FixtureSimilar` must
    // be too. Isolation is applied per-member rather than to the whole class on purpose: the
    // static fixtures must stay nonisolated so `FixtureSource` (a plain, nonisolated
    // `MangaSource`) can read them from its async methods.
    @MainActor
    func testForYouBlendRankingGolden() async throws {
        let rendered = try await renderRanking()
        try assertMatchesGolden(rendered, named: "foryou-ranking.txt")
    }

    /// Guards the fixture invariant the golden's stability depends on. If this fails, the
    /// golden test above may flake rather than fail honestly.
    @MainActor
    func testFixtureProducesNoTiedScores() async throws {
        let tagPool = try await tagProvider().candidates(for: Self.makeProfile(),
                                                         excluding: Self.excluded, limit: 20)
        let malPool = try await malProvider().candidates(for: Self.makeProfile(),
                                                         excluding: Self.excluded, limit: 20)
        for (label, pool) in [("tag", tagPool), ("mal", malPool)] {
            let scores = pool.map { ($0.score * 1e9).rounded() }
            XCTAssertEqual(Set(scores).count, scores.count,
                           "\(label) pool has tied scores — sub-providers have no stable "
                           + "tie-break, so the golden can reorder between runs")
        }
    }

    // MARK: - Rendering

    private func tagProvider() -> TagCandidateProvider {
        TagCandidateProvider(source: FixtureSource(), topK: 6, perTagLimit: 20)
    }

    @MainActor
    private func malProvider() -> MALCandidateProvider {
        MALCandidateProvider(similar: FixtureSimilar(), perSeedLimit: 8)
    }

    /// Renders the ranking as a fixed-width table.
    ///
    /// The `final` and `reason` columns come from `CompositeCandidateProvider` — the system
    /// under test. The `tagNorm` / `malNorm` / `agree` columns are re-derived here from the two
    /// sub-pools, so they are *observed inputs*, not restatements of the implementation. If the
    /// composite's formula changes, `final` moves while the component columns hold still, and
    /// the diff shows precisely what the new formula did.
    @MainActor
    private func renderRanking() async throws -> String {
        let profile = Self.makeProfile()
        let composite = CompositeCandidateProvider(tag: tagProvider(), mal: malProvider())

        let blended = try await composite.candidates(for: profile,
                                                     excluding: Self.excluded, limit: 20)
        let tagNorm = Self.normalized(
            try await tagProvider().candidates(for: profile, excluding: Self.excluded, limit: 20))
        let malNorm = Self.normalized(
            try await malProvider().candidates(for: profile, excluding: Self.excluded, limit: 20))

        var out = """
        For You — blended candidate ranking (synthetic fixture)

        Generated by RecommendationGoldenTests. Do not hand-edit; regenerate with
        TEST_RUNNER_REGENERATE_GOLDENS=1 and read the diff.

        weights: wTag=\(fmt(composite.wTag)) wMal=\(fmt(composite.wMal)) \
        overlapBonus=\(fmt(composite.overlapBonus))
          (read off the provider under test, so this line can never disagree with the code)

        tagNorm / malNorm : each pool's score divided by that pool's own maximum.
        agree             : the bonus actually applied for appearing in both pools.
        final             : CompositeCandidateProvider's output score.


        """

        out += Self.pad("rank", 5) + Self.pad("title", 22) + Self.pad("tagNorm", 9)
            + Self.pad("malNorm", 9) + Self.pad("agree", 8) + Self.pad("final", 9) + "reason\n"
        out += String(repeating: "-", count: 96) + "\n"

        for (i, c) in blended.enumerated() {
            let t = tagNorm[c.manga.id]
            let m = malNorm[c.manga.id]
            // Whatever the composite added beyond the weighted sum of the two pools. Uses the
            // provider's OWN weights, not literals — deriving this with hardcoded 1.0/0.85
            // makes the column silently wrong the moment someone tunes wMal, which is exactly
            // when the column matters most.
            let agree = c.score - (t ?? 0) * composite.wTag - (m ?? 0) * composite.wMal
            out += Self.pad(String(i + 1), 5)
                + Self.pad(c.manga.title, 22)
                + Self.pad(t.map { String(format: "%.4f", $0) } ?? "-", 9)
                + Self.pad(m.map { String(format: "%.4f", $0) } ?? "-", 9)
                + Self.pad(String(format: "%.4f", agree), 8)
                + Self.pad(String(format: "%.4f", c.score), 9)
                + c.reason + "\n"
        }

        out += "\nexcluded (already read/saved/dismissed): "
            + Self.excluded.sorted().map { Self.titles[$0] ?? $0 }.joined(separator: ", ") + "\n"
        return out
    }

    private static func normalized(_ pool: [ScoredManga]) -> [String: Double] {
        guard let max = pool.map(\.score).max(), max > 0 else { return [:] }
        return Dictionary(pool.map { ($0.manga.id, $0.score / max) },
                          uniquingKeysWith: { first, _ in first })
    }

    private func fmt(_ d: Double) -> String { String(format: "%g", d) }

    private static func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s + " " : s + String(repeating: " ", count: width - s.count)
    }

    // MARK: - Golden file plumbing

    /// Goldens live next to their test file and are resolved from `#filePath`, so no Xcode
    /// resource-bundle wiring is needed — `Manga-ReaderTests` is a plain PBXGroup, not a
    /// synchronized one, and adding bundled resources to it would mean hand-editing pbxproj.
    private func assertMatchesGolden(_ actual: String, named name: String,
                                     file: StaticString = #filePath,
                                     line: UInt = #line) throws {
        let dir = URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Goldens__")
        let url = dir.appendingPathComponent(name)
        let fm = FileManager.default

        if ProcessInfo.processInfo.environment["REGENERATE_GOLDENS"] == "1" {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }

        guard let expected = try? String(contentsOf: url, encoding: .utf8) else {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            XCTFail("Golden '\(name)' did not exist — wrote it. Review it, then re-run.",
                    file: file, line: line)
            return
        }

        if actual != expected {
            XCTFail("""
                Golden '\(name)' mismatch. If this change is intended, regenerate with \
                TEST_RUNNER_REGENERATE_GOLDENS=1 and review the diff.

                --- expected ---
                \(expected)
                --- actual ---
                \(actual)
                """, file: file, line: line)
        }
    }
}
