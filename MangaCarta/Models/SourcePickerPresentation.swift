//
//  SourcePickerPresentation.swift
//  MangaCarta
//
//  The detail page's answer to "where am I reading this from, and what else is
//  there?" — ADR-0004's picker, as a value the view renders without deciding
//  anything itself.
//

import Foundation

/// One row in the picker: a Listing, described.
struct SourceOptionPresentation: Equatable, Identifiable {
    let key: ListingKey
    let name: String
    /// What is known about this Listing's chapters, in words.
    let detail: String
    let isCurrent: Bool

    var id: ListingKey { key }

    /// Read as one element, because the pieces are a sentence rather than a list.
    var accessibilityLabel: String {
        isCurrent ? "\(name), \(detail), currently reading" : "\(name), \(detail)"
    }
}

struct SourcePickerPresentation {

    let candidates: [ListingCandidate]
    let current: ListingKey
    let names: [String: String]

    /// Whether there is anything to choose between. One Listing is the common case
    /// and is not a choice — a picker offering a single entry promises an
    /// alternative that does not exist, so the view keeps the plain source stamp.
    var offersAChoice: Bool { candidates.count > 1 }

    /// The rows, in ranked order — so the best Listing is the first thing read, by
    /// eye and by VoiceOver alike.
    var rows: [SourceOptionPresentation] {
        candidates.map { candidate in
            SourceOptionPresentation(
                key: candidate.key,
                name: names[candidate.key.sourceId] ?? candidate.key.sourceId,
                detail: detail(for: candidate.chapterCount),
                isCurrent: candidate.key == current)
        }
    }

    /// An uncounted Listing must never read as an empty one. "0 chapters" is a lie
    /// the router is careful not to tell itself — `nil` means unknown — and the user
    /// gets the same distinction rather than a number the app does not have.
    private func detail(for count: Int?) -> String {
        guard let count else { return "Not counted yet" }
        return count == 1 ? "1 chapter" : "\(count) chapters"
    }
}
