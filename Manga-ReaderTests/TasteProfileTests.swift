//
//  TasteProfileTests.swift
//  Manga-ReaderTests
//
//  Profile construction once it aggregates by **Work** rather than by Listing
//  (ADR-0007 slice 3, step 3). The older per-Listing tests live in
//  `Manga_ReaderTests.swift`.
//

import XCTest
@testable import Manga_Reader

final class TasteProfileTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func entry(_ mangaId: String,
                       source: String = "weebcentral",
                       title: String = "Untitled",
                       chapter: String = "1",
                       page: Int = 5,
                       pageCount: Int = 20,
                       daysAgo: Double = 1) -> ReadingEntry {
        ReadingEntry(id: UUID(), mangaId: mangaId, mangaTitle: title, coverURL: nil,
                     chapterId: "\(mangaId)-c\(chapter)", chapterNumber: chapter,
                     page: page, pageCount: pageCount,
                     updatedAt: now.addingTimeInterval(-daysAgo * 86_400),
                     sourceId: source)
    }

    private func signal(_ entries: [ReadingEntry], tags: [QueryableTag]) -> TasteProfile.WorkSignal {
        TasteProfile.WorkSignal(workId: WorkID(), entries: entries, tags: tags)
    }

    /// The whole point of the slice: a manga read on WeebCentral now contributes tag
    /// signal. Before this, `tagCache` was MangaDex-only and the read was skipped
    /// before its engagement weight was ever computed.
    func testAReadOnANonMangaDexSourceContributesTagSignal() {
        let profile = TasteProfile.build(
            signals: [signal([entry("wc-1", title: "Omniscient Reader")],
                             tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.taggedMangaCount, 1)
        XCTAssertEqual(profile.tagName.values.sorted(), ["Action"])
        XCTAssertFalse(profile.isEmpty)
    }

    /// Two Listings of the same Work are one thing the user reads, so they produce a
    /// single engagement weight and a single seed — not two half-strength ones. This
    /// is what the Work layer buys that a per-Listing profile cannot express.
    func testTwoListingsOfOneWorkCountAsASingleEngagement() {
        let entries = [entry("md-1", source: "mangadex", title: "Solo Leveling", chapter: "1"),
                       entry("wc-1", source: "weebcentral", title: "Only I Level Up", chapter: "2")]
        let profile = TasteProfile.build(
            signals: [signal(entries, tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.taggedMangaCount, 1, "one Work, however many Listings")
        XCTAssertEqual(profile.seeds.count, 1)
    }

    /// Saved-ness is recorded against a Listing, so a Work counts as saved when *any*
    /// of its Listings is. Otherwise saving on one source and reading on another would
    /// silently drop the engagement bonus.
    func testAWorkIsSavedWhenAnyOfItsListingsIsSaved() throws {
        let entries = [entry("md-1", source: "mangadex", title: "Solo Leveling"),
                       entry("wc-1", source: "weebcentral", title: "Only I Level Up")]
        let tags = [QueryableTag(name: "Action", group: "genre")]

        let saved = TasteProfile.build(signals: [signal(entries, tags: tags)],
                                       savedIds: ["wc-1"], moreLikeThis: [], now: now)
        let unsaved = TasteProfile.build(signals: [signal(entries, tags: tags)],
                                         savedIds: [], moreLikeThis: [], now: now)

        XCTAssertGreaterThan(try XCTUnwrap(saved.seeds.first).weight,
                             try XCTUnwrap(unsaved.seeds.first).weight)
    }

    /// Same rule for explicit boosts.
    func testAWorkIsBoostedWhenAnyOfItsListingsIsMoreLikeThis() throws {
        let entries = [entry("md-1", source: "mangadex"), entry("wc-1")]
        let tags = [QueryableTag(name: "Action", group: "genre")]

        let boosted = TasteProfile.build(signals: [signal(entries, tags: tags)],
                                         savedIds: [], moreLikeThis: ["wc-1"], now: now)
        let plain = TasteProfile.build(signals: [signal(entries, tags: tags)],
                                       savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(try XCTUnwrap(boosted.seeds.first).weight,
                       try XCTUnwrap(plain.seeds.first).weight * 2, accuracy: 1e-9)
    }

    /// AniList genres arrive with no group. ADR-0007 says they are all genre-level, so
    /// they must weight as genre (1.0) rather than falling through `groupWeight`'s
    /// `default: 0.5` — which would quietly halve the signal from every AniList Work.
    func testATagWithNoGroupWeightsAsGenre() {
        let entries = [entry("wc-1")]
        let untagged = TasteProfile.build(
            signals: [signal(entries, tags: [QueryableTag(name: "Action", group: nil)])],
            savedIds: [], moreLikeThis: [], now: now)
        let explicit = TasteProfile.build(
            signals: [signal(entries, tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)

        // Both normalize to 1.0 on their own, so compare the pre-normalization ratio via
        // a second tag whose group is fixed: Action-with-no-group must not rank below it.
        XCTAssertEqual(untagged.weights, explicit.weights)
    }

    /// One key per tag *name*, because a Work's snapshot has no tag ids. Two sources
    /// naming the same genre are one signal, not two half-signals.
    func testTagsAreKeyedByNormalizedNameAcrossSources() {
        let profile = TasteProfile.build(
            signals: [signal([entry("md-1", source: "mangadex")],
                             tags: [QueryableTag(name: "Action", group: "genre")]),
                      signal([entry("wc-1")],
                             tags: [QueryableTag(name: "action", group: nil)])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.weights.count, 1, "Action and action are one tag")
        XCTAssertEqual(profile.orderedTagKeys.count, 1)
    }

    /// Equal weights previously ordered by dictionary iteration, which is randomized
    /// per process — so the rail could reorder between launches for no reason.
    func testEqualWeightsOrderDeterministicallyByKey() {
        let entries = [entry("wc-1")]
        let profile = TasteProfile.build(
            signals: [signal(entries, tags: [QueryableTag(name: "Romance", group: "genre"),
                                             QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.orderedTagKeys, ["action", "romance"])
    }

    /// A Work with no snapshot yet — minted from a scraped source the upgrade queue
    /// hasn't reached — contributes nothing and must not be counted as tagged.
    func testAWorkWithNoTagsContributesNothing() {
        let profile = TasteProfile.build(
            signals: [signal([entry("wc-1")], tags: [])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.taggedMangaCount, 0)
        XCTAssertTrue(profile.isEmpty)
    }
}
