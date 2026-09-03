//
//  ReadingResume.swift
//  MangaCarta
//
//  Pure helpers for numeric chapter ordering and choosing where the "Continue"
//  button should drop the reader. Kept free of UI / persistence so they unit-test
//  cleanly.
//

import Foundation

/// Numeric value of a chapter "number" string ("10.5" -> 10.5). `nil` when the
/// number is unparseable (e.g. "?", oneshot labels).
func numericChapterValue(_ number: String) -> Double? {
    Double(number)
}

/// Sort chapters by numeric value. Unparseable numbers always sort to the end,
/// in both directions. Stable on ties (preserves source order).
func sortChapters(_ chapters: [Chapter], descending: Bool) -> [Chapter] {
    chapters.enumerated().sorted { lhs, rhs in
        switch (numericChapterValue(lhs.element.number), numericChapterValue(rhs.element.number)) {
        case let (l?, r?):
            if l == r { return lhs.offset < rhs.offset }        // stable
            return descending ? l > r : l < r
        case (nil, nil): return lhs.offset < rhs.offset
        case (_?, nil):  return true                            // parseable before unparseable
        case (nil, _?):  return false
        }
    }.map(\.element)
}

/// The chapters shown in the detail-page preview: newest-first, capped at `limit`.
/// Truncation lives here (pure) so the detail view stays declarative and this is
/// unit-tested independently of SwiftUI.
func chapterPreview(_ chapters: [Chapter], limit: Int) -> [Chapter] {
    Array(sortChapters(chapters, descending: true).prefix(limit))
}

/// The chapter immediately after `number` in ascending numeric order.
func nextChapter(after number: String, in ascending: [Chapter]) -> Chapter? {
    guard let value = numericChapterValue(number) else { return nil }
    return sortChapters(ascending, descending: false)
        .first { ($0.number != number) && (numericChapterValue($0.number).map { $0 > value } ?? false) }
}

/// What the detail-screen "Continue" button should do.
///
/// Only `.cont` carries a position: the other three all open at the start of a chapter.
/// `.reread` used to carry the last page read and no caller ever honoured it — the button
/// has always restarted the chapter, which is what "Read Again" means (ADR-0014 decision 4).
enum ResumeAction: Equatable {
    case start(Chapter)                          // no history -> first chapter, page 0
    case cont(Chapter, position: ReadingPosition) // mid-chapter -> exactly where they stopped
    case next(Chapter)                           // finished a chapter -> next chapter, page 0
    case reread(Chapter)                         // finished the latest chapter -> from the top
}

/// Choose the resume action from the latest history entry and the chapter list
/// (any order — sorted ascending internally). `nil` when there are no chapters.
func resumeAction(entry: ReadingEntry?, chapters: [Chapter]) -> ResumeAction? {
    let ascending = sortChapters(chapters, descending: false)
    guard let first = ascending.first else { return nil }
    guard let entry else { return .start(first) }

    // The chapter the entry refers to (fall back to a reconstructed one if it has
    // since disappeared from the list).
    let current = ascending.first { $0.id == entry.chapterId }
        ?? ascending.first { $0.number == entry.chapterNumber }
        ?? Chapter(id: entry.chapterId, number: entry.chapterNumber, title: nil)

    let finished = entry.pageCount > 0 && entry.page >= entry.pageCount - 1
    if !finished { return .cont(current, position: entry.position) }
    if let nxt = nextChapter(after: entry.chapterNumber, in: ascending) { return .next(nxt) }
    return .reread(current)
}

/// How far into the resume chapter the reader has got, 0...1, or `nil` when the action is
/// not a mid-chapter continue. Drives the hairline fill on the Continue button.
///
/// **`fraction == 0` is read as "this page has been seen"**, which is right for the paged
/// modes — where a page is consumed the moment it is on screen — and knowingly wrong for a
/// webtoon sitting at the exact top of a strip. The entry does not record which mode it was
/// read in, so the ambiguity cannot be resolved here; ADR-0014 decision 12 takes the error
/// that keeps paged progress honest, because paged reading is the common case. The visible
/// cost is that the fill *retreats* on the first scroll into a freshly opened webtoon
/// chapter — see the ADR's hazards.
func continueProgress(action: ResumeAction, entry: ReadingEntry?) -> Double? {
    guard case .cont(_, let position) = action,
          let entry, entry.pageCount > 0 else { return nil }
    let consumed = Double(position.page) + (position.fraction > 0 ? position.fraction : 1)
    return min(1, consumed / Double(entry.pageCount))
}
