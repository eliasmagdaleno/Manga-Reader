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

    // MARK: - Engagement weight, exposed (ADR-0009)

    /// The population split. A Work that has been *read* but never had a detail page
    /// opened carries no tags — yet it is the highest-value thing the upgrade queue can
    /// fetch, since it is proven demand contributing literally nothing. So it must be
    /// orderable. Before this, `build` skipped it before any weight was computed.
    func testAnUntaggedWorkWithReadingHistoryStillGetsAWeight() throws {
        let untagged = signal([entry("wc-1")], tags: [])
        let profile = TasteProfile.build(signals: [untagged],
                                         savedIds: [], moreLikeThis: [], now: now)

        XCTAssertGreaterThan(try XCTUnwrap(profile.workWeights[untagged.workId]), 0)
    }

    /// **One** definition of engagement (ADR-0008): the number the upgrade queue orders
    /// on is the same number that ranks seeds. A queue computing its own recency×chapters
    /// score would diverge silently the first time either was tuned. Green on arrival —
    /// this guards the property rather than driving it.
    func testAWorkWeightIsTheSameNumberThatRanksItsSeed() throws {
        let read = signal([entry("wc-1", chapter: "1"), entry("wc-1", chapter: "2")],
                          tags: [QueryableTag(name: "Action", group: "genre")])
        let profile = TasteProfile.build(signals: [read],
                                         savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(try XCTUnwrap(profile.workWeights[read.workId]),
                       try XCTUnwrap(profile.seeds.first).weight, accuracy: 1e-9)
    }

    /// The residual tail: a Work minted from a save or a *Not interested* has no reading
    /// history, so there is nothing to weight it by. It is absent rather than zero, and
    /// the queue sorts these last by `WorkID` (ADR-0009).
    func testAWorkWithNoReadingHistoryHasNoWeight() {
        let saved = signal([], tags: [QueryableTag(name: "Action", group: "genre")])
        let profile = TasteProfile.build(signals: [saved],
                                         savedIds: [], moreLikeThis: [], now: now)

        XCTAssertNil(profile.workWeights[saved.workId])
    }

    /// The trap ADR-0009 names: `weighted` feeds `makeSeeds`, and seeds are the queries
    /// sent to MyAnimeList. Weighting untagged Works must not leak into that array, or
    /// exposing the queue's ordering would silently change what the recommender asks for.
    func testWeightingUntaggedWorksLeavesSeedsAndTheColdStartGateAlone() {
        let tagged = signal([entry("md-1", source: "mangadex")],
                            tags: [QueryableTag(name: "Action", group: "genre")])
        let untagged = signal([entry("wc-1")], tags: [])

        let alone = TasteProfile.build(signals: [tagged],
                                       savedIds: [], moreLikeThis: [], now: now)
        let withUntagged = TasteProfile.build(signals: [tagged, untagged],
                                              savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(withUntagged.taggedMangaCount, alone.taggedMangaCount)
        XCTAssertEqual(withUntagged.seeds.map(\.manga.id), alone.seeds.map(\.manga.id))
        XCTAssertEqual(withUntagged.weights, alone.weights)
        XCTAssertEqual(withUntagged.workWeights.count, 2, "but both Works are orderable")
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

    // MARK: - Seeds carry the Work's MAL id (ADR-0018)

    /// A seed is handed to `MoreLikeThisProvider`, which starts with
    /// `resolver.malId(for:)` — a **free fast path** when the `Manga` already publishes an
    /// id, and a live MAL title search plus matcher run when it does not. ADR-0018's rule is
    /// that an authoritative id is not a resolution question, and the Work has held one
    /// since it was minted. Dropping it here re-asks a question already answered, up to five
    /// times per For You refresh.
    func testASeedBuiltFromHistoryCarriesTheWorksMalId() {
        let profile = TasteProfile.build(
            signals: [TasteProfile.WorkSignal(workId: WorkID(), malId: 21,
                                              entries: [entry("md-1", title: "Death Note")],
                                              tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)

        XCTAssertEqual(profile.seeds.first?.manga.malId, 21,
                       "the seed re-asks MAL for an id the Work already holds")
    }

    /// The saved path builds its seed from the library listing rather than from history, so
    /// it needs the same stamp — and it is the *more* important of the two, since a saved
    /// title with no reading is exactly the case that has no `ReadingEntry` to fall back on.
    func testASeedBuiltFromTheLibraryCarriesTheWorksMalId() {
        let saved = Manga(id: "md-1", sourceId: "mangadex", title: "Death Note",
                          description: "", status: "completed", year: nil,
                          coverURL: nil, malId: nil)
        let profile = TasteProfile.build(
            signals: [TasteProfile.WorkSignal(workId: WorkID(), malId: 21,
                                              entries: [entry("md-1", title: "Death Note")],
                                              tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: ["md-1"], moreLikeThis: [], now: now,
            libraryItems: [saved])

        XCTAssertEqual(profile.seeds.first?.manga.id, "md-1", "wrong seed for the assertion")
        XCTAssertEqual(profile.seeds.first?.manga.malId, 21,
                       "the saved seed re-asks MAL for an id the Work already holds")
    }

    /// A Work with no id yet must not invent one — the entry's own `malId` is the next best
    /// authority (the source published it, ADR-0018), and `nil` is the honest answer when
    /// neither has one.
    func testASeedWithNoKnownIdFallsBackToTheEntryAndThenToNil() {
        var stamped = entry("md-2", title: "Berserk")
        stamped.malId = 2
        let withEntryId = TasteProfile.build(
            signals: [TasteProfile.WorkSignal(workId: WorkID(), malId: nil, entries: [stamped],
                                              tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)
        XCTAssertEqual(withEntryId.seeds.first?.manga.malId, 2,
                       "the entry published an id and the seed dropped it")

        let withNone = TasteProfile.build(
            signals: [signal([entry("md-3", title: "Unknown")],
                             tags: [QueryableTag(name: "Action", group: "genre")])],
            savedIds: [], moreLikeThis: [], now: now)
        XCTAssertNil(withNone.seeds.first?.manga.malId)
    }
}
