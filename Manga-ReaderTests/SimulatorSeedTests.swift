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

    /// An isolated defaults suite, so seeding never touches the test runner's own
    /// `standard` defaults and each test starts empty.
    private func makeDefaults() -> UserDefaults {
        let name = "seed-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    /// The history and library halves must be written **by the real stores**, for the
    /// same reason `works.json` is: the keys and the encoders are theirs, and a
    /// hand-rolled copy drifts silently. This asserts the bytes that land in the suite
    /// decode back through the app's own Codables.
    @MainActor
    func testSeedWritesHistoryAndLibraryThroughTheRealStores() throws {
        let (works, _) = makeStore()
        let defaults = makeDefaults()
        let history = HistoryStore(defaults: defaults, works: works, saveInterval: 0)
        let library = LibraryStore(defaults: defaults, works: works)

        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works,
                            history: history, library: library)

        let entryData = try XCTUnwrap(defaults.data(forKey: "history.entries"),
                                      "no history written to the defaults suite")
        let entries = try JSONDecoder().decode([ReadingEntry].self, from: entryData)
        let expectedReads = SimulatorSeed.sampleRows.flatMap { $0.reading }
        XCTAssertEqual(entries.count, expectedReads.count)
        XCTAssertEqual(Set(entries.map(\.chapterId)), Set(expectedReads.map { $0.chapterId }))
        for entry in entries {
            XCTAssertEqual(entry.sourceId, "mangadex", "\(entry.mangaTitle) lost its source")
            XCTAssertNotNil(entry.malId, "\(entry.mangaTitle) lost its MAL id")
        }

        let itemData = try XCTUnwrap(defaults.data(forKey: "library.items"),
                                     "no library written to the defaults suite")
        // Qualified: SwiftUI ships a `LibraryItem` of its own, and `@testable import`
        // re-exports it into this file.
        let items = try JSONDecoder().decode([Manga_Reader.LibraryItem].self, from: itemData)
        let expectedSaved = SimulatorSeed.sampleRows.filter { $0.isSaved }.map { $0.mangaId }
        XCTAssertFalse(expectedSaved.isEmpty, "the sample rows save nothing to the library")
        XCTAssertEqual(Set(items.map { $0.id }), Set(expectedSaved))
    }

    /// Reading is a commitment, so history and library rows mint Works of their own
    /// (ADR-0007). If a seeded row were read or saved under a listing key the AniList
    /// upgrade never touched, the fixture would carry a provisional twin — a Work with no
    /// snapshot, invisible to the taste profile. One Work per row, not two.
    @MainActor
    func testHistoryAndLibraryRowsReuseTheMintedWork() throws {
        let (works, _) = makeStore()
        let defaults = makeDefaults()

        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works,
                            history: HistoryStore(defaults: defaults, works: works,
                                                  saveInterval: 0),
                            library: LibraryStore(defaults: defaults, works: works))

        XCTAssertEqual(works.allWorkIds().count, SimulatorSeed.sampleRows.count)
        for id in works.allWorkIds() {
            XCTAssertNotNil(works.work(id)?.snapshot,
                            "a seeded Work has no snapshot; a duplicate was minted")
        }
    }

    /// The seeding run hands the shell script a `defaults.json` of key -> base64, because
    /// `simctl spawn booted defaults write -data <hex>` is the only verified way to put
    /// real `Data` into a simulator app's defaults. Only the seeded keys may travel: the
    /// suite also holds Foundation's own bookkeeping, and writing that into the app's
    /// domain would be seeding noise the app never wrote.
    @MainActor
    func testDefaultsPayloadCarriesExactlyTheSeededKeysAsBase64() throws {
        let (works, _) = makeStore()
        let defaults = makeDefaults()
        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works,
                            history: HistoryStore(defaults: defaults, works: works,
                                                  saveInterval: 0),
                            library: LibraryStore(defaults: defaults, works: works))

        let payload = SimulatorSeed.defaultsPayload(from: defaults)

        XCTAssertEqual(Set(payload.keys), Set(SimulatorSeed.seededDefaultsKeys))
        for (key, encoded) in payload {
            XCTAssertEqual(Data(base64Encoded: encoded), defaults.data(forKey: key),
                           "\(key) did not round-trip through base64")
        }
    }
}
