import Foundation
import Testing
@testable import Manga_Reader

@MainActor
@Suite("Library updates presentation")
struct LibraryUpdatesPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("Freshness boundaries use the centralized window")
    func freshnessBoundaries() {
        #expect(LibraryUpdatesPresentation.freshness(
            for: WorkUpdateState(), isRefreshing: false, now: now) == .notChecked)

        var state = WorkUpdateState(hasBaseline: true, lastSuccessfulCheck: now)
        #expect(LibraryUpdatesPresentation.freshness(
            for: state, isRefreshing: false, now: now.addingTimeInterval(UpdateTuning.freshWindow)) == .fresh)
        #expect(LibraryUpdatesPresentation.freshness(
            for: state, isRefreshing: false,
            now: now.addingTimeInterval(UpdateTuning.freshWindow + 1)) == .stale)

        state.listings[ListingKey(sourceId: "mangadex", mangaId: "m1")] =
            ListingCheckState(consecutiveFailures: 1)
        #expect(LibraryUpdatesPresentation.freshness(
            for: state, isRefreshing: false, now: now) == .partialFailure)
        #expect(LibraryUpdatesPresentation.freshness(
            for: state, isRefreshing: true, now: now) == .refreshing)
    }

    @Test("New discovery state and unread state remain independent")
    func discoveryAndUnreadDiverge() throws {
        let fixture = try Fixture()
        let manga = fixture.save("m1", title: "Alpha")
        let id = try #require(fixture.works.workId(for: ListingKey(manga)))
        _ = fixture.updates.absorb(workId: id, listing: ListingKey(manga),
                                   rawNumbers: ["1", "2"], now: now)
        _ = fixture.updates.absorb(workId: id, listing: ListingKey(manga),
                                   rawNumbers: ["1", "2", "3"], now: now)

        var summary = try #require(fixture.summaries(now: now).first)
        #expect(summary.newlyDiscoveredCount == 1)
        #expect(summary.unreadChapterCount == 3)

        fixture.updates.clearNewlyDiscovered(workId: id)
        summary = try #require(fixture.summaries(now: now).first)
        #expect(summary.newlyDiscoveredCount == 0)
        #expect(summary.unreadChapterCount == 3)
    }

    @Test("Summaries sort by newest discovery and then title")
    func sorting() throws {
        let fixture = try Fixture()
        let beta = fixture.save("b", title: "Beta")
        let alpha = fixture.save("a", title: "Alpha")
        for manga in [beta, alpha] {
            let id = try #require(fixture.works.workId(for: ListingKey(manga)))
            _ = fixture.updates.absorb(workId: id, listing: ListingKey(manga),
                                       rawNumbers: ["1"], now: now)
            _ = fixture.updates.absorb(workId: id, listing: ListingKey(manga),
                                       rawNumbers: ["1", "2"], now: now)
        }

        #expect(fixture.summaries(now: now).map(\.displayManga.title) == ["Alpha", "Beta"])
    }

    @Test("Home shows five summaries and preserves the full count")
    func homeLimit() throws {
        let fixture = try Fixture()
        for index in 0..<7 { _ = fixture.save("m\(index)", title: "Title \(index)") }
        let all = fixture.summaries(now: now)
        #expect(all.count == 7)
        #expect(LibraryUpdatesPresentation.homeSummaries(all).count == 5)
        #expect(all.count - LibraryUpdatesPresentation.homeSummaries(all).count == 2)
    }

    @Test("Changing the active browse source cannot change personal update truth")
    func activeSourceIndependence() throws {
        let first = StubSource(id: "first", name: "First")
        let second = StubSource(id: "second", name: "Second")
        let registry = SourceRegistry(sources: [first, second])
        let fixture = try Fixture(registry: registry)
        _ = fixture.save("m1", title: "Alpha", sourceId: first.id)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(fixture.summaries(now: now))

        registry.activeSourceID = second.id
        let after = try encoder.encode(fixture.summaries(now: now))
        #expect(before == after)
    }
}

@MainActor
private final class Fixture {
    let directory: URL
    let defaults: UserDefaults
    let works: WorkStore
    let library: LibraryStore
    let history: HistoryStore
    let updates: UpdateStateStore
    let registry: SourceRegistry

    init(registry: SourceRegistry? = nil) throws {
        let sourceRegistry = registry
            ?? SourceRegistry(sources: [StubSource(id: "mangadex", name: "MangaDex")])
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let isolatedDefaults = UserDefaults(suiteName: UUID().uuidString) else {
            fatalError("Unable to create isolated defaults")
        }
        defaults = isolatedDefaults
        works = WorkStore(directory: directory)
        library = LibraryStore(defaults: defaults, works: works, registry: sourceRegistry)
        history = HistoryStore(defaults: defaults, works: works)
        updates = UpdateStateStore(directory: directory, works: works)
        self.registry = sourceRegistry
    }

    func save(_ id: String, title: String, sourceId: String = "mangadex") -> Manga {
        let manga = Manga(id: id, sourceId: sourceId, title: title, description: "",
                          status: "ongoing", year: nil, coverURL: nil, malId: nil)
        library.toggle(manga)
        return manga
    }

    func summaries(now: Date) -> [WorkUpdateSummary] {
        LibraryUpdatesPresentation.summaries(works: works, library: library, history: history,
                                             updates: updates, registry: registry, now: now)
    }
}

private struct StubSource: MangaSource {
    let id: String
    let name: String
    let isNSFW = false
    func search(title: String, limit: Int, offset: Int) async throws -> [Manga] { [] }
    func popular(limit: Int, offset: Int) async throws -> [Manga] { [] }
    func mangaDetail(id: String) async throws -> MangaDetail { throw SourceError.unsupported("detail") }
    func chapters(mangaId: String) async throws -> [Chapter] { [] }
    func pageURLs(chapterId: String, preferDataSaver: Bool) async throws -> [URL] { [] }
    func webURL(forManga id: String) -> URL? { nil }
}
