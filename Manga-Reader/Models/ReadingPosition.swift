//
//  ReadingPosition.swift
//  Manga-Reader
//
//  Where a reader is inside a chapter. See ADR-0014.
//

import Foundation

/// A place inside a chapter: a page index plus how far down that page the reader
/// had scrolled.
///
/// `fraction` is only meaningful against the `page` it was captured on, and is only
/// ever non-zero in the vertical mode, where a page is a long **strip**. The paged
/// modes read `page` and ignore it.
///
/// **`Comparable` is lexicographic** — page first, fraction as the tiebreak — because
/// `HistoryStore.record` takes `max()` over it. Recorded progress only ever moving
/// forward is what keeps a backwards scroll from un-finishing a finished chapter, and
/// `page` doubles as the completion signal for Continue Reading, the in-progress badge
/// and taste signals (ADR-0014).
struct ReadingPosition: Equatable, Comparable {
    var page: Int
    var fraction: Double

    init(page: Int, fraction: Double = 0) {
        self.page = page
        self.fraction = fraction
    }

    static func < (lhs: ReadingPosition, rhs: ReadingPosition) -> Bool {
        (lhs.page, lhs.fraction) < (rhs.page, rhs.fraction)
    }
}
