//
//  SimulatorSeedTests.swift
//  Manga-ReaderTests
//
//  Builds the seeded-simulator fixture by driving the **real** stores, so the fixture
//  cannot drift from the app's own encoders. A hand-rolled works.json would decode into
//  something subtly wrong the day `Work` changes shape, and a fixture you cannot trust is
//  worse than no fixture — this project has paid for that lesson once already, when the
//  seeded simulator was erased and the ADR-0020 AniList arm lost its instrument.
//
//  The seeding *run* is `testWriteSeedToDisk`, which is skipped unless `SEED_SIMULATOR_OUT`
//  names an output directory. Everything else here is an ordinary unit test of the builder
//  and runs on every `xcodebuild test`, including CI.
//

import XCTest
@testable import Manga_Reader

final class SimulatorSeedTests: XCTestCase {

    @MainActor
    private func makeStore() -> (WorkStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (WorkStore(directory: dir, saveDebounce: 0), dir)
    }

    /// The seed must mint one Work per listing and stamp each with the AniList snapshot
    /// its row carries — the same route `MetadataUpgradeQueue` takes when it upgrades a
    /// provisional Work, rather than a shortcut that writes the snapshot directly.
    @MainActor
    func testSeedMintsOneWorkPerRowWithItsSnapshot() throws {
        let (store, _) = makeStore()

        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: store)

        XCTAssertEqual(store.allWorkIds().count, SimulatorSeed.sampleRows.count)
        for row in SimulatorSeed.sampleRows {
            let id = try XCTUnwrap(store.workId(for: ListingKey(sourceId: row.sourceId,
                                                               mangaId: row.mangaId)),
                                   "no Work minted for \(row.title)")
            let work = try XCTUnwrap(store.work(id))
            XCTAssertEqual(work.externalIds.mal, row.malId, "\(row.title) lost its MAL id")
            let snapshot = try XCTUnwrap(work.snapshot, "\(row.title) has no snapshot")
            XCTAssertEqual(snapshot.provider, .anilist,
                           "\(row.title) kept its provisional snapshot")
            XCTAssertEqual(snapshot.tags.map(\.name), row.tags.map(\.name))
        }
    }

    /// The fixture exists to unblock the AniList arm, and that arm is dead without seed
    /// pairs. `TagPairSeeding` only counts a Work toward a pair when **both** legs sit at
    /// rank >= 60, so a seed can look full of tags and still produce nothing. This asserts
    /// the property the fixture is actually for, rather than the row count.
    @MainActor
    func testSeedClearsTheThreeWorkTagPairGate() throws {
        let (store, _) = makeStore()
        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: store)

        let works = store.allWorkIds().compactMap { store.work($0) }
        let weights = Dictionary(uniqueKeysWithValues: works.map { ($0.id, 1.0) })
        let pairs = seedPairs(works: works,
                              weights: weights,
                              vocabulary: TagVocabulary(fetchedAt: Date(), entries: []))

        let gated = pairs.filter { $0.contributingWorks.count >= 3 }
        XCTAssertFalse(gated.isEmpty,
                       "no tag pair reached 3 contributing Works; the AniList pool would "
                       + "have nothing to query. Pairs: "
                       + pairs.map { "\($0.pair.a)+\($0.pair.b)=\($0.contributingWorks.count)" }
                           .joined(separator: ", "))
    }
}
