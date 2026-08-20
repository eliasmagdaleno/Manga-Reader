//
//  TasteProfileGoldenTests.swift
//  Manga-ReaderTests
//
//  A golden-file harness for **profile construction** — the layer
//  `RecommendationGoldenTests` deliberately does not cover.
//
//  WHY A SECOND GOLDEN
//  `RecommendationGoldenTests` builds a `TasteProfile` from literal weights on purpose, so that
//  harness isolates *ranking*. That makes it blind to every change in `TasteProfile.build`:
//  engagement weighting, which manga contribute at all, and what the tag key space is. ADR-0007
//  slice 3 changes exactly those things, so without this file the slice's central change — a
//  manga read on a non-MangaDex source finally contributing tag signal — would land with no
//  reviewable evidence at all.
//
//  WHAT THE FIXTURE ENCODES
//  A reading history spanning **two sources**, and a tag table that is the *world's* truth: what
//  each manga's tags actually are, regardless of whether the app ever managed to record them.
//  Before slice 3, tag recording was gated on `sourceId == "mangadex"`
//  (`MangaDetailView.swift:56`), so only the MangaDex subset ever reached the profile. The
//  fixture reproduces that gate honestly rather than pretending the cache was complete — which
//  is what makes the diff meaningful when the gate comes out.
//
//  REGENERATING
//      TEST_RUNNER_REGENERATE_GOLDENS=1 xcodebuild -scheme Manga-Reader \
//        -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO \
//        test -only-testing:Manga-ReaderTests/TasteProfileGoldenTests
//
//  The `TEST_RUNNER_` prefix is required; a bare `REGENERATE_GOLDENS=1` is silently dropped.
//  Read the diff before committing it.
//

import XCTest
@testable import Manga_Reader

final class TasteProfileGoldenTests: XCTestCase {

    // MARK: - Fixture

    /// Fixed so recency weighting is reproducible. Every `lastRead` below is an offset from this.
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct ReadFixture {
        let mangaId: String
        let sourceId: String
        let title: String
        let chapters: [String]
        let page: Int
        let pageCount: Int
        let daysAgo: Double
    }

    // swiftlint:disable colon comma
    /// What the user read. Two sources, and the WeebCentral titles are the ones the shipped
    /// recommender cannot see at all.
    private static let reads: [ReadFixture] = [
        ReadFixture(mangaId: "md-solo",   sourceId: "mangadex",    title: "Solo Leveling",
                    chapters: ["1", "2", "3"], page: 19, pageCount: 20, daysAgo: 2),
        ReadFixture(mangaId: "md-berserk", sourceId: "mangadex",   title: "Berserk",
                    chapters: ["1"],           page: 4,  pageCount: 30, daysAgo: 40),
        ReadFixture(mangaId: "wc-orv",    sourceId: "weebcentral", title: "Omniscient Reader",
                    chapters: ["1", "2", "3", "4"], page: 17, pageCount: 18, daysAgo: 5),
        ReadFixture(mangaId: "wc-tower",  sourceId: "weebcentral", title: "Tower of God",
                    chapters: ["1", "2"],      page: 3,  pageCount: 25, daysAgo: 11),
    ]

    /// The world's truth: every manga's real tags. Whether they reach the profile is the
    /// behaviour under test.
    private static let tagTable: [String: [Tag]] = [
        "md-solo":    [Tag(id: "t-action",    name: "Action",     group: "genre"),
                       Tag(id: "t-isekai",    name: "Isekai",     group: "theme"),
                       Tag(id: "t-longstrip", name: "Long Strip", group: "format")],
        "md-berserk": [Tag(id: "t-action",    name: "Action",     group: "genre"),
                       Tag(id: "t-drama",     name: "Drama",      group: "theme")],
        "wc-orv":     [Tag(id: "t-action",    name: "Action",     group: "genre"),
                       Tag(id: "t-fantasy",   name: "Fantasy",    group: "genre")],
        "wc-tower":   [Tag(id: "t-fantasy",   name: "Fantasy",    group: "genre"),
                       Tag(id: "t-adventure", name: "Adventure",  group: "genre")],
    ]
    // swiftlint:enable colon comma

    /// Saved to the library — an engagement bonus in `build`.
    private static let savedIds: Set<String> = ["md-solo"]

    /// The tags that actually reach the profile. **This is the line slice 3 moves:** it
    /// used to filter `tagTable` down to the MangaDex subset, mirroring the
    /// `sourceId == "mangadex"` gate in `MangaDetailView`. Now every source's tags land
    /// on the Work, so the whole table gets through.
    private static func reachableTags() -> [String: [Tag]] { tagTable }

    /// One Work per manga, which is what the store produces for Listings nothing has
    /// linked. Cross-source merging has its own unit tests; keeping it out here means
    /// the golden diff shows one change, not two.
    private static func signals() -> [TasteProfile.WorkSignal] {
        var byManga: [String: [ReadingEntry]] = [:]
        for e in history() { byManga[e.mangaId, default: []].append(e) }
        let reachable = reachableTags()
        return reads.map { fixture in
            TasteProfile.WorkSignal(
                workId: WorkID(),
                entries: byManga[fixture.mangaId] ?? [],
                tags: (reachable[fixture.mangaId] ?? [])
                    .map { QueryableTag(name: $0.name, group: $0.group) })
        }
    }

    private static func history() -> [ReadingEntry] {
        reads.flatMap { fixture in
            fixture.chapters.enumerated().map { index, number in
                // Chapters of one manga are read in order, the last one most recently; only the
                // newest entry per manga drives recency and completion, matching `build`.
                let age = fixture.daysAgo + Double(fixture.chapters.count - 1 - index)
                let isNewest = index == fixture.chapters.count - 1
                return ReadingEntry(id: UUID(),
                                    mangaId: fixture.mangaId,
                                    mangaTitle: fixture.title,
                                    coverURL: nil,
                                    chapterId: "\(fixture.mangaId)-c\(number)",
                                    chapterNumber: number,
                                    page: isNewest ? fixture.page : fixture.pageCount - 1,
                                    pageCount: fixture.pageCount,
                                    updatedAt: now.addingTimeInterval(-age * 86_400),
                                    sourceId: fixture.sourceId)
            }
        }
    }

    // MARK: - The golden test

    func testTasteProfileConstructionGolden() throws {
        let profile = TasteProfile.build(signals: Self.signals(),
                                         savedIds: Self.savedIds,
                                         moreLikeThis: [],
                                         now: Self.now,
                                         libraryItems: [],
                                         seedLimit: 5)
        try assertMatchesGolden(render(profile), named: "taste-profile.txt")
    }

    // MARK: - Rendering

    private func render(_ profile: TasteProfile) -> String {
        var out = """
        Taste profile — built from a synthetic two-source reading history

        Generated by TasteProfileGoldenTests. Do not hand-edit; regenerate with
        TEST_RUNNER_REGENERATE_GOLDENS=1 and read the diff.

        The `key` column is the profile's tag key space, shown because slice 3 changes it: a
        Work's snapshot carries tag names and groups but no MangaDex tag id.


        """

        out += pad("source", 14) + pad("manga", 12) + pad("title", 20)
            + pad("chapters", 10) + pad("finished", 10) + "last read\n"
        out += String(repeating: "-", count: 78) + "\n"
        for r in Self.reads.sorted(by: { $0.mangaId < $1.mangaId }) {
            let finished = r.page >= r.pageCount - 1
            out += pad(r.sourceId, 14) + pad(r.mangaId, 12) + pad(r.title, 20)
                + pad(String(r.chapters.count), 10) + pad(finished ? "yes" : "no", 10)
                + "\(fmt(r.daysAgo))d ago\n"
        }

        out += "\ntaggedMangaCount: \(profile.taggedMangaCount)"
        out += "   (manga contributing tag signal — the rest are invisible to the recommender)\n\n"

        out += pad("weight", 10) + pad("name", 14) + "key\n"
        out += String(repeating: "-", count: 44) + "\n"
        // Sorted here rather than trusting `orderedTagKeys`, so a change in the profile's own
        // ordering shows up as moved *values* instead of silently reshuffling every row.
        let ordered = profile.weights.sorted {
            $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key
        }
        for (key, weight) in ordered {
            out += pad(String(format: "%.4f", weight), 10)
                + pad(profile.tagName[key] ?? "-", 14) + key + "\n"
        }

        out += "\nseeds (highest engagement first — these are the MAL recommendation seeds)\n"
        out += String(repeating: "-", count: 44) + "\n"
        for seed in profile.seeds {
            out += pad(String(format: "%.4f", seed.weight), 10)
                + pad(seed.manga.title, 22) + seed.manga.sourceId + "\n"
        }
        return out
    }

    private func fmt(_ d: Double) -> String { String(format: "%g", d) }

    private func pad(_ s: String, _ width: Int) -> String {
        s.count >= width ? s + " " : s + String(repeating: " ", count: width - s.count)
    }

    // MARK: - Golden file plumbing

    /// Mirrors `RecommendationGoldenTests` — goldens live next to their test file, resolved from
    /// `#filePath`, so no Xcode resource-bundle wiring is needed.
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
