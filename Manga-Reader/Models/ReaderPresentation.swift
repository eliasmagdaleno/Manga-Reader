//
//  ReaderPresentation.swift
//  Manga-Reader
//
//  ADR-0012. Two small pieces the reader needs and nothing else owns:
//
//    • `isTransientFailure` — is retrying worth offering? Permanent failures get a
//      way out instead of a button that cannot work.
//    • `ReaderPresentation` — the whole state → screen decision as one pure value.
//
//  The second exists because the reader once let two decisions disagree: "which body
//  do we show" and "can the user leave" were separate branches, and a 404 landed in a
//  state where the error filled the screen and the dismiss control was unreachable.
//  Deciding both here, from the same inputs, makes that combination unrepresentable
//  rather than merely avoided.
//

import Foundation

// MARK: - Failure classification

/// An error that knows whether retrying could plausibly succeed.
///
/// The reader reaches sources through `MangaSource`, so it sees `MangaDexError` from
/// one and `SourceError` from another and cannot switch on either concrete type.
protocol ClassifiedFailure {
    /// `true` when the failure might resolve on its own — an outage, a timeout, a
    /// throttle. `false` when it is an *answer*: the thing asked for is not there.
    var isTransient: Bool { get }
}

/// Whether `error` is worth retrying. **Anything unrecognised is transient.**
///
/// This mirrors `MetadataUpgradeQueue.permanentStatus(of:)`, whose `default: return nil`
/// makes the same call, and the asymmetry justifies it either way: wrongly offering
/// Retry costs a wasted tap, while wrongly withholding it strands a user whose network
/// blipped. A bridged extension source (ADR-0003) cannot conform to a Swift protocol,
/// so it lands here by construction — the right default for a source we know nothing about.
func isTransientFailure(_ error: Error) -> Bool {
    (error as? ClassifiedFailure)?.isTransient ?? true
}

extension MangaDexError: ClassifiedFailure {
    var isTransient: Bool {
        switch self {
        case .rateLimited:
            return true
        case .invalidResponse:
            return true                 // Malformed reply; the next one may be fine.
        case .invalidURL:
            return false                // We built a bad URL. Retrying rebuilds the same one.
        case .httpStatus(let code):
            // 4xx is the server answering "no". The two exceptions mean "not now":
            // 429 (throttled) matches the upgrade queue; 408 (timeout) is ADR-0012's
            // deliberate divergence from it, because the reader talks to an image CDN
            // where a timeout is plausible and MAL/AniList never emit one.
            guard (400..<500).contains(code) else { return true }
            return code == 429 || code == 408
        }
    }
}

extension SourceError: ClassifiedFailure {
    var isTransient: Bool {
        switch self {
        case .unsupported:
            return false                // The capability does not exist. It will not appear.
        case .extractionFailed:
            return false                // The scraper's script stopped matching the page.
        case .cloudflareUnsolved:
            return true                 // Retry re-presents the challenge, which is the fix.
        case .navigationFailed:
            return true                 // The page did not load; it may next time.
        }
    }
}

// MARK: - Presentation

/// What the reader should put on screen, and whether the user can get out.
///
/// A pure function of four scalars, so `ReaderPresentationTests` walks the input space
/// exhaustively — including the invariant that carries this type's reason for existing:
/// **no pages ⇒ chrome forced**.
struct ReaderPresentation: Equatable {

    enum Body: Equatable {
        /// Nothing readable behind it. `canRetry` is false for permanent failures, where
        /// the offered action is to leave rather than to try again.
        case error(message: String, canRetry: Bool)
        case loading
        case content
    }

    let body: Body

    /// Forces the chrome — and with it the only dismiss control — visible regardless of
    /// the user's own toggle. True exactly when there is no page on screen, so every
    /// state that cannot be read out of can still be left.
    let chromeForced: Bool

    /// A failure to surface *over* readable content. Non-nil only when a chapter advance
    /// failed while the previous chapter was still loaded (ADR-0012's load-then-commit):
    /// blanking out a chapter the user is reading to report that a different one is
    /// missing is the opposite of what that decision is for.
    let banner: String?

    init(errorMessage: String?, isTransient: Bool, isLoading: Bool, pageCount: Int) {
        let hasPages = pageCount > 0
        chromeForced = !hasPages

        if let errorMessage, !hasPages {
            // An error outranks a retry already in flight: hiding the message behind a
            // spinner would leave the user with no idea why they are waiting.
            body = .error(message: errorMessage, canRetry: isTransient)
            banner = nil
        } else if isLoading, !hasPages {
            body = .loading
            banner = nil
        } else {
            body = .content
            banner = errorMessage
        }
    }
}
