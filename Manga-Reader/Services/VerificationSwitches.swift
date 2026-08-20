//
//  VerificationSwitches.swift
//  Manga-Reader
//
//  Debug-only instrument for the ADR-0020 in-app run
//  (`docs/superpowers/specs/2026-08-19-adr-0020-in-app-run-protocol.md`).
//
//  **Why this exists.** ADR-0020's widened search is invisible from outside: a recovered
//  row and a row that never needed widening produce the same card. Decision 5 registers
//  claims about *which query* recovered a row and *how many searches* it cost, and neither
//  is observable from the UI, the cache, or the network trace — the cache records an
//  outcome, not a path.
//
//  **Why an inline call rather than an injected seam.** ADR-0019's instrument wrapped an
//  injected closure and touched no production code, which is the better shape when it is
//  available. It is not available here. `searchWidening` runs up to four targets
//  concurrently, so a wrapper around the `search` closure would see a stream of queries it
//  cannot attribute to a target. This logs what the type decided, from inside the type.
//
//  **Why `#if DEBUG` and an environment variable.** A release build cannot take this path —
//  the code is not in it. The switch is read from the environment, so nothing in the app's
//  own state or UI can reach it; it takes an `xcodebuild` / `simctl` invocation that
//  deliberately sets the variable. Unset, every call here is an early return.
//
//  This is a measuring instrument, not a feature flag. Delete it when the run is written
//  up — see the protocol.
//

#if DEBUG
import Foundation

enum VerificationSwitches {

    /// One reverse-resolution target's path through `MALReverseResolver.searchWidening`.
    struct ReverseTrace: Encodable {
        let malId: Int
        /// Every spelling held after any `fetchTitles`, before the `searchLimit` cap.
        let spellings: [String]
        /// The spellings actually sent to MangaDex, in order. Its count is the claim-4
        /// observable: it must never exceed `MALReverseResolver.searchLimit`.
        let searched: [String]
        let outcome: String        // baseline-resolved | recovered | unresolved
        let arm: String            // exact | fuzzy | none
        let recoveredAtQuery: Int?
        let mangaDexId: String?
        /// Whether the MAL arm's extra `mangaDetail` request was spent on this row.
        let fetchedTitles: Bool
    }

    /// `ADR0020_REVERSE_LOG=1` appends one JSON line per target to
    /// `Documents/adr0020-reverse.log`.
    private static var reverseLogEnabled: Bool {
        ProcessInfo.processInfo.environment["ADR0020_REVERSE_LOG"] == "1"
    }

    private static let logURL: URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("adr0020-reverse.log")
    }()

    /// Serialises the append. Up to four targets resolve concurrently, and interleaved
    /// partial writes would produce a corrupt frame — which, per the protocol's scar list,
    /// is exactly the failure that reads as a believable smaller result.
    private static let lock = NSLock()

    static func logReverse(_ trace: ReverseTrace) {
        guard reverseLogEnabled, let logURL else { return }
        guard let data = try? JSONEncoder().encode(trace) else { return }
        var line = data
        line.append(0x0A)

        lock.lock()
        defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: logURL)
        }
    }
}
#endif
