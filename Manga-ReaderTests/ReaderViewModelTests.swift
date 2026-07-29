//
//  ReaderViewModelTests.swift
//  Manga-ReaderTests
//
//  ADR-0012. The reader was the one screen that never got a view model, which is why
//  none of its loading behaviour was testable. These drive it through a stub
//  `MangaSource` — no network, no simulator timing.
//
//  `testFailedAdvanceLeavesTheChapterBeingReadIntact` is the one that earns the
//  refactor. Load-then-commit's entire value is "on failure, nothing was mutated",
//  and that can only be checked by failing a fetch and inspecting state afterwards.
//  The shipped code mutated first and loaded second, so one 404 chapter mid-series
//  destroyed the chapter the user was on.
//

import XCTest
@testable import Manga_Reader

@MainActor
final class ReaderViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private static let manga = Manga(id: "m1", sourceId: "stub", title: "Solo Leveling",
                                     description: "", status: "ongoing", year: nil,
                                     coverURL: nil, malId: nil)

    private static func chapter(_ n: String) -> Chapter {
        Chapter(id: "ch\(n)", number: n, title: nil, date: nil)
    }

    private static let three = [chapter("1"), chapter("2"), chapter("3")]

    private static func urls(_ count: Int) -> [URL] {
        (0..<count).map { URL(string: "https://cdn.test/p\($0).jpg")! }
    }

    /// A source whose `pageURLs` answer is programmable per chapter id, so a single
    /// test can have chapter 2 succeed and chapter 3 fail.
    private final class StubSource: MangaSource {
        let id = "stub"
        let name = "Stub"

        /// chapterId → what `pageURLs` should do.
        var pages: [String: Result<[URL], Error>] = [:]
        var chapterList: [Chapter] = []
        private(set) var chapterFetchCount = 0

        func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] {
            switch pages[chapterId] {
            case .success(let urls): return urls
            case .failure(let error): throw error
            case nil: return []
            }
        }

        func chapters(mangaId: String) async throws -> [Chapter] {
            chapterFetchCount += 1
            return chapterList
        }

        func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
        func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
        func mangaDetail(id: String) async throws -> MangaDetail {
            throw SourceError.unsupported("mangaDetail")
        }
    }

    private func makeVM(chapter: Chapter,
                        chapters: [Chapter] = ReaderViewModelTests.three,
                        initialPage: Int = 0,
                        configure: (StubSource) -> Void) -> (ReaderViewModel, StubSource) {
        let source = StubSource()
        configure(source)
        // Swallow the prefetch: these tests must not touch the network or the real cache.
        let vm = ReaderViewModel(manga: Self.manga, chapter: chapter, chapters: chapters,
                                 initialPage: initialPage, source: source,
                                 prefetch: { _, _ in })
        return (vm, source)
    }

    // MARK: - Initial load

    func testSuccessfulLoadPopulatesPagesAndClearsError() async {
        let (vm, _) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .success(Self.urls(20))
        }
        await vm.begin()

        XCTAssertEqual(vm.pages.count, 20)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.presentation.body, .content)
        XCTAssertFalse(vm.presentation.chromeForced)
    }

    /// The reported bug's trigger. A 404 must leave the reader escapable, which means
    /// chrome forced, and must not offer a Retry that cannot work.
    func testNotFoundIsAPermanentFullScreenErrorWithChromeForced() async {
        let (vm, _) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .failure(MangaDexError.httpStatus(404))
        }
        await vm.begin()

        XCTAssertTrue(vm.pages.isEmpty)
        XCTAssertTrue(vm.presentation.chromeForced, "a failed load must stay escapable")
        XCTAssertEqual(vm.presentation.body,
                       .error(message: MangaDexError.httpStatus(404).localizedDescription,
                              canRetry: false))
    }

    func testTransientFailureKeepsRetryAvailable() async {
        let (vm, _) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .failure(URLError(.notConnectedToInternet))
        }
        await vm.begin()

        guard case .error(_, let canRetry) = vm.presentation.body else {
            return XCTFail("expected an error body, got \(vm.presentation.body)")
        }
        XCTAssertTrue(canRetry)
    }

    /// Both sources `compactMap` their page lists and can return `[]` without throwing
    /// (`MangaDexAPI.swift:591`, `WeebCentralSource.swift:87`). That used to render a
    /// blank screen with no message at all.
    func testEmptyPageListBecomesAPermanentErrorRatherThanABlankScreen() async {
        let (vm, _) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .success([])
        }
        await vm.begin()

        XCTAssertTrue(vm.presentation.chromeForced)
        guard case .error(let message, let canRetry) = vm.presentation.body else {
            return XCTFail("expected an error body, got \(vm.presentation.body)")
        }
        XCTAssertFalse(canRetry, "no amount of retrying adds pages to an empty chapter")
        XCTAssertFalse(message.isEmpty)
    }

    func testRetryAfterATransientFailureRecovers() async {
        let (vm, source) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .failure(URLError(.timedOut))
        }
        await vm.begin()
        XCTAssertTrue(vm.pages.isEmpty)

        source.pages["ch1"] = .success(Self.urls(5))
        await vm.retry()

        XCTAssertEqual(vm.pages.count, 5)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.presentation.body, .content)
    }

    func testChaptersAreFetchedOnlyWhenNotSupplied() async {
        let (supplied, suppliedSource) = makeVM(chapter: Self.chapter("1")) {
            $0.pages["ch1"] = .success(Self.urls(3))
        }
        await supplied.begin()
        XCTAssertEqual(suppliedSource.chapterFetchCount, 0, "chapters were passed in")

        let (bare, bareSource) = makeVM(chapter: Self.chapter("1"), chapters: []) {
            $0.pages["ch1"] = .success(Self.urls(3))
            $0.chapterList = Self.three
        }
        await bare.begin()
        XCTAssertEqual(bareSource.chapterFetchCount, 1)
        XCTAssertEqual(bare.chapters.count, 3)
    }

    // MARK: - Landing page

    func testInitialPageIsClampedToTheChapterLength() async {
        let (vm, _) = makeVM(chapter: Self.chapter("1"), initialPage: 999) {
            $0.pages["ch1"] = .success(Self.urls(10))
        }
        await vm.begin()
        XCTAssertEqual(vm.landingPage, 9)
    }

    func testMovingBackwardsLandsOnTheLastPage() async {
        let (vm, _) = makeVM(chapter: Self.chapter("2")) {
            $0.pages["ch2"] = .success(Self.urls(8))
            $0.pages["ch1"] = .success(Self.urls(12))
        }
        await vm.begin()
        await vm.loadPrevious()

        XCTAssertEqual(vm.currentChapter.id, "ch1")
        XCTAssertEqual(vm.landingPage, 11, "entering a chapter backwards opens at its end")
    }

    // MARK: - Load-then-commit

    /// The decision this refactor exists for. Chapter 3 is a 404; chapter 2 must survive
    /// intact — same chapter, same pages — so the user keeps reading instead of being
    /// ejected from the series.
    func testFailedAdvanceLeavesTheChapterBeingReadIntact() async {
        let (vm, _) = makeVM(chapter: Self.chapter("2")) {
            $0.pages["ch2"] = .success(Self.urls(20))
            $0.pages["ch3"] = .failure(MangaDexError.httpStatus(404))
        }
        await vm.begin()
        let pagesBefore = vm.pages

        await vm.loadNext()

        XCTAssertEqual(vm.currentChapter.id, "ch2", "a failed advance must not move the chapter")
        XCTAssertEqual(vm.pages, pagesBefore, "a failed advance must not discard loaded pages")
    }

    /// ...and the failure still has to be *told* to the user — over the content, not
    /// instead of it.
    func testFailedAdvanceBannersTheErrorWithoutBlankingTheChapter() async {
        let (vm, _) = makeVM(chapter: Self.chapter("2")) {
            $0.pages["ch2"] = .success(Self.urls(20))
            $0.pages["ch3"] = .failure(MangaDexError.httpStatus(404))
        }
        await vm.begin()
        await vm.loadNext()

        XCTAssertEqual(vm.presentation.body, .content)
        XCTAssertNotNil(vm.presentation.banner)
        XCTAssertFalse(vm.presentation.chromeForced, "pages are still on screen")
    }

    func testSuccessfulAdvanceCommitsTheNewChapter() async {
        let (vm, _) = makeVM(chapter: Self.chapter("2")) {
            $0.pages["ch2"] = .success(Self.urls(20))
            $0.pages["ch3"] = .success(Self.urls(14))
        }
        await vm.begin()
        await vm.loadNext()

        XCTAssertEqual(vm.currentChapter.id, "ch3")
        XCTAssertEqual(vm.pages.count, 14)
        XCTAssertEqual(vm.landingPage, 0)
        XCTAssertNil(vm.errorMessage)
        XCTAssertNil(vm.presentation.banner)
    }

    /// A stale banner from a failed advance must not outlive a successful one.
    func testASuccessfulAdvanceClearsAPreviousFailure() async {
        let (vm, source) = makeVM(chapter: Self.chapter("2")) {
            $0.pages["ch2"] = .success(Self.urls(20))
            $0.pages["ch3"] = .failure(MangaDexError.httpStatus(404))
        }
        await vm.begin()
        await vm.loadNext()
        XCTAssertNotNil(vm.presentation.banner)

        source.pages["ch3"] = .success(Self.urls(9))
        await vm.loadNext()

        XCTAssertEqual(vm.currentChapter.id, "ch3")
        XCTAssertNil(vm.presentation.banner)
    }

    func testAdvancingPastTheLastChapterDoesNothing() async {
        let (vm, _) = makeVM(chapter: Self.chapter("3")) {
            $0.pages["ch3"] = .success(Self.urls(6))
        }
        await vm.begin()
        await vm.loadNext()

        XCTAssertEqual(vm.currentChapter.id, "ch3")
        XCTAssertEqual(vm.pages.count, 6)
        XCTAssertNil(vm.errorMessage)
    }
}
