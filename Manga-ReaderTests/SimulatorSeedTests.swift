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
            // A refused row is deliberately left provisional — that is the state the
            // ADR-0018 guard exists to release, so the fixture has to contain it.
            guard row.refusal == nil else {
                XCTAssertNil(work.snapshot,
                             "\(row.title) is a refusal but was upgraded anyway")
                continue
            }
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
        for row in SimulatorSeed.sampleRows where row.refusal == nil {
            let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: row.sourceId,
                                                               mangaId: row.mangaId)))
            XCTAssertNotNil(works.work(id)?.snapshot,
                            "\(row.title) has no snapshot; a duplicate was minted")
        }
    }

    /// The in-place run wipes the app's own defaults for these keys before seeding, so
    /// the list has to be exactly what the seed writes. Too short and stale state from a
    /// previous fixture survives underneath the new one; too long and the run deletes a
    /// key the app owns and the seed never sets.
    ///
    /// `taste.notInterested` / `taste.moreLikeThis` are deliberately excluded — they hold
    /// explicit user feedback, and a fixture that pre-dismisses titles would silently
    /// subtract from every recommendation run made against it.
    @MainActor
    func testSeededDefaultsKeysAreExactlyWhatTheSeedWrites() throws {
        let (works, _) = makeStore()
        let name = "seed-keys-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works,
                            history: HistoryStore(defaults: defaults, works: works,
                                                  saveInterval: 0),
                            library: LibraryStore(defaults: defaults, works: works))

        // The suite's *own* domain, not `dictionaryRepresentation()`: that one merges the
        // whole search list, so it answers with the simulator's globals as well as ours.
        let written = try XCTUnwrap(UserDefaults().persistentDomain(forName: name)).keys
        XCTAssertEqual(Set(written), Set(SimulatorSeed.seededDefaultsKeys),
                       "the seed writes a different set of keys than the run clears")
    }

    /// A fixture with nothing but successes cannot exercise the ADR-0018 guard: the
    /// interesting behaviour is a Work the queue has already refused, and whether an
    /// authoritative id releases it. So the seed carries both refusal shapes, and this
    /// asserts they actually suppress — a stored `knownTitlesCount` that no longer
    /// matches what `mint` produces would silently stop suppressing, and the fixture
    /// would look fine while testing nothing.
    @MainActor
    func testSeedRecordsRefusalsThatActuallySuppress() throws {
        let (works, dir) = makeStore()
        let memory = UpgradeAttemptMemory(directory: dir, saveDebounce: 0)

        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works, attempts: memory)

        let refused = SimulatorSeed.sampleRows.filter { $0.refusal != nil }
        XCTAssertFalse(refused.isEmpty, "the sample rows contain no refusal")
        XCTAssertTrue(refused.contains { if case .unmatched = $0.refusal { return true }
                                         else { return false } },
                      "no .unmatched refusal in the seed")
        XCTAssertTrue(refused.contains { if case .absentFromProvider = $0.refusal { return true }
                                         else { return false } },
                      "no .absentFromProvider refusal in the seed")

        for row in SimulatorSeed.sampleRows {
            let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: row.sourceId,
                                                               mangaId: row.mangaId)))
            let work = try XCTUnwrap(works.work(id))
            XCTAssertEqual(memory.suppresses(work), row.refusal != nil,
                           "\(row.title) suppression does not match its row")
        }
    }

    /// The refusals only reach the simulator if they land in `upgrade-attempts.json`, and
    /// `record` writes through a debounce — the same throttle that made the history half
    /// arrive empty until the seed learned to flush.
    @MainActor
    func testSeedFlushesUpgradeAttemptsToDisk() throws {
        let (works, dir) = makeStore()
        let memory = UpgradeAttemptMemory(directory: dir, saveDebounce: 60)

        SimulatorSeed.apply(SimulatorSeed.sampleRows, to: works, attempts: memory)

        let file = dir.appendingPathComponent("upgrade-attempts.json")
        let data = try XCTUnwrap(try? Data(contentsOf: file),
                                 "upgrade-attempts.json was never written")
        // Read back through a fresh memory rather than the JSON shape, which is private
        // to the store on purpose.
        let reloaded = UpgradeAttemptMemory(directory: dir, saveDebounce: 0)
        let refusedTitles = SimulatorSeed.sampleRows.filter { $0.refusal != nil }.map(\.title)
        for title in refusedTitles {
            let row = try XCTUnwrap(SimulatorSeed.sampleRows.first { $0.title == title })
            let id = try XCTUnwrap(works.workId(for: ListingKey(sourceId: row.sourceId,
                                                               mangaId: row.mangaId)))
            XCTAssertTrue(reloaded.suppresses(try XCTUnwrap(works.work(id))),
                          "\(title)'s refusal did not survive the round trip")
        }
        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - The seeding run

    /// The run itself. **It writes into the booted simulator's live app container**, and
    /// is skipped unless `scripts/seed-simulator.sh` has dropped its marker file there.
    ///
    /// In place, rather than to a staging directory the script copies from: this target is
    /// hosted by the app, so the test process already runs inside the very container the
    /// fixture is for — `WorkStore()`'s default directory *is* the app's Application
    /// Support, and `UserDefaults.standard` *is* the app's domain. Writing anywhere else
    /// would mean re-deriving both locations in shell and copying between them, which is
    /// two more things to get wrong than seeding through the stores directly.
    ///
    /// The gate is a marker file rather than an environment variable because `xcodebuild`
    /// forwards no environment into the test process — verified, with and without the
    /// `TEST_RUNNER_` prefix. A marker the script drops into a container it located with
    /// `simctl get_app_container` cannot be tripped by an ordinary `xcodebuild test` or
    /// by CI, which is the property that matters for a destructive run.
    ///
    /// **Backing up the container is the script's job**, and it does that before writing
    /// the marker. By the time this runs, clobbering is the intent.
    @MainActor
    func testSeedTheBootedSimulatorInPlace() throws {
        let marker = SimulatorSeed.markerURL()
        guard FileManager.default.fileExists(atPath: marker.path) else {
            throw XCTSkip("no seeding marker; run scripts/seed-simulator.sh to seed")
        }
        // Consumed first, so a crash mid-seed cannot leave a marker that re-fires the
        // destructive path on the next ordinary test run.
        try FileManager.default.removeItem(at: marker)

        let support = WorkStore.applicationSupportDirectory()
        let defaults = UserDefaults.standard
        // Seeding *onto* an existing fixture would merge, not replace — the stores load
        // what is there and mint alongside it. Clear the halves the seed owns, and only
        // those: the caches half rebuilds itself and is not ours to touch.
        for name in ["works.json", "upgrade-attempts.json"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
        for key in SimulatorSeed.seededDefaultsKeys { defaults.removeObject(forKey: key) }

        let works = WorkStore(directory: support, saveDebounce: 0)
        let attempts = UpgradeAttemptMemory(directory: support, saveDebounce: 0)
        SimulatorSeed.apply(SimulatorSeed.fixtureRows, to: works,
                            history: HistoryStore(defaults: defaults, works: works,
                                                  saveInterval: 0),
                            library: LibraryStore(defaults: defaults, works: works),
                            attempts: attempts)
        works.flush()
        defaults.synchronize()

        // Assert against the container, not the in-memory stores: the whole point of the
        // run is that the bytes reached the app's own locations.
        XCTAssertEqual(works.allWorkIds().count, SimulatorSeed.fixtureRows.count)
        for name in ["works.json", "upgrade-attempts.json"] {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: support.appendingPathComponent(name).path),
                "\(name) is missing from the app container after seeding")
        }
        for key in SimulatorSeed.seededDefaultsKeys {
            XCTAssertNotNil(defaults.data(forKey: key), "\(key) never reached the app's defaults")
        }
        print("seeded \(SimulatorSeed.fixtureRows.count) rows into \(support.path)")
    }
}
