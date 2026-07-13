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

}
