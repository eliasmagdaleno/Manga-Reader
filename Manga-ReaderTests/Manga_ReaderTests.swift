//
//  Manga_ReaderTests.swift
//  Manga-ReaderTests
//
//  Created by Elias Magdaleno on 5/31/24.
//

import XCTest
import UIKit
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

    private func sampleManga(_ id: String = "m1", sourceId: String = "mangadex") -> Manga {
        Manga(id: id, sourceId: sourceId, title: "Title \(id)", description: "", status: "ongoing", year: nil, coverURL: nil)
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

    @MainActor func testReadingEntryRecordsSourceId() {
        let store = makeHistoryStore()
        let manga = sampleManga("m", sourceId: "weebcentral")
        store.record(manga: manga, chapter: Chapter(id: "c1", number: "1", title: nil), page: 0, pageCount: 5)
        XCTAssertEqual(store.entries.first?.sourceId, "weebcentral")
    }

    func testReadingEntryDecodesLegacyJSONAsNil() throws {
        // JSON saved before sourceId existed.
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000000","mangaId":"m","mangaTitle":"T","coverURL":null,"chapterId":"c","chapterNumber":"1","page":0,"pageCount":5,"updatedAt":0}"#
            .data(using: .utf8)!
        let entry = try JSONDecoder().decode(ReadingEntry.self, from: legacy)
        XCTAssertNil(entry.sourceId)
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

    func testUnreadCountNilChapterNumbersIsZero() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: nil)
        XCTAssertEqual(item.unreadCount(readNumbers: []), 0)
    }

    func testUnreadCountWithNoneReadCountsAll() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2", "3"])
        XCTAssertEqual(item.unreadCount(readNumbers: []), 3)
    }

    func testUnreadCountExcludesReadNumbers() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2", "3"])
        XCTAssertEqual(item.unreadCount(readNumbers: ["2"]), 2)
    }

    func testUnreadCountAllReadIsZero() {
        let item = LibraryItem(id: "m1", title: "T", coverURL: nil, chapterNumbers: ["1", "2"])
        XCTAssertEqual(item.unreadCount(readNumbers: ["1", "2"]), 0)
    }

    @MainActor func testReadChapterNumbersForManga() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga("m"), chapter: Chapter(id: "c1", number: "1", title: nil), page: 1, pageCount: 5)
        store.record(manga: sampleManga("m"), chapter: Chapter(id: "c2", number: "2", title: nil), page: 1, pageCount: 5)
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["1", "2"])
        XCTAssertTrue(store.readChapterNumbers(forManga: "other").isEmpty)
    }

    // MARK: - Read / unread marks

    @MainActor func testOpenedChapterCountsAsRead() throws {
        let store = makeHistoryStore()
        store.record(manga: sampleManga("m"), chapter: Chapter(id: "c1", number: "1", title: nil), page: 0, pageCount: 5)
        XCTAssertTrue(store.isRead(chapterId: "c1"))       // has a history entry → read
        XCTAssertFalse(store.isRead(chapterId: "c2"))
    }

    @MainActor func testMarkReadWithoutOpening() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "3", title: nil)
        XCTAssertFalse(store.isRead(chapterId: "c1"))
        store.markRead(manga: sampleManga("m"), chapter: chapter)
        XCTAssertTrue(store.isRead(chapterId: "c1"))
        // Manual mark contributes to the shared read-numbers set (badge reconciliation).
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["3"])
        // ...but never pollutes the chronological reading log.
        XCTAssertTrue(store.entries.isEmpty)
    }

    @MainActor func testMarkReadIsIdempotent() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.markRead(manga: sampleManga("m"), chapter: chapter)
        store.markRead(manga: sampleManga("m"), chapter: chapter)
        XCTAssertEqual(store.readMarks.count, 1)
    }

    @MainActor func testMarkUnreadClearsBothMarkAndHistory() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.record(manga: sampleManga("m"), chapter: chapter, page: 2, pageCount: 5) // opened
        store.markRead(manga: sampleManga("m"), chapter: chapter)                       // and marked
        XCTAssertTrue(store.isRead(chapterId: "c1"))

        store.markUnread(manga: sampleManga("m"), chapter: chapter)
        XCTAssertFalse(store.isRead(chapterId: "c1"))                 // no longer read
        XCTAssertTrue(store.entries.isEmpty)                          // history entry removed
        XCTAssertTrue(store.readChapterNumbers(forManga: "m").isEmpty)
    }

    @MainActor func testToggleReadRoundTrips() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.toggleRead(manga: sampleManga("m"), chapter: chapter)
        XCTAssertTrue(store.isRead(chapterId: "c1"))
        store.toggleRead(manga: sampleManga("m"), chapter: chapter)
        XCTAssertFalse(store.isRead(chapterId: "c1"))
    }

    @MainActor func testMarkReadBatchMarksAllGivenChapters() throws {
        let store = makeHistoryStore()
        let chapters = [Chapter(id: "c1", number: "1", title: nil), Chapter(id: "c2", number: "2", title: nil)]
        store.markRead(manga: sampleManga("m"), chapters: chapters)
        XCTAssertTrue(store.isRead(chapterId: "c1"))
        XCTAssertTrue(store.isRead(chapterId: "c2"))
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["1", "2"])
    }

    @MainActor func testMarkReadBatchIsIdempotent() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.markRead(manga: sampleManga("m"), chapters: [chapter])
        store.markRead(manga: sampleManga("m"), chapters: [chapter])
        XCTAssertEqual(store.readMarks.count, 1)
    }

    @MainActor func testMarkReadBatchIsIdempotentWithinSingleCallDuplicates() throws {
        let store = makeHistoryStore()
        let chapter = Chapter(id: "c1", number: "1", title: nil)
        store.markRead(manga: sampleManga("m"), chapters: [chapter, chapter])
        XCTAssertEqual(store.readMarks.count, 1)
    }

    @MainActor func testMarkUnreadBatchClearsOnlyGivenChapters() throws {
        let store = makeHistoryStore()
        let manga = sampleManga("m")
        let c1 = Chapter(id: "c1", number: "1", title: nil)
        let c2 = Chapter(id: "c2", number: "2", title: nil)
        let c3 = Chapter(id: "c3", number: "3", title: nil)
        store.record(manga: manga, chapter: c1, page: 2, pageCount: 5)  // opened
        store.markRead(manga: manga, chapter: c2)                       // manually marked
        store.markRead(manga: manga, chapter: c3)                       // manually marked, untouched below

        store.markUnread(manga: manga, chapters: [c1, c2])
        XCTAssertFalse(store.isRead(chapterId: "c1"))
        XCTAssertFalse(store.isRead(chapterId: "c2"))
        XCTAssertTrue(store.isRead(chapterId: "c3"))                    // not in the batch, stays read
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.readChapterNumbers(forManga: "m"), ["3"])
    }

    @MainActor func testReadMarksPersistAcrossReload() throws {
        let suite = UserDefaults(suiteName: "test.history.\(UUID().uuidString)")!
        let store = HistoryStore(defaults: suite)
        store.markRead(manga: sampleManga("m"), chapter: Chapter(id: "c1", number: "7", title: nil))

        let reloaded = HistoryStore(defaults: suite)
        XCTAssertTrue(reloaded.isRead(chapterId: "c1"))
        XCTAssertEqual(reloaded.readChapterNumbers(forManga: "m"), ["7"])
    }

    func testLibraryItemDecodesLegacyJSON() throws {
        // JSON saved before chapterNumbers existed (pre-migration installs).
        let legacy = #"{"id":"m1","title":"Old","coverURL":null}"#.data(using: .utf8)!
        let item = try JSONDecoder().decode(LibraryItem.self, from: legacy)
        XCTAssertEqual(item.id, "m1")
        XCTAssertNil(item.chapterNumbers)
        XCTAssertEqual(item.unreadCount(readNumbers: []), 0)
    }

    // MARK: - Source abstraction

    /// Minimal in-memory `MangaSource` proving the protocol is mockable / bridge-friendly.
    private struct MockSource: MangaSource {
        let id: String
        let name: String
        var detail: MangaDetail = MangaDetail(description: "d", authors: ["A"], tags: ["T"], contentRating: "safe")
        var stubChapters: [Chapter] = [Chapter(id: "c1", number: "1", title: nil)]
        var stubManga: [Manga] = []

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func newTitles(limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func latestUpdates(limitTitles: Int, language: String) async throws -> [MangaUpdate] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail { detail }
        func chapters(mangaId: String) async throws -> [Chapter] { stubChapters }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    /// A source that omits the optional feed capabilities to exercise the default impls.
    private struct MinimalSource: MangaSource {
        let id = "minimal"
        let name = "Minimal"
        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    @MainActor func testRegistryResolvesActiveAndByID() {
        let a = MockSource(id: "a", name: "A")
        let b = MockSource(id: "b", name: "B")
        let registry = SourceRegistry(sources: [a, b])

        XCTAssertEqual(registry.active.id, "a")               // first source is active by default
        XCTAssertEqual(registry.source(id: "b")?.id, "b")     // lookup by id
        XCTAssertNil(registry.source(id: "nope"))             // unknown id → nil

        registry.activeSourceID = "b"
        XCTAssertEqual(registry.active.id, "b")               // switching active source works
    }

    @MainActor func testRegistryActiveFallsBackWhenActiveIDMissing() {
        let registry = SourceRegistry(sources: [MockSource(id: "only", name: "Only")])
        registry.activeSourceID = "ghost"                     // point at a non-existent source
        XCTAssertEqual(registry.active.id, "only")            // still resolves to the first source
    }

    @MainActor func testRegistrySourceForMangaUsesSourceId() {
        let a = MockSource(id: "a", name: "A")
        let b = MockSource(id: "b", name: "B")
        let registry = SourceRegistry(sources: [a, b])
        let manga = Manga(id: "x", sourceId: "b", title: "T", description: "", status: "ongoing", year: nil, coverURL: nil)
        XCTAssertEqual(registry.source(for: manga).id, "b")   // resolves to the manga's own source
    }

    @MainActor func testDetailViewModelLoadsThroughInjectedSource() async {
        let source = MockSource(
            id: "mock", name: "Mock",
            detail: MangaDetail(description: "desc", authors: ["Author"], tags: ["Tag"], contentRating: "safe"),
            stubChapters: [Chapter(id: "c1", number: "1", title: "One"),
                           Chapter(id: "c2", number: "2", title: nil)]
        )
        let manga = sampleManga("m", sourceId: "mock")
        let vm = MangaDetailViewModel(manga: manga, source: source)

        await vm.loadAsync()

        XCTAssertEqual(vm.description, "desc")
        XCTAssertEqual(vm.authors, ["Author"])
        XCTAssertEqual(vm.tags, ["Tag"])
        XCTAssertEqual(vm.contentRating, "safe")
        XCTAssertEqual(vm.chapters.map(\.id), ["c1", "c2"])
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
    }

    func testUnsupportedFeedCapabilityThrows() async {
        let source = MinimalSource()
        do {
            _ = try await source.newTitles(limit: 10, offset: 0)
            XCTFail("newTitles should be unsupported on MinimalSource")
        } catch let SourceError.unsupported(capability) {
            XCTAssertEqual(capability, "newTitles")
        } catch {
            XCTFail("Expected SourceError.unsupported, got \(error)")
        }
    }

    func testMangaDexSourceIsNotNSFWByDefault() {
        XCTAssertFalse(MangaDexSource().isNSFW)
    }

    func testSourceCanDeclareNSFW() {
        struct AdultMock: MangaSource {
            let id = "adult"; let name = "Adult"
            var isNSFW: Bool { true }
            func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
            func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
            func mangaDetail(id: String) async throws -> MangaDetail {
                MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
            }
            func chapters(mangaId: String) async throws -> [Chapter] { [] }
            func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
        }
        XCTAssertTrue(AdultMock().isNSFW)
    }

    func testMangaDexDecodeStampsSourceId() throws {
        // A /manga list entry decoded exactly as the API layer does it must carry the
        // MangaDex source id so downstream source resolution works.
        let json = #"""
        {"data":[{"id":"abc","attributes":{"title":{"en":"Berserk"},"description":{"en":"d"},"status":"ongoing","year":1989},"relationships":[]}]}
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let res = try decoder.decode(MangaListResponse.self, from: json)
        let manga = res.data[0].attributes.toManga(id: res.data[0].id, relationships: res.data[0].relationships)

        XCTAssertEqual(manga.id, "abc")
        XCTAssertEqual(manga.sourceId, "mangadex")
        XCTAssertEqual(manga.sourceId, MangaDexSource.sourceID)
    }

    // MARK: - Image cache

    /// Thread-safe call counter for the injected fetcher.
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
        func bump() { lock.lock(); _count += 1; lock.unlock() }
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("imgcache-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @MainActor private func tinyPNG(_ color: UIColor = .red) -> Data {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2))
        return r.pngData { ctx in color.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
    }

    @MainActor func testLoadImageFetchesOnceThenServesFromMemory() async {
        let png = tinyPNG()
        let counter = CallCounter()
        let cache = ImageCache(directory: makeTempDir(), fetcher: { _ in counter.bump(); return png })
        let url = URL(string: "https://example.com/p1.png")!

        let first = await cache.loadImage(for: url)        // network
        XCTAssertNotNil(first)
        XCTAssertEqual(counter.count, 1)
        let second = await cache.loadImage(for: url)       // memory hit
        XCTAssertNotNil(second)
        XCTAssertEqual(counter.count, 1)
    }

    @MainActor func testDiskPersistsAcrossInstancesWithoutRefetch() async {
        let dir = makeTempDir()
        let png = tinyPNG()
        let url = URL(string: "https://example.com/p2.png")!

        let c1 = CallCounter()
        let cache1 = ImageCache(directory: dir, fetcher: { _ in c1.bump(); return png })
        _ = await cache1.loadImage(for: url)               // network → disk
        XCTAssertEqual(c1.count, 1)

        let c2 = CallCounter()
        let cache2 = ImageCache(directory: dir, fetcher: { _ in c2.bump(); return png }) // fresh memory, same disk
        let hit = await cache2.loadImage(for: url)         // disk hit
        XCTAssertNotNil(hit)
        XCTAssertEqual(c2.count, 0)                        // no network
    }

    func testKeyIsStableAndURLSpecific() {
        let u1 = URL(string: "https://example.com/a.png")!
        let u2 = URL(string: "https://example.com/b.png")!
        XCTAssertEqual(ImageCache.key(for: u1), ImageCache.key(for: u1))
        XCTAssertNotEqual(ImageCache.key(for: u1), ImageCache.key(for: u2))
        XCTAssertEqual(ImageCache.key(for: u1).count, 64)  // sha256 hex length
    }

    func testDiskTrimEnforcesCap() async {
        let disk = ImageDiskCache(directory: makeTempDir(), maxBytes: 1000)
        await disk.store(Data(count: 400), for: "a")
        await disk.store(Data(count: 400), for: "b")
        await disk.store(Data(count: 400), for: "c")       // 1200 > cap
        var total = await disk.totalBytes()
        XCTAssertEqual(total, 1200)
        await disk.trim()
        total = await disk.totalBytes()
        XCTAssertLessThanOrEqual(total, 800)               // trimmed to <= 80% of cap
    }

    func testDiskClearRemovesFiles() async {
        let disk = ImageDiskCache(directory: makeTempDir(), maxBytes: 1000)
        await disk.store(Data(count: 100), for: "x")
        var present = await disk.has("x")
        XCTAssertTrue(present)
        await disk.clear()
        present = await disk.has("x")
        XCTAssertFalse(present)
    }

    @MainActor func testClearEmptiesMemory() async {
        let png = tinyPNG()
        let cache = ImageCache(directory: makeTempDir(), fetcher: { _ in png })
        let url = URL(string: "https://example.com/p3.png")!
        _ = await cache.loadImage(for: url)
        XCTAssertNotNil(cache.image(for: url))
        cache.clear()
        XCTAssertNil(cache.image(for: url))
    }

    @MainActor func testPrefetchWarmsAllURLsAndDedupes() async {
        let png = tinyPNG()
        let counter = CallCounter()
        let cache = ImageCache(directory: makeTempDir(), fetcher: { _ in counter.bump(); return png })
        let urls = (0..<8).map { URL(string: "https://example.com/pf\($0).png")! }

        await cache.prefetchAwaitable(urls)
        for u in urls { XCTAssertNotNil(cache.image(for: u)) }
        XCTAssertEqual(counter.count, 8)

        await cache.prefetchAwaitable(urls)                // all cached now
        XCTAssertEqual(counter.count, 8)                   // no new fetches
    }

}
