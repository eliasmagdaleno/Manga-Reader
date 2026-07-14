//
//  ReadingResume.swift
//  Manga-Reader
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

/// The chapter immediately after `number` in ascending numeric order.
func nextChapter(after number: String, in ascending: [Chapter]) -> Chapter? {
    guard let value = numericChapterValue(number) else { return nil }
    return sortChapters(ascending, descending: false)
        .first { ($0.number != number) && (numericChapterValue($0.number).map { $0 > value } ?? false) }
}

/// What the detail-screen "Continue" button should do.
enum ResumeAction: Equatable {
    case start(Chapter)             // no history -> first chapter, page 0
    case cont(Chapter, page: Int)   // mid-chapter -> exact page
    case next(Chapter)              // finished a chapter -> next chapter, page 0
    case reread(Chapter, page: Int) // finished the latest chapter -> re-read last page
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
    if !finished { return .cont(current, page: entry.page) }
    if let nxt = nextChapter(after: entry.chapterNumber, in: ascending) { return .next(nxt) }
    return .reread(current, page: entry.page)
}
