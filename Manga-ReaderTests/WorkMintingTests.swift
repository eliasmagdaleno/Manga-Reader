//
//  WorkMintingTests.swift
//  Manga-ReaderTests
//
//  Slice 3 of ADR-0007: minting at the commitment points. A Work comes into
//  existence when the user commits to a manga — reads it, saves it, or gives it
//  explicit feedback — and never from browsing (ADR-0007, "Minting").
//
//  These tests pin the *wiring*: that each commitment path reaches `WorkStore`.
//  `WorkStoreTests` covers what minting itself does.
//

import XCTest
@testable import Manga_Reader

final class WorkMintingTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeWorkStore() -> WorkStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkMintingTests-\(UUID().uuidString)")
        return WorkStore(directory: dir)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.minting.\(UUID().uuidString)")!
    }

    /// A Listing. `Manga` *is* a Listing despite the name (ADR-0001).
    private func listing(_ id: String,
                         source: String = "weebcentral",
                         title: String = "Untitled",
                         malId: Int? = nil) -> Manga {
        Manga(id: id, sourceId: source, title: title, description: "",
              status: "ongoing", year: nil, coverURL: nil, malId: malId)
    }

    // MARK: - Read

    /// The bug ADR-0001 documented: a manga read on a non-MangaDex source was
    /// structurally invisible to the recommender. Minting on the read is the first
    /// half of the fix — the read now has a Work to hang tags off.
    @MainActor
    func testReadingAChapterOnANonMangaDexSourceMintsAWork() throws {
        let works = makeWorkStore()
        let history = HistoryStore(defaults: makeDefaults(), works: works)

        history.record(manga: listing("wc-1", title: "Omniscient Reader"),
                       chapter: Chapter(id: "c1", number: "1", title: nil),
                       page: 0, pageCount: 20)

        let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-1")))
        XCTAssertEqual(works.work(id)?.displayTitle, "Omniscient Reader")
    }

    /// `record` runs on every page turn, so this is the common case by far.
    @MainActor
    func testReadingTheSameMangaRepeatedlyMintsOneWork() throws {
        let works = makeWorkStore()
        let history = HistoryStore(defaults: makeDefaults(), works: works)
        let orv = listing("wc-1", title: "Omniscient Reader")

        history.record(manga: orv, chapter: Chapter(id: "c1", number: "1", title: nil),
                       page: 0, pageCount: 20)
        history.record(manga: orv, chapter: Chapter(id: "c1", number: "1", title: nil),
                       page: 5, pageCount: 20)
        history.record(manga: orv, chapter: Chapter(id: "c2", number: "2", title: nil),
                       page: 0, pageCount: 18)

        let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-1")))
        XCTAssertEqual(works.work(id)?.listings.count, 1)
    }

    // MARK: - Save

    @MainActor
    func testSavingToTheLibraryMintsAWork() throws {
        let works = makeWorkStore()
        let library = LibraryStore(defaults: makeDefaults(), works: works)

        library.toggle(listing("wc-2", title: "Solo Leveling"))

        let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-2")))
        XCTAssertEqual(works.work(id)?.displayTitle, "Solo Leveling")
    }

    /// Unsaving is not an anti-commitment. The Work records that the user once
    /// cared; the *library* records whether they still do. Deleting the Work would
    /// also throw away external ids and any snapshot the upgrade queue had fetched.
    @MainActor
    func testUnsavingLeavesTheWorkInPlace() {
        let works = makeWorkStore()
        let library = LibraryStore(defaults: makeDefaults(), works: works)
        let solo = listing("wc-2", title: "Solo Leveling")

        library.toggle(solo)
        library.toggle(solo)

        XCTAssertFalse(library.contains("wc-2"))
        XCTAssertNotNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-2")))
    }

    /// `toggle` is not the only save-shaped entry point: adding straight to a
    /// collection from the detail sheet skips it entirely.
    @MainActor
    func testAddingToACollectionMintsAWork() {
        let works = makeWorkStore()
        let library = LibraryStore(defaults: makeDefaults(), works: works)

        library.toggleCollection(for: listing("wc-3", title: "Berserk"),
                                 collectionId: LibraryCollection.readingID)

        XCTAssertNotNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-3")))
    }

    @MainActor
    func testSettingCollectionsMintsAWork() {
        let works = makeWorkStore()
        let library = LibraryStore(defaults: makeDefaults(), works: works)

        library.setCollections(for: listing("wc-4", title: "Vinland Saga"),
                               collectionIds: [LibraryCollection.readingID])

        XCTAssertNotNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-4")))
    }

    /// Clearing every collection removes the item, and must not mint on the way out:
    /// there is no commitment in a removal.
    @MainActor
    func testClearingEveryCollectionDoesNotMint() {
        let works = makeWorkStore()
        let library = LibraryStore(defaults: makeDefaults(), works: works)

        library.setCollections(for: listing("wc-5", title: "Gantz"), collectionIds: [])

        XCTAssertNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-5")))
    }

    // MARK: - Feedback

    /// Under Listing-keyed edges, *Not interested* on a MangaDex Listing would not
    /// suppress the same manga surfaced from WeebCentral. Minting on the tap is what
    /// eventually makes suppression cross-source (ADR-0007).
    @MainActor
    func testNotInterestedMintsAWork() {
        let works = makeWorkStore()
        let engine = makeEngine(works: works)

        engine.markNotInterested(listing("wc-6", title: "Gantz"))

        XCTAssertNotNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-6")))
    }

    @MainActor
    func testMoreLikeThisMintsAWork() {
        let works = makeWorkStore()
        let engine = makeEngine(works: works)

        engine.markMoreLikeThis(listing("wc-7", title: "Vagabond"))

        XCTAssertNotNil(works.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-7")))
    }

    @MainActor
    private func makeEngine(works: WorkStore) -> RecommendationEngine {
        RecommendationEngine(history: HistoryStore(defaults: makeDefaults()),
                             library: LibraryStore(defaults: makeDefaults()),
                             profileStore: TasteProfileStore(defaults: makeDefaults()),
                             workStore: works,
                             makeProvider: { _ in EmptyProvider() })
    }

    private struct EmptyProvider: CandidateProvider {
        func candidates(for profile: TasteProfile, excluding: Set<String>, limit: Int) async throws -> [ScoredManga] { [] }
    }
}
