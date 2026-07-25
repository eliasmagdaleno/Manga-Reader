//
//  WorkStoreTests.swift
//  Manga-ReaderTests
//
//  Slice 2 of ADR-0007: Work identity. Each test gets its own temp directory, so
//  the JSON file under test is never shared and never the real one.
//

import XCTest
@testable import Manga_Reader

final class WorkStoreTests: XCTestCase {

    // MARK: - Helpers

    @MainActor
    private func makeStore() -> WorkStore {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkStoreTests-\(UUID().uuidString)")
        return WorkStore(directory: dir)
    }

    /// A Listing. `Manga` *is* a Listing despite the name (ADR-0001).
    private func listing(_ id: String,
                         source: String = "mangadex",
                         title: String = "Untitled",
                         malId: Int? = nil) -> Manga {
        Manga(id: id, sourceId: source, title: title, description: "",
              status: "ongoing", year: nil, coverURL: nil, malId: malId)
    }

    // MARK: - Minting

    @MainActor func testMintCreatesAWorkFindableByItsListingKey() {
        let store = makeStore()
        let solo = listing("md-1", title: "Solo Leveling")

        let id = store.mint(from: solo)

        XCTAssertEqual(store.work(id)?.displayTitle, "Solo Leveling")
        XCTAssertEqual(store.workId(for: ListingKey(sourceId: "mangadex", mangaId: "md-1")), id)
    }

    /// Minting is on the read path, so it runs every time a chapter is opened.
    /// It has to be idempotent or the store grows without bound.
    @MainActor func testMintingTheSameListingTwiceReturnsTheSameWork() {
        let store = makeStore()
        let solo = listing("md-1", title: "Solo Leveling")

        let first = store.mint(from: solo)
        let second = store.mint(from: solo)

        XCTAssertEqual(first, second)
        XCTAssertEqual(store.work(first)?.listings.count, 1)
    }

    /// The free dedupe path: MangaDex publishes `attributes.links.mal`, so a Work
    /// minted from a MangaDex Listing already carries an external id. A Listing
    /// from another source with the same malId is the same Work — no request, no
    /// title matching.
    @MainActor func testMintDedupesOnASharedExternalId() {
        let store = makeStore()
        let onMangaDex = listing("md-1", source: "mangadex", title: "Solo Leveling", malId: 121_496)
        let onWeebCentral = listing("wc-9", source: "weebcentral", title: "Solo Leveling", malId: 121_496)

        let first = store.mint(from: onMangaDex)
        let second = store.mint(from: onWeebCentral)

        XCTAssertEqual(first, second, "same malId ⇒ same Work")
        XCTAssertEqual(store.work(first)?.listings.count, 2)
        XCTAssertEqual(store.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-9")), first)
    }

    /// The precision bias, at the store level: two Listings that merely *look*
    /// alike are two Works. Nothing here guesses — a wrong link corrupts identity,
    /// history, and recommendations, while a missing one only omits something
    /// (ADR-0005). Linking them is resolution's job, or the user's.
    @MainActor func testMintDoesNotGuessAcrossSourcesWithoutAnExternalId() {
        let store = makeStore()
        let onMangaDex = listing("md-1", source: "mangadex", title: "Solo Leveling")
        let onWeebCentral = listing("wc-9", source: "weebcentral", title: "Solo Leveling")

        let first = store.mint(from: onMangaDex)
        let second = store.mint(from: onWeebCentral)

        XCTAssertNotEqual(first, second, "identical titles are not evidence of identity")
    }

    // MARK: - Merging

    /// The losing id stays **resolvable forever**. A stale Work id — from a screen
    /// already open when a background reconcile merged underneath it, which
    /// ADR-0004's optimistic render makes routine — must redirect, not resolve to
    /// nil. A nil Work degrades exactly like the cross-source invisibility bug this
    /// whole line of work exists to fix, which makes it hard to notice.
    @MainActor func testMergeAliasesTheLoserRatherThanErasingIt() {
        let store = makeStore()
        let winner = store.mint(from: listing("md-1", title: "Solo Leveling"))
        let loser = store.mint(from: listing("wc-9", source: "weebcentral", title: "Only I Level Up"))

        store.merge(loser, into: winner)

        XCTAssertEqual(store.work(loser)?.id, winner, "the loser's id must still resolve")
    }

    @MainActor func testMergeUnionsListingsTitlesAndExternalIdsKeepingTheWinnersDisplayTitle() {
        let store = makeStore()
        let winner = store.mint(from: listing("md-1", title: "Solo Leveling", malId: 121_496))
        let loser = store.mint(from: listing("wc-9", source: "weebcentral", title: "Only I Level Up"))
        store.setExternalIds(ExternalIDs(mal: nil, anilist: 105_398), on: loser)

        store.merge(loser, into: winner)

        let merged = store.work(winner)
        XCTAssertEqual(merged?.displayTitle, "Solo Leveling", "surviving Work keeps its own title")
        XCTAssertEqual(merged?.knownTitles, ["Solo Leveling", "Only I Level Up"])
        XCTAssertEqual(merged?.externalIds, ExternalIDs(mal: 121_496, anilist: 105_398))
        XCTAssertEqual(merged?.listings.count, 2)
        // The loser's Listing now routes to the winner.
        XCTAssertEqual(store.workId(for: ListingKey(sourceId: "weebcentral", mangaId: "wc-9")), winner)
    }

    /// Merges chain in practice: a Work merged away can later have *its* survivor
    /// merged away too, as sources link up over time. Every id in the chain has to
    /// keep resolving to the one live Work at the end of it.
    @MainActor func testAliasChainsResolveToTheSurvivingWork() {
        let store = makeStore()
        let first = store.mint(from: listing("md-1", title: "A"))
        let second = store.mint(from: listing("wc-9", source: "weebcentral", title: "B"))
        let third = store.mint(from: listing("xx-3", source: "other", title: "C"))

        store.merge(first, into: second)
        store.merge(second, into: third)

        XCTAssertEqual(store.work(first)?.id, third, "two hops must still resolve")
        XCTAssertEqual(store.work(second)?.id, third)
        XCTAssertEqual(store.work(third)?.listings.count, 3)
    }

    // MARK: - Metadata snapshots

    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    private var mangaDexTags: [Tag] {
        [Tag(id: "t1", name: "Action", group: "genre"),
         Tag(id: "t2", name: "Isekai", group: "theme"),
         Tag(id: "t3", name: "Long Strip", group: "format")]
    }

    /// The provisional tier: MangaDex's tags arrive free with the detail fetch the UI
    /// already makes, so the recommender works from launch with no request and no
    /// rate limit. They carry no rank, and their `group` is preserved because
    /// `TasteProfile.groupWeight` still weights genre above theme above format.
    @MainActor func testProvisionalSnapshotUsesTheListingsOwnTagsAndCarriesNoRank() {
        let store = makeStore()
        let id = store.mint(from: listing("md-1", title: "Solo Leveling"))

        store.applyProvisionalSnapshot(tags: mangaDexTags, to: id, now: noon)

        let snapshot = store.work(id)?.snapshot
        XCTAssertEqual(snapshot?.provider, .mangadex)
        XCTAssertEqual(snapshot?.genres, [QueryableTag(name: "Action", group: "genre"),
                                         QueryableTag(name: "Isekai", group: "theme"),
                                         QueryableTag(name: "Long Strip", group: "format")])
        XCTAssertEqual(snapshot?.tags, [], "MangaDex publishes no tag rank")
        XCTAssertEqual(snapshot?.fetchedAt, noon)
    }

    /// An AniList snapshot **replaces** the provisional one wholesale — one
    /// authority per Work, never a per-field merge — but external ids accumulate.
    @MainActor func testAniListSnapshotReplacesTheProvisionalOneAndAccumulatesIds() {
        let store = makeStore()
        let id = store.mint(from: listing("md-1", title: "Solo Leveling", malId: 121_496))
        store.applyProvisionalSnapshot(tags: mangaDexTags, to: id, now: noon)

        let fromAniList = AniListWork(anilistId: 105_398,
                                      malId: 121_496,
                                      knownTitles: ["Na Honjaman Level Up", "Solo Leveling"],
                                      genres: ["Action", "Adventure", "Fantasy"],
                                      tags: [RankedTag(name: "Dungeon", rank: 95)],
                                      publicationStatus: .finished,
                                      chapterTotal: 201)
        store.apply(fromAniList, to: id, now: noon)

        let work = store.work(id)
        XCTAssertEqual(work?.snapshot?.provider, .anilist)
        XCTAssertEqual(work?.snapshot?.genres.map(\.name), ["Action", "Adventure", "Fantasy"],
                       "wholesale replacement, so Isekai and Long Strip are gone")
        XCTAssertEqual(work?.snapshot?.tags, [RankedTag(name: "Dungeon", rank: 95)])
        XCTAssertEqual(work?.snapshot?.chapterTotal, 201)
        XCTAssertEqual(work?.externalIds, ExternalIDs(mal: 121_496, anilist: 105_398))
        // Provider titles become matcher fuel; the display title stays put.
        XCTAssertEqual(work?.displayTitle, "Solo Leveling")
        XCTAssertTrue(work?.knownTitles.contains("Na Honjaman Level Up") == true)
        // And the Work is now reachable by its AniList id.
        XCTAssertEqual(store.workId(externalId: ExternalIDs(mal: nil, anilist: 105_398)), id)
    }

    /// Wholesale replacement can lose information, so it's guarded: a provider
    /// snapshot with nothing on the searchable axis doesn't get to discard tags we
    /// already had. The *ids* still accumulate — learning the AniList id is useful
    /// even when the metadata behind it isn't.
    ///
    /// ADR-0007 calls this the one rule of its kind; a third such rule means
    /// per-field provenance was the right design after all.
    @MainActor func testAnEmptyProviderSnapshotDoesNotDiscardTheProvisionalOne() {
        let store = makeStore()
        let id = store.mint(from: listing("md-1", title: "Solo Leveling", malId: 121_496))
        store.applyProvisionalSnapshot(tags: mangaDexTags, to: id, now: noon)

        let emptyish = AniListWork(anilistId: 105_398, malId: 121_496, knownTitles: [],
                                   genres: [], tags: [], publicationStatus: .finished,
                                   chapterTotal: nil)
        store.apply(emptyish, to: id, now: noon)

        let work = store.work(id)
        XCTAssertEqual(work?.snapshot?.provider, .mangadex, "kept the snapshot that had content")
        XCTAssertEqual(work?.snapshot?.genres.count, 3)
        XCTAssertEqual(work?.externalIds.anilist, 105_398, "ids accumulate regardless")
    }

    // MARK: - Snapshot staleness

    /// TTL derives from the data's own semantics rather than a guessed constant.
    @MainActor func testStalenessFollowsPublicationStatus() {
        let day: TimeInterval = 86_400

        // FINISHED is terminal: the chapter total will never change again.
        let finished = MetadataSnapshot(provider: .anilist, fetchedAt: noon, genres: [],
                                       tags: [], publicationStatus: .finished, chapterTotal: 201)
        XCTAssertFalse(finished.isStale(now: noon.addingTimeInterval(3650 * day)))

        // RELEASING is known-incomplete -- `chapters` is null by definition -- so it
        // is re-checked on a 14-day cycle, mirroring EntityResolutionStore's miss TTL.
        let releasing = MetadataSnapshot(provider: .anilist, fetchedAt: noon, genres: [],
                                        tags: [], publicationStatus: .releasing, chapterTotal: nil)
        XCTAssertFalse(releasing.isStale(now: noon.addingTimeInterval(13 * day)))
        XCTAssertTrue(releasing.isStale(now: noon.addingTimeInterval(15 * day)))

        // A provisional snapshot is *always* stale: it is a placeholder, and this is
        // how the upgrade queue knows there is work to do.
        let provisional = MetadataSnapshot(provider: .mangadex, fetchedAt: noon, genres: [],
                                          tags: [], publicationStatus: .unknown, chapterTotal: nil)
        XCTAssertTrue(provisional.isStale(now: noon))
    }

    // MARK: - Persistence

    @MainActor func testWorksSurviveAReload() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkStoreTests-\(UUID().uuidString)")
        let first = WorkStore(directory: dir)
        let id = first.mint(from: listing("md-1", title: "Solo Leveling", malId: 121_496))
        first.applyProvisionalSnapshot(tags: mangaDexTags, to: id, now: noon)
        first.flush()

        let reloaded = WorkStore(directory: dir)

        XCTAssertEqual(reloaded.work(id)?.displayTitle, "Solo Leveling")
        XCTAssertEqual(reloaded.work(id)?.snapshot?.genres.count, 3)
        // Both indexes are rebuilt on load rather than persisted, so they cannot
        // drift out of sync with the Works they point at.
        XCTAssertEqual(reloaded.workId(for: ListingKey(sourceId: "mangadex", mangaId: "md-1")), id)
        XCTAssertEqual(reloaded.workId(externalId: ExternalIDs(mal: 121_496, anilist: nil)), id)
    }

    /// Aliases have to persist. A Work id from before a relaunch is exactly the
    /// stale id aliasing exists to protect — a manual link override (ADR-0005) is
    /// permanent and may name a Work that was later merged away.
    @MainActor func testAliasesSurviveAReload() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WorkStoreTests-\(UUID().uuidString)")
        let first = WorkStore(directory: dir)
        let winner = first.mint(from: listing("md-1", title: "Solo Leveling"))
        let loser = first.mint(from: listing("wc-9", source: "weebcentral", title: "Only I Level Up"))
        first.merge(loser, into: winner)
        first.flush()

        let reloaded = WorkStore(directory: dir)

        XCTAssertEqual(reloaded.work(loser)?.id, winner, "a merged-away id must still resolve after relaunch")
    }

    @MainActor func testAnEmptyDirectoryLoadsAsAnEmptyStore() {
        let store = makeStore()

        XCTAssertNil(store.work(WorkID()))
        XCTAssertNil(store.workId(for: ListingKey(sourceId: "mangadex", mangaId: "nope")))
    }

    @MainActor func testMergingAWorkIntoItselfIsANoOp() {
        let store = makeStore()
        let id = store.mint(from: listing("md-1", title: "Solo Leveling"))

        store.merge(id, into: id)

        XCTAssertEqual(store.work(id)?.listings.count, 1)
        XCTAssertEqual(store.work(id)?.displayTitle, "Solo Leveling")
    }
}
