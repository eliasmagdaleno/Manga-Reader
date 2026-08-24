//
//  MALAccountPresentation.swift
//  Manga-Reader
//
//  What the Settings MyAnimeList section shows, decided away from SwiftUI.
//
//  The account has six states and an error that wraps any of them, which is more branching
//  than a view body should carry. Mapping it here means every branch the design specifies
//  is asserted by a test rather than by looking at a simulator.
//

import Foundation

/// The queue as the user is allowed to see it: four counts, no titles and no ids. Settings
/// must never leak what somebody reads, and a raw response body never reaches here at all.
struct MALSyncSummary: Equatable, Sendable {
    /// Queued and sendable.
    var pending = 0
    /// Permanently rejected for one title (MAL answered 400/404). Blocked, not lost.
    var failed = 0
    /// Finished chapters whose Work has no MyAnimeList match yet.
    var waiting = 0
    /// Not on the user's list, with automatic addition off. Dropped on purpose.
    var skipped = 0

    static let empty = MALSyncSummary()

    var isEmpty: Bool { self == .empty }

    /// One line per non-zero count, in the order the design lists them. Empty when there is
    /// nothing queued, so the section says nothing rather than saying "0 pending".
    var lines: [String] {
        var lines: [String] = []
        if pending > 0 {
            lines.append(pending == 1 ? "1 update waiting to send"
                                      : "\(pending) updates waiting to send")
        }
        if failed > 0 { lines.append("\(failed) failed") }
        if waiting > 0 { lines.append("\(waiting) waiting for a MyAnimeList match") }
        if skipped > 0 { lines.append("\(skipped) skipped") }
        return lines
    }
}

/// The two switches, carried together because `refreshing` does not restate them and the
/// section still has to render them as the user last set them.
struct MALSyncToggles: Equatable, Sendable {
    var syncEnabled: Bool
    var automaticallyAddsTitles: Bool

    static let defaults = MALSyncToggles(syncEnabled: true, automaticallyAddsTitles: true)
}

/// The section's content, with the error lifted out — an error is inline and nonmodal, so it
/// never replaces what it interrupted.
enum MALAccountSection: Equatable {
    case signedOut
    case authorizing
    case signedIn(profile: MALUserIdentity,
                  syncEnabled: Bool,
                  automaticallyAddsTitles: Bool,
                  summary: MALSyncSummary,
                  /// A token refresh in flight. The content stays; only destructive and
                  /// repeated-auth actions are disabled while it is true.
                  isRefreshing: Bool)
    case reauthorizationRequired(profile: MALUserIdentity?, summary: MALSyncSummary)
}

struct MALAccountPresentation: Equatable {
    let section: MALAccountSection
    /// Shown above the section, dismissible, never modal, and never a server body.
    let inlineError: String?

    static func make(state: MALAccountStore.State,
                     summary: MALSyncSummary,
                     toggles: MALSyncToggles) -> MALAccountPresentation {
        switch state {
        case let .error(message, previousStable):
            // The error wraps a stable state; render that state and put the message above it.
            let underlying = make(state: previousStable, summary: summary, toggles: toggles)
            return MALAccountPresentation(section: underlying.section, inlineError: message)
        default:
            return MALAccountPresentation(
                section: makeSection(for: state, summary: summary, toggles: toggles),
                inlineError: nil)
        }
    }

    private static func makeSection(for state: MALAccountStore.State,
                                    summary: MALSyncSummary,
                                    toggles: MALSyncToggles) -> MALAccountSection {
        switch state {
        case .signedOut:
            return .signedOut
        case .authorizing:
            return .authorizing
        case let .signedIn(profile, syncEnabled, automaticallyAddsTitles):
            return .signedIn(profile: profile,
                             syncEnabled: syncEnabled,
                             automaticallyAddsTitles: automaticallyAddsTitles,
                             summary: summary,
                             isRefreshing: false)
        case let .refreshing(profile):
            return .signedIn(profile: profile,
                             syncEnabled: toggles.syncEnabled,
                             automaticallyAddsTitles: toggles.automaticallyAddsTitles,
                             summary: summary,
                             isRefreshing: true)
        case let .reauthorizationRequired(profile):
            return .reauthorizationRequired(profile: profile, summary: summary)
        case .error:
            // Unreachable: `make` peels the error off before asking for a section, and an
            // error's `previousStable` is never itself an error.
            return .signedOut
        }
    }
}
