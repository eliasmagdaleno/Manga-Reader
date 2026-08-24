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

    /// The signed-out MyAnimeList section, in the real Settings screen. It is the one state
    /// reachable without an account, and the only wiring that cannot be proven below the
    /// UI: that `MALAccountSettingsView` is actually in `SettingsView`, and that the store
    /// reaches it through the environment (a missing `environmentObject` traps at runtime,
    /// so this test failing is how that shows up).
    func testSettingsShowsTheSignedOutMyAnimeListSection() throws {
        let app = XCUIApplication()
        // Without this the test reads the real Keychain and preferences: it passes on a
        // fresh simulator and fails on any machine where someone has actually signed in.
        app.launchArguments.append("-uitest-mal-signed-out")
        app.launch()

        app.tabBars.buttons["Settings"].tap()

        let header = app.staticTexts["MyAnimeList"]
        XCTAssertTrue(header.waitForExistence(timeout: 10),
                      "the MyAnimeList section should be in Settings")
        XCTAssertTrue(app.buttons["Sign in"].exists,
                      "signed out, the section offers Sign in")
        XCTAssertFalse(app.staticTexts["Sync reading progress"].exists,
                       "signed out, no account controls are rendered")

        attach(app, name: "10-settings-mal-signed-out")
    }

    /// **The four MAL Settings states that had never been rendered on a device** (MAL plan,
    /// Task 12). Everything below the view — which branch a state maps to — is decided in
    /// `MALAccountPresentation` and tested there; what only a device can answer is whether
    /// the resulting section actually lays out, and at an accessibility text size whether it
    /// still fits. The screenshots are the artifact.
    ///
    /// Runs on a seeded stand-in account, never this device's real one.
    func testMyAnimeListSettingsStatesRender() throws {
        for state in ["signed-in", "refreshing", "reauthorization-required", "account-switch"] {
            let app = XCUIApplication()
            app.launchArguments += ["-uitest-mal-state", state]
            // A previous test can leave the simulator on its side, and these screenshots
            // are the deliverable. Set it rather than inherit it.
            XCUIDevice.shared.orientation = .portrait
            app.launch()
            app.tabBars.buttons["Settings"].tap()

            XCTAssertTrue(app.staticTexts["MyAnimeList"].waitForExistence(timeout: 10),
                          "the MyAnimeList section should be in Settings for \(state)")
            // The switch alert is modal, so nothing under it is hittable — that state's
            // screenshot is of the alert, which is the thing that had never been seen.
            if state != "account-switch" { scrollToMALSection(app) }
            // Every one of these is a signed-in-shaped section, so the sign-in offer must
            // be gone — that is what tells a rendered state from a silently signed-out one.
            XCTAssertFalse(app.buttons["Sign in"].exists,
                           "\(state) should not be offering a fresh sign-in")
            attach(app, name: "11-settings-mal-\(state)")

            if state == "account-switch" {
                XCTAssertTrue(app.buttons["Keep them"].waitForExistence(timeout: 5),
                              "the account-switch alert should be up")
                XCTAssertTrue(app.buttons["Delete queued updates"].exists)
                app.buttons["Keep them"].tap()
            }
            app.terminate()
        }
    }

    /// The signed-in section at the largest accessibility text size. Separate from the loop
    /// above because the size is set by a launch argument to the whole app, not by state.
    func testMyAnimeListSettingsAtAccessibilityTextSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-mal-state", "signed-in",
                                "-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.tabBars.buttons["Settings"].tap()

        XCTAssertTrue(app.staticTexts["MyAnimeList"].waitForExistence(timeout: 10),
                      "the MyAnimeList section should survive accessibility text sizes")
        scrollToMALSection(app)
        attach(app, name: "12-settings-mal-large-text")
    }

    /// Existing in the hierarchy is not the same as being on screen, and a screenshot of
    /// the section scrolled past proves nothing. MyAnimeList is the last section in
    /// Settings, so this scrolls to the bottom — stopping at the header would leave the
    /// card itself behind the tab bar, which is what the first attempt at this captured.
    private func scrollToMALSection(_ app: XCUIApplication) {
        let header = app.staticTexts["MyAnimeList"]
        for _ in 0..<8 where !header.isHittable {
            app.swipeUp(velocity: .fast)
            usleep(400_000)
        }
        XCTAssertTrue(header.isHittable, "the MyAnimeList section should be reachable on screen")
        // Past the header, to the end of the scroll view.
        for _ in 0..<3 {
            app.swipeUp(velocity: .fast)
            usleep(400_000)
        }
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
        // Any of the detail page's library labels ("Add to Library", "In Library",
        // "Remove from Library") proves it opened — which one shows depends on whether this
        // device already has the title, and Home's ranking drifts, so naming one is a
        // coin flip the test would lose.
        let libraryToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Library"))
            .firstMatch
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        // Retry only while the card is still there to tap. Once the push has happened the
        // same coordinate lands on the detail page and can navigate deeper, out of reach of
        // the assertion below — a slow detail page would then read as a broken one.
        if !libraryToggle.waitForExistence(timeout: 8) && firstCard.isHittable {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15),
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
        // Any of the detail page's library labels ("Add to Library", "In Library",
        // "Remove from Library") proves it opened — which one shows depends on whether this
        // device already has the title, and Home's ranking drifts, so naming one is a
        // coin flip the test would lose.
        let libraryToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Library"))
            .firstMatch
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        // Retry only while the card is still there to tap. Once the push has happened the
        // same coordinate lands on the detail page and can navigate deeper, out of reach of
        // the assertion below — a slow detail page would then read as a broken one.
        if !libraryToggle.waitForExistence(timeout: 8) && firstCard.isHittable {
            firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap()
        }
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 15),
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
        // Two things this test must establish rather than inherit. The browse source is
        // persisted (`SourceRegistry`), so a previous WeebCentral run would otherwise
        // decide which catalog this searches.
        app.launchArguments += ["-uitest-source", "mangadex"]
        app.launch()

        // **Searched, not taken from Home.** The full-list screen only exists above five
        // chapters, and Home's first card is whatever live ranking puts there — it was
        // "6000: Rokusen", three chapters, the day this was written, and the row was
        // correctly absent. Berserk is long, complete, and not going to shorten.
        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field should be present")
        field.tap()
        field.typeText("Berserk\n")

        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Berserk"))
            .firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 25), "search should return Berserk")
        result.tap()

        // Any of the detail page's library labels ("Add to Library", "In Library",
        // "Remove from Library") proves it opened — which one shows depends on whether this
        // device already holds the title.
        let libraryToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Library"))
            .firstMatch
        XCTAssertTrue(libraryToggle.waitForExistence(timeout: 25),
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
        if !foundShowAll {
            // Which title, and what the chapter section actually rendered — this assertion
            // failed for two very different reasons historically (wrong source, short
            // title), and the label alone cannot tell them apart.
            attach(app, name: "20-show-all-missing")
            let dump = XCTAttachment(string: app.debugDescription)
            dump.name = "20-show-all-missing-hierarchy"
            dump.lifetime = .keepAlways
            add(dump)
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

    /// **The seeding control for the ADR-0019 Amendment 1 run**, not a CI test.
    ///
    /// The run plants 80 WeebCentral Works into `works.json` rather than adding them by
    /// hand. The protocol
    /// (`docs/superpowers/specs/2026-08-11-adr-0019-amendment-1-run-protocol.md`) allows
    /// that only if the planted shape is *checked* against one the app really produces —
    /// so this mints exactly one, through `Add to Library`, and the run diffs its stored
    /// entry against a planted one before pass 1 starts.
    ///
    /// Asserts nothing about resolution. Its output is the file the app writes.
    func testMintOneWeebCentralWorkThroughTheRealPath() throws {
        let app = XCUIApplication()
        app.launch()

        let weeb = app.buttons["Browse WeebCentral"]
        XCTAssertTrue(weeb.waitForExistence(timeout: 15), "the WeebCentral source chip should exist")
        weeb.tap()

        let card = app.buttons.matching(identifier: "mangaCoverCard").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 60),
                      "WeebCentral should load cover cards — a failure here is Cloudflare, not logic")
        attach(app, name: "seed-01-weebcentral-home")
        card.tap()

        // Either library state proves the detail page rendered, which is all this assertion
        // ever meant. The test seeds a Work, so a title a previous run already added has
        // satisfied it — re-adding is not what is being verified.
        let addToLibrary = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Add to Library"))
            .firstMatch
        let anyLibraryToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Library"))
            .firstMatch
        XCTAssertTrue(anyLibraryToggle.waitForExistence(timeout: 45),
                      "should reach a WeebCentral detail page")
        attach(app, name: "seed-02-detail")
        if addToLibrary.exists {
            addToLibrary.tap()
            sleep(4)
        }
        attach(app, name: "seed-03-after-add")

        // Background to force the stores to flush; a run that just ends loses the write.
        XCUIDevice.shared.press(.home)
        sleep(3)
    }

    // MARK: - ADR-0018 Decision 1, in-app (2026-08-13)

    /// The two legs below verify **Decision 1** — *history carries the id its source published* —
    /// which `2026-08-11-adr-0018-in-app-verification.md` explicitly could not reach. Protocol and
    /// registered predictions: `docs/superpowers/specs/2026-08-13-adr-0018-decision-1-run-protocol.md`;
    /// the run itself is `…-adr-0018-decision-1-verified.md`.
    ///
    /// **Not CI tests.** They are instruments, pinned to the seeded simulator (`2A0D54DF-…`) and to
    /// live network. They assert what the UI can see; **the actual verification is the plist** each
    /// one leaves behind, because `ReadingEntry.malId` is never rendered.
    ///
    /// **Both fixtures are MangaDex titles on purpose.** The original leg B — a still-refused
    /// WeebCentral read, showing the scraped path writes `malId: nil` — was deleted on 2026-08-13
    /// because its fixture aged out with the 14-day refusal TTL (~2026-08-25) and it could not be
    /// re-pointed without hand-picking a fresh refusal each time. Its result is recorded in the run
    /// write-up; recover the test itself from `git show 7f434b8` if the scraped path needs
    /// re-checking, and expect to find a new fixture for it.
    ///
    /// **Run them in order, one at a time.** Leg C used to depend on leg B running between to
    /// displace Berserk from the top of history — `record` updates the newest entry in place when
    /// manga *and* chapter match, so an undisplaced resume writes nothing new. Leg C now displaces
    /// Berserk itself, which is what makes it standalone.
    ///
    /// Every one presses home before returning — `HistoryStore` throttles its writes and flushes on
    /// `.background`, and a run that just ends loses the entry it was verifying.

    /// **Leg A — the substantive one.** Berserk (`801513ba…`, `links.mal = 2`) reached through
    /// Search, so the `Manga` handed to the reader came off the API carrying its published id.
    /// Berserk is already in this sim's history from the pre-0018 seeding with `malId: null` under
    /// the same `mangaId`, so the before-state is on record rather than asserted.
    func testADR0018Decision1MangaDexReadWritesThePublishedId() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field should be present")
        field.tap()
        field.typeText("Berserk\n")

        // MangaDex returns `Boushoku no Berserk` (mal 113958) ahead of the target for this query.
        // Excluding it by label is load-bearing: the wrong hit would write a real id and read as a
        // pass.
        let target = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)",
                        "Berserk", "Boushoku")
        ).element(boundBy: 0)
        XCTAssertTrue(target.waitForExistence(timeout: 25), "search should return Berserk itself")
        attach(app, name: "legA-01-search-results")
        target.tap()

        readFirstChapter(app, label: "legA")
    }

    /// **Leg C — the resume route.** Amendment 1 found `ReadingEntry.asManga` hardcoding
    /// `malId: nil`, which broke exactly this path. Resuming leg A's entry from History must
    /// prepend a **new** entry still carrying `mal 2`; the plist check is on the entry's UUID being
    /// new, since a silent in-place update would preserve the value while proving nothing.
    ///
    /// Reads Junjou Romantica first purely to displace Berserk from the top of history — an
    /// undisplaced resume matches on manga *and* chapter and updates in place, which would preserve
    /// `mal 2` while proving nothing. It is a MangaDex title, so unlike the deleted leg B it carries
    /// no refusal TTL and does not expire. The displacer's own entry is not the subject of any
    /// assertion.
    ///
    /// **A displacer needs readable chapters, which is not the same as existing.** The first
    /// candidate here was Wind Breaker: search found it and the detail page opened correctly, but
    /// that entry reads `0 AVAILABLE / No chapters yet.` in English, so there was nothing to open
    /// and nothing was displaced. Junjou Romantica was checked against `/chapter` with
    /// `translatedLanguage[]=en` before being used (134), as were both titles its search returns.
    func testADR0018Decision1ResumeFromHistoryKeepsTheId() throws {
        let app = XCUIApplication()
        app.launch()

        // --- displacement, not the measurement ---
        app.buttons["Search"].tap()
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "the search field should be present")
        field.tap()
        field.typeText("Junjou Romantica\n")

        let displacer = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Junjou")
        ).element(boundBy: 0)
        XCTAssertTrue(displacer.waitForExistence(timeout: 25),
                      "search should return Junjou Romantica, leg C's displacer")
        attach(app, name: "legC-00-displacer-search")
        displacer.tap()
        readFirstChapter(app, label: "legC-displacer")

        // --- the measurement ---
        // Relaunch rather than re-activate: `readFirstChapter` leaves the app backgrounded *in the
        // reader*, and the tab bar is not reachable from there. The relaunch is also what makes the
        // displacer's write durable before the resume reads it back.
        app.terminate()
        app.launch()

        app.buttons["History"].tap()
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@ AND NOT (label CONTAINS[c] %@)",
                        "Berserk", "Boushoku")
        ).element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 15), "leg A's Berserk entry should be in History")
        attach(app, name: "legC-01-history")
        row.tap()

        turnPagesAndBackground(app, label: "legC")
    }

    /// Opens the first chapter row on a detail page and reads far enough to commit.
    private func readFirstChapter(_ app: XCUIApplication, label: String) {
        let chapter = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "CH·"))
            .element(boundBy: 0)
        XCTAssertTrue(chapter.waitForExistence(timeout: 45), "the detail page should list a chapter")
        attach(app, name: "\(label)-02-detail")
        chapter.tap()

        turnPagesAndBackground(app, label: label)
    }

    /// Turns pages in both directions — the reader's advancing direction depends on the stored
    /// R→L setting, and a swipe the wrong way at page 0 moves nothing — then waits out
    /// `HistoryStore`'s 2s throttle and backgrounds to force the flush.
    private func turnPagesAndBackground(_ app: XCUIApplication, label: String) {
        sleep(8)
        attach(app, name: "\(label)-03-reader-opened")
        for _ in 0..<3 { app.swipeLeft(velocity: .fast); usleep(700_000) }
        for _ in 0..<3 { app.swipeRight(velocity: .fast); usleep(700_000) }
        sleep(4)
        attach(app, name: "\(label)-04-reader-after-turns")

        XCUIDevice.shared.press(.home)
        sleep(4)
    }

    // MARK: - ADR-0019, the gate leg (2026-08-13) — REMOVED 2026-08-13
    //
    // The two seeding tests that lived here (`testADR0019SeedGateSubject`,
    // `testADR0019SeedGateControl`) and their `addFirstResultToLibrary` helper are deleted.
    // They asserted nothing — they only pushed two fixtures into the library so the drain that
    // followed under `simctl launch` had something to attempt — and that drain is done and
    // written up in `docs/superpowers/specs/2026-08-13-adr-0019-gate-verified.md`. Re-running
    // them would seed the same two Works into an already-seeded sim.
    //
    // Recover them from `git show 7f434b8` if a second gate run is ever needed. Note the finding
    // that killed the first attempt: a fresh control is not enough, it has to be a Work this app
    // has already refused, and its TTL suppression has to be lifted or the drain asks nothing.

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

    // MARK: - ADR-0020 in-app run

    /// One seed for the widening regression: a MangaDex title to search for, the substring
    /// that identifies its result cell, and the cards its More Like This rail must show.
    ///
    /// `cards` are the **MangaDex display titles** of targets that ADR-0020's widening
    /// recovered on 2026-08-19 — each one a row whose MAL spelling misses and whose MangaDex
    /// spelling differs. They are the user-visible effect of the ADR: without widening these
    /// cards are simply absent from the rail.
    private struct ReverseSeed {
        let query: String
        let match: String
        let cards: [String]
    }

    /// The seed list registered in
    /// `docs/superpowers/specs/2026-08-19-adr-0020-in-app-run-protocol-amendment-1.md`.
    /// **Do not edit this array in response to a run.** Claim 6 says under-delivery is
    /// answered with more seeds drawn by the published rule in a further amendment
    /// committed before the re-run, never by swapping out the rows that disappointed.
    ///
    /// *Never Give Up*'s second registered target (Teppen!, MAL 10776) is **not** listed as a
    /// card: it never appeared in the discharging run, which reported it as never-observed
    /// rather than as a loss. Asserting on it here would encode a row we have never seen.
    private static let adr0020Seeds: [ReverseSeed] = [
        .init(query: "Vagabond", match: "Vagabond", cards: ["Mugen no Junin"]),
        .init(query: "Golden Kamuy", match: "Golden Kamuy",
              cards: ["Mugen no Junin", "RED: Living On the Edge"]),
        .init(query: "Meitantei Conan", match: "Meitantei Conan",
              cards: ["Kindaichi Case Files", "Q.E.D"]),
        .init(query: "Angel Sanctuary", match: "Tenshi Kinryouku", cards: ["X (CLAMP)"]),
        .init(query: "Kimi wa Pet", match: "Kimi wa Pet", cards: ["Futago", "The One"]),
        .init(query: "Eden: It's an Endless World", match: "Eden",
              cards: ["Neon Genesis Evangelion"]),
        .init(query: "Blood+ Adagio", match: "BLOOD+", cards: ["BLOOD+"]),
        .init(query: "Ai wo Utau yori Ore ni Oborero", match: "Oborero",
              cards: ["Kaikan Phrase"]),
        .init(query: "Kaichou-san Chi no Koneko", match: "Kaichou-san",
              cards: ["Cosplay Animal"]),
        .init(query: "Hotaru no Hikari", match: "Hotaru no Hikari",
              cards: ["Lifetime of a Man"]),
        .init(query: "Ugly Duckling to Swan", match: "Swan", cards: ["Ahiru no Oujisama"]),
        .init(query: "Never Give Up", match: "Never Give Up", cards: ["The One"]),
        .init(query: "Kaikan Phrase", match: "Kaikan", cards: ["Love Monster"]),
    ]

    /// Drives the thirteen registered seeds through **Search** and asserts that the cards
    /// ADR-0020's widening recovers actually appear in each seed's More Like This rail.
    ///
    /// ADR-0020: `docs/adr/0020-widening-the-search-input-on-the-reverse-resolution-path.md`.
    /// The discharging run is
    /// `docs/superpowers/specs/2026-08-19-adr-0020-in-app-run-enriched.md`.
    ///
    /// **This asserts cards, not log lines.** The run that discharged Decision 5 read its
    /// claims off a debug instrument inside `MALReverseResolver`; that instrument is deleted
    /// now the run is written up, and what survives it is this: fourteen rows that miss on
    /// MAL's spelling and are carried by MangaDex under another one. If widening regresses,
    /// these cards vanish from the rail and this test says which ones.
    ///
    /// **The floor is 10 of 14, not 14 of 14, and that is deliberate.** Both MAL and MangaDex
    /// are live here, and MAL's recommendation ordering shifts — a target can leave the top 8
    /// that `MoreLikeThisProvider.topRecommendations` takes without anything in this app
    /// changing. A hard all-or-nothing assertion would turn that into a red build. Losing a
    /// third of the set is not ordering drift.
    func testADR0020WidenedCardsAppearInTheRail() throws {
        let app = XCUIApplication()
        app.launch()

        var seedsMissed: [String] = []
        var railsReached: [String] = []
        var railsUnreached: [String] = []
        var cardsFound: [String] = []
        var cardsMissing: [String] = []

        for seed in Self.adr0020Seeds {
            // Always start a seed from the Search tab with no detail page underneath. An
            // earlier revision skipped this on the `continue` paths, so one seed that failed
            // to reach its rail left its detail page open — and the next iteration found two
            // "Search" buttons, the tab and the page's own, and failed on ambiguity rather
            // than on anything to do with widening.
            returnToSearchRoot(app)
            searchTab(app).tap()
            let field = app.searchFields.firstMatch
            guard field.waitForExistence(timeout: 15) else {
                seedsMissed.append("\(seed.query) [no search field]")
                continue
            }
            field.tap()
            // Clear whatever the previous seed left behind; the field persists across tabs.
            if let existing = field.value as? String, !existing.isEmpty,
               existing != "Search titles" {
                field.buttons.firstMatch.tap()
            }
            field.typeText(seed.query + "\n")

            let result = app.buttons
                .matching(NSPredicate(format: "label CONTAINS[c] %@", seed.match))
                .element(boundBy: 0)
            guard result.waitForExistence(timeout: 30) else {
                seedsMissed.append("\(seed.query) [no result]")
                continue
            }
            result.tap()

            let libraryToggle = app.buttons
                .matching(NSPredicate(format: "label CONTAINS[c] %@", "Library")).firstMatch
            guard libraryToggle.waitForExistence(timeout: 25) else {
                seedsMissed.append("\(seed.query) [detail page never appeared]")
                continue
            }

            // Scroll until the rail's first cell is **hittable**, not until its header
            // `exists`. XCUITest reports a lazily-built element as existing while it is still
            // below the fold, so the discharging run's screenshots were all framed at the top
            // of the detail page and showed no cards at all. Hittability is what "on screen"
            // actually means here, and it is also what makes the card assertions below
            // meaningful rather than accidental.
            let header = app.staticTexts["More Like This"]
            let deadline = Date().addingTimeInterval(45)
            while Date() < deadline && !railIsOnScreen(app, header: header) {
                app.swipeUp(velocity: .fast)
                usleep(700_000)
            }
            // Not reaching the rail is a **scroll budget** problem, not a navigation one:
            // a seed with hundreds of chapters can outrun 45 seconds of swiping. The rail is
            // built either way, so the card checks below still mean something — they just
            // rest on `exists` rather than on a picture. Kept separate from `seedsMissed` so
            // a long page never reads as a broken app.
            if railIsOnScreen(app, header: header) {
                railsReached.append(seed.query)
            } else {
                railsUnreached.append(seed.query)
            }

            for card in seed.cards {
                let cell = app.buttons
                    .matching(NSPredicate(format: "label CONTAINS[c] %@", card))
                    .firstMatch
                // The rail is horizontally scrollable and the target may sit off its right
                // edge; `exists` is the right predicate for membership, hittability was the
                // question for the rail as a whole.
                if cell.waitForExistence(timeout: 10) {
                    cardsFound.append("\(seed.query) → \(card)")
                } else {
                    cardsMissing.append("\(seed.query) → \(card)")
                }
            }

            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "seed-\(seed.query)-rail"
            shot.lifetime = .keepAlways
            add(shot)
        }

        // A run where navigation broke must never read as a run where widening had nothing
        // to do, so the frame is asserted before the cards are.
        XCTAssertTrue(seedsMissed.isEmpty,
                      "seeds whose detail page never opened: \(seedsMissed)")
        XCTAssertGreaterThanOrEqual(
            railsReached.count, 10,
            "rails brought on screen \(railsReached.count)/13; outran the scroll budget: \(railsUnreached)")
        XCTAssertGreaterThanOrEqual(
            cardsFound.count, 10,
            "widened cards found \(cardsFound.count)/14; missing: \(cardsMissing)")
    }

    /// The rail the ADR-0020 AniList-arm run was driven through
    /// (`docs/superpowers/specs/2026-08-20-adr-0020-anilist-arm-results.md`).
    ///
    /// What survives the run is the regression it needs anyway: the For You rail — which is
    /// where the AniList pool's reverse-resolved candidates surface — is built and reaches
    /// the screen with cards on it. The instrument that scored the run is gone, so this
    /// asserts the visible thing rather than the path.
    ///
    /// **Preconditions, none of them assertable from here:** a seeded library (the pool
    /// gate needs 3+ AniList-resolved Works) plus live AniList and MangaDex. Run it through
    /// `-only-testing:`, the way the other live tests in this file are run; CI runs unit
    /// tests only.
    func testForYouRailReachesTheScreenWithCards() throws {
        let app = XCUIApplication()
        app.launch()

        // The rail is built from a live AniList query plus up to 12 MangaDex searches, so
        // it arrives well after Home does. Waiting on the header's *existence* first is
        // deliberate: it is the signal the section was built at all, which is what tells an
        // empty log apart from a pool that never ran.
        let header = app.staticTexts["For You"]
        XCTAssertTrue(header.waitForExistence(timeout: 120),
                      "the For You rail never appeared; the pool did not run, so an empty "
                      + "log would say nothing about widening")

        // Then scroll until it is **hittable**. `exists` is true for a lazily-built element
        // still below the fold — the bug that made every screenshot in the MAL arm's
        // discharging run useless.
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline && !railIsOnScreen(app, header: header) {
            app.swipeUp(velocity: .fast)
            usleep(700_000)
        }
        XCTAssertTrue(railIsOnScreen(app, header: header),
                      "the For You rail never reached the screen")

        // Claim 4's visual half: the card, on screen, in the rail the widened queries fed.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "adr0020-anilist-arm-for-you-rail"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(app.buttons.matching(identifier: "mangaCoverCard")
                        .allElementsBoundByIndex.contains { $0.isHittable },
                      "the For You rail reached the screen with no cards on it")
    }

    /// True once the More Like This rail is actually on screen — either its header or one of
    /// its cells is **hittable**, not merely `exists`.
    ///
    /// Both halves are needed. A card alone is the strong signal, but a title with no
    /// recommendations renders the section header over an empty rail, and treating that as
    /// "not reached" would spin the scroll loop to its deadline and then report a navigation
    /// failure for what is really an empty rail. The card assertions tell those apart.
    private func railIsOnScreen(_ app: XCUIApplication, header: XCUIElement) -> Bool {
        if header.isHittable { return true }
        return app.buttons.matching(identifier: "mangaCoverCard")
            .allElementsBoundByIndex.contains { $0.isHittable }
    }

    /// The Search tab. A detail page carries its own "Search" affordance, so an unqualified
    /// `app.buttons["Search"]` is ambiguous whenever one is open; the tab is the bottom-most
    /// match.
    private func searchTab(_ app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", "Search"))
            .allElementsBoundByIndex
        return matches.max(by: { $0.frame.minY < $1.frame.minY }) ?? app.buttons["Search"]
    }

    /// Pops any open detail page so the next seed starts from a known state.
    private func returnToSearchRoot(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists && back.isHittable {
            back.tap()
            _ = app.searchFields.firstMatch.waitForExistence(timeout: 15)
        }
    }

}
