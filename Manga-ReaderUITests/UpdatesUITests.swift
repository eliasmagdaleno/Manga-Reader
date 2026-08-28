//
//  UpdatesUITests.swift
//  Manga-ReaderUITests
//

import XCTest

/// Device-level evidence for the five update surfaces in ADR-0021. Every launch
/// uses the app's deterministic fixture; these assertions intentionally never
/// infer state from a live source request.
final class UpdatesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    func testNoSavedWorksExplainsHowToBeginUpdates() throws {
        let app = launch(state: "empty", accessibilitySize: true)

        XCTAssertTrue(app.staticTexts["Keep your library current"].waitForExistence(timeout: 10),
                      "Home should explain the no-saved-Works update state")
        XCTAssertTrue(app.buttons["Browse Titles"].exists,
                      "the empty update state should offer a direct browse action")
        XCTAssertTrue(app.buttons["Search Titles"].exists,
                      "the empty update state should offer a direct search action")
        XCTAssertFalse(app.staticTexts["Not checked yet"].exists,
                       "an empty library must not make a freshness claim")
        attach(app, name: "01-updates-no-saved-works")
    }

    func testSavedWorkWithoutBaselineShowsNotCheckedYet() throws {
        let app = launch(state: "not-checked", accessibilitySize: true)

        XCTAssertTrue(app.staticTexts["Not checked yet"].waitForExistence(timeout: 10),
                      "a saved work without a baseline should say Not checked yet")
        XCTAssertTrue(app.buttons["updatesRefreshButton"].exists,
                      "the foreground refresh action should be available")
        attach(app, name: "02-updates-not-checked-yet")
    }

    func testForegroundRefreshCompletesWithoutUsingALiveSource() throws {
        let app = launch(state: "refresh-complete")

        let refresh = app.buttons["updatesRefreshButton"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Not checked yet"].exists)
        refresh.tap()

        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Last checked")
        ).firstMatch.waitForExistence(timeout: 10),
                      "the fixture-backed foreground refresh should finish and expose fresh status")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Last checked")
        ).firstMatch.exists,
                      "the refresh control should expose its completed state to VoiceOver")
        attach(app, name: "03-updates-refresh-complete")
    }

    func testUpdatesFilterExposesSelectedState() throws {
        let app = launch(state: "updates-filter")

        app.tabBars.buttons["Library"].tap()
        let updates = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Updates")
        ).firstMatch
        XCTAssertTrue(updates.waitForExistence(timeout: 10))
        updates.tap()

        XCTAssertEqual(updates.value as? String, "Selected",
                       "the Updates filter must expose selection beyond its color")
        XCTAssertTrue(app.buttons.matching(identifier: "libraryCoverCard").firstMatch.exists,
                      "the selected filter should retain the fixture's discovered work")
        attach(app, name: "04-updates-filter-selected")
    }

    func testSettingsShowsNotificationAuthorizationRowAtAccessibilitySize() throws {
        let app = launch(state: "not-checked", accessibilitySize: true)

        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Updates"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["System notifications"].exists,
                      "Settings should identify the system authorization row")
        XCTAssertTrue(app.staticTexts["Not requested"].exists,
                      "the fixture must not inherit this simulator's authorization state")
        XCTAssertTrue(app.switches["Notify about new chapters"].exists,
                      "the authorization control should remain reachable at accessibility sizes")
        attach(app, name: "05-updates-settings-authorization-large-text")
    }

    private func launch(state: String, accessibilitySize: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest-updates-state", state]
        if accessibilitySize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                    "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
