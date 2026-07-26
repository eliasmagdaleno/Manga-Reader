//
//  UpgradeAttemptMemoryTests.swift
//  Manga-ReaderTests
//
//  The queue's record of what already failed (ADR-0008). Each test gets its own temp
//  directory, so the JSON file under test is never shared and never the real one.
//

import XCTest
@testable import Manga_Reader

final class UpgradeAttemptMemoryTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    @MainActor
    private func makeMemory() -> UpgradeAttemptMemory {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UpgradeAttemptMemoryTests-\(UUID().uuidString)")
        return UpgradeAttemptMemory(directory: dir)
    }

    private func work(_ id: WorkID, titles: [String]) -> Work {
        Work(id: id, displayTitle: titles.first ?? "", knownTitles: titles,
             externalIds: ExternalIDs(), listings: [], snapshot: nil)
    }

    /// A miss means "no confident match **given these titles**", so the title count is the
    /// fingerprint. When a Listing links or a provider contributes synonyms, the miss is
    /// stale immediately rather than in fourteen days — and the count is sound as a
    /// fingerprint because `knownTitles` only ever appends.
    @MainActor func testAnUnmatchedWorkIsSuppressedUntilItsTitleCountChanges() {
        let memory = makeMemory()
        let id = WorkID()
        memory.record(.unmatched(knownTitlesCount: 1), for: id, now: noon)

        XCTAssertTrue(memory.suppresses(work(id, titles: ["Only I Level Up"]), now: noon))
        XCTAssertFalse(memory.suppresses(work(id, titles: ["Only I Level Up", "Solo Leveling"]),
                                         now: noon),
                       "a new title is new evidence — re-ask now, don't wait for the TTL")
    }

    /// The asymmetry that justifies two outcomes rather than one timestamp. Once
    /// resolution succeeds, the Work has stopped being a resolution case — re-matching
    /// yields the same id forever, so more titles are not new evidence here.
    @MainActor func testAnAbsentFromProviderWorkIsNotReopenedByNewTitles() {
        let memory = makeMemory()
        let id = WorkID()
        memory.record(.absentFromProvider(malId: 123), for: id, now: noon)

        XCTAssertTrue(memory.suppresses(work(id, titles: ["A"]), now: noon))
        XCTAssertTrue(memory.suppresses(work(id, titles: ["A", "B", "C"]), now: noon),
                      "AniList will 404 the same id no matter what we call it")
    }

    /// The backstop for both. AniList adds entries over time, so nothing here is terminal.
    @MainActor func testTheTTLReopensBothOutcomes() {
        let memory = makeMemory()
        let unmatched = WorkID()
        let absent = WorkID()
        memory.record(.unmatched(knownTitlesCount: 1), for: unmatched, now: noon)
        memory.record(.absentFromProvider(malId: 123), for: absent, now: noon)
        let later = noon.addingTimeInterval(UpgradeAttemptMemory.ttl)

        XCTAssertFalse(memory.suppresses(work(unmatched, titles: ["A"]), now: later))
        XCTAssertFalse(memory.suppresses(work(absent, titles: ["A"]), now: later))
    }

    /// A transient failure records nothing at all, so an outage cannot poison the memory
    /// for the TTL. From this side that is simply an absent entry.
    @MainActor func testAWorkWithNoRecordIsNeverSuppressed() {
        let memory = makeMemory()

        XCTAssertFalse(memory.suppresses(work(WorkID(), titles: ["A"]), now: noon))
    }

    /// A successful upgrade drops the record. The fresh snapshot already makes the Work
    /// ineligible, so this is about not hoarding answers to questions nobody will ask.
    @MainActor func testForgettingAWorkClearsItsSuppression() {
        let memory = makeMemory()
        let id = WorkID()
        memory.record(.unmatched(knownTitlesCount: 1), for: id, now: noon)

        memory.forget(id)

        XCTAssertFalse(memory.suppresses(work(id, titles: ["A"]), now: noon))
    }

    /// The whole point of a file: a drain that ends when the app is closed must not start
    /// over from scratch on the next launch.
    @MainActor func testAttemptsSurviveAReload() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("UpgradeAttemptMemoryTests-\(UUID().uuidString)")
        let id = WorkID()
        let first = UpgradeAttemptMemory(directory: dir)
        first.record(.absentFromProvider(malId: 123), for: id, now: noon)
        first.flush()

        let reloaded = UpgradeAttemptMemory(directory: dir)

        XCTAssertTrue(reloaded.suppresses(work(id, titles: ["A"]), now: noon))
        XCTAssertFalse(reloaded.suppresses(work(id, titles: ["A"]),
                                           now: noon.addingTimeInterval(UpgradeAttemptMemory.ttl)),
                       "the TTL is measured from the original attempt, not from the reload")
    }
}
