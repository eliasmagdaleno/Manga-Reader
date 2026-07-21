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

    @MainActor func testLibraryToggleRecordsSourceId() {
        let suite = UserDefaults(suiteName: "test.library.\(UUID().uuidString)")!
        let store = LibraryStore(defaults: suite)
        let manga = sampleManga("m", sourceId: "weebcentral")
        store.toggle(manga)
        XCTAssertEqual(store.items.first?.sourceId, "weebcentral")
    }

    func testLibraryItemRoundTripsSourceId() throws {
        let item = LibraryItem(id: "m", title: "T", coverURL: nil, sourceId: "weebcentral")
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(LibraryItem.self, from: data)
        XCTAssertEqual(decoded.sourceId, "weebcentral")
    }

    // MARK: - Source abstraction

    /// Minimal in-memory `MangaSource` proving the protocol is mockable / bridge-friendly.
    private struct MockSource: MangaSource {
        let id: String
        let name: String
        var detail: MangaDetail = MangaDetail(description: "d", authors: ["A"], tags: [], contentRating: "safe")
        var stubChapters: [Chapter] = [Chapter(id: "c1", number: "1", title: nil)]
        var stubManga: [Manga] = []

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func newTitles(limit: Int, offset: Int) async throws -> [Manga] { stubManga }
        func latestUpdates(limitTitles: Int, language: String, offset: Int) async throws -> [MangaUpdate] { [] }
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
            detail: MangaDetail(description: "desc", authors: ["Author"], tags: [Tag(id: "t1", name: "Action", group: "genre")], contentRating: "safe"),
            stubChapters: [Chapter(id: "c1", number: "1", title: "One"),
                           Chapter(id: "c2", number: "2", title: nil)]
        )
        let manga = sampleManga("m", sourceId: "mock")
        let vm = MangaDetailViewModel(manga: manga, source: source)

        await vm.loadAsync()

        XCTAssertEqual(vm.description, "desc")
        XCTAssertEqual(vm.authors, ["Author"])
        XCTAssertEqual(vm.tags, ["Action"])
        XCTAssertEqual(vm.detailTags, [Tag(id: "t1", name: "Action", group: "genre")])
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

    @MainActor func testVisibleSourcesRespectAdultToggle() {
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
        let registry = SourceRegistry(sources: [MangaDexSource(), AdultMock()])

        XCTAssertEqual(registry.visibleSources(includeAdult: false).map(\.id), ["mangadex"])
        XCTAssertEqual(registry.visibleSources(includeAdult: true).map(\.id), ["mangadex", "adult"])
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
    private final class SyncCallCounter: @unchecked Sendable {
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
        let counter = SyncCallCounter()
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

        let c1 = SyncCallCounter()
        let cache1 = ImageCache(directory: dir, fetcher: { _ in c1.bump(); return png })
        _ = await cache1.loadImage(for: url)               // network → disk
        XCTAssertEqual(c1.count, 1)

        let c2 = SyncCallCounter()
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
        let counter = SyncCallCounter()
        let cache = ImageCache(directory: makeTempDir(), fetcher: { _ in counter.bump(); return png })
        let urls = (0..<8).map { URL(string: "https://example.com/pf\($0).png")! }

        await cache.prefetchAwaitable(urls)
        for u in urls { XCTAssertNotNil(cache.image(for: u)) }
        XCTAssertEqual(counter.count, 8)

        await cache.prefetchAwaitable(urls)                // all cached now
        XCTAssertEqual(counter.count, 8)                   // no new fetches
    }

    // MARK: - Image rate-limit backoff (Phase 3)

    /// Serial call counter for injected fetchers.
    private actor CallCounter {
        private(set) var count = 0
        func next() -> Int { defer { count += 1 }; return count }
    }

    private func onePixelPNGData() -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.pngData { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }

    private func tempCacheDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("imgcache-\(UUID().uuidString)")
    }

    func testImageBackoffDelayDoublesPerAttempt() {
        XCTAssertEqual(ImageCache.imageBackoffDelay(attempt: 0, base: 0.5), 0.5, accuracy: 0.0001)
        XCTAssertEqual(ImageCache.imageBackoffDelay(attempt: 1, base: 0.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(ImageCache.imageBackoffDelay(attempt: 2, base: 0.5), 2.0, accuracy: 0.0001)
    }

    func testImageCacheRetriesAfterRateLimitThenSucceeds() async {
        let png = onePixelPNGData()
        let counter = CallCounter()
        let cache = ImageCache(directory: tempCacheDir(), retryBaseDelay: 0, maxImageRetries: 2,
                               fetcher: { _ in
            let n = await counter.next()
            if n == 0 { throw ImageFetchError.rateLimited }
            return png
        })
        let img = await cache.loadImage(for: URL(string: "https://i.example/1.jpg")!)
        XCTAssertNotNil(img)
        let calls = await counter.count
        XCTAssertEqual(calls, 2)   // first attempt rate-limited, retry succeeded
    }

    func testImageCacheGivesUpAfterMaxRetries() async {
        let cache = ImageCache(directory: tempCacheDir(), retryBaseDelay: 0, maxImageRetries: 2,
                               fetcher: { _ in throw ImageFetchError.rateLimited })
        let img = await cache.loadImage(for: URL(string: "https://i.example/2.jpg")!)
        XCTAssertNil(img)
    }

    // MARK: - Per-source prefetch hint (Phase 3)

    private actor FetchedURLs {
        private(set) var urls: [URL] = []
        func add(_ u: URL) { urls.append(u) }
        var count: Int { urls.count }
    }

    func testDefaultImagePrefetchConcurrencyIsFive() {
        XCTAssertEqual(MangaDexSource().imagePrefetchConcurrency, 5)
    }

    func testPrefetchWithConcurrencyCapStillLoadsEveryURL() async {
        let png = onePixelPNGData()
        let fetched = FetchedURLs()
        let cache = ImageCache(directory: tempCacheDir(), fetcher: { url in
            await fetched.add(url); return png
        })
        let urls = (1...6).map { URL(string: "https://i.example/\($0).jpg")! }
        await cache.prefetchAwaitable(urls, maxConcurrent: 2)
        let count = await fetched.count
        XCTAssertEqual(count, 6)
    }

    // MARK: - Source-layer contract (Phase 2)

    func testSourceErrorWebViewCasesHaveDescriptions() {
        XCTAssertEqual(SourceError.cloudflareUnsolved.errorDescription,
                       "Cloudflare verification wasn't completed.")
        XCTAssertEqual(SourceError.navigationFailed("timeout").errorDescription,
                       "Couldn't load the page: timeout")
        XCTAssertEqual(SourceError.extractionFailed("bad JSON").errorDescription,
                       "Couldn't read the page: bad JSON")
    }

    /// Reference box so a value-type source can record what it was called with.
    private final class OffsetBox: @unchecked Sendable { var seen: [Int] = [] }

    /// A source that omits `latestUpdates` still reports it as unsupported through the
    /// offset-bearing signature.
    func testMinimalSourceLatestUpdatesStillUnsupportedWithOffset() async {
        do {
            _ = try await MinimalSource().latestUpdates(limitTitles: 10, language: "en", offset: 24)
            XCTFail("expected .unsupported")
        } catch let error as SourceError {
            guard case .unsupported(let capability) = error else {
                return XCTFail("expected .unsupported, got \(error)")
            }
            XCTAssertEqual(capability, "latestUpdates")
        } catch {
            XCTFail("expected SourceError, got \(error)")
        }
    }

    /// The two-arg convenience must forward offset 0, so existing Home/rail callers keep
    /// getting the top of the feed.
    func testLatestUpdatesConvenienceForwardsZeroOffset() async throws {
        struct OffsetRecordingSource: MangaSource {
            let id = "offrec"
            let name = "OffRec"
            let box: OffsetBox
            func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
            func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
            func latestUpdates(limitTitles: Int, language: String, offset: Int) async throws -> [MangaUpdate] {
                box.seen.append(offset)
                return []
            }
            func mangaDetail(id: String) async throws -> MangaDetail {
                MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
            }
            func chapters(mangaId: String) async throws -> [Chapter] { [] }
            func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
        }

        let box = OffsetBox()
        let source: any MangaSource = OffsetRecordingSource(box: box)
        _ = try await source.latestUpdates(limitTitles: 20, language: "en")
        _ = try await source.latestUpdates(limitTitles: 20, language: "en", offset: 48)
        XCTAssertEqual(box.seen, [0, 48])
    }

    // MARK: - WeebCentralSource (Phase 2)

    /// Canned-response fake for the WebView seam: returns fixture JSON per URL and
    /// records what was requested, so tests cover URL building + DTO→domain mapping.
    @MainActor
    private final class MockWebView: WebViewExtracting {
        var responses: [String: String] = [:]           // URL absoluteString → JSON
        private(set) var requestedURLs: [URL] = []

        func extract<T: Decodable>(from url: URL, script: String, as type: T.Type) async throws -> T {
            requestedURLs.append(url)
            guard let json = responses[url.absoluteString] else {
                throw SourceError.extractionFailed("no canned response for \(url.absoluteString)")
            }
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }
    }

    @MainActor
    private func makeWeebCentral() -> (WeebCentralSource, MockWebView) {
        let mock = MockWebView()
        return (WeebCentralSource(context: SourceContext(webView: mock)), mock)
    }

    @MainActor func testWeebCentralIdentity() {
        let (source, _) = makeWeebCentral()
        XCTAssertEqual(source.id, "weebcentral")
        XCTAssertEqual(source.name, "WeebCentral")
        XCTAssertFalse(source.isNSFW)
    }

    @MainActor func testWeebCentralSearchBuildsURLAndMapsManga() async throws {
        let (source, mock) = makeWeebCentral()
        let expected = "https://weebcentral.com/search/data?sort=Best%20Match&display_mode=Full%20Display&limit=20&offset=0&text=Naruto"
        mock.responses[expected] = #"""
        [{"id": "01J76XYZ", "title": "Naruto", "cover": "https://temp.compsci88.com/cover/naruto.webp"},
         {"id": "01J76ABC", "title": "Boruto", "cover": null}]
        """#
        let results = try await source.search(title: "Naruto", limit: 20, offset: 0)
        XCTAssertEqual(mock.requestedURLs.first?.absoluteString, expected)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].id, "01J76XYZ")
        XCTAssertEqual(results[0].sourceId, "weebcentral")
        XCTAssertEqual(results[0].title, "Naruto")
        XCTAssertEqual(results[0].coverURL?.absoluteString, "https://temp.compsci88.com/cover/naruto.webp")
        XCTAssertNil(results[1].coverURL)
    }

    @MainActor func testWeebCentralPopularAndNewTitlesUseSortFeeds() async throws {
        let (source, mock) = makeWeebCentral()
        let popularURL = "https://weebcentral.com/search/data?sort=Popularity&display_mode=Full%20Display&limit=10&offset=5"
        let newURL = "https://weebcentral.com/search/data?sort=Recently%20Added&display_mode=Full%20Display&limit=10&offset=0"
        mock.responses[popularURL] = #"[{"id": "p1", "title": "Popular One", "cover": null}]"#
        mock.responses[newURL] = #"[{"id": "n1", "title": "New One", "cover": null}]"#
        let popular = try await source.popular(limit: 10, offset: 5)
        let new = try await source.newTitles(limit: 10, offset: 0)
        XCTAssertEqual(popular.first?.id, "p1")
        XCTAssertEqual(new.first?.id, "n1")
        XCTAssertEqual(new.first?.sourceId, "weebcentral")
    }

    @MainActor func testWeebCentralMangaDetailMapping() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ"] = #"""
        {"description": "A ninja story.", "authors": ["Masashi Kishimoto"],
         "tags": ["Action", "Adventure"], "adult": false}
        """#
        let detail = try await source.mangaDetail(id: "01J76XYZ")
        XCTAssertEqual(detail.description, "A ninja story.")
        XCTAssertEqual(detail.authors, ["Masashi Kishimoto"])
        XCTAssertEqual(detail.tags.map(\.name), ["Action", "Adventure"])
        XCTAssertEqual(detail.contentRating, "safe")
    }

    @MainActor func testWeebCentralChaptersMapping() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ/full-chapter-list"] = #"""
        [{"id": "chap3", "title": "Chapter 105"},
         {"id": "chap2", "title": "Special 3.5"},
         {"id": "chap1", "title": "Oneshot"}]
        """#
        let chapters = try await source.chapters(mangaId: "01J76XYZ")
        XCTAssertEqual(chapters.map(\.id), ["chap3", "chap2", "chap1"])
        XCTAssertEqual(chapters.map(\.number), ["105", "3.5", "?"])
        XCTAssertEqual(chapters[0].title, "Chapter 105")
    }

    // MARK: - Chapter date-added (WeebCentral)

    @MainActor func testWeebCentralChaptersCarryDate() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/series/01J76XYZ/full-chapter-list"] = #"""
        [{"id": "chap3", "title": "Chapter 105", "date": "2024-01-15T12:00:00Z"},
         {"id": "chap2", "title": "Chapter 104", "date": null}]
        """#
        let chapters = try await source.chapters(mangaId: "01J76XYZ")
        XCTAssertEqual(chapters[0].date, Chapter.parseISO8601("2024-01-15T12:00:00Z"))
        XCTAssertNil(chapters[1].date)
    }

    @MainActor func testWeebCentralPageURLs() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/chapters/chap3/images?reading_style=long_strip"] = #"""
        ["https://official.lowee.us/manga/x/0001.png", "https://official.lowee.us/manga/x/0002.png"]
        """#
        let pages = try await source.pageURLs(chapterId: "chap3", preferDataSaver: true)
        XCTAssertEqual(pages.map(\.absoluteString),
                       ["https://official.lowee.us/manga/x/0001.png",
                        "https://official.lowee.us/manga/x/0002.png"])
    }

    @MainActor func testWeebCentralLatestUpdates() async throws {
        let (source, mock) = makeWeebCentral()
        mock.responses["https://weebcentral.com/latest-updates/1"] = #"""
        [{"mangaId": "01J76XYZ", "chapterId": "chapZ", "title": "Naruto",
          "cover": "https://temp.compsci88.com/cover/naruto.webp"},
         {"mangaId": "01J76ABC", "chapterId": "chapY", "title": "Boruto", "cover": null}]
        """#
        let updates = try await source.latestUpdates(limitTitles: 1, language: "en")
        XCTAssertEqual(updates.count, 1)                 // truncated to limitTitles
        XCTAssertEqual(updates[0].chapterId, "chapZ")
        XCTAssertEqual(updates[0].manga.id, "01J76XYZ")
        XCTAssertEqual(updates[0].manga.sourceId, "weebcentral")
    }

    func testWeebCentralChapterNumberHelper() {
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Chapter 105"), "105")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Special 3.5"), "3.5")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Season 2 Chapter 12"), "12")
        XCTAssertEqual(WeebCentralSource.chapterNumber(fromTitle: "Oneshot"), "?")
    }

    // MARK: - Tag decode widening (recommendation engine)

    func testMangaDetailDecodesTagIdNameAndGroup() throws {
        let json = #"""
        {"data":{"id":"m1","type":"manga","attributes":{
            "title":{"en":"T"},"description":{"en":"d"},
            "tags":[{"id":"tag-uuid-1","type":"tag","attributes":{"name":{"en":"Action"},"group":"genre"}}],
            "content_rating":"safe"},
          "relationships":[]}}
        """#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(MangaDetailResponse.self, from: json).toDomain()
        XCTAssertEqual(detail.tags, [Tag(id: "tag-uuid-1", name: "Action", group: "genre")])
    }

    // MARK: - Default source registration (Phase 2)

    @MainActor func testDefaultRegistryContainsAllBuiltInSources() {
        let registry = SourceRegistry()
        XCTAssertEqual(registry.sources.map(\.id), ["mangadex", "weebcentral"])
        XCTAssertNotNil(registry.source(id: "weebcentral"))
        // WeebCentral is not adult content — visible without the adult toggle.
        XCTAssertTrue(registry.visibleSources(includeAdult: false).contains { $0.id == "weebcentral" })
    }

    @MainActor func testDisablingAdultToggleReSourcesAwayFromActiveAdultSource() {
        struct AdultMock: MangaSource {
            let id = "adult"; let name = "Adult"
            var isNSFW: Bool { true }
            func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
            func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
            func mangaDetail(id: String) async throws -> MangaDetail { MangaDetail(description: "", authors: [], tags: [], contentRating: nil) }
            func chapters(mangaId: String) async throws -> [Chapter] { [] }
            func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
        }
        let registry = SourceRegistry(sources: [MangaDexSource(), AdultMock()])
        registry.activeSourceID = "adult"
        registry.enforceAdultGating(includeAdult: false)
        XCTAssertEqual(registry.activeSourceID, "mangadex")   // fell back to the non-adult source
        registry.activeSourceID = "adult"
        registry.enforceAdultGating(includeAdult: true)
        XCTAssertEqual(registry.activeSourceID, "adult")      // no change while adult shown
    }

    // MARK: - Home source switching (Phase 2 addendum)

    @MainActor func testHomeViewModelInjectedSourceWins() {
        let vm = HomeViewModel(source: MockSource(id: "mock", name: "Mock"))
        XCTAssertEqual(vm.source.id, "mock")
    }

    /// A source whose FIRST popular() call suspends until the test lets it proceed;
    /// every later call returns `fresh` immediately. Two first-call behaviors:
    /// - `.parkUntilReleased` parks on a continuation that deliberately ignores task
    ///   cancellation, so a superseded load runs to completion *late* — exercising the
    ///   "stale task must never write" guard.
    /// - `.sleepCancellably` suspends in `Task.sleep`, which throws `CancellationError`
    ///   the moment the load is superseded — exercising the "cancellation is not a
    ///   user-facing error" path.
    private actor SupersededSource: MangaSource {
        enum FirstCallBehavior { case parkUntilReleased, sleepCancellably }

        nonisolated let id = "superseded"
        nonisolated let name = "Superseded"
        private let firstCall: FirstCallBehavior
        private let stale: [Manga]
        private let fresh: [Manga]
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var popularCalls = 0

        init(firstCall: FirstCallBehavior, stale: [Manga], fresh: [Manga]) {
            self.firstCall = firstCall
            self.stale = stale
            self.fresh = fresh
        }

        var isParked: Bool { gate != nil }
        func releaseGate() { gate?.resume(); gate = nil }

        func popular(limit: Int, offset: Int) async throws -> [Manga] {
            popularCalls += 1
            guard popularCalls == 1 else { return fresh }
            switch firstCall {
            case .parkUntilReleased:
                await withCheckedContinuation { gate = $0 } // cancellation-blind on purpose
            case .sleepCancellably:
                try await Task.sleep(nanoseconds: 3_600_000_000_000) // cancelled long before 1h
            }
            return stale
        }

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func newTitles(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func latestUpdates(limitTitles: Int, language: String, offset: Int) async throws -> [MangaUpdate] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    /// Polls an async condition until it holds or a 5s deadline expires.
    @MainActor private func waitUntil(_ what: String, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for \(what)")
    }

    @MainActor func testSupersededHomeLoadNeitherClobbersRailsNorSurfacesCancellation() async throws {
        let stale = [sampleManga("stale", sourceId: "superseded")]
        let fresh = [sampleManga("fresh", sourceId: "superseded")]

        // Phase A: the superseded load's fetch ignores cancellation and completes LATE —
        // it must not overwrite the rails the superseding load already populated.
        let sourceA = SupersededSource(firstCall: .parkUntilReleased, stale: stale, fresh: fresh)
        let vmA = HomeViewModel(source: sourceA)

        vmA.loadHome()                                    // load #1 parks inside popular()
        try await waitUntil("first load to park") { await sourceA.isParked }
        vmA.loadHome()                                    // load #2 supersedes #1, finishes fast
        try await waitUntil("fresh rails to land") { vmA.popular.map(\.id) == ["fresh"] }

        await sourceA.releaseGate()                       // late-complete the superseded load
        try await Task.sleep(nanoseconds: 200_000_000)    // give it time to (wrongly) write

        XCTAssertEqual(vmA.popular.map(\.id), ["fresh"])  // stale data must not clobber
        XCTAssertNil(vmA.errorMessage)
        XCTAssertFalse(vmA.isLoading)

        // Phase B: the superseded load's fetch IS cancellation-aware — the resulting
        // CancellationError must not surface as a user-facing errorMessage.
        let sourceB = SupersededSource(firstCall: .sleepCancellably, stale: stale, fresh: fresh)
        let vmB = HomeViewModel(source: sourceB)

        vmB.loadHome()                                    // load #1 suspends in Task.sleep
        try await waitUntil("first load to start") { await sourceB.popularCalls == 1 }
        vmB.loadHome()                                    // cancels #1 → sleep throws CancellationError
        try await waitUntil("fresh rails to land") { vmB.popular.map(\.id) == ["fresh"] }
        try await Task.sleep(nanoseconds: 200_000_000)    // let the cancelled load unwind

        XCTAssertNil(vmB.errorMessage)                    // cancellation is not an error
        XCTAssertEqual(vmB.popular.map(\.id), ["fresh"])
        XCTAssertFalse(vmB.isLoading)
    }

    // MARK: - Source web URLs (Phase 2 addendum)

    func testMangaDexWebURL() {
        XCTAssertEqual(MangaDexSource().webURL(forManga: "abc-123")?.absoluteString,
                       "https://mangadex.org/title/abc-123")
    }

    @MainActor func testWeebCentralWebURL() {
        let (source, _) = makeWeebCentral()
        XCTAssertEqual(source.webURL(forManga: "01J76XYZ")?.absoluteString,
                       "https://weebcentral.com/series/01J76XYZ")
    }

    func testWebURLDefaultsToNil() {
        XCTAssertNil(MockSource(id: "x", name: "X").webURL(forManga: "y"))
    }

    // MARK: - Chapter date-added (MangaDex)

    func testChapterParseISO8601() {
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00+00:00"))
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00.123+00:00"))  // fractional seconds
        XCTAssertNotNil(Chapter.parseISO8601("2024-01-15T12:00:00Z"))
        XCTAssertNil(Chapter.parseISO8601(nil))
        XCTAssertNil(Chapter.parseISO8601(""))
        XCTAssertNil(Chapter.parseISO8601("not a date"))
    }

    func testChapterDateDefaultsToNil() {
        XCTAssertNil(Chapter(id: "c1", number: "1", title: nil).date)   // existing call shape → nil
    }

    func testMangaDexToChapterUsesPublishAt() throws {
        let json = #"{"chapter":"12","title":"T","translatedLanguage":"en","publishAt":"2024-01-15T12:00:00+00:00","readableAt":"2024-01-16T12:00:00+00:00"}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attrs.toChapter(id: "c1").date, Chapter.parseISO8601("2024-01-15T12:00:00+00:00"))
    }

    func testMangaDexToChapterFallsBackToReadableAt() throws {
        let json = #"{"chapter":"12","title":null,"translatedLanguage":"en","publishAt":null,"readableAt":"2024-01-16T12:00:00+00:00"}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertEqual(attrs.toChapter(id: "c1").date, Chapter.parseISO8601("2024-01-16T12:00:00+00:00"))
    }

    func testMangaDexToChapterNilWhenNoTimestamps() throws {
        let json = #"{"chapter":"12","title":null,"translatedLanguage":"en","publishAt":null,"readableAt":null}"#
        let attrs = try JSONDecoder().decode(ChapterAttributes.self, from: Data(json.utf8))
        XCTAssertNil(attrs.toChapter(id: "c1").date)
    }

    // MARK: - PagedMangaLoader (search / genre pagination)

    /// A `MangaSource` that records its search calls and returns programmable pages —
    /// exercises `SearchViewModel`'s debounce / re-run wiring without a network.
    @MainActor
    private final class RecordingSource: MangaSource {
        nonisolated let id: String
        nonisolated let name: String
        private(set) var searchCalls: [(title: String, limit: Int, offset: Int)] = []
        private let pageProvider: (_ limit: Int, _ offset: Int) -> [Manga]

        init(id: String = "rec", name: String = "Rec",
             pageProvider: @escaping (_ limit: Int, _ offset: Int) -> [Manga]) {
            self.id = id
            self.name = name
            self.pageProvider = pageProvider
        }

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] {
            searchCalls.append((title, limit, offset))
            return pageProvider(limit, offset)
        }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    private enum LoaderTestError: Error { case boom }

    @MainActor func testLoaderFirstPageSetsHasMoreWhenFull() async throws {
        let loader = PagedMangaLoader(pageSize: 24)
        loader.load { limit, _ in (0..<limit).map { self.sampleManga("m\($0)") } }
        try await waitUntil("first page") { !loader.isLoading && loader.items.count == 24 }
        XCTAssertTrue(loader.hasMore)
    }

    /// A SHORT page must NOT end the feed. Latest-updates pages the chapter feed and
    /// dedupes chapters→manga, so a perfectly healthy page arrives well under `pageSize`.
    @MainActor func testLoaderPartialPageKeepsHasMore() async throws {
        let loader = PagedMangaLoader(pageSize: 24)
        loader.load { _, _ in (0..<10).map { self.sampleManga("m\($0)") } }
        try await waitUntil("partial page") { !loader.isLoading && loader.items.count == 10 }
        XCTAssertTrue(loader.hasMore)
    }

    /// Only a genuinely empty page ends the feed.
    @MainActor func testLoaderEmptyPageEndsFeed() async throws {
        let loader = PagedMangaLoader(pageSize: 24)
        loader.load { _, _ in [] }
        try await waitUntil("empty page") { !loader.isLoading }
        XCTAssertFalse(loader.hasMore)
        XCTAssertTrue(loader.items.isEmpty)
    }

    /// A page of nothing but already-seen ids means the source is cycling — also the end.
    @MainActor func testLoaderAllDuplicatePageEndsFeed() async throws {
        let loader = PagedMangaLoader(pageSize: 4)
        loader.load { limit, _ in (0..<limit).map { self.sampleManga("dup\($0)") } }
        try await waitUntil("page 1") { loader.items.count == 4 }
        loader.loadMoreIfNeeded(current: loader.items.last!)
        try await waitUntil("page 2 settled") { !loader.isLoadingMore }
        XCTAssertEqual(loader.items.count, 4)   // nothing new appended
        XCTAssertFalse(loader.hasMore)
    }

    @MainActor func testLoaderAdvancesOffsetByPageSizeRegardlessOfReturnedCount() async throws {
        let loader = PagedMangaLoader(pageSize: 24)
        var offsets: [Int] = []
        // Full pages keep hasMore true; unique ids per page so nothing is deduped away.
        loader.load { limit, offset in
            offsets.append(offset)
            return (0..<limit).map { self.sampleManga("m\(offset + $0)") }
        }
        try await waitUntil("page 1") { !loader.isLoading && loader.items.count == 24 }
        loader.loadMoreIfNeeded(current: loader.items.last!)
        try await waitUntil("page 2") { loader.items.count == 48 }
        loader.loadMoreIfNeeded(current: loader.items.last!)
        try await waitUntil("page 3") { loader.items.count == 72 }
        XCTAssertEqual(offsets, [0, 24, 48])   // constant step — the offset→page conversion contract
    }

    @MainActor func testLoaderDeduplicatesRepeatedIDsAcrossPages() async throws {
        let loader = PagedMangaLoader(pageSize: 24)
        // Page 2 overlaps page 1 by ids 12...23; only 12 of its entries are new.
        loader.load { limit, offset in
            let start = offset == 0 ? 0 : 12
            return (0..<limit).map { self.sampleManga("m\(start + $0)") }
        }
        try await waitUntil("page 1") { loader.items.count == 24 }
        loader.loadMoreIfNeeded(current: loader.items.last!)
        try await waitUntil("page 2 appended") { loader.items.count == 36 }
        XCTAssertEqual(Set(loader.items.map(\.id)).count, 36)   // no duplicate ids
    }

    @MainActor func testLoaderNewLoadSupersedesInFlightAndSwallowsCancellation() async throws {
        let loader = PagedMangaLoader(pageSize: 2)
        // First load parks in a long sleep; superseding it must cancel it cleanly.
        loader.load { _, _ in
            try await Task.sleep(nanoseconds: 3_600_000_000_000)
            return [self.sampleManga("stale")]
        }
        loader.load { _, _ in [self.sampleManga("fresh1"), self.sampleManga("fresh2")] }
        try await waitUntil("fresh landed") { loader.items.map(\.id) == ["fresh1", "fresh2"] }
        try await Task.sleep(nanoseconds: 150_000_000)   // give the cancelled load time to (wrongly) write
        XCTAssertEqual(loader.items.map(\.id), ["fresh1", "fresh2"])
        XCTAssertNil(loader.errorMessage)                // cancellation is not surfaced as an error
    }

    @MainActor func testLoaderErrorSetsThenClearsMessage() async throws {
        let loader = PagedMangaLoader(pageSize: 5)
        loader.load { _, _ in throw LoaderTestError.boom }
        try await waitUntil("error set") { loader.errorMessage != nil }
        XCTAssertTrue(loader.items.isEmpty)
        loader.load { _, _ in [self.sampleManga("ok")] }
        try await waitUntil("error cleared") { loader.errorMessage == nil && loader.items.map(\.id) == ["ok"] }
    }

    /// A transient failure on page one used to be terminal: `hasMore` stayed false and
    /// `CategoryGridView.loadedOnce` blocked any re-trigger, so one 429 killed the feed
    /// for the life of the view. `retry()` must recover it.
    @MainActor func testLoaderRetryRecoversFromFailedFirstPage() async throws {
        let loader = PagedMangaLoader(pageSize: 4)
        var shouldFail = true
        loader.load { limit, _ in
            if shouldFail { throw LoaderTestError.boom }
            return (0..<limit).map { self.sampleManga("m\($0)") }
        }
        try await waitUntil("first page failed") { loader.errorMessage != nil }
        XCTAssertTrue(loader.items.isEmpty)

        shouldFail = false
        loader.retry()
        try await waitUntil("retry succeeded") { loader.items.count == 4 }
        XCTAssertNil(loader.errorMessage)
        XCTAssertTrue(loader.hasMore)
    }

    /// `retry()` resumes the same feed at the current offset — it must not restart it or
    /// discard pages already loaded.
    @MainActor func testLoaderRetryResumesAtOffsetWithoutDiscardingItems() async throws {
        let loader = PagedMangaLoader(pageSize: 4)
        var offsets: [Int] = []
        var failNextPage = false
        loader.load { limit, offset in
            offsets.append(offset)
            if failNextPage { throw LoaderTestError.boom }
            return (0..<limit).map { self.sampleManga("m\(offset + $0)") }
        }
        try await waitUntil("page 1") { loader.items.count == 4 }

        failNextPage = true
        loader.loadMoreIfNeeded(current: loader.items.last!)
        try await waitUntil("page 2 failed") { loader.errorMessage != nil }
        XCTAssertEqual(loader.items.count, 4)   // page one survives the failure

        failNextPage = false
        loader.retry()
        try await waitUntil("page 2 recovered") { loader.items.count == 8 }
        XCTAssertEqual(offsets, [0, 4, 4])      // retried the SAME offset, didn't restart at 0
    }

    @MainActor func testLoaderRetryIsANoopWhileAFetchIsInFlight() async throws {
        let loader = PagedMangaLoader(pageSize: 2)
        var calls = 0
        loader.load { _, _ in
            calls += 1
            try await Task.sleep(nanoseconds: 200_000_000)
            return [self.sampleManga("a"), self.sampleManga("b")]
        }
        loader.retry()                                   // in flight — must be ignored
        try await waitUntil("page landed") { loader.items.count == 2 }
        XCTAssertEqual(calls, 1)
    }

    // MARK: - SearchViewModel

    @MainActor func testSearchDebouncesRapidQueriesToSingleFetch() async throws {
        let source = RecordingSource(pageProvider: { _, _ in [self.sampleManga("r")] })
        let vm = SearchViewModel(source: source, debounce: .milliseconds(50), pageSize: 24)
        vm.queryChanged("a")
        vm.queryChanged("ab")
        vm.queryChanged("abc")
        try await waitUntil("one search") { source.searchCalls.count == 1 }
        try await Task.sleep(nanoseconds: 120_000_000)   // no late extra calls
        XCTAssertEqual(source.searchCalls.count, 1)
        XCTAssertEqual(source.searchCalls.first?.title, "abc")
        XCTAssertTrue(vm.hasSearched)
    }

    @MainActor func testSearchBlankQueryClearsWithoutFetching() async throws {
        let source = RecordingSource(pageProvider: { _, _ in [self.sampleManga("x")] })
        let vm = SearchViewModel(source: source, debounce: .milliseconds(20))
        vm.queryChanged("   ")
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(source.searchCalls.count, 0)
        XCTAssertFalse(vm.hasSearched)
        XCTAssertTrue(vm.loader.items.isEmpty)
    }

    @MainActor func testSelectSourceRerunsPendingQuery() async throws {
        let source = RecordingSource(pageProvider: { _, _ in [self.sampleManga("r")] })
        let vm = SearchViewModel(source: source, debounce: .milliseconds(20))
        vm.queryChanged("hero")
        try await waitUntil("first search") { source.searchCalls.count == 1 }
        vm.selectSource(id: "someid")
        try await waitUntil("re-run") { source.searchCalls.count == 2 }
        XCTAssertEqual(vm.selectedSourceID, "someid")
        XCTAssertEqual(source.searchCalls.last?.title, "hero")
    }

    @MainActor func testRetryRerunsLastQuery() async throws {
        let source = RecordingSource(pageProvider: { _, _ in [self.sampleManga("r")] })
        let vm = SearchViewModel(source: source, debounce: .milliseconds(20))
        vm.queryChanged("hero")
        try await waitUntil("first search") { source.searchCalls.count == 1 }
        vm.retry()
        try await waitUntil("retry re-runs") { source.searchCalls.count == 2 }
        XCTAssertEqual(source.searchCalls.last?.title, "hero")
    }

    @MainActor func testRetryIsNoopWithoutAQuery() async throws {
        let source = RecordingSource(pageProvider: { _, _ in [] })
        let vm = SearchViewModel(source: source, debounce: .milliseconds(20))
        vm.retry()   // nothing searched yet
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(source.searchCalls.count, 0)
    }

    // MARK: - Tag browse capability (Feature B)

    func testTagBrowseDefaultsToUnsupported() async {
        let source = MinimalSource()
        XCTAssertFalse(source.supportsTagBrowse)
        do {
            _ = try await source.mangaByTag(tag: "romance", limit: 10, offset: 0)
            XCTFail("mangaByTag should be unsupported on MinimalSource")
        } catch let SourceError.unsupported(capability) {
            XCTAssertEqual(capability, "mangaByTag")
        } catch {
            XCTFail("Expected SourceError.unsupported, got \(error)")
        }
    }

    func testMangaDexSupportsTagBrowse() {
        XCTAssertTrue(MangaDexSource().supportsTagBrowse)
    }

    func testMangaDexTagCatalogResolvesNameCaseInsensitively() async throws {
        let entities = [
            MDTagEntity(id: "uuid-romance", attributes: MDTagAttributes(name: ["en": "Romance"], group: nil)),
            MDTagEntity(id: "uuid-comedy", attributes: MDTagAttributes(name: ["en": "Comedy"], group: nil))
        ]
        let catalog = MangaDexTagCatalog(fetchAll: { entities })
        let romanceLower = try await catalog.id(forName: "romance")
        let romanceUpper = try await catalog.id(forName: "ROMANCE")
        let unknown = try await catalog.id(forName: "Isekai")
        XCTAssertEqual(romanceLower, "uuid-romance")
        XCTAssertEqual(romanceUpper, "uuid-romance")   // case-insensitive
        XCTAssertNil(unknown)                          // unknown name → nil → empty result upstream
    }

    // MARK: - TasteProfileStore

    @MainActor private func makeTasteStore() -> TasteProfileStore {
        let suite = UserDefaults(suiteName: "test.taste.\(UUID().uuidString)")!
        return TasteProfileStore(defaults: suite)
    }

    @MainActor func testTasteStoreRecordsAndPersistsTags() throws {
        let suite = UserDefaults(suiteName: "test.taste.\(UUID().uuidString)")!
        let store = TasteProfileStore(defaults: suite)
        let tags = [Tag(id: "t1", name: "Action", group: "genre")]
        store.recordTags(mangaId: "m1", tags: tags)
        store.markNotInterested(mangaId: "m2")
        store.markMoreLikeThis(mangaId: "m3")

        let reloaded = TasteProfileStore(defaults: suite)   // fresh instance, same suite
        XCTAssertEqual(reloaded.tagCache["m1"], tags)
        XCTAssertTrue(reloaded.notInterested.contains("m2"))
        XCTAssertEqual(reloaded.moreLikeThis, ["m3"])
    }

    @MainActor func testTasteStoreRecordTagsIgnoresEmpty() {
        let store = makeTasteStore()
        store.recordTags(mangaId: "m1", tags: [])
        XCTAssertNil(store.tagCache["m1"])
    }

    @MainActor func testMangaIdsMissingTagsDedupesAndSkipsCached() {
        let store = makeTasteStore()
        store.recordTags(mangaId: "m1", tags: [Tag(id: "t1", name: "Action", group: "genre")])
        let missing = store.mangaIdsMissingTags(readIds: ["m1", "m2", "m2", "m3"])
        XCTAssertEqual(missing, ["m2", "m3"])   // m1 cached, m2 deduped, order preserved
    }

    @MainActor func testTasteStoreDecodesAbsentKeysAsEmpty() {
        let store = TasteProfileStore(defaults: UserDefaults(suiteName: "test.taste.\(UUID().uuidString)")!)
        XCTAssertTrue(store.tagCache.isEmpty)
        XCTAssertTrue(store.notInterested.isEmpty)
        XCTAssertTrue(store.moreLikeThis.isEmpty)
    }

    // MARK: - TasteProfile

    private func entry(_ mangaId: String, chapter: String, page: Int, pageCount: Int,
                       daysAgo: Double, now: Date) -> ReadingEntry {
        ReadingEntry(id: UUID(), mangaId: mangaId, mangaTitle: mangaId, coverURL: nil,
                     chapterId: "\(mangaId)-\(chapter)", chapterNumber: chapter,
                     page: page, pageCount: pageCount,
                     updatedAt: now.addingTimeInterval(-daysAgo * 86_400), sourceId: "mangadex")
    }

    func testProfileWeightsGenreAboveFormatForEqualEngagement() {
        let now = Date()
        let tagCache = ["m1": [Tag(id: "g", name: "Action", group: "genre"),
                               Tag(id: "f", name: "Oneshot", group: "format")]]
        let history = [entry("m1", chapter: "1", page: 9, pageCount: 10, daysAgo: 0, now: now)]
        let p = TasteProfile.build(history: history, savedIds: [], tagCache: tagCache,
                                   moreLikeThis: [], now: now)
        XCTAssertEqual(p.orderedTagIds.first, "g")               // genre outranks format
        XCTAssertGreaterThan(p.weights["g"]!, p.weights["f"]!)
        XCTAssertEqual(p.weights.values.max()!, 1.0, accuracy: 1e-9)   // normalized to max 1
    }

    func testProfileRecencyDecayHalvesAtThirtyDays() {
        let now = Date()
        let tagCache = ["recent": [Tag(id: "a", name: "A", group: "genre")],
                        "old":    [Tag(id: "b", name: "B", group: "genre")]]
        let history = [
            entry("recent", chapter: "1", page: 0, pageCount: 10, daysAgo: 0,  now: now),
            entry("old",    chapter: "1", page: 0, pageCount: 10, daysAgo: 30, now: now),
        ]
        let p = TasteProfile.build(history: history, savedIds: [], tagCache: tagCache,
                                   moreLikeThis: [], now: now)
        // Same engagement, but "old" is one 30-day half-life back → half the weight.
        XCTAssertEqual(p.weights["b"]! / p.weights["a"]!, 0.5, accuracy: 0.02)
    }

    func testProfileSavedAndFinishedMangaOutranksBareRead() {
        let now = Date()
        // Two manga, distinct genre tags, read the same recency/chapter count. One is
        // finished + saved; the other is a bare unfinished read. The boosted one must win.
        let tagCache = ["boost": [Tag(id: "b", name: "B", group: "genre")],
                        "bare":  [Tag(id: "p", name: "P", group: "genre")]]
        let history = [
            entry("boost", chapter: "1", page: 9, pageCount: 10, daysAgo: 0, now: now),   // finished
            entry("bare",  chapter: "1", page: 3, pageCount: 10, daysAgo: 0, now: now),   // unfinished
        ]
        let p = TasteProfile.build(history: history, savedIds: ["boost"], tagCache: tagCache,
                                   moreLikeThis: [], now: now)
        XCTAssertEqual(p.orderedTagIds.first, "b")
        XCTAssertGreaterThan(p.weights["b"]!, p.weights["p"]!)
    }

    func testProfileMoreLikeThisDoublesContribution() {
        let now = Date()
        let tagCache = ["seed": [Tag(id: "s", name: "S", group: "genre")],
                        "plain": [Tag(id: "n", name: "N", group: "genre")]]
        let history = [
            entry("seed",  chapter: "1", page: 3, pageCount: 10, daysAgo: 0, now: now),
            entry("plain", chapter: "1", page: 3, pageCount: 10, daysAgo: 0, now: now),
        ]
        let p = TasteProfile.build(history: history, savedIds: [], tagCache: tagCache,
                                   moreLikeThis: ["seed"], now: now)
        // Identical engagement; seed's ×2 boost makes it the top tag at exactly 2× "plain".
        XCTAssertEqual(p.orderedTagIds.first, "s")
        XCTAssertEqual(p.weights["n"]! / p.weights["s"]!, 0.5, accuracy: 1e-9)
    }

    func testProfileEmptyWhenNoTaggedHistory() {
        let p = TasteProfile.build(history: [], savedIds: [], tagCache: [:], moreLikeThis: [], now: Date())
        XCTAssertTrue(p.isEmpty)
        XCTAssertEqual(p.taggedMangaCount, 0)
    }

    func testProfileFinishedBonusRanksAboveUnfinishedAcrossManga() {
        let now = Date()
        let tagCache = ["fin": [Tag(id: "f", name: "F", group: "genre")],
                        "unf": [Tag(id: "u", name: "U", group: "genre")]]
        let history = [
            entry("fin", chapter: "1", page: 9, pageCount: 10, daysAgo: 0, now: now),   // finished
            entry("unf", chapter: "1", page: 2, pageCount: 10, daysAgo: 0, now: now),   // abandoned
        ]
        let p = TasteProfile.build(history: history, savedIds: [], tagCache: tagCache,
                                   moreLikeThis: [], now: now)
        XCTAssertEqual(p.orderedTagIds.first, "f")
        XCTAssertGreaterThan(p.weights["f"]!, p.weights["u"]!)
    }

    // MARK: - TagCandidateProvider

    /// A source whose mangaByTag returns canned lists keyed by tag name.
    private struct CannedTagSource: MangaSource {
        let id = "mangadex"
        let name = "MangaDex"
        let lists: [String: [Manga]]
        let failTags: Set<String>

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaByTag(tag: String, limit: Int, offset: Int) async throws -> [Manga] {
            if failTags.contains(tag) { throw LoaderTestError.boom }
            return lists[tag] ?? []
        }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: [], contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    private func profile(_ pairs: [(id: String, name: String, weight: Double)]) -> TasteProfile {
        var weights: [String: Double] = [:]; var names: [String: String] = [:]
        for p in pairs { weights[p.id] = p.weight; names[p.id] = p.name }
        let ordered = weights.sorted { $0.value > $1.value }.map(\.key)
        return TasteProfile(weights: weights, tagName: names, orderedTagIds: ordered, taggedMangaCount: 5)
    }

    func testCandidateInTwoTagFeedsOutscoresOne() async throws {
        let both = sampleManga("both"); let one = sampleManga("one")
        let source = CannedTagSource(
            lists: ["Action": [both], "Romance": [both, one]], failTags: [])
        let prof = profile([("a", "Action", 1.0), ("r", "Romance", 0.8)])
        let out = try await TagCandidateProvider(source: source)
            .candidates(for: prof, excluding: [], limit: 10)
        XCTAssertEqual(out.first?.manga.id, "both")               // summed across two feeds
        XCTAssertEqual(out.map(\.manga.id).sorted(), ["both", "one"])
    }

    func testCandidateExcludesGivenIds() async throws {
        let source = CannedTagSource(lists: ["Action": [sampleManga("keep"), sampleManga("drop")]], failTags: [])
        let prof = profile([("a", "Action", 1.0)])
        let out = try await TagCandidateProvider(source: source)
            .candidates(for: prof, excluding: ["drop"], limit: 10)
        XCTAssertEqual(out.map(\.manga.id), ["keep"])
    }

    func testCandidateReasonIsHighestWeightProvenanceTag() async throws {
        let m = sampleManga("m")
        let source = CannedTagSource(lists: ["Action": [m], "Romance": [m]], failTags: [])
        let prof = profile([("a", "Action", 1.0), ("r", "Romance", 0.5)])
        let out = try await TagCandidateProvider(source: source)
            .candidates(for: prof, excluding: [], limit: 10)
        XCTAssertEqual(out.first?.reason, "More Action")
    }

    func testCandidateSkipsFailingTagFeed() async throws {
        let source = CannedTagSource(lists: ["Romance": [sampleManga("r1")]], failTags: ["Action"])
        let prof = profile([("a", "Action", 1.0), ("r", "Romance", 0.8)])
        let out = try await TagCandidateProvider(source: source)
            .candidates(for: prof, excluding: [], limit: 10)
        XCTAssertEqual(out.map(\.manga.id), ["r1"])               // Action threw, Romance survived
    }

    // MARK: - RecommendationEngine

    @MainActor
    private func makeEngine(history: HistoryStore, tasteStore: TasteProfileStore,
                            provider: CandidateProvider,
                            mangaDexSource: MangaSource = CannedTagSource(lists: [:], failTags: []),
                            now: Date = Date(), seed: UInt64 = 1)
        -> RecommendationEngine {
        let lib = LibraryStore(defaults: UserDefaults(suiteName: "test.lib.\(UUID().uuidString)")!)
        return RecommendationEngine(history: history, library: lib, profileStore: tasteStore,
                                    mangaDexSource: mangaDexSource,
                                    makeProvider: { _ in provider }, now: { now }, seed: seed)
    }

    /// A provider returning a fixed ranked pool, ignoring the profile.
    private struct FixedPoolProvider: CandidateProvider {
        let pool: [ScoredManga]
        func candidates(for profile: TasteProfile, excluding: Set<String>, limit: Int) async throws -> [ScoredManga] {
            Array(pool.filter { !excluding.contains($0.manga.id) }.prefix(limit))
        }
    }

    private func scored(_ id: String) -> ScoredManga {
        ScoredManga(manga: sampleManga(id), score: 1, reason: "More Action")
    }

    /// A source whose mangaDetail returns fixed tags — for backfill tests.
    private struct DetailStubSource: MangaSource {
        let id = "mangadex"; let name = "MangaDex"
        let tags: [Tag]
        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaByTag(tag: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            MangaDetail(description: "", authors: [], tags: tags, contentRating: nil)
        }
        func chapters(mangaId: String) async throws -> [Chapter] { [] }
        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    }

    @MainActor func testEngineColdStartHidesRailBelowThreshold() async throws {
        let history = makeHistoryStore()
        let taste = makeTasteStore()
        // Only 2 tagged read manga — below the 3 threshold.
        taste.recordTags(mangaId: "m1", tags: [Tag(id: "a", name: "A", group: "genre")])
        taste.recordTags(mangaId: "m2", tags: [Tag(id: "b", name: "B", group: "genre")])
        history.record(manga: sampleManga("m1"), chapter: ch("1"), page: 1, pageCount: 10)
        history.record(manga: sampleManga("m2"), chapter: ch("1"), page: 1, pageCount: 10)

        let engine = makeEngine(history: history, tasteStore: taste,
                                provider: FixedPoolProvider(pool: [scored("x")]))
        await engine.refresh()
        XCTAssertTrue(engine.recommendations.isEmpty)
    }

    @MainActor func testEngineProducesRecommendationsAboveThreshold() async throws {
        let history = makeHistoryStore()
        let taste = makeTasteStore()
        for i in 1...3 {
            taste.recordTags(mangaId: "m\(i)", tags: [Tag(id: "a", name: "Action", group: "genre")])
            history.record(manga: sampleManga("m\(i)"), chapter: ch("1"), page: 9, pageCount: 10)
        }
        let engine = makeEngine(history: history, tasteStore: taste,
                                provider: FixedPoolProvider(pool: [scored("rec1"), scored("rec2")]))
        await engine.refresh()
        XCTAssertEqual(Set(engine.recommendations.map(\.manga.id)), ["rec1", "rec2"])
    }

    @MainActor func testEngineExcludesReadAndNotInterested() async throws {
        let history = makeHistoryStore()
        let taste = makeTasteStore()
        for i in 1...3 {
            taste.recordTags(mangaId: "m\(i)", tags: [Tag(id: "a", name: "Action", group: "genre")])
            history.record(manga: sampleManga("m\(i)"), chapter: ch("1"), page: 9, pageCount: 10)
        }
        taste.markNotInterested(mangaId: "rec2")
        let engine = makeEngine(history: history, tasteStore: taste,
                                provider: FixedPoolProvider(pool: [scored("rec1"), scored("rec2"), scored("m1")]))
        await engine.refresh()
        // rec2 = not interested, m1 = already read → both excluded.
        XCTAssertEqual(engine.recommendations.map(\.manga.id), ["rec1"])
    }

    @MainActor func testComposeIsDeterministicForASeed() {
        let history = makeHistoryStore(); let taste = makeTasteStore()
        let pool = (0..<40).map { scored("p\($0)") }
        let a = makeEngine(history: history, tasteStore: taste, provider: FixedPoolProvider(pool: []), seed: 42)
        let b = makeEngine(history: history, tasteStore: taste, provider: FixedPoolProvider(pool: []), seed: 42)
        XCTAssertEqual(a.compose(pool: pool).map(\.manga.id), b.compose(pool: pool).map(\.manga.id))
    }

    @MainActor func testComposeKeepsAllWhenPoolSmall() {
        let history = makeHistoryStore(); let taste = makeTasteStore()
        let pool = (0..<5).map { scored("p\($0)") }
        let engine = makeEngine(history: history, tasteStore: taste, provider: FixedPoolProvider(pool: []))
        XCTAssertEqual(engine.compose(pool: pool).count, 5)
    }

    @MainActor func testMarkNotInterestedRemovesFromRailAndPersists() async throws {
        let history = makeHistoryStore(); let taste = makeTasteStore()
        for i in 1...3 {
            taste.recordTags(mangaId: "m\(i)", tags: [Tag(id: "a", name: "Action", group: "genre")])
            history.record(manga: sampleManga("m\(i)"), chapter: ch("1"), page: 9, pageCount: 10)
        }
        let engine = makeEngine(history: history, tasteStore: taste,
                                provider: FixedPoolProvider(pool: [scored("rec1"), scored("rec2")]))
        await engine.refresh()
        engine.markNotInterested(sampleManga("rec1"))
        XCTAssertFalse(engine.recommendations.contains { $0.manga.id == "rec1" })
        XCTAssertTrue(taste.notInterested.contains("rec1"))
    }

    @MainActor func testBackfillRecordsTagsFromDetailSource() async throws {
        let taste = makeTasteStore()
        let detailSource = DetailStubSource(tags: [Tag(id: "a", name: "Action", group: "genre")])
        let engine = makeEngine(history: makeHistoryStore(), tasteStore: taste,
                                provider: FixedPoolProvider(pool: []), mangaDexSource: detailSource)
        await engine.backfill(ids: ["m1", "m2"])
        XCTAssertNotNil(taste.tagCache["m1"])
        XCTAssertNotNil(taste.tagCache["m2"])
    }

    @MainActor func testRankedRecommendationsEmptyOnColdStart() async {
        let engine = makeEngine(history: makeHistoryStore(), tasteStore: makeTasteStore(),
                                provider: FixedPoolProvider(pool: [scored("x")]))
        let out = await engine.rankedRecommendations(limit: 50)
        XCTAssertTrue(out.isEmpty)
    }

    @MainActor func testRankedRecommendationsReturnsRankedMangaWithoutShuffle() async {
        let history = makeHistoryStore(); let taste = makeTasteStore()
        for i in 1...3 {
            taste.recordTags(mangaId: "m\(i)", tags: [Tag(id: "a", name: "Action", group: "genre")])
            history.record(manga: sampleManga("m\(i)"), chapter: ch("1"), page: 9, pageCount: 10)
        }
        let engine = makeEngine(history: history, tasteStore: taste,
                                provider: FixedPoolProvider(pool: [scored("r1"), scored("r2"), scored("m1")]))
        let out = await engine.rankedRecommendations(limit: 50)
        // Straight ranking order, read manga (m1) excluded, no exploration reshuffle.
        XCTAssertEqual(out.map(\.id), ["r1", "r2"])
    }

    // MARK: - MyAnimeListAPI DTOs

    func testMyAnimeListSearchResponseDecodesAndUnwrapsNode() throws {
        let json = """
        {
          "data": [
            {
              "node": {
                "id": 2,
                "title": "Berserk",
                "main_picture": {
                  "medium": "https://example.com/berserk_m.jpg",
                  "large": "https://example.com/berserk_l.jpg"
                }
              }
            },
            {
              "node": { "id": 401, "title": "Berserk: The Prototype" }
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(MyAnimeListSearchResponse.self, from: json)
        XCTAssertEqual(response.data.map(\.node.id), [2, 401])
        XCTAssertEqual(response.data[0].node.title, "Berserk")
        XCTAssertEqual(response.data[0].node.mainPicture?.medium,
                       "https://example.com/berserk_m.jpg")
        XCTAssertNil(response.data[1].node.mainPicture)
    }

    func testMyAnimeListMangaDetailDecodesRelatedAndRecommendations() throws {
        let json = """
        {
          "id": 2,
          "title": "Berserk",
          "synopsis": "Guts, a former mercenary...",
          "main_picture": {
            "medium": "https://example.com/berserk_m.jpg",
            "large": "https://example.com/berserk_l.jpg"
          },
          "genres": [
            {"id": 1, "name": "Action"},
            {"id": 8, "name": "Drama"}
          ],
          "related_manga": [
            {
              "node": {"id": 401, "title": "Berserk: The Prototype"},
              "relation_type": "prequel",
              "relation_type_formatted": "Prequel"
            }
          ],
          "recommendations": [
            {
              "node": {"id": 656, "title": "Vagabond"},
              "num_recommendations": 42
            }
          ]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(MyAnimeListMangaDetail.self, from: json)
        XCTAssertEqual(detail.title, "Berserk")
        XCTAssertEqual(detail.genres?.map(\.name), ["Action", "Drama"])
        XCTAssertEqual(detail.relatedManga?.first?.node.title, "Berserk: The Prototype")
        XCTAssertEqual(detail.relatedManga?.first?.relationTypeFormatted, "Prequel")
        XCTAssertEqual(detail.recommendations?.first?.node.title, "Vagabond")
        XCTAssertEqual(detail.recommendations?.first?.numRecommendations, 42)
    }

    func testMyAnimeListMangaDetailDecodesWithoutOptionalRelations() throws {
        let json = """
        {
          "id": 977,
          "title": "One-Off Oneshot",
          "synopsis": null,
          "main_picture": null,
          "genres": null
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let detail = try decoder.decode(MyAnimeListMangaDetail.self, from: json)
        XCTAssertEqual(detail.id, 977)
        XCTAssertEqual(detail.title, "One-Off Oneshot")
        XCTAssertNil(detail.synopsis)
        XCTAssertNil(detail.genres)
        XCTAssertNil(detail.relatedManga)
        XCTAssertNil(detail.recommendations)
    }

    func testMyAnimeListMangaDecodesAlternativeTitlesAndAllTitles() throws {
        let json = """
        {
          "id": 25,
          "title": "Shingeki no Kyojin",
          "alternative_titles": {
            "synonyms": ["AoT"],
            "en": "Attack on Titan",
            "ja": "進撃の巨人"
          }
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manga = try decoder.decode(MyAnimeListManga.self, from: json)

        XCTAssertEqual(manga.alternativeTitles?.en, "Attack on Titan")
        XCTAssertEqual(manga.alternativeTitles?.ja, "進撃の巨人")
        XCTAssertEqual(manga.alternativeTitles?.synonyms, ["AoT"])
        // allTitles: main first, then en, ja, synonyms — no empties, deduped.
        XCTAssertEqual(manga.allTitles,
                       ["Shingeki no Kyojin", "Attack on Titan", "進撃の巨人", "AoT"])
    }

    func testMyAnimeListMangaAllTitlesWithoutAlternatives() throws {
        let json = #"{ "id": 1, "title": "Solo Leveling" }"#.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manga = try decoder.decode(MyAnimeListManga.self, from: json)
        XCTAssertNil(manga.alternativeTitles)
        XCTAssertEqual(manga.allTitles, ["Solo Leveling"])
    }

    func testMyAnimeListErrorDescriptions() {
        XCTAssertEqual(MyAnimeListError.missingClientID.errorDescription,
                       "Missing MyAnimeList API client ID. Set MAL_CLIENT_ID in Secrets.xcconfig.")
        XCTAssertEqual(MyAnimeListError.httpStatus(404).errorDescription,
                       "MyAnimeList request failed with HTTP status 404.")
    }

}
