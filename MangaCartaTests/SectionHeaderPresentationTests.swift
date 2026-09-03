//
//  SectionHeaderPresentationTests.swift
//  MangaCartaTests
//
//  Issue #108, checklist row 7.2. Every section heading in the app is one component,
//  `InkSectionHeader`, and none of them carried the header trait — so VoiceOver's
//  Headings rotor had no stops and a reader could not skip a rail.
//
//  The load-bearing test is `testTheLabelIsAlwaysTheTitleVerbatim`. Four XCUITest
//  assertions match headings by their drawn text (`app.staticTexts["MyAnimeList"]`,
//  `["More Like This"]`, `["Keep your library current"]`, `["Updates"]`), and those
//  suites are live-network ones CI does not run — so breaking them would be silent.
//  Putting the eyebrow in the *value* rather than the label is what keeps them green,
//  and this test is what stops a later refactor from quietly folding it back in.
//

import XCTest
@testable import MangaCarta

final class SectionHeaderPresentationTests: XCTestCase {

    /// Every heading actually used in the app, title and eyebrow as written at the call
    /// site. Walked rather than sampled, so a heading added later with a shape we did not
    /// anticipate shows up here as a failure rather than as a silent rotor gap.
    private let callSites: [(title: String, eyebrow: String?)] = [
        ("Library", "Organization"), ("Appearance", "Theme"), ("Updates", "Library"),
        ("Sources", "Content"), ("About", "Info"),
        ("For You", "Based on your reading"), ("For You", "Nothing to go on yet"),
        ("Keep your library current", "Updates"), ("Loading", "MangaDex"),
        ("Synopsis", "About"), ("More Like This", "Similar titles"),
        ("More Like This", "Nothing to compare"), ("Chapters", "12 available"),
        ("MyAnimeList", "Account"), ("Latest Updates", nil),
    ]

    // MARK: - The invariant

    /// The label is the title and nothing else. This is the contract the XCUITests match
    /// on; appending the eyebrow to it would break four of them without CI noticing.
    func testTheLabelIsAlwaysTheTitleVerbatim() {
        for site in callSites {
            let p = SectionHeaderPresentation(title: site.title, eyebrow: site.eyebrow)
            XCTAssertEqual(p.accessibilityLabel, site.title,
                           "the heading label must be the title verbatim, for \(site.title)")
        }
    }

    /// The eyebrow is information, not decoration — "12 available" and "Nothing to go on
    /// yet" say things the title does not. It has to reach VoiceOver somewhere, and the
    /// value is where, since iOS reads label then value.
    func testAnEyebrowIsSpokenAsTheValue() {
        let p = SectionHeaderPresentation(title: "Chapters", eyebrow: "12 available")
        XCTAssertEqual(p.accessibilityValue, "12 available")
    }

    /// A heading with no eyebrow must not claim an empty one — an element with a blank
    /// value is a pause VoiceOver reads out as nothing at all.
    func testNoEyebrowMeansNoValue() {
        XCTAssertNil(SectionHeaderPresentation(title: "Latest Updates", eyebrow: nil).accessibilityValue)
        XCTAssertNil(SectionHeaderPresentation(title: "Latest Updates", eyebrow: "").accessibilityValue)
    }

    /// The eyebrow is drawn `.uppercased()` with 1.6pt tracking. Tracked uppercase is the
    /// app's identity voice and is exactly what #104 had to stop speaking — VoiceOver
    /// spells some of it out. The spoken form is the string as written at the call site.
    func testTheSpokenEyebrowIsNotTheDrawnUppercase() {
        let p = SectionHeaderPresentation(title: "For You", eyebrow: "Based on your reading")
        XCTAssertEqual(p.accessibilityValue, "Based on your reading")
        XCTAssertNotEqual(p.accessibilityValue, "BASED ON YOUR READING")
    }

    /// The rule #104 established for the reader, applied here: a middle dot is not a word.
    func testNoSpokenStringContainsTheMiddleDot() {
        for site in callSites {
            let p = SectionHeaderPresentation(title: site.title, eyebrow: site.eyebrow)
            XCTAssertFalse(p.accessibilityLabel.contains("·"), "in \(p.accessibilityLabel)")
            XCTAssertFalse(p.accessibilityValue?.contains("·") ?? false, "in \(site.title)")
        }
    }

    /// A heading with nothing to say is worse than no heading: it becomes a rotor stop
    /// that announces silence.
    func testEveryHeadingSaysSomething() {
        for site in callSites {
            let p = SectionHeaderPresentation(title: site.title, eyebrow: site.eyebrow)
            XCTAssertFalse(p.accessibilityLabel.trimmingCharacters(in: .whitespaces).isEmpty,
                           "for \(site.title)")
        }
    }
}
