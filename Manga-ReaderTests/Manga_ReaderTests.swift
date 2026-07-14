//
//  Manga_ReaderTests.swift
//  Manga-ReaderTests
//
//  Created by Elias Magdaleno on 5/31/24.
//

import XCTest
@testable import Manga_Reader

final class Manga_ReaderTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

    // MARK: - HistoryStore

    @MainActor
    private func makeHistoryStore() -> HistoryStore {
        let suite = UserDefaults(suiteName: "test.history.\(UUID().uuidString)")!
        return HistoryStore(defaults: suite)
    }

    private func sampleManga(_ id: String = "m1") -> Manga {
        Manga(id: id, title: "Title \(id)", description: "", status: "ongoing", year: nil, coverURL: nil)
    }

    @MainActor func testRecordPrependsNewEntry() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 2, pageCount: 10)
        store.record(manga: sampleManga(), chapter: Chapter(id: "c2", number: "2", title: nil), page: 0, pageCount: 8)
        XCTAssertEqual(store.entries.count, 2)
        XCTAssertEqual(store.entries.first?.chapterId, "c2") // most-recent-first
    }

    @MainActor func testRecordSameChapterUpdatesInPlace() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 2, pageCount: 10)
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 5, pageCount: 10)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.page, 5)
    }

    @MainActor func testRecordNonConsecutiveChapterCreatesNewEntry() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
        store.record(manga: sampleManga(), chapter: Chapter(id: "c2", number: "2", title: nil), page: 1, pageCount: 10)
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 3, pageCount: 10) // reopened later
        XCTAssertEqual(store.entries.count, 3)          // new session, not an in-place update
        XCTAssertEqual(store.entries.first?.chapterId, "c1")
        XCTAssertEqual(store.entries.first?.page, 3)
    }

    @MainActor func testLatestEntryForManga() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga("a"), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
        store.record(manga: sampleManga("b"), chapter: Chapter(id: "c2", number: "1", title: nil), page: 1, pageCount: 10)
        XCTAssertEqual(store.latestEntry(forManga: "a")?.chapterId, "c1")
        XCTAssertNil(store.latestEntry(forManga: "zzz"))
    }

    @MainActor func testDeleteAndClear() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
        let entry = store.entries[0]
        store.delete(entry)
        XCTAssertTrue(store.entries.isEmpty)
        store.record(manga: sampleManga(), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 10)
        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    // MARK: - Chapter ordering & resume

    private func ch(_ n: String, _ id: String? = nil) -> Chapter {
        Chapter(id: id ?? "id\(n)", number: n, title: nil)
    }

    func testNumericChapterValue() {
        XCTAssertEqual(numericChapterValue("10.5"), 10.5)
        XCTAssertNil(numericChapterValue("?"))
    }

    func testSortChaptersNumeric() {
        let input = [ch("2"), ch("10"), ch("1"), ch("10.5"), ch("?")]
        let asc = sortChapters(input, descending: false).map(\.number)
        XCTAssertEqual(asc, ["1", "2", "10", "10.5", "?"])   // unparseable sorts last
        let desc = sortChapters(input, descending: true).map(\.number)
        XCTAssertEqual(desc, ["10.5", "10", "2", "1", "?"])  // unparseable still last
    }

    func testNextChapter() {
        let asc = [ch("1"), ch("2"), ch("3")]
        XCTAssertEqual(nextChapter(after: "2", in: asc)?.number, "3")
        XCTAssertNil(nextChapter(after: "3", in: asc))
    }

    func testResumeActionNoHistory() {
        let action = resumeAction(entry: nil, chapters: [ch("2"), ch("1")])
        XCTAssertEqual(action, .start(ch("1")))
    }

    func testResumeActionMidChapter() {
        let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                                 chapterId: "id2", chapterNumber: "2", page: 3, pageCount: 10, updatedAt: Date())
        XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                       .cont(ch("2"), page: 3))
    }

    func testResumeActionFinishedJumpsToNext() {
        let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                                 chapterId: "id2", chapterNumber: "2", page: 9, pageCount: 10, updatedAt: Date())
        XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                       .next(ch("3")))
    }

    func testResumeActionFinishedLatestRereads() {
        let entry = ReadingEntry(id: UUID(), mangaId: "m", mangaTitle: "t", coverURL: nil,
                                 chapterId: "id3", chapterNumber: "3", page: 9, pageCount: 10, updatedAt: Date())
        XCTAssertEqual(resumeAction(entry: entry, chapters: [ch("1"), ch("2"), ch("3")]),
                       .reread(ch("3"), page: 9))
    }

    // MARK: - Library updates

    func testNewChapterCountCountsNewerDistinct() {
        let recent = [
            RecentChapter(id: "a", number: "12", readableAt: "2026-07-13T00:00:00Z"),
            RecentChapter(id: "b", number: "12", readableAt: "2026-07-12T00:00:00Z"), // dup number
            RecentChapter(id: "c", number: "11", readableAt: "2026-07-11T00:00:00Z"),
            RecentChapter(id: "d", number: "10", readableAt: "2026-07-01T00:00:00Z"),
        ]
        // baseline just after ch10 -> ch11 and ch12 are new (distinct) = 2
        XCTAssertEqual(newChapterCount(recent, since: "2026-07-05T00:00:00Z"), 2)
    }

    func testNewChapterCountNilBaselineCountsAllDistinct() {
        let recent = [
            RecentChapter(id: "a", number: "2", readableAt: "2026-07-13T00:00:00Z"),
            RecentChapter(id: "b", number: "1", readableAt: "2026-07-12T00:00:00Z"),
        ]
        XCTAssertEqual(newChapterCount(recent, since: nil), 2)
    }

    func testNewChapterCountExcludesReadNumbers() {
        let recent = [
            RecentChapter(id: "a", number: "12", readableAt: "2026-07-13T00:00:00Z"),
            RecentChapter(id: "c", number: "11", readableAt: "2026-07-11T00:00:00Z"),
        ]
        // Both newer than baseline, but ch 12 already read → only ch 11 counts as new.
        XCTAssertEqual(
            newChapterCount(recent, since: "2026-07-05T00:00:00Z", excludingNumbers: ["12"]),
            1)
    }

    @MainActor func testReadChapterNumbersForManga() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga("m"), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 5)
        store.record(manga: sampleManga("m"), chapter: Chapter(id: "c2", number: "2", title: nil), page: 1, pageCount: 5)
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["1", "2"])
        XCTAssertTrue(store.readChapterNumbers(forManga: "other").isEmpty)
    }

    func testLibraryItemDecodesLegacyJSON() throws {
        // JSON saved before the update-tracking fields existed.
        let legacy = #"{"id":"m1","title":"Old","coverURL":null}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(LibraryItem.self, from: legacy)
        XCTAssertEqual(item.id, "m1")
        XCTAssertNil(item.newChapterCount)
        XCTAssertNil(item.lastSeenReadableAt)
    }

}
