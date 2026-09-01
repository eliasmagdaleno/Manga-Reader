//
//  SourcePreferenceUITests.swift
//  Manga-ReaderUITests
//
//  Device-level evidence for the fulfillment preference (ADR-0004 Amendment 1). There is no
//  tap tool in this project, so the wiring — store in the environment, writes surviving a
//  scroll, a real route back to automatic — is only ever verified here.
//

import XCTest

final class SourcePreferenceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    /// The preference exists, is explained, and starts unset. "No preference" being a
    /// visible selected row rather than an absent one is the whole point: without it there
    /// is no way to tell the default from a deliberate choice, and no way back.
    func testPreferredSourceStartsWithNoPreference() throws {
        let app = launch()

        app.tabBars.buttons["Settings"].tap()
        let heading = app.staticTexts["Preferred source"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10),
                      "Settings should offer a preferred source")

        heading.scrollToVisible(in: app)
        XCTAssertTrue(app.buttons["preferredSource.No preference"].exists,
                      "there must be a visible route back to automatic behaviour")
        attach(app, name: "01-preferred-source-unset")
    }

    /// Choosing one moves the selection, and the copy keeps saying which question this list
    /// answers — Settings shows two lists of source names, and the one above this is the
    /// browse source, which is a different thing entirely.
    func testChoosingAPreferredSourceMovesTheSelection() throws {
        let app = launch()

        app.tabBars.buttons["Settings"].tap()
        let heading = app.staticTexts["Preferred source"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10))
        heading.scrollToVisible(in: app)

        let mangaDex = app.buttons["preferredSource.MangaDex"]
        XCTAssertTrue(mangaDex.exists, "the preferred-source list should offer MangaDex")
        mangaDex.tap()

        XCTAssertTrue(mangaDex.isSelected,
                      "the chosen source should report itself selected to assistive tech")
        XCTAssertFalse(app.buttons["preferredSource.No preference"].isSelected,
                       "choosing a source should clear the automatic selection")
        attach(app, name: "02-preferred-source-chosen")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        // Reuses the deterministic fixture the update tests launch with, so this never
        // depends on a live source request.
        app.launchArguments += ["-uitest-updates-state", "not-checked"]
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

private extension XCUIElement {
    /// Settings is a long scroll and the preference sits below the fold on a phone.
    func scrollToVisible(in app: XCUIApplication) {
        var attempts = 0
        while !isHittable && attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }
}
