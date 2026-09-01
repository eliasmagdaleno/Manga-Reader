//
//  SourcePickerPresentationTests.swift
//  Manga-ReaderTests
//
//  What the detail page shows when a Work has more than one Listing. Pure, because
//  there is no tap tool here — the view stays thin enough that testing this covers
//  the behaviour, and XCUITest is reserved for the wiring.
//

import XCTest
@testable import Manga_Reader

final class SourcePickerPresentationTests: XCTestCase {

    private func candidate(_ sourceId: String,
                           _ mangaId: String,
                           count: Int?,
                           order: Int) -> ListingCandidate {
        ListingCandidate(key: ListingKey(sourceId: sourceId, mangaId: mangaId),
                         chapterCount: count,
                         registrationIndex: order)
    }

    private let names = ["mangadex": "MangaDex", "weebcentral": "WeebCentral"]

    /// One Listing is the common case and it is not a choice. Showing a picker with
    /// a single entry would promise an alternative that does not exist.
    func testASingleListingIsNotAChoice() {
        let presentation = SourcePickerPresentation(
            candidates: [candidate("mangadex", "op", count: 120, order: 0)],
            current: ListingKey(sourceId: "mangadex", mangaId: "op"),
            names: names)

        XCTAssertFalse(presentation.offersAChoice)
    }

    private var twoListings: SourcePickerPresentation {
        SourcePickerPresentation(
            candidates: [candidate("weebcentral", "one-piece", count: 120, order: 1),
                         candidate("mangadex", "op", count: nil, order: 0)],
            current: ListingKey(sourceId: "weebcentral", mangaId: "one-piece"),
            names: names)
    }

    /// A counted Listing says what it has. This is the number the whole ranking
    /// turns on, so the user can see why the app picked what it picked.
    func testACountedListingShowsItsChapterCount() {
        XCTAssertEqual(twoListings.rows.first?.detail, "120 chapters")
    }

    /// An uncounted Listing must not read as an empty one. "0 chapters" would be a
    /// lie the router itself is careful never to tell — nil means unknown, and the
    /// user deserves the same distinction the ranking makes.
    func testAnUncountedListingDoesNotClaimZeroChapters() {
        XCTAssertEqual(twoListings.rows.last?.detail, "Not counted yet")
    }

    /// The row the user is reading from is marked, because the picker's first job
    /// is answering "where is this coming from?" before "what else is there?".
    func testTheCurrentListingIsMarked() {
        XCTAssertEqual(twoListings.rows.map(\.isCurrent), [true, false])
    }

    /// Rows arrive in ranked order, so the best Listing is the first thing read —
    /// by eye and by VoiceOver alike.
    func testRowsFollowTheRanking() {
        XCTAssertEqual(twoListings.rows.map(\.name), ["WeebCentral", "MangaDex"])
    }

    /// A source that is registered but has no display name still has to render.
    /// Falling back to the id keeps a row that works over a row that is blank.
    func testAnUnnamedSourceFallsBackToItsId() {
        let presentation = SourcePickerPresentation(
            candidates: [candidate("mystery", "x", count: 2, order: 1),
                         candidate("mangadex", "op", count: 1, order: 0)],
            current: ListingKey(sourceId: "mangadex", mangaId: "op"),
            names: names)

        XCTAssertEqual(presentation.rows.first?.name, "mystery")
    }

    /// Rows are given already ranked and are rendered in that order — the ranking
    /// is the router's job and is not repeated here. Stated as a test because the
    /// alternative, sorting again in the view layer, is the kind of duplicate
    /// authority that drifts.
    func testRowsPreserveTheOrderTheyAreGiven() {
        let presentation = SourcePickerPresentation(
            candidates: [candidate("mangadex", "op", count: 1, order: 0),
                         candidate("weebcentral", "one-piece", count: 999, order: 1)],
            current: ListingKey(sourceId: "mangadex", mangaId: "op"),
            names: names)

        XCTAssertEqual(presentation.rows.map(\.name), ["MangaDex", "WeebCentral"])
    }
}
