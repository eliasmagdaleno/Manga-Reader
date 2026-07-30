//
//  ReadingPositionTests.swift
//  Manga-ReaderTests
//
//  Where a reader stopped inside a chapter, and the rule that recorded progress
//  only ever moves forward (ADR-0014).
//

import XCTest
@testable import Manga_Reader

final class ReadingPositionTests: XCTestCase {

    // MARK: - Ordering

    /// The ordering is lexicographic: the page dominates, the fraction breaks ties.
    /// `HistoryStore.record` takes `max()` over this, so it is what keeps a backwards
    /// scroll from un-finishing a finished chapter (ADR-0014 decision 2).
    func testAPositionIsOrderedByPageThenFraction() {
        let midStrip5 = ReadingPosition(page: 5, fraction: 0.2)
        let lateStrip5 = ReadingPosition(page: 5, fraction: 0.9)
        let topStrip6 = ReadingPosition(page: 6, fraction: 0)

        XCTAssertLessThan(midStrip5, lateStrip5)        // same page, fraction decides
        XCTAssertLessThan(lateStrip5, topStrip6)        // a higher page wins outright
        XCTAssertEqual(max(lateStrip5, midStrip5), lateStrip5)
        XCTAssertEqual(max(lateStrip5, topStrip6), topStrip6)
    }

    // MARK: - Persistence

    /// The whole reason `fraction` is a flat field with a default rather than a nested
    /// value: every entry saved before ADR-0014 has to keep reading as today's
    /// behaviour, which is "the top of the recorded page".
    func testAnEntrySavedBeforeFractionExistedResumesAtTheTopOfItsPage() throws {
        let legacy = """
            {"id":"00000000-0000-0000-0000-000000000000","mangaId":"m","mangaTitle":"T",\
            "coverURL":null,"chapterId":"c","chapterNumber":"1","page":4,"pageCount":8,\
            "updatedAt":0,"sourceId":"mangadex"}
            """
            .data(using: .utf8)!

        let entry = try JSONDecoder().decode(ReadingEntry.self, from: legacy)

        XCTAssertEqual(entry.fraction, 0)
        XCTAssertEqual(entry.position, ReadingPosition(page: 4, fraction: 0))
    }

    // MARK: - Recording

    @MainActor
    private func makeHistoryStore() -> HistoryStore {
        let suite = UserDefaults(suiteName: "test.position.\(UUID().uuidString)")!
        return HistoryStore(defaults: suite)
    }

    private func sampleManga() -> Manga {
        Manga(id: "m1", sourceId: "mangadex", title: "T", description: "", status: "ongoing",
              year: nil, coverURL: nil, malId: nil)
    }

    private let chapter = Chapter(id: "c1", number: "1", title: nil)

    @MainActor func testScrollingFurtherDownTheSameStripAdvancesTheFraction() {
        let store = makeHistoryStore()

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.2), pageCount: 8)
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.62), pageCount: 8)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.position, ReadingPosition(page: 5, fraction: 0.62))
    }

    /// The load-bearing invariant: `page` doubles as the completion signal for Continue
    /// Reading, the in-progress badge and taste signals, so nothing a reader does may
    /// walk it backwards — including scrolling back up to re-read (ADR-0014 decision 2).
    @MainActor func testScrollingBackwardsNeverReducesRecordedProgress() {
        let store = makeHistoryStore()

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 6, fraction: 0.5), pageCount: 8)
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 6, fraction: 0.1), pageCount: 8)
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 2, fraction: 0.9), pageCount: 8)

        XCTAssertEqual(store.entries.first?.position, ReadingPosition(page: 6, fraction: 0.5))
    }

    @MainActor func testReachingANewStripTakesTheWholeNewPair() {
        let store = makeHistoryStore()

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.9), pageCount: 8)
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 6, fraction: 0), pageCount: 8)

        // Not (6, 0.9): a fraction is only meaningful against the page it was captured on.
        XCTAssertEqual(store.entries.first?.position, ReadingPosition(page: 6, fraction: 0))
    }

    /// A `record` that advances nothing is a no-op, down to the timestamp. The reader
    /// calls it on every throttled tick and every backwards scroll now that the view
    /// holds no latch of its own (ADR-0014 decision 3), and `updatedAt` orders the
    /// History tab and weights taste recency.
    @MainActor func testARecordThatAdvancesNothingLeavesTheEntryUntouched() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.5), pageCount: 8)
        let recorded = try XCTUnwrap(store.entries.first)

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.5), pageCount: 8)
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 3, fraction: 0.9), pageCount: 8)

        XCTAssertEqual(store.entries.first, recorded)
    }

    /// `pageCount` is not part of the position and must still land — a chapter whose page
    /// count was recorded wrong (or before a source fixed it) has to be able to correct
    /// itself without the reader scrolling forwards.
    @MainActor func testAChangedPageCountIsRecordedEvenWhenThePositionDoesNot() {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.5), pageCount: 8)

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 5, fraction: 0.5), pageCount: 9)

        XCTAssertEqual(store.entries.first?.pageCount, 9)
        XCTAssertEqual(store.entries.first?.position, ReadingPosition(page: 5, fraction: 0.5))
    }

    /// A fraction must not be able to flip `finished`, which all three consumers derive
    /// from `page` alone (`ReadingResume`, `TasteProfile`, `ChapterRow`).
    @MainActor func testAFractionOnTheLastPageDoesNotChangeWhetherAChapterIsFinished() {
        let store = makeHistoryStore()
        let chapters = [chapter]

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 7, fraction: 0.1), pageCount: 8)
        let atLastPage = resumeAction(entry: store.entries.first, chapters: chapters)

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 7, fraction: 0.99), pageCount: 8)
        let deepIntoLastPage = resumeAction(entry: store.entries.first, chapters: chapters)

        XCTAssertEqual(atLastPage, deepIntoLastPage)
        XCTAssertEqual(atLastPage, .reread(chapter, page: 7))
    }

    // MARK: - Save timing

    /// Scroll position is recorded continuously, and `save()` re-encodes every entry plus
    /// the read marks. So `record` coalesces its writes — and `flush()` is what
    /// backgrounding calls so a session that ends there is not lost (ADR-0014 decision 5).
    @MainActor func testRecordingCoalescesItsWritesAndFlushForcesThem() {
        let suite = UserDefaults(suiteName: "test.position.\(UUID().uuidString)")!
        let store = HistoryStore(defaults: suite, saveInterval: 60)

        store.record(manga: sampleManga(), chapter: chapter,
                     position: ReadingPosition(page: 3, fraction: 0.4), pageCount: 8)
        XCTAssertTrue(HistoryStore(defaults: suite).entries.isEmpty,
                      "a recorded position should not hit the defaults synchronously")

        store.flush()

        let reloaded = HistoryStore(defaults: suite)
        XCTAssertEqual(reloaded.entries.first?.position, ReadingPosition(page: 3, fraction: 0.4))
    }

    /// **Throttle, not debounce.** Every tick carries a new position, so a cancel-and-rearm
    /// timer would push the write out for as long as the reader keeps scrolling — and a
    /// webtoon is read by scrolling continuously for many minutes. `WorkStore` hit the same
    /// trap on this same path (`WorkStoreTests.testAReMintThatLearnsNothing...`).
    @MainActor func testContinuousScrollingStillLandsAWrite() async throws {
        let suite = UserDefaults(suiteName: "test.position.\(UUID().uuidString)")!
        let store = HistoryStore(defaults: suite, saveInterval: 0.2)

        for tick in 0..<5 {                       // "scroll ticks" every 0.15s, t ≈ 0.6 total
            store.record(manga: sampleManga(), chapter: chapter,
                         position: ReadingPosition(page: 1, fraction: Double(tick) / 10),
                         pageCount: 8)
            try await Task.sleep(nanoseconds: 150_000_000)
        }

        XCTAssertFalse(HistoryStore(defaults: suite).entries.isEmpty,
                       "each new position rescheduled the pending write, so nothing was ever saved")
    }

    /// Deliberate user actions are not part of the scroll path and keep writing straight
    /// through — a marked chapter that survives one relaunch but not another would be a
    /// worse bug than a lost fraction.
    @MainActor func testMarkingReadWritesWithoutWaitingForTheThrottle() {
        let suite = UserDefaults(suiteName: "test.position.\(UUID().uuidString)")!
        let store = HistoryStore(defaults: suite, saveInterval: 60)

        store.markRead(manga: sampleManga(), chapter: chapter)

        XCTAssertTrue(HistoryStore(defaults: suite).isRead(chapterId: chapter.id))
    }

    func testAnEntryCarriesItsPositionAsOneValue() throws {
        var entry = try JSONDecoder().decode(
            ReadingEntry.self,
            from: """
                {"id":"00000000-0000-0000-0000-000000000000","mangaId":"m","mangaTitle":"T",\
                "coverURL":null,"chapterId":"c","chapterNumber":"1","page":4,"pageCount":8,"updatedAt":0}
                """
                .data(using: .utf8)!
        )

        entry.position = ReadingPosition(page: 5, fraction: 0.62)

        XCTAssertEqual(entry.page, 5)
        XCTAssertEqual(entry.fraction, 0.62)
    }
}
