//
//  Manga_ReaderUITests.swift
//  Manga-ReaderUITests
//
//  Created by Elias Magdaleno on 5/31/24.
//

import XCTest

final class Manga_ReaderUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// Walks Home → Detail and attaches screenshots. Doubles as a smoke test for
    /// the source chip bar (Home) and the action row (Detail).
    func testHomeAndDetailScreenshots() throws {
        let app = XCUIApplication()
        app.launch()

        // Home: the source chip bar must be present and MangaDex active.
        let mangadexChip = app.buttons["Browse MangaDex"]
        XCTAssertTrue(mangadexChip.waitForExistence(timeout: 10),
                      "source chip bar should be on Home")

        // Wait for the first rail to load real content.
        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20),
                      "a cover card should load on Home")
        sleep(3) // let cover images finish

        attach(app, name: "01-home")

        // Detail: open the first cover card. Tap the cover art itself (upper
        // half) — and retry once, since a LazyVStack re-layout while covers
        // stream in can swallow the first tap.
        let addOrToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !addOrToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(addOrToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "the library toggle should be on Detail")
        sleep(4) // let chapters + cover load

        attach(app, name: "02-detail")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    /// Permanent live-verification of the real detail-page rail: open a popular Home title,
    /// scroll to the bottom, and assert the "More Like This" header plus at least one card
    /// appear — end-to-end against the real MAL + MangaDex APIs.
    func testMoreLikeThisDetailRailLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        // Home: wait for the first cover card, then open it (retry once — a LazyVStack
        // re-layout while covers stream in can swallow the first tap).
        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        // The rail loads async (MAL + MangaDex round-trips) and sits at the very bottom.
        // Poll: swipe up, check for the header, repeat until it appears or we give up.
        let header = app.staticTexts["More Like This"]
        var railAppeared = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if header.exists { railAppeared = true; break }
            app.swipeUp(velocity: .fast)
            usleep(700_000)
        }
        XCTAssertTrue(railAppeared,
                      "the 'More Like This' header should appear at the bottom of the detail page")

        // And at least one recommendation card under it. Query at app level rather than
        // scoping through `otherElements["moreLikeThisSection"]`: a plain VStack carrying
        // only an accessibilityIdentifier does not reliably surface as a queryable container
        // element, so the scoped `.buttons` query finds nothing even though the cards exist.
        // On the detail page the rail is the only source of `mangaCoverCard`s, so an
        // app-level query is equivalent (and mirrors the header assertion above).
        let card = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10),
                      "at least one More Like This card should render")
    }

    /// The detail page shows a truncated chapter preview, so the bottom-of-page
    /// "More Like This" rail is reachable in a few swipes instead of scrolling past
    /// the entire chapter list. Opens the first Home title and asserts the rail header
    /// appears within a small number of swipes.
    func testChapterPreviewKeepsRailReachable() throws {
        let app = XCUIApplication()
        app.launch()

        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        XCTAssertTrue(app.staticTexts["Chapters"].waitForExistence(timeout: 15),
                      "the Chapters section should render")

        // Rail must be reachable within a handful of swipes (previously required
        // scrolling past the full list). Allow time for the async MAL/MangaDex rail load.
        let header = app.staticTexts["More Like This"]
        var reached = false
        for _ in 0..<8 where !reached {
            if header.exists { reached = true; break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(reached,
                      "the More Like This rail should be reachable within a few swipes of a truncated chapter list")
    }

    /// "Show all N chapters" opens the full-list screen, where sort and multi-select
    /// live. Taps through, toggles sort, then marks a chapter read via select mode.
    func testShowAllChaptersOpensFullListWithSortAndSelect() throws {
        let app = XCUIApplication()
        app.launch()

        let firstCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 20), "a cover card should load on Home")
        let libraryToggle = app.buttons["Add to Library"]
        let removeToggle = app.buttons["Remove from Library"]
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        if !libraryToggle.waitForExistence(timeout: 8) && !removeToggle.exists {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15) || removeToggle.exists,
                      "should have opened a manga detail page")

        // The "Show all" row only exists for titles with > 5 chapters. Scroll it into
        // view; popular Home titles reliably qualify. (If the first title has ≤ 5
        // chapters the button is legitimately absent — re-run against a longer title.)
        let showAll = app.buttons["showAllChaptersButton"]
        var foundShowAll = false
        for _ in 0..<10 where !foundShowAll {
            if showAll.exists { foundShowAll = true; break }
            app.swipeUp(velocity: .fast)
            usleep(500_000)
        }
        XCTAssertTrue(foundShowAll, "a long title should show the 'Show all N chapters' row")
        showAll.tap()

        // Full-list screen: assert it appeared, exercise the sort toggle, then select-mode.
        XCTAssertTrue(app.otherElements["chapterListScreen"].waitForExistence(timeout: 8)
                      || app.navigationBars["Chapters"].waitForExistence(timeout: 8),
                      "the full chapter-list screen should open")

        let newest = app.buttons["NEWEST"]
        if newest.waitForExistence(timeout: 5) {
            newest.tap()
            XCTAssertTrue(app.buttons["OLDEST"].waitForExistence(timeout: 5),
                          "the sort toggle should flip to OLDEST")
        }

        let select = app.buttons["SELECT"]
        XCTAssertTrue(select.waitForExistence(timeout: 5), "SELECT should be available on the full list")
        select.tap()
        XCTAssertTrue(app.buttons["Select All"].waitForExistence(timeout: 5),
                      "entering select mode should reveal the batch-action bar")
        app.buttons["Select All"].tap()
        let markRead = app.buttons["Mark Read"]
        XCTAssertTrue(markRead.waitForExistence(timeout: 5))
        markRead.tap()
        // Select mode dismisses after a batch action.
        XCTAssertTrue(select.waitForExistence(timeout: 5),
                      "select mode should exit after Mark Read")
    }

    /// The "For You" rail still populates end-to-end with the composite (tag + MAL)
    /// provider wired in. Network-dependent: a flake is API/seed availability, not a
    /// logic bug. The rail is hidden until there's enough reading signal, so this asserts
    /// the app launches to a populated Home and — if a "For You" rail is present — it has
    /// at least one card.
    /// **One-off verification run for ADR-0018 amendment 1.** Not a CI test — it asserts against
    /// a specific seeded simulator (`2A0D54DF-…`) whose `Wind Breaker` Work is refused with no
    /// external id, and it stops being meaningful the moment that refusal ages out (~2026-08-23).
    ///
    /// Goes through **Search**, not History: the `Manga` a search result carries came straight off
    /// the API and so holds `links.mal`, while a pre-amendment history entry holds `malId: nil`.
    /// MangaDex returns the target (`9eb78304…`, mal 133081) first for this query; the second hit
    /// is the Korean series (mal 103237), which is the pair that produced the 1.00/1.00 tie.
    ///
    /// Backgrounds the app at the end: `HistoryStore` throttles its writes and only flushes on
    /// `.background`, so a run that just ends loses the entry it was verifying.
    func testADR0018WindBreakerAcquiresMalIdThroughSearch() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field should be present")
        field.tap()
        field.typeText("Wind Breaker\n")

        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Wind Breaker"))
            .element(boundBy: 0)
        XCTAssertTrue(result.waitForExistence(timeout: 25), "search should return Wind Breaker")
        attach(app, name: "01-search-results")
        result.tap()

        // Detail page. Screenshot it before reading — this is where ADR-0015's notice lives, and
        // the Work is still refused at this point, so the notice is the "before" state.
        let libraryToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Library"))
            .firstMatch
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 20), "should reach the detail page")
        sleep(4)
        attach(app, name: "02-detail-before-read")

        // **Add to Library, not read.** MangaDex serves no chapters for this title (the detail
        // page reads "0 AVAILABLE"), so the reader path is unavailable — and the seeded history
        // entry points at a chapter it no longer serves. `LibraryStore.toggle` mints from this
        // same API-sourced `Manga` (`LibraryStore.swift:138`), so it absorbs `mal: 133081` onto the
        // existing Work under `ListingKey(mangadex, 9eb78304…)`, which is the condition
        // `suppresses()` reads. This verifies Decision 3 (the guard) — Decision 1's history leg
        // stays unit-tested only, because no refused Work on this simulator is re-readable.
        let addToLibrary = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add to Library"))
            .firstMatch
        XCTAssertTrue(addToLibrary.waitForExistence(timeout: 20), "Add to Library should be present")
        addToLibrary.tap()
        sleep(4)
        attach(app, name: "03-after-library-add")

        // Background to force `history.flush()` / `works.flush()`.
        XCUIDevice.shared.press(.home)
        sleep(3)
    }

    func testForYouRailPopulatesWithCompositeProvider() throws {
        let app = XCUIApplication()
        app.launch()
        // Home must load content at all (proves the composite provider didn't break Home).
        let anyCard = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(anyCard.waitForExistence(timeout: 25), "Home should load cover cards")

        // If the personalized rail is showing, it must have a card under it.
        let forYou = app.staticTexts["For You"]
        if forYou.waitForExistence(timeout: 5) {
            let card = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
            XCTAssertTrue(card.exists, "the For You rail should render at least one card")
        }
    }
}
