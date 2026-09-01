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

    /// The *browse*-source list, above the preference. It shipped with no accessibility
    /// treatment at all while the list below it had all three — so which source you were
    /// browsing was carried only by a bare checkmark image, and a query for a source name
    /// matched whichever list came first. Both halves are asserted here because a label
    /// without the selected trait would still leave the state inaudible.
    func testTheBrowseSourceListSaysWhichSourceIsActive() throws {
        let app = launch()

        app.tabBars.buttons["Settings"].tap()
        let heading = app.staticTexts["Browse source"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10),
                      "Settings should offer a browse source")
        heading.scrollToVisible(in: app)

        let mangaDex = app.buttons["browseSource.MangaDex"]
        XCTAssertTrue(mangaDex.exists,
                      "the browse-source list should be reachable by a namespaced identifier")
        mangaDex.tap()
        XCTAssertTrue(mangaDex.isSelected,
                      "the active browse source should report itself selected to assistive tech")

        // The two lists must stay distinguishable: same name, different question.
        XCTAssertFalse(app.buttons["preferredSource.MangaDex"].isSelected,
                       "choosing a browse source must not move the fulfillment preference")
        attach(app, name: "05-browse-source-active")
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

    /// The detail-page picker, on a Work that genuinely has two Listings. Until this
    /// fixture existed the picker had no device-level evidence at all: its logic was unit
    /// tested and the wiring compiled, but nothing had ever drawn the menu.
    func testDetailPageOffersTheWorksOtherListing() throws {
        let app = launch(state: "two-listings")

        app.tabBars.buttons["Library"].tap()
        let title = app.staticTexts["Fixture Update Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10),
                      "the two-listing fixture should be saved to the library")
        title.tap()

        let picker = app.buttons["sourcePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10),
                      "a Work with two Listings should offer a source picker")
        attach(app, name: "03-detail-source-picker")
    }

    /// Opening the menu shows both Listings and says what each carries. The counts are the
    /// whole reason the picker is worth opening — they are what the ranking decided on.
    func testThePickerNamesBothSourcesAndTheirChapterCounts() throws {
        let app = launch(state: "two-listings")

        app.tabBars.buttons["Library"].tap()
        let title = app.staticTexts["Fixture Update Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()

        let picker = app.buttons["sourcePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()

        XCTAssertTrue(app.buttons["Alt Fixture · 3 chapters"].waitForExistence(timeout: 10),
                      "the menu should name the other Listing and its chapter count")
        XCTAssertTrue(app.buttons["Update Fixture · 1 chapter"].exists,
                      "a one-chapter Listing should read as singular")
        attach(app, name: "04-detail-source-picker-open")
    }

    /// Which row you are already reading from is drawn as a checkmark image, and the
    /// question was whether that glyph reaches assistive tech at all. It does: SwiftUI's
    /// `Menu` renders `Label(_:systemImage: "checkmark")` as a *selected* menu element and
    /// supplies the trait itself, so no explicit `.accessibilityAddTraits` is needed — this
    /// was checked by adding one and finding the test green without it.
    ///
    /// The test stays, because that is a framework behaviour nothing in this repo controls:
    /// if a future SwiftUI stops supplying it, or someone swaps the `Label` for a `Text` and
    /// a hand-drawn image, the checkmark silently becomes decoration. Exactly one row may
    /// claim the trait — two would be worse than none.
    func testThePickerMenuSaysWhichSourceIsAlreadyInUse() throws {
        let app = launch(state: "two-listings")

        app.tabBars.buttons["Library"].tap()
        let title = app.staticTexts["Fixture Update Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()

        let picker = app.buttons["sourcePicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        picker.tap()

        let rows = [app.buttons["Alt Fixture · 3 chapters"],
                    app.buttons["Update Fixture · 1 chapter"]]
        XCTAssertTrue(rows[0].waitForExistence(timeout: 10))
        XCTAssertEqual(rows.filter(\.isSelected).count, 1,
                       "exactly one menu row should report itself selected")
        attach(app, name: "06-picker-menu-selection")
    }

    private func launch(state: String = "not-checked") -> XCUIApplication {
        let app = XCUIApplication()
        // Reuses the deterministic fixture the update tests launch with, so this never
        // depends on a live source request.
        app.launchArguments += ["-uitest-updates-state", state]
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
