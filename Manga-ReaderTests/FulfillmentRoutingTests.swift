//
//  FulfillmentRoutingTests.swift
//  Manga-ReaderTests
//
//  ADR-0004: a Work with several Listings must choose one to open. Rank by
//  English chapter completeness, MangaDex breaks ties.
//

import XCTest
@testable import Manga_Reader

final class FulfillmentRoutingTests: XCTestCase {

    private func candidate(_ sourceId: String,
                           count: Int?,
                           order: Int) -> ListingCandidate {
        ListingCandidate(key: ListingKey(sourceId: sourceId, mangaId: "m"),
                         chapterCount: count,
                         registrationIndex: order)
    }

    /// The ADR's step 2. A source with materially more chapters wins, and it wins
    /// even over MangaDex — MangaDex-first is a quality preference that only
    /// applies at equal completeness.
    func testRanksByChapterCountDescending() {
        let ranked = FulfillmentRouter.rank([
            candidate("mangadex", count: 40, order: 0),
            candidate("weebcentral", count: 120, order: 1)
        ], referenceTotal: nil)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["weebcentral", "mangadex"])
    }

    /// The ADR's step 3, first clause. Equal completeness is where the quality
    /// preference applies — better scans, better metadata, no ads — so MangaDex
    /// wins a tie regardless of where it sits in registration order.
    func testMangaDexWinsAtEqualChapterCount() {
        let ranked = FulfillmentRouter.rank([
            candidate("weebcentral", count: 120, order: 0),
            candidate("mangadex", count: 120, order: 1)
        ], referenceTotal: nil)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["mangadex", "weebcentral"])
    }

    /// ADR-0007's rule, and the one a `?? 0` quietly breaks: a missing count means
    /// **unknown**, never zero. A Listing nobody has counted yet is a better bet
    /// than one counted and found empty, so it outranks it — even though the empty
    /// one is MangaDex and would win any tie.
    func testUncountedListingOutranksOneCountedEmpty() {
        let ranked = FulfillmentRouter.rank([
            candidate("mangadex", count: 0, order: 0),
            candidate("weebcentral", count: nil, order: 1)
        ], referenceTotal: nil)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["weebcentral", "mangadex"])
    }

    /// The cold-start case the ADR calls out by name: "the MangaDex-first default
    /// when nothing is cached." With no evidence at all, ranking falls back
    /// entirely to the preference order.
    func testNothingCachedFallsBackToMangaDexFirst() {
        let ranked = FulfillmentRouter.rank([
            candidate("weebcentral", count: nil, order: 1),
            candidate("mangadex", count: nil, order: 0)
        ], referenceTotal: nil)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["mangadex", "weebcentral"])
    }

    /// When the reference total is known, completeness — not raw count — is the
    /// ranking. A source carrying *more* entries than the series has chapters is
    /// padding its list (duplicate uploads, split parts, extras); it is not more
    /// complete than a source that already has every chapter. So a Listing at 100%
    /// short-circuits, and the larger raw count loses.
    func testReachingTheReferenceTotalBeatsALargerRawCount() {
        let ranked = FulfillmentRouter.rank([
            candidate("weebcentral", count: 205, order: 1),
            candidate("mangadex", count: 201, order: 0)
        ], referenceTotal: 201)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["mangadex", "weebcentral"])
    }

    /// The One Piece case, verified live in the ADR: ongoing series report a `nil`
    /// total, which is exactly when routing matters most. With no total the sources
    /// define the frontier, so the biggest raw count simply wins.
    func testAnUnknownReferenceTotalRanksOnRawCount() {
        let ranked = FulfillmentRouter.rank([
            candidate("mangadex", count: 1100, order: 0),
            candidate("weebcentral", count: 1104, order: 1)
        ], referenceTotal: nil)

        XCTAssertEqual(ranked.map(\.key.sourceId), ["weebcentral", "mangadex"])
    }

    // MARK: - Counting

    private func chapter(_ number: String) -> Chapter {
        Chapter(id: UUID().uuidString, number: number, title: nil, date: nil)
    }

    /// The ADR's step 1 says *distinct* chapters, and a chapter list is full of
    /// duplicates: multiple scanlation groups upload the same chapter, and sources
    /// relabel `"07"` as `"7"`. Counting rows instead of chapters would let the
    /// most duplicated source win every comparison.
    func testCountsDistinctChaptersNotRows() {
        let count = FulfillmentRouter.distinctChapterCount([
            chapter("7"), chapter("07"), chapter("7"), chapter("8")
        ])

        XCTAssertEqual(count, 2)
    }

    /// Unnumbered entries — "Oneshot", "Extra", "Special" — are readable chapters
    /// but they are **not comparable across sources**: one site's "Oneshot" is
    /// another's "Chapter 0", and free-text labels never line up. Counting them
    /// would make the completeness comparison depend on labelling style, so the
    /// count is of numbered chapters only.
    func testUnnumberedEntriesDoNotCountTowardCompleteness() {
        let count = FulfillmentRouter.distinctChapterCount([
            chapter("1"), chapter("Oneshot"), chapter("Extra")
        ])

        XCTAssertEqual(count, 1)
    }
}
