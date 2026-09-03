//
//  MALAuthenticationSession.swift
//  MangaCarta
//
//  The web-authentication seam. `ASWebAuthenticationSession` and the presentation-anchor
//  lookup live behind `MALAuthPresenting` so the account store — where all the interesting
//  decisions are — is testable without a window.
//

import AuthenticationServices
import Foundation

/// Presents the MAL authorization page and returns the redirect that came back.
protocol MALAuthPresenting: Sendable {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

enum MALAuthPresentationError: Error, Equatable {
    /// The user dismissed the sheet. Not an error to report: nothing is broken.
    case cancelled
    /// The system could not present or complete the session.
    case failed
}

#if canImport(UIKit)
import UIKit

/// Production adapter. The anchor lookup stays here, so nothing above this file knows about
/// windows or scenes.
final class MALWebAuthPresenter: NSObject, MALAuthPresenting,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callback, error in
                    if let callback {
                        continuation.resume(returning: callback)
                        return
                    }
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code
                        == .canceledLogin
                    continuation.resume(
                        throwing: cancelled
                            ? MALAuthPresentationError.cancelled
                            : MALAuthPresentationError.failed
                    )
                }
                session.presentationContextProvider = self
                // MAL sign-in is the point of the sheet; a shared cookie jar would let a
                // stale Safari session decide who signs in.
                session.prefersEphemeralWebBrowserSession = true
                if !session.start() {
                    continuation.resume(throwing: MALAuthPresentationError.failed)
                }
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
#endif
