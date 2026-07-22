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

    /// Throwaway live-verification for Task 3 (MAL networking + debug screen): drives
    /// Settings → "MyAnimeList Client" → search "One Piece" → tap a result, and asserts
    /// (not just screenshots) that real search results and a real detail payload
    /// (synopsis/genres/related/recommendations) rendered from the live MAL API. This
    /// is this codebase's established technique for verifying network code with no
    /// mocking harness (see `testHomeAndDetailScreenshots` above for the same pattern
    /// against MangaDex). Leave this test in place — whether it should stay long-term
    /// once the real "More Like This" UI ships is a call for a human, not this test.
    func testMyAnimeListDebugScreenLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        // Navigate to Settings. Retry the tab tap: on a slow/loaded Home tab the first
        // tap can land while the app is still busy and get swallowed.
        let settingsNavTitle = app.navigationBars["Settings"]
        var reachedSettings = false
        for _ in 0..<3 {
            app.tabBars.buttons["Settings"].tap()
            if settingsNavTitle.waitForExistence(timeout: 8) {
                reachedSettings = true
                break
            }
        }
        XCTAssertTrue(reachedSettings, "should have navigated to the Settings tab")

        let malRow = app.buttons["malClientRow"]
        XCTAssertTrue(malRow.waitForExistence(timeout: 10),
                      "the DEBUG 'MyAnimeList Client' row should be on Settings")

        // Retry the tap into the debug screen too — same rationale as the tab switch.
        let searchField = app.textFields["malSearchField"]
        var reachedDebugScreen = false
        for _ in 0..<3 {
            malRow.tap()
            if searchField.waitForExistence(timeout: 8) {
                reachedDebugScreen = true
                break
            }
        }
        XCTAssertTrue(reachedDebugScreen, "the MAL debug search field should be present")

        // Retry the tap-to-focus too: typeText fails outright ("Neither element nor any
        // descendant has keyboard focus") if the tap didn't land while this app is busy.
        var focused = false
        for _ in 0..<3 {
            searchField.tap()
            if app.keyboards.element.waitForExistence(timeout: 5) {
                focused = true
                break
            }
        }
        XCTAssertTrue(focused, "the search field should have keyboard focus before typing")
        searchField.typeText("One Piece")

        let searchButton = app.buttons["malSearchButton"]
        XCTAssertTrue(searchButton.exists)
        searchButton.tap()

        // Ground truth: a result row must actually appear (proves searchManga() +
        // the node-unwrapping worked against the real API, not a fixture). Poll for
        // either a result or an error (e.g. .rateLimited) rather than a single fixed
        // wait — MAL's Retry-After on a 429 can itself run tens of seconds, and this
        // test has hammered the live search endpoint a lot while being developed.
        let firstResult = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'malResultRow_'")
        ).firstMatch
        let searchErrorMessage = app.staticTexts["malErrorMessage"]
        var resultAppeared = false
        var searchErrorAppeared = false
        let searchDeadline = Date().addingTimeInterval(90)
        while Date() < searchDeadline {
            if firstResult.exists { resultAppeared = true; break }
            if searchErrorMessage.exists { searchErrorAppeared = true; break }
            usleep(500_000)
        }
        attach(app, name: "01-mal-search-results")
        if searchErrorAppeared {
            XCTFail("searchManga() surfaced an error instead of results: \(searchErrorMessage.label)")
        }
        XCTAssertTrue(resultAppeared,
                      "a search result row should render from the live MAL API")

        // Tap into detail, then poll for either outcome: the detail title rendering, or
        // an error surfacing (e.g. .missingClientID / an HTTP status / .rateLimited
        // after MAL's 429 retry-after wait). This also swipes the List up periodically:
        // the Detail section is appended after up to 10 Results rows, and SwiftUI's
        // List is lazy — a row that hasn't scrolled into view yet isn't materialized as
        // an XCUIElement at all, so `.exists` alone stays false even after the data has
        // loaded. (Verified live while writing this test: a temporary file-marker
        // diagnostic in loadDetail() proved mangaDetail() was resolving successfully —
        // real title, 27 related, 10 recommendations — long before the query found it,
        // which is what pointed at "not materialized," not "never fetched.")
        //
        // The outer attempt loop guards against this app's occasional swallowed-first-tap
        // flakiness (seen at every other navigation step above too, while Home's rails
        // are still loading in the background) — bounded at 2 attempts, not spammed,
        // since a real in-flight network request shouldn't be interrupted by a re-tap.
        let detailTitle = app.staticTexts["malDetailTitle"]
        let errorMessage = app.staticTexts["malErrorMessage"]
        var detailAppeared = false
        var errorAppeared = false
        for attempt in 0..<2 {
            firstResult.tap()
            let budget: TimeInterval = attempt == 0 ? 60 : 90
            let deadline = Date().addingTimeInterval(budget)
            while Date() < deadline {
                if detailTitle.exists { detailAppeared = true; break }
                if errorMessage.exists { errorAppeared = true; break }
                app.swipeUp()
                usleep(500_000)
            }
            if detailAppeared || errorAppeared { break }
        }
        sleep(2) // let synopsis/genres/related/recommendations text finish laying out
        attach(app, name: "02-mal-detail")

        if errorAppeared {
            XCTFail("mangaDetail() surfaced an error instead of detail: \(errorMessage.label)")
        }
        XCTAssertTrue(detailAppeared,
                      "the MAL detail title should render from the live API")

        // The actual point of this verification: related manga and/or recommendations
        // (not just title/synopsis) must have rendered from the real API response.
        // These rows sit even further down (One Piece has 27 related entries before
        // Recommendations even starts), so keep swiping until one header appears.
        let relatedHeader = app.staticTexts["malRelatedHeader"]
        let recommendationsHeader = app.staticTexts["malRecommendationsHeader"]
        var relatedOrRecsAppeared = relatedHeader.exists || recommendationsHeader.exists
        let relatedDeadline = Date().addingTimeInterval(30)
        while !relatedOrRecsAppeared && Date() < relatedDeadline {
            app.swipeUp()
            usleep(500_000)
            relatedOrRecsAppeared = relatedHeader.exists || recommendationsHeader.exists
        }
        // Rows can exist in the AX tree slightly ahead of what's actually scrolled into
        // the visible viewport (List prefetches nearby cells). Swipe a couple more times
        // so the screenshot below actually shows Related/Recommendations content on
        // screen, not just proves it exists off-screen.
        for _ in 0..<3 {
            app.swipeUp()
            usleep(300_000)
        }
        attach(app, name: "03-mal-related-recommendations")
        XCTAssertTrue(relatedOrRecsAppeared,
                      "Related and/or Recommendations should render from the live API's " +
                      "related_manga / recommendations fields")
    }

    /// Throwaway live-verification for cross-source entity resolution: drives the MAL
    /// debug screen's "Resolve source title" field with a title whose MAL main title
    /// differs from the scraped one ("Attack on Titan" → Shingeki no Kyojin), proving the
    /// alt-title fuzzy path lands on the right MAL entry against the real API. Same
    /// no-mock live technique as testMyAnimeListDebugScreenLiveVerification; keeping it
    /// long-term is a human call (it hits the network and is slow).
    func testMALEntityResolutionLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsNavTitle = app.navigationBars["Settings"]
        var reachedSettings = false
        for _ in 0..<3 {
            app.tabBars.buttons["Settings"].tap()
            if settingsNavTitle.waitForExistence(timeout: 8) { reachedSettings = true; break }
        }
        XCTAssertTrue(reachedSettings, "should have navigated to the Settings tab")

        let malRow = app.buttons["malClientRow"]
        XCTAssertTrue(malRow.waitForExistence(timeout: 10), "the DEBUG MAL row should be on Settings")

        let resolveField = app.textFields["malResolveField"]
        var reachedDebugScreen = false
        for _ in 0..<3 {
            malRow.tap()
            if resolveField.waitForExistence(timeout: 8) { reachedDebugScreen = true; break }
        }
        XCTAssertTrue(reachedDebugScreen, "the MAL resolve field should be present")

        var focused = false
        for _ in 0..<3 {
            resolveField.tap()
            if app.keyboards.element.waitForExistence(timeout: 5) { focused = true; break }
        }
        XCTAssertTrue(focused, "the resolve field should have keyboard focus before typing")
        resolveField.typeText("Attack on Titan")
        app.buttons["malResolveButton"].tap()

        // Ground truth: the resolver must land on Shingeki no Kyojin via the English
        // alternate title. Poll generously — MAL rate-limits and this does 2 requests.
        let result = app.staticTexts["malResolveResult"]
        XCTAssertTrue(result.waitForExistence(timeout: 90), "a resolve result should appear")
        attach(app, name: "mal-entity-resolution")  // existing screenshot helper in this file
        XCTAssertTrue(result.label.contains("Shingeki no Kyojin"),
                      "expected resolution to Shingeki no Kyojin, got: \(result.label)")
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    /// Throwaway live-verification for the More Like This provider via the debug screen:
    /// Settings → "MyAnimeList Client" → type a well-known title → "Find similar" → assert
    /// at least one resolved MangaDex recommendation row appears (proves forward resolution
    /// + MAL recommendations + reverse resolution against the real APIs). Retired with the
    /// debug screen once the real detail-page rail is proven (see the rail test below).
    func testMoreLikeThisDebugProbeLiveVerification() throws {
        let app = XCUIApplication()
        app.launch()

        // Settings tab (retry — a busy Home can swallow the first tap).
        let settingsNavTitle = app.navigationBars["Settings"]
        var reachedSettings = false
        for _ in 0..<3 {
            app.tabBars.buttons["Settings"].tap()
            if settingsNavTitle.waitForExistence(timeout: 8) { reachedSettings = true; break }
        }
        XCTAssertTrue(reachedSettings, "should have navigated to the Settings tab")

        let malRow = app.buttons["malClientRow"]
        XCTAssertTrue(malRow.waitForExistence(timeout: 10),
                      "the DEBUG 'MyAnimeList Client' row should be on Settings")

        let mltField = app.textFields["mltField"]
        var reachedDebugScreen = false
        for _ in 0..<3 {
            malRow.tap()
            if mltField.waitForExistence(timeout: 8) { reachedDebugScreen = true; break }
        }
        XCTAssertTrue(reachedDebugScreen, "the More Like This probe field should be present")

        // Focus + type (retry — typeText fails if the tap didn't land while busy).
        var focused = false
        for _ in 0..<3 {
            mltField.tap()
            if app.keyboards.element.waitForExistence(timeout: 5) { focused = true; break }
        }
        XCTAssertTrue(focused, "the probe field should have keyboard focus before typing")
        mltField.typeText("Berserk")

        let button = app.buttons["mltButton"]
        XCTAssertTrue(button.exists)
        button.tap()

        // Ground truth: at least one resolved MangaDex recommendation row. Poll generously
        // — this hits MAL search + detail + several MangaDex searches serially/concurrently.
        let firstResult = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'mltResultRow_'")
        ).firstMatch
        var appeared = false
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if firstResult.exists { appeared = true; break }
            usleep(500_000)
        }
        XCTAssertTrue(appeared, "at least one More Like This recommendation should resolve from the live APIs")
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
}
