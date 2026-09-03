//
//  SectionHeaderPresentation.swift
//  MangaCarta
//
//  Issue #108, checklist row 7.2. What a section heading says to VoiceOver, decided
//  beside the view rather than inside it — the shape #103 and #104 established.
//
//  `grep -rn isHeader` over this repository used to return nothing. Not one heading
//  carried the trait, so the Headings rotor had no stops at all and the only way past a
//  rail was to swipe through every cover in it. `InkSectionHeader` is the single component
//  behind all fifteen headings in the app, which makes that one fix in one place.
//
//  **The eyebrow goes in the value, not the label, and that is load-bearing.** Four
//  XCUITest assertions find headings by their drawn text — `app.staticTexts["MyAnimeList"]`,
//  `["More Like This"]`, `["Keep your library current"]`, `["Updates"]` — and they live in
//  the live-network suites CI does not run. Folding the eyebrow into the label would break
//  all four with nothing to catch it. It also happens to read better: iOS speaks label,
//  then value, then trait, so "Chapters, 12 available, Heading" is what a reader hears.
//
//  The eyebrow is spoken as written at the call site, never as drawn. `InkSectionHeader`
//  renders it `.uppercased()` with 1.6pt tracking, and tracked uppercase is precisely the
//  identity voice #104 had to stop VoiceOver from spelling out.
//

import Foundation

struct SectionHeaderPresentation: Equatable {

    /// The heading itself. The title verbatim — see the note above about the four
    /// XCUITests that match on exactly this string.
    let accessibilityLabel: String

    /// The eyebrow, which states something the title does not: a count, an ordering, a
    /// reason a section is empty. `nil` when there is no eyebrow, so a heading never
    /// announces a blank value.
    let accessibilityValue: String?

    init(title: String, eyebrow: String?) {
        self.accessibilityLabel = title
        self.accessibilityValue = eyebrow.flatMap { $0.isEmpty ? nil : $0 }
    }
}
