//
//  AppCompositionTests.swift
//  Manga-ReaderTests
//
//  The one thing every other test cannot see: whether the *app* wires the graph the way
//  the ADRs say it does. Every engine test builds its own engine and passes its own
//  `tagBlocked`, so deleting that argument from the composition root breaks none of them —
//  the rail would simply stop explaining itself, silently, which is the exact failure
//  ADR-0015 exists to prevent.
//
//  These build the real `AppComposition` against a temp directory and an isolated
//  `UserDefaults`. No network: every assertion below is on a *closed* gate, and the engine
//  refuses before it ever asks a provider for candidates.
//
//  **The view branch stays manual, deliberately.** `HomeView.swift:74` renders
//  `ForYouUnavailableNotice` for the state these tests drive, and covering *that* would need
//  a launch-argument seam shipping in the app — to test one `else if` whose decision is
//  already asserted here and in the engine's own rail-state tests. It is verified instead by
//  the two-phase simulator recipe in the 2026-08-08 handoff, which is also the only tool that
//  could have caught ADR-0015's amendment 6 (a notice that read as an error banner). The
//  identifier `forYouUnavailableNotice` is in place if that trade is ever revisited.
//

import XCTest
@testable import Manga_Reader

@MainActor
final class AppCompositionTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppCompositionTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "AppCompositionTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removeSuite(named: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeComposition() -> AppComposition {
        AppComposition(defaults: defaults, directory: directory)
    }

    /// Reads a manga from a scraping source under an opaque id, so nothing can tag it —
    /// the untaggable case, minted through the app's own commitment path rather than
    /// inserted into `WorkStore` directly.
    private func untaggedRead(_ composition: AppComposition, _ id: String) {
        composition.history.record(
            manga: Manga(id: id, sourceId: "weebcentral", title: "Title \(id)",
                         description: "", status: "ongoing", year: nil, coverURL: nil, malId: nil),
            chapter: Chapter(id: "c-\(id)", number: "1", title: nil),
            position: ReadingPosition(page: 9),
            pageCount: 10)
    }

    /// The wiring claim, in the only form that can fail: the engine's rail state has to
    /// *change* when the queue's attempt memory changes. One instance is passed to both
    /// `MetadataUpgradeQueue(memory:)` and `RecommendationEngine(tagBlocked:)`, and if that
    /// ever stops being true this test is what says so.
    ///
    /// Both halves matter. The first proves `tagBlocked` is not wired to a constant `true`
    /// (which would make the second pass for the wrong reason); the second proves the
    /// engine is reading *this* memory rather than a private one of its own.
    func testRailStateFollowsTheQueuesAttemptMemory() async throws {
        let composition = makeComposition()
        for i in 1...3 { untaggedRead(composition, "m\(i)") }

        await composition.engine.refresh()
        XCTAssertEqual(composition.engine.railState, .needMoreReading(tagged: 0, needed: 3),
                       "with nothing recorded, untagged Works are still in play")

        // Exactly what the drain writes when MyAnimeList returns no confident match.
        for id in composition.works.allWorkIds() {
            guard let work = composition.works.work(id) else { continue }
            composition.attempts.record(.unmatched(knownTitlesCount: work.knownTitles.count),
                                        for: work.id)
        }

        await composition.engine.refresh()
        XCTAssertEqual(composition.engine.railState, .noTaggableSignal,
                       "the rail must see the drain's own records, not a memory of its own")
    }

    /// ADR-0007: the commitment paths mint into one `WorkStore`. Reading a title has to be
    /// visible to the store the engine and the queue were handed, or the Works minted by
    /// reading would be invisible to everything that consumes them.
    func testCommitmentPathsMintIntoTheSharedWorkStore() {
        let composition = makeComposition()
        XCTAssertTrue(composition.works.allWorkIds().isEmpty)

        untaggedRead(composition, "m1")

        XCTAssertEqual(composition.works.allWorkIds().count, 1,
                       "reading must mint into the WorkStore the composition shares")
    }
}
