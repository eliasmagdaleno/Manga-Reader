//
//  MALAccountPresentationTests.swift
//  MangaCartaTests
//
//  What the Settings section renders for each account state. Pure mapping, so every
//  branch the design specifies is asserted here rather than through a simulator.
//

import Testing
@testable import MangaCarta

@Suite("MAL account presentation")
struct MALAccountPresentationTests {
    private let profile = MALUserIdentity(id: 7, name: "elias", pictureURL: nil)
    private let toggles = MALSyncToggles(syncEnabled: true, automaticallyAddsTitles: true)

    private func make(_ state: MALAccountStore.State,
                      summary: MALSyncSummary = .empty) -> MALAccountPresentation {
        MALAccountPresentation.make(state: state, summary: summary, toggles: toggles)
    }

    @Test("Signed out offers sign-in and nothing else")
    func signedOut() {
        #expect(make(.signedOut).section == .signedOut)
        #expect(make(.signedOut).inlineError == nil)
    }

    @Test("Authorizing is cancelable and shows no account content")
    func authorizing() {
        #expect(make(.authorizing).section == .authorizing)
    }

    @Test("Signed in carries the identity, both toggles, and the counts")
    func signedIn() {
        let summary = MALSyncSummary(pending: 3, failed: 1, waiting: 2, skipped: 4)
        let presentation = make(
            .signedIn(profile: profile, syncEnabled: false, automaticallyAddsTitles: true),
            summary: summary)

        #expect(presentation.section == .signedIn(profile: profile,
                                                  syncEnabled: false,
                                                  automaticallyAddsTitles: true,
                                                  summary: summary,
                                                  isRefreshing: false))
    }

    /// A refresh must not blank the section out — the user is still signed in, and the
    /// toggles they set are still theirs.
    @Test("Refreshing keeps the signed-in presentation and marks it busy")
    func refreshing() {
        let presentation = make(.refreshing(profile: profile))

        #expect(presentation.section == .signedIn(profile: profile,
                                                  syncEnabled: true,
                                                  automaticallyAddsTitles: true,
                                                  summary: .empty,
                                                  isRefreshing: true))
    }

    /// The pending count is exactly what reassures the user that nothing was lost, so it
    /// survives into the reauthorization state rather than being replaced by an error.
    @Test("Reauthorization keeps the queued counts visible")
    func reauthorization() {
        let summary = MALSyncSummary(pending: 5, failed: 0, waiting: 0, skipped: 0)
        let presentation = make(.reauthorizationRequired(profile: profile), summary: summary)

        #expect(presentation.section == .reauthorizationRequired(profile: profile,
                                                                 summary: summary))
    }

    /// An error is inline and nonmodal: the section underneath it is whatever the error
    /// interrupted, so dismissing the message returns the user exactly where they were.
    @Test("A recoverable error renders inline over the state it interrupted")
    func recoverableError() {
        let stable = MALAccountStore.State.signedIn(profile: profile,
                                                    syncEnabled: true,
                                                    automaticallyAddsTitles: false)
        let presentation = make(.error(message: "Could not sign in.", previousStable: stable))

        #expect(presentation.inlineError == "Could not sign in.")
        #expect(presentation.section == .signedIn(profile: profile,
                                                  syncEnabled: true,
                                                  automaticallyAddsTitles: false,
                                                  summary: .empty,
                                                  isRefreshing: false))
    }

    @Test("Counts describe themselves only when there is something to say")
    func summaryLines() {
        #expect(MALSyncSummary.empty.lines == [])
        #expect(MALSyncSummary(pending: 1, failed: 0, waiting: 0, skipped: 0).lines
                == ["1 update waiting to send"])
        #expect(MALSyncSummary(pending: 2, failed: 3, waiting: 4, skipped: 5).lines
                == ["2 updates waiting to send",
                    "3 failed",
                    "4 waiting for a MyAnimeList match",
                    "5 skipped"])
    }
}
