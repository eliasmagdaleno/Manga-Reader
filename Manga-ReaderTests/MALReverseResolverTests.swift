//
//  MALReverseResolverTests.swift
//  Manga-ReaderTests
//
//  The cache-write discipline `MALReverseResolver` exists to keep single. Until the
//  extraction these lines lived as a private method on `MoreLikeThisProvider` calling
//  `MangaDexAPI` statics, so none of it was reachable without a network — the ADR-0011
//  claim that "the golden proves the extraction moved nothing" was false, because every
//  existing test stubs `resolve` and injects *past* this code entirely.
//
//  The load-bearing case is `search THREW → record nothing`. Its failure mode is silent:
//  a transient network error recorded as `.unresolved` poisons the store against that
//  title for the full 14-day miss TTL, and nothing in the UI would ever say so.
//

import XCTest
@testable import Manga_Reader

@MainActor
final class MALReverseResolverTests: XCTestCase {

    // MARK: - Fixtures

    private func store() -> EntityResolutionStore {
        EntityResolutionStore(
            defaults: UserDefaults(suiteName: "test.reverse.\(UUID().uuidString)")!)
    }

    // MARK: - Cache-write discipline

    /// A candidate carrying the target `malId` is a confirmed match — the strong arm of
    /// `MoreLikeThis.pickMatch`, no title similarity required.
    func testConfidentMatchIsReturnedAndRecordedResolved() async {
        let store = store()
        let hit = manga("md-1", title: "Something Else Entirely", malId: 55)
        let resolver = MALReverseResolver(store: store,
                                          search: { _ in [hit] },
                                          fetchByIds: { _ in [] })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertEqual(out[55]?.id, "md-1")
        XCTAssertEqual(store.reverseResolution(malId: 55), .resolved(mangaDexId: "md-1"))
    }

    /// The search completed and simply found nothing confident. That IS information —
    /// record it, so the next rail build doesn't pay for the same search.
    func testSearchedWithNoMatchRecordsUnresolved() async {
        let store = store()
        let miss = manga("md-9", title: "Totally Unrelated Title", malId: 999)
        let resolver = MALReverseResolver(store: store,
                                          search: { _ in [miss] },
                                          fetchByIds: { _ in [] })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertTrue(out.isEmpty)
        guard case .unresolved = store.reverseResolution(malId: 55) else {
            return XCTFail("expected an .unresolved record, got \(String(describing: store.reverseResolution(malId: 55)))")
        }
    }

    /// The one that matters. A thrown search carries no information about the title, so
    /// writing `.unresolved` would poison the cache for 14 days over a dropped connection.
    func testThrownSearchRecordsNothing() async {
        let store = store()
        let resolver = MALReverseResolver(store: store,
                                          search: { _ in throw SearchFailed() },
                                          fetchByIds: { _ in [] })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertTrue(out.isEmpty)
        XCTAssertNil(store.reverseResolution(malId: 55),
                     "a transient failure must leave the cache untouched")
    }

    /// One target throwing must not suppress the others — the task group's results are
    /// independent, and a partial pool is the normal outcome.
    func testOneThrownSearchDoesNotAffectItsSiblings() async {
        let store = store()
        let resolver = MALReverseResolver(
            store: store,
            search: { title in
                if title == "Bad" { throw SearchFailed() }
                return [manga("md-ok", title: title, malId: 1)]
            },
            fetchByIds: { _ in [] })

        let out = await resolver.resolve([.init(malId: 2, title: "Bad"),
                                          .init(malId: 1, title: "Good")])

        XCTAssertEqual(out[1]?.id, "md-ok")
        XCTAssertNil(out[2])
        XCTAssertNil(store.reverseResolution(malId: 2))
    }

    // MARK: - Cache partition

    /// A fresh `.resolved` hit skips the search entirely and is filled in by ONE batch
    /// fetch — the whole reason the partition exists.
    func testFreshResolvedHitSkipsSearchAndIsBatchFetched() async {
        let store = store()
        store.recordReverse(malId: 55, .resolved(mangaDexId: "md-1"))
        let searches = Counter()
        let fetches = Counter()
        let resolver = MALReverseResolver(
            store: store,
            search: { _ in await searches.increment(); return [] },
            fetchByIds: { ids in
                await fetches.increment()
                return ids.map { manga($0, title: "Cached \($0)") }
            })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertEqual(out[55]?.id, "md-1")
        let (searchCount, fetchCount) = (await searches.value, await fetches.value)
        XCTAssertEqual(searchCount, 0, "a fresh hit must not re-search")
        XCTAssertEqual(fetchCount, 1, "cache hits are filled by a single batch fetch")
    }

    /// A fresh `.unresolved` miss is skipped outright — neither re-searched nor fetched.
    /// It is re-attempted only once past the 14-day TTL.
    func testFreshUnresolvedMissIsSkippedEntirely() async {
        let store = store()
        store.recordReverse(malId: 55, .unresolved(checkedAt: Date()))
        let searches = Counter()
        let fetches = Counter()
        let resolver = MALReverseResolver(
            store: store,
            search: { _ in await searches.increment(); return [] },
            fetchByIds: { _ in await fetches.increment(); return [] })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertTrue(out.isEmpty)
        let (searchCount, fetchCount) = (await searches.value, await fetches.value)
        XCTAssertEqual(searchCount, 0)
        XCTAssertEqual(fetchCount, 0)
    }

    /// A *stale* `.unresolved` miss is re-attempted — that is what the TTL buys, and what
    /// makes an improved matcher (or a title MangaDex adds later) eventually take effect.
    func testStaleUnresolvedMissIsResearched() async {
        let store = store()
        let old = Date().addingTimeInterval(-(EntityResolutionStore.missTTL + 60))
        store.recordReverse(malId: 55, .unresolved(checkedAt: old))
        let resolver = MALReverseResolver(
            store: store,
            search: { _ in [manga("md-1", title: "Whatever", malId: 55)] },
            fetchByIds: { _ in [] })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertEqual(out[55]?.id, "md-1")
        XCTAssertEqual(store.reverseResolution(malId: 55), .resolved(mangaDexId: "md-1"))
    }

    /// A failed batch fetch degrades to fewer entries rather than throwing — the cache
    /// record stays `.resolved`, so the next build tries the fetch again.
    func testFailedBatchFetchDegradesWithoutClearingTheCache() async {
        let store = store()
        store.recordReverse(malId: 55, .resolved(mangaDexId: "md-1"))
        let resolver = MALReverseResolver(store: store,
                                          search: { _ in [] },
                                          fetchByIds: { _ in throw SearchFailed() })

        let out = await resolver.resolve([.init(malId: 55, title: "Crimson Vow")])

        XCTAssertTrue(out.isEmpty)
        XCTAssertEqual(store.reverseResolution(malId: 55), .resolved(mangaDexId: "md-1"))
    }

    // MARK: - The AniList adapter

    /// Which titles get searched is one decision in one place: Works past `limit`, and
    /// Works carrying no MAL id, never become targets.
    func testWorksAdapterHonoursLimitAndDropsWorksWithoutAMALId() async {
        let store = store()
        let searched = Box()
        let resolver = MALReverseResolver(
            store: store,
            search: { title in
                await searched.append(title)
                return []
            },
            fetchByIds: { _ in [] })

        let works = [aniList(1, malId: 11), aniList(2, malId: nil), aniList(3, malId: 33)]
        _ = await resolver.resolve(works: works, limit: 2)

        let titles = await searched.value
        XCTAssertEqual(titles, ["Title 1"],
                       "work 2 carries no malId and work 3 is past the limit")
    }

}

/// File-scope, not methods: these are called from inside `@Sendable` closures running on
/// the task group's child tasks, and `XCTestCase` here is `@MainActor`-isolated — a method
/// would capture `self` across the isolation boundary.
private func manga(_ id: String, title: String, malId: Int? = nil) -> Manga {
    Manga(id: id, sourceId: "mangadex", title: title, description: "",
          status: "ongoing", year: nil, coverURL: nil, malId: malId)
}

private func aniList(_ id: Int, malId: Int?) -> AniListWork {
    AniListWork(anilistId: id, malId: malId, knownTitles: ["Title \(id)"],
                genres: [], tags: [], publicationStatus: .releasing, chapterTotal: nil)
}

private struct SearchFailed: Error {}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}

private actor Box {
    private(set) var value: [String] = []
    func append(_ new: String) { value.append(new) }
}
